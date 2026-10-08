import SwiftUI
import AVFoundation

struct ClipPreviewSelection: Identifiable {
    let project: VideoProject
    let clip: Clip
    var id: String { "\(project.id.uuidString)-\(clip.id.uuidString)" }
}

/// Uses the same exact cover and GPU presentation as the editor and exporter.
struct ClipPlaybackPreview: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.scenePhase) private var scenePhase
    let project: VideoProject
    let clip: Clip
    var isActive = true
    var autoplay = false
    var identifier = "clipPlaybackPreview"
    var onPlay: () -> Void = {}
    var onEnlarge: (() -> Void)?
    @StateObject private var cover = CoverPreview()
    @State private var player = AVPlayer()
    @State private var prepared: VideoPreview?
    @State private var playing = false
    @State private var ready = false
    @State private var loading = false
    @State private var error: String?
    @State private var playbackTask: Task<Void, Never>?
    @State private var generation = UUID()

    private var canPlay: Bool { project.settings.format != .photo }
    private var source: URL { store.url(for: project.filename) }
    private var status: String {
        let dimensions = MediaProcessor.dimensions(CGSize(width: project.width, height: project.height), settings: project.settings)
        let state = playing && ready ? "正在播放" : loading ? "正在准备" : "封面"
        return "\(Int(dimensions.width))×\(Int(dimensions.height)) · \(project.settings.look.title) · \(project.settings.speed.formatted())× · \(String(format: "%.2f", clip.duration / project.settings.speed))秒 · \(state)"
    }

    var body: some View {
        ZStack {
            Color.black
            PreviewSurface(player: player, preview: prepared, playing: playing) { ready = $0 }
            if prepared == nil || !ready {
                if let image = cover.image { Image(uiImage: image).resizable().scaledToFit() }
                else { ProgressView().tint(.white) }
            }
            if let error = error ?? cover.errorMessage {
                Text(error).font(.caption).foregroundStyle(.white).padding(12)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
            } else if loading { ProgressView().tint(.white) }
            else if canPlay && !playing {
                Image(systemName: "play.fill").font(.system(size: 17))
                    .foregroundStyle(.white).frame(width: 44, height: 44)
                    .studioGlass(in: Circle(), interactive: true, overImage: true)
            }
        }.clipped().contentShape(Rectangle())
            .onTapGesture { togglePlayback() }
            .onLongPressGesture(minimumDuration: 0.45) { enlarge() }
            .accessibilityElement(children: .ignore).accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(project.title)片段预览").accessibilityValue(status)
            .accessibilityHint(canPlay ? "轻点播放或暂停，长按放大预览" : "长按放大封面")
            .accessibilityAction { togglePlayback() }
            .accessibilityAction(named: Text("放大预览")) { enlarge() }
            .accessibilityIdentifier(identifier)
            .task(id: project.settings) {
                stopPlayback(release: true)
                let renderer = CoverFrameRenderer(source: source, project: project)
                cover.configure(cancel: { Task { await renderer.cancel() } }) { time, photo, exact in
                    try await renderer.frame(time: time, photo: photo, exact: exact)
                }
                cover.request(time: clip.cover, photo: clip.coverPhotoFilename.map { store.url(for: $0) })
                if autoplay && canPlay { togglePlayback() }
            }
            .onChange(of: isActive) { _, active in if !active { stopPlayback(release: true) } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { stopPlayback(release: true) } }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
                guard playing, let item = note.object as? AVPlayerItem, item === prepared?.item else { return }
                startPlayback()
            }
            .onDisappear { stopPlayback(release: true); cover.stop() }
    }

    private func enlarge() {
        guard let onEnlarge else { return }
        stopPlayback(release: true)
        onEnlarge()
    }

    private func togglePlayback() {
        guard canPlay else { return }
        if playing || loading { stopPlayback(); return }
        onPlay()
        if prepared != nil { startPlayback(); return }
        error = nil; loading = true
        let token = UUID(); generation = token
        playbackTask = Task {
            do {
                let preview = try await MediaProcessor.previewItem(source: source, clip: clip, settings: project.settings)
                guard !Task.isCancelled, generation == token else { return }
                prepared = preview; ready = false
                player.replaceCurrentItem(with: preview.item)
                player.isMuted = project.settings.muted || project.settings.format == .gif
                loading = false
                startPlayback()
            } catch is CancellationError {} catch {
                guard generation == token else { return }
                loading = false; self.error = "预览失败：\(error.localizedDescription)。轻点重试。"
            }
        }
    }

    private func startPlayback() {
        guard let prepared else { return }
        let token = UUID(); generation = token
        playing = true
        player.seek(to: prepared.start, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            Task { @MainActor in
                guard playing, generation == token else { return }
                if !finished || player.currentItem?.status == .failed {
                    stopPlayback(release: true); error = "视频暂时无法预览，请重试。"
                    return
                }
                player.playImmediately(atRate: prepared.rate)
            }
        }
    }

    private func stopPlayback(release: Bool = false) {
        generation = UUID(); playbackTask?.cancel(); playbackTask = nil
        playing = false; loading = false; player.pause()
        if release { player.replaceCurrentItem(with: nil); prepared = nil; ready = false }
    }
}

struct EnlargedClipPreview: View {
    @Environment(\.dismiss) private var dismiss
    let selection: ClipPreviewSelection
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let dimensions = MediaProcessor.dimensions(CGSize(width: selection.project.width, height: selection.project.height), settings: selection.project.settings)
                let scale = min((geometry.size.width - 32) / dimensions.width, (geometry.size.height - 32) / dimensions.height)
                ClipPlaybackPreview(project: selection.project, clip: selection.clip, autoplay: true, identifier: "expandedClipPreview")
                    .frame(width: dimensions.width * scale, height: dimensions.height * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }.background(StudioTheme.background)
                .navigationTitle("片段预览").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() }.accessibilityIdentifier("closeExpandedPreview") } }
        }
    }
}
