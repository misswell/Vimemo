import SwiftUI
import PhotosUI

struct CoverPickerView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let project: VideoProject
    let clip: Clip
    let onSave: (Double, String?) -> Void
    @State private var time: Double
    @State private var photoFilename: String?
    @State private var importedFilename: String?
    @State private var photoItem: PhotosPickerItem?
    @StateObject private var preview = CoverPreview()
    @State private var loadingPhoto = false
    @State private var committed = false
    @State private var errorMessage: String?
    @State private var photoTask: Task<Void, Never>?
    @State private var photoGeneration = UUID()
    @State private var scrubbing = false

    init(project: VideoProject, clip: Clip, onSave: @escaping (Double, String?) -> Void) {
        self.project = project; self.clip = clip; self.onSave = onSave
        _time = State(initialValue: min(clip.cover, max(clip.start, clip.end - 1 / max(1, project.frameRate))))
        _photoFilename = State(initialValue: clip.coverPhotoFilename)
    }

    private var lastFrame: Double { max(clip.start, clip.end - 1 / max(1, project.frameRate)) }
    private struct Selection: Equatable {
        let time: Double
        let photoFilename: String?
        let scrubbing: Bool
    }
    private var selection: Selection { Selection(time: time, photoFilename: photoFilename, scrubbing: scrubbing) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ZStack {
                        Color.black
                        if let image = preview.image {
                            Image(uiImage: image).resizable().scaledToFit().accessibilityIdentifier("coverPreviewImage")
                        } else { ProgressView().tint(.white).accessibilityIdentifier("coverPreviewLoading") }
                    }.foregroundStyle(.white).frame(height: 290).clipShape(RoundedRectangle(cornerRadius: 20))
                    StudioGlassGroup(spacing: 12) {
                        HStack(spacing: 12) {
                            PillButton(title: "视频画面", selected: photoFilename == nil) {
                                photoTask?.cancel(); photoGeneration = UUID(); loadingPhoto = false
                                photoItem = nil; photoFilename = nil
                            }
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label("相册照片", systemImage: "photo").font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 16).frame(minHeight: 44).contentShape(Capsule())
                                    .foregroundStyle(photoFilename == nil ? StudioTheme.ink : StudioTheme.accent)
                            }.studioGlassButton(tint: photoFilename == nil ? nil : StudioTheme.accent.opacity(0.18))
                                .accessibilityIdentifier("pickCoverPhoto")
                        }
                    }
                    if loadingPhoto { ProgressView("正在读取照片…").font(.caption) }
                    if photoFilename == nil {
                        StudioCard {
                            VStack(spacing: 16) {
                                SectionLabel(title: "挑选视频中的一帧", detail: time.timeLabel)
                                Slider(value: $time, in: clip.start...max(clip.start + 0.001, lastFrame), step: 1 / max(1, project.frameRate)) { editing in
                                    scrubbing = editing
                                }
                                    .tint(StudioTheme.peach).accessibilityLabel("手动封面时间")
                                FrameSelectionControl(time: $time, range: clip.start...lastFrame, frameRate: project.frameRate) { _, editing in
                                    scrubbing = editing
                                }
                                Text("左右拖动帧数微调 · 从当前片段内选择")
                                    .font(.caption).foregroundStyle(StudioTheme.secondary)
                            }
                        }
                    } else {
                        Text("这张照片将作为静态封面，按视频输出比例裁切，并应用当前画面和调色设置。长按实况时播放所选视频片段。")
                            .font(.caption).foregroundStyle(StudioTheme.secondary).lineSpacing(4)
                    }
                }.padding(20)
            }.scrollIndicators(.hidden).background(StudioTheme.background)
                .navigationTitle("选择封面").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("使用此封面") { onSave(time, photoFilename); committed = true; dismiss() }
                            .disabled(loadingPhoto || !preview.isSettled).accessibilityIdentifier("confirmCover")
                    }
                }
                .task {
                    let renderer = CoverFrameRenderer(source: store.url(for: project.filename), project: project)
                    preview.configure(cancel: { Task { await renderer.cancel() } }) { time, photo, exact in
                        try await renderer.frame(time: time, photo: photo, exact: exact)
                    }
                    requestPreview(selection)
                }
                .onChange(of: selection) { _, selected in requestPreview(selected) }
                .onChange(of: preview.errorMessage) { _, message in errorMessage = message }
                .onChange(of: photoItem) { _, item in loadPhoto(item) }
                .alert("封面选择失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                    Button("好") { errorMessage = nil }
                } message: { Text(errorMessage ?? "") }
                .onDisappear {
                    preview.stop()
                    photoTask?.cancel()
                    if let importedFilename, !committed || importedFilename != photoFilename {
                        try? FileManager.default.removeItem(at: store.url(for: importedFilename))
                    }
                }
        }
    }

    private func requestPreview(_ selected: Selection) {
        preview.request(time: selected.time, photo: selected.photoFilename.map { store.url(for: $0) }, exact: !selected.scrubbing)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        photoTask?.cancel()
        let generation = UUID(); photoGeneration = generation; loadingPhoto = true
        photoTask = Task {
            defer { if photoGeneration == generation { loadingPhoto = false } }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw StudioError.message("照片下载失败，请确认 iCloud 原片可用。") }
                try Task.checkCancellation()
                let filename = try store.importCoverPhoto(data, project: project)
                if let importedFilename { try? FileManager.default.removeItem(at: store.url(for: importedFilename)) }
                importedFilename = filename; photoFilename = filename
            } catch is CancellationError {} catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
        }
    }
}
