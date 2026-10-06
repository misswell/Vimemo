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
    @State private var preview: UIImage?
    @State private var loadingPhoto = false
    @State private var committed = false
    @State private var errorMessage: String?
    @State private var photoTask: Task<Void, Never>?
    @State private var photoGeneration = UUID()

    init(project: VideoProject, clip: Clip, onSave: @escaping (Double, String?) -> Void) {
        self.project = project; self.clip = clip; self.onSave = onSave
        _time = State(initialValue: min(clip.cover, max(clip.start, clip.end - 1 / max(1, project.frameRate))))
        _photoFilename = State(initialValue: clip.coverPhotoFilename)
    }

    private var lastFrame: Double { max(clip.start, clip.end - 1 / max(1, project.frameRate)) }
    private var previewKey: String { "\(time)|\(photoFilename ?? "video")" }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ZStack {
                        Color.black
                        if let preview { Image(uiImage: preview).resizable().scaledToFit() }
                        else { ProgressView().tint(.white) }
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
                                Slider(value: $time, in: clip.start...max(clip.start + 0.001, lastFrame), step: 1 / max(1, project.frameRate))
                                    .tint(StudioTheme.peach).accessibilityLabel("手动封面时间")
                                HStack {
                                    Button { time = max(clip.start, time - 1 / max(1, project.frameRate)) } label: { Label("上一帧", systemImage: "backward.end.fill").frame(minHeight: 44).contentShape(Capsule()) }
                                    Spacer()
                                    Button { time = min(lastFrame, time + 1 / max(1, project.frameRate)) } label: { Label("下一帧", systemImage: "forward.end.fill").frame(minHeight: 44).contentShape(Capsule()) }
                                }.font(.system(size: 13)).foregroundStyle(StudioTheme.accent)
                                    .studioGlassButton(tint: StudioTheme.accent.opacity(0.08))
                                Text("第 \(Int((time * project.frameRate).rounded())) 帧 · 从当前片段内选择")
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
                            .disabled(loadingPhoto || preview == nil).accessibilityIdentifier("confirmCover")
                    }
                }
                .task(id: previewKey) {
                    preview = nil
                    do {
                        var selected = clip; selected.cover = time
                        let photo = photoFilename.map { store.url(for: $0) }
                        let image = try await MediaProcessor.cover(source: store.url(for: project.filename), project: project, clip: selected, photo: photo)
                        guard !Task.isCancelled else { return }
                        preview = UIImage(cgImage: image)
                    } catch is CancellationError {} catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
                }
                .onChange(of: photoItem) { _, item in loadPhoto(item) }
                .alert("封面选择失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                    Button("好") { errorMessage = nil }
                } message: { Text(errorMessage ?? "") }
                .onDisappear {
                    photoTask?.cancel()
                    if let importedFilename, !committed || importedFilename != photoFilename {
                        try? FileManager.default.removeItem(at: store.url(for: importedFilename))
                    }
                }
        }
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
