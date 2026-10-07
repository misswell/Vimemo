import SwiftUI
import AVKit

struct EditorView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var exporter: ExportCoordinator
    @Environment(\.dismiss) private var dismiss
    @State var project: VideoProject
    @State private var activeClipID: UUID
    @State private var thumbnails: [UIImage] = []
    @State private var coverImage: UIImage?
    @State private var player = AVPlayer()
    @State private var playing = false
    @State private var tool = 0
    @State private var showExport = false
    @State private var showRename = false
    @State private var showReset = false
    @State private var showCoverPicker = false
    @State private var titleDraft = ""
    @State private var previewTask: Task<Void, Never>?
    @State private var frameTask: Task<Void, Never>?
    @State private var playerObserver: NSObjectProtocol?
    @State private var previewGeneration = UUID()
    @State private var frameGeneration = UUID()
    @State private var findingCover = false
    @State private var coverTask: Task<Void, Never>?

    init(project: VideoProject) {
        _project = State(initialValue: project)
        _activeClipID = State(initialValue: project.clips[0].id)
    }

    private var clipIndex: Int { project.clips.firstIndex { $0.id == activeClipID } ?? 0 }
    private var clip: Clip { project.clips[clipIndex] }
    private var clipBinding: Binding<Clip> {
        Binding(get: { clip }, set: { project.clips[clipIndex] = $0 })
    }
    private var sourceURL: URL { store.url(for: project.filename) }
    private var maxSourceClipDuration: Double { project.settings.maxOutputDuration.map { $0 * project.settings.speed } ?? project.duration }
    private var previewDimensions: CGSize {
        MediaProcessor.dimensions(CGSize(width: project.width, height: project.height), settings: project.settings)
    }

    private func previewSize(availableWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        let dimensions = previewDimensions
        let aspectRatio = dimensions.width / max(1, dimensions.height)
        let width = min(max(1, availableWidth), max(1, maxHeight) * aspectRatio)
        return CGSize(width: width, height: width / aspectRatio)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StudioTheme.background.ignoresSafeArea()
                GeometryReader { geometry in
                    if geometry.size.width > 700 {
                        let previewSize = previewSize(
                            availableWidth: geometry.size.width * 0.46,
                            maxHeight: min(520, max(260, geometry.size.height - 92))
                        )
                        HStack(alignment: .top, spacing: 24) {
                            VStack(spacing: 12) {
                                preview.frame(width: previewSize.width, height: previewSize.height)
                                coverControls
                            }.frame(width: geometry.size.width * 0.46)
                            editorPanels
                        }.padding(.horizontal, 24).padding(.vertical, 12)
                    } else {
                        let previewSize = previewSize(
                            availableWidth: geometry.size.width - 32,
                            maxHeight: min(280, max(136, geometry.size.height * 0.34))
                        )
                        VStack(spacing: 0) {
                            preview.frame(width: previewSize.width, height: previewSize.height)
                                .padding(.top, 6)
                            coverControls.padding(.horizontal, 20).padding(.vertical, 8)
                            editorPanels
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { store.update(project); store.persist(); dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium)) }.accessibilityLabel("返回工作台")
                }
                ToolbarItem(placement: .principal) {
                    Button { titleDraft = project.title; showRename = true } label: {
                        VStack(spacing: 3) {
                            Text(project.title).font(.system(size: 14, weight: .semibold)).lineLimit(1).foregroundStyle(StudioTheme.ink)
                            Text("\(project.sizeLabel) · \(Int(project.frameRate.rounded())) FPS").font(.system(size: 9, design: .monospaced)).foregroundStyle(StudioTheme.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showReset = true } label: { Image(systemName: "arrow.counterclockwise").font(.system(size: 15)) }.accessibilityLabel("重置画面编辑")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    toolSelector
                    PrimaryButton(title: "导出 · \(project.clips.count) 个作品", symbol: "arrow.up.right") {
                        playing = false; player.pause(); store.update(project); store.persist(); showExport = true
                    }.disabled(exporter.running).accessibilityIdentifier("makeLivePhotos")
                }.frame(maxWidth: 680).frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
                    .background(.bar)
            }
            .sheet(isPresented: $showExport, onDismiss: {
                if let saved = store.projects.first(where: { $0.id == project.id }) { project = saved }
            }) { ExportSheet(projects: [project]) }
            .sheet(isPresented: $showCoverPicker) {
                CoverPickerView(project: project, clip: clip) { time, filename in
                    project.clips[clipIndex].cover = time
                    project.clips[clipIndex].coverPhotoFilename = filename
                    store.update(project); store.persist()
                }
            }
            .alert("重置画面编辑", isPresented: $showReset) {
                Button("重置画面编辑", role: .destructive) { resetPicture() }
                Button("取消", role: .cancel) {}
            } message: { Text("重置构图和调色？片段与封面选择会保留。") }
            .alert("重命名视频", isPresented: $showRename) {
                TextField("视频名称", text: $titleDraft)
                Button("取消", role: .cancel) {}
                Button("保存") { let title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines); if !title.isEmpty { project.title = title } }
            }
            .task {
                await loadThumbnails()
                refreshPreview()
            }
            .onChange(of: project.settings) { _, _ in
                for index in project.clips.indices { project.clips[index].normalize(sourceDuration: project.duration, speed: project.settings.speed, maxOutputDuration: project.settings.maxOutputDuration) }
                store.update(project)
                refreshPreview()
            }
            .onChange(of: project.clips) { _, _ in store.update(project); refreshPreview() }
            .onChange(of: project.title) { _, _ in store.update(project) }
            .onChange(of: activeClipID) { _, _ in refreshPreview() }
            .onDisappear {
                player.pause(); previewTask?.cancel(); frameTask?.cancel(); coverTask?.cancel()
                if let playerObserver { NotificationCenter.default.removeObserver(playerObserver) }
                store.update(project); store.persist()
            }
        }
    }

    private var editorPanels: some View {
        ScrollView {
            VStack(spacing: 16) {
                if tool == 0 {
                    clipSelector
                    timelineCard
                    DisclosureGroup("发现更多片段") { momentsPanel.padding(.top, 12) }
                        .font(.subheadline).padding(.horizontal, 4)
                } else { toolPanel }
            }.frame(maxWidth: 680).frame(maxWidth: .infinity)
                .padding(.horizontal, 16).padding(.vertical, 12)
        }.scrollIndicators(.hidden).accessibilityIdentifier("editorScroll")
    }

    private var preview: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if playing {
                PlayerSurface(player: player)
            } else if let coverImage {
                Image(uiImage: coverImage).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity) }
            HStack {
                Label("LIVE", systemImage: "livephoto").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1)
                Spacer()
                Text(String(format: "%.2f s", clip.duration / project.settings.speed)).font(.system(size: 10, weight: .medium, design: .monospaced))
            }.padding(13).foregroundStyle(.white).background(LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom))
            Button { togglePlayback() } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 19)).foregroundStyle(.white)
                    .frame(width: 48, height: 48).contentShape(Circle())
            }.studioGlassButton(circular: true, overImage: true).contentShape(Circle()).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(13).accessibilityLabel(playing ? "暂停预览" : "播放编辑后片段").accessibilityIdentifier("previewPlayback")
        }.accessibilityElement(children: .contain).accessibilityIdentifier("editorPreview").clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(StudioTheme.line, lineWidth: 1))
    }

    private var clipSelector: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(project.clips.enumerated()), id: \.element.id) { index, item in
                    PillButton(title: "片段 \(index + 1)", selected: item.id == activeClipID) { activeClipID = item.id }
                        .frame(width: 84, height: 44).fixedSize()
                }
                Button {
                    let start = min(clip.end, max(0, project.duration - maxSourceClipDuration))
                    var newClip = Clip(start: start, end: min(project.duration, start + maxSourceClipDuration), cover: start + min(1.5 * project.settings.speed, (project.duration - start) / 2))
                    newClip.normalize(sourceDuration: project.duration, speed: project.settings.speed, maxOutputDuration: project.settings.maxOutputDuration)
                    project.clips.append(newClip); activeClipID = newClip.id
                } label: { Image(systemName: "plus").font(.system(size: 14, weight: .medium)).padding(12).background(StudioTheme.surface, in: Circle()) }
                    .frame(width: 44, height: 44).fixedSize()
                    .disabled(project.clips.count >= 20).accessibilityLabel("添加片段")
                if project.clips.count > 1 {
                    Button {
                        let removedID = activeClipID
                        activeClipID = project.clips.first { $0.id != removedID }!.id
                        project.clips.removeAll { $0.id == removedID }
                    } label: { Image(systemName: "trash").font(.system(size: 13)).padding(12).foregroundStyle(StudioTheme.secondary) }
                        .frame(width: 44, height: 44).fixedSize().accessibilityLabel("删除当前片段")
                }
            }.buttonStyle(.plain)
        }.scrollIndicators(.hidden)
    }

    private var timelineCard: some View {
        StudioCard {
            VStack(spacing: 16) {
                SectionLabel(title: "裁剪片段", detail: "原视频 \(project.duration.timeLabel)")
                TimelineView(clip: clipBinding, duration: project.duration, speed: project.settings.speed, maxOutputDuration: project.settings.maxOutputDuration, thumbnails: thumbnails) { time in seekFrame(time) }
                if project.settings.maxOutputDuration == nil {
                    Button("使用整段视频") {
                        var value = clip; value.start = 0; value.end = project.duration
                        value.normalize(sourceDuration: project.duration, speed: project.settings.speed, maxOutputDuration: nil)
                        project.clips[clipIndex] = value
                    }.font(.system(size: 12, weight: .medium)).accessibilityIdentifier("useFullVideo")
                }
                HStack(spacing: 8) {
                    frameButton("上一帧", symbol: "backward.end.fill", delta: -1)
                    Text(clip.coverPhotoFilename == nil ? "第 \(Int((clip.cover * max(1, project.frameRate)).rounded())) 帧" : "照片封面")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(StudioTheme.secondary)
                    frameButton("下一帧", symbol: "forward.end.fill", delta: 1)
                }
                DisclosureGroup("精确裁剪") {
                    HStack {
                        VStack(spacing: 8) { Text("入点 \(clip.start.timeLabel)"); timeStepper(isStart: true) }
                        Spacer()
                        VStack(spacing: 8) { Text("出点 \(clip.end.timeLabel)"); timeStepper(isStart: false) }
                    }.font(.caption).padding(.top, 12)
                }.font(.caption)

            }
        }.buttonStyle(.plain)
    }
    private func timeStepper(isStart: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach([-1, 1], id: \.self) { direction in
                Button {
                    var value = clip
                    if isStart {
                        value.start = min(value.end - 0.1, max(0, value.start + Double(direction) / max(1, project.frameRate)))
                        if let maximum = project.settings.maxOutputDuration { value.start = max(value.start, value.end - maximum * project.settings.speed) }
                    } else { value.end += Double(direction) / max(1, project.frameRate) }
                    value.normalize(sourceDuration: project.duration, speed: project.settings.speed, maxOutputDuration: project.settings.maxOutputDuration)
                    project.clips[clipIndex] = value
                } label: { Image(systemName: direction == -1 ? "minus" : "plus").font(.system(size: 10)).frame(width: 44, height: 44).contentShape(Circle()) }
                    .studioGlassButton(circular: true, tint: StudioTheme.accent.opacity(0.12))
                    .accessibilityLabel("\(isStart ? "入点" : "出点")\(direction == -1 ? "前移" : "后移")一帧")
            }
        }.buttonStyle(.plain)
    }

    private func frameButton(_ title: String, symbol: String, delta: Double) -> some View {
        Button {
            coverTask?.cancel()
            project.clips[clipIndex].coverPhotoFilename = nil
            project.clips[clipIndex].cover = min(clip.end - 1.0 / 600, max(clip.start, clip.cover + delta / max(1, project.frameRate)))
        } label: { Label(title, systemImage: symbol).font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).frame(minHeight: 44).contentShape(RoundedRectangle(cornerRadius: 12)) }
            .studioGlass(in: RoundedRectangle(cornerRadius: 12), interactive: true, tint: StudioTheme.accent.opacity(0.08))
    }

    private var toolSelector: some View {
        StudioGlassGroup(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array([("片段", "scissors"), ("画面", "crop.rotate"), ("调色", "camera.filters"), ("播放", "speedometer")].enumerated()), id: \.offset) { index, item in
                    Button { tool = index } label: {
                        Label(item.0, systemImage: item.1).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tool == index ? StudioTheme.accent : StudioTheme.secondary)
                            .frame(maxWidth: .infinity).frame(minHeight: 44)
                            .background(tool == index ? StudioTheme.accent.opacity(0.12) : .clear, in: Capsule())
                            .contentShape(Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier("editorTool\(index)")
                        .accessibilityValue(tool == index ? "已选择" : "未选择")
                }
            }.padding(5).studioGlass(in: Capsule(), interactive: false)
        }
    }
    private var coverControls: some View {
        StudioGlassGroup {
            HStack(spacing: 12) {
                Button {
                    coverTask?.cancel(); findingCover = false; playing = false; player.pause(); showCoverPicker = true
                } label: {
                    Label("选择封面", systemImage: "photo.on.rectangle").font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16).frame(minHeight: 44).contentShape(Capsule())
                }.studioGlassButton().accessibilityIdentifier("chooseCover")
                Spacer(minLength: 0)
                if clip.coverPhotoFilename != nil {
                    Text("已使用相册照片作为封面").font(.system(size: 10)).foregroundStyle(StudioTheme.secondary).lineLimit(2)
                } else {
                    Button { findClearCover() } label: {
                        Group {
                            if findingCover { ProgressView().controlSize(.small) }
                            else { Label("自动选帧", systemImage: "sparkle").font(.system(size: 12)) }
                        }.padding(.horizontal, 16).frame(minHeight: 44).contentShape(Capsule())
                    }.studioGlassButton().disabled(findingCover).accessibilityLabel("自动选清晰封面")
                }
            }.buttonStyle(.plain)
        }
    }
    private func resetPicture() {
        project.settings.ratio = .original; project.settings.rotation = 0; project.settings.mirrored = false
        project.settings.look = .original; project.settings.exposure = 0; project.settings.contrast = 1; project.settings.saturation = 1
        project.settings.cropX = 0.5; project.settings.cropY = 0.5
    }
    @ViewBuilder private var toolPanel: some View {
        switch tool {
        case 0: momentsPanel
        case 1: cropPanel
        case 2: colorPanel
        default: playbackPanel
        }
    }
    private var momentsPanel: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 15) {
                SectionLabel(title: "沿时间发现片段", detail: "\(min(6, max(1, Int(ceil(project.duration / 3))))) 个候选")
                Text("按时间均匀选取，点选切换，长按加入制作队列。").font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(0..<min(6, max(1, Int(ceil(project.duration / 3)))), id: \.self) { index in
                            let count = min(6, max(1, Int(ceil(project.duration / 3))))
                            let start = count > 1 ? Double(index) / Double(count - 1) * max(0, project.duration - min(3 * project.settings.speed, maxSourceClipDuration)) : 0
                            VStack(alignment: .leading, spacing: 8) {
                                if !thumbnails.isEmpty {
                                    let thumbnailIndex = min(thumbnails.count - 1, Int(start / project.duration * Double(thumbnails.count)))
                                    Image(uiImage: thumbnails[thumbnailIndex]).resizable().scaledToFill().frame(width: 90, height: 62).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                Text(start.timeLabel).font(.system(size: 10, design: .monospaced)).foregroundStyle(StudioTheme.secondary)
                            }.contentShape(Rectangle())
                                .onTapGesture { project.clips[clipIndex] = suggestedClip(start: start, id: activeClipID) }
                                .onLongPressGesture {
                                    guard project.clips.count < 20 else { return }
                                    let suggested = suggestedClip(start: start, id: UUID())
                                    project.clips.append(suggested); activeClipID = suggested.id
                                }
                                .accessibilityAddTraits(.isButton).accessibilityLabel("选择 \(start.timeLabel) 的片段")
                        }
                    }
                }.scrollIndicators(.hidden)
            }
        }
    }
    private func suggestedClip(start: Double, id: UUID) -> Clip {
        let end = min(project.duration, start + maxSourceClipDuration)
        return Clip(id: id, start: start, end: end, cover: (start + end) / 2)
    }
    private var cropPanel: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 18) {
                SectionLabel(title: "构图", detail: "同时应用到照片与视频")
                ScrollView(.horizontal) {
                    HStack(spacing: 8) { ForEach(FrameRatio.allCases) { ratio in PillButton(title: ratio.title, selected: project.settings.ratio == ratio) { project.settings.ratio = ratio } } }
                }.scrollIndicators(.hidden)
                HStack(spacing: 10) {
                    PillButton(title: "旋转 90°") { project.settings.rotation = (project.settings.rotation + 1) % 4 }
                    PillButton(title: "水平翻转", selected: project.settings.mirrored) { project.settings.mirrored.toggle() }
                }
                if project.settings.ratio != .original {
                    adjustment("水平位置", value: $project.settings.cropX, range: 0...1)
                    adjustment("垂直位置", value: $project.settings.cropY, range: 0...1)
                }
            }
        }
    }
    private var colorPanel: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 17) {
                SectionLabel(title: "让色彩贴近记忆")
                ScrollView(.horizontal) {
                    HStack(spacing: 8) { ForEach(ColorLook.allCases) { look in PillButton(title: look.title, selected: project.settings.look == look) { project.settings.look = look } } }
                }.scrollIndicators(.hidden)
                adjustment("曝光", value: $project.settings.exposure, range: -2...2)
                adjustment("对比度", value: $project.settings.contrast, range: 0.5...1.5)
                adjustment("饱和度", value: $project.settings.saturation, range: 0...2)
            }
        }
    }
    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 4) {
            HStack { Text(title); Spacer(); Text(String(format: "%.2f", value.wrappedValue)).monospacedDigit() }.font(.system(size: 12)).foregroundStyle(StudioTheme.secondary)
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }
    private var playbackPanel: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 18) {
                SectionLabel(title: "播放方式")
                HStack(spacing: 7) {
                    ForEach([0.5, 1, 1.5, 2], id: \.self) { speed in PillButton(title: "\(speed.formatted())×", selected: project.settings.speed == speed) { project.settings.speed = speed } }
                }
                Toggle("静音", isOn: $project.settings.muted).font(.system(size: 14)).disabled(!project.hasAudio)
                Text(project.settings.maxOutputDuration == nil ? "当前不限制时长。调整倍速会改变输出长度。" : "输出最长 3 秒。可在设置中开启「不限制时长」。")
                    .font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
            }
        }
    }

    private func loadThumbnails() async {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: sourceURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 120, height: 120)
        var frames: [UIImage] = []
        for index in 0..<16 {
            if Task.isCancelled { return }
            let time = Double(index) / 16 * project.duration
            if let frame = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)) { frames.append(UIImage(cgImage: frame.image)) }
        }
        thumbnails = frames
    }
    private func findClearCover() {
        guard !findingCover else { return }
        findingCover = true
        let selectedClip = clip, settings = project.settings, source = sourceURL
        coverTask = Task {
            defer { findingCover = false }
            do {
                let time = try await FrameAnalysis.bestCover(source: source, clip: selectedClip, settings: settings)
                guard !Task.isCancelled, activeClipID == selectedClip.id, project.settings == settings, clip == selectedClip else { return }
                project.clips[clipIndex].coverPhotoFilename = nil
                project.clips[clipIndex].cover = time
            } catch is CancellationError {} catch { store.errorMessage = "自动选帧失败：\(error.localizedDescription)" }
        }
    }
    private func seekFrame(_ time: Double) {
        playing = false; player.pause()
        frameTask?.cancel()
        let generation = UUID(); frameGeneration = generation
        let source = sourceURL, currentProject = project
        var currentClip = clip; currentClip.cover = time
        let photo = currentClip.coverPhotoFilename.map { store.url(for: $0) }
        frameTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(50))
                let image = try await MediaProcessor.cover(source: source, project: currentProject, clip: currentClip, photo: photo)
                guard !Task.isCancelled, frameGeneration == generation else { return }
                coverImage = UIImage(cgImage: image)
            } catch is CancellationError {} catch { store.errorMessage = "封面预览失败：\(error.localizedDescription)" }
        }
    }
    private func refreshPreview() {
        playing = false; player.pause()
        seekFrame(clip.cover)
        previewTask?.cancel()
        let generation = UUID(); previewGeneration = generation
        let source = sourceURL, currentClip = clip, settings = project.settings
        previewTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(180))
                let item = try await MediaProcessor.previewItem(source: source, clip: currentClip, settings: settings)
                guard !Task.isCancelled, previewGeneration == generation else { return }
                player.replaceCurrentItem(with: item)
                if let playerObserver { NotificationCenter.default.removeObserver(playerObserver) }
                playerObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                    Task { @MainActor in playing = false; player.seek(to: .zero) }
                }
            } catch is CancellationError {} catch { store.errorMessage = "动态预览失败：\(error.localizedDescription)" }
        }
    }
    private func togglePlayback() {
        if playing { player.pause(); playing = false }
        else {
            guard player.currentItem != nil else { return }
            player.seek(to: .zero); playing = true; player.play()
        }
    }
}

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    func makeUIView(context: Context) -> Surface { let view = Surface(); view.playerLayer.videoGravity = .resizeAspect; view.playerLayer.player = player; return view }
    func updateUIView(_ uiView: Surface, context: Context) { uiView.playerLayer.player = player }
}
