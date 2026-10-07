import SwiftUI
import PhotosUI
import AVKit
import ImageIO

struct ExportSheet: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var coordinator: ExportCoordinator
    @EnvironmentObject private var purchases: PurchaseStore
    @Environment(\.dismiss) private var dismiss
    @State var projects: [VideoProject]
    @State private var format: OutputFormat
    @State private var gifSize: GIFSize
    @State private var gifFrameRate: GIFFrameRate
    @State private var quality: ExportQuality
    @State private var preserveDate: Bool
    @State private var preserveLocation: Bool
    @State private var muted: Bool
    @State private var saveToPhotos = true
    @State private var started = false
    @State private var sharing = false
    @State private var showPurchase = false

    init(projects: [VideoProject]) {
        _projects = State(initialValue: projects)
        let settings = projects.first?.settings ?? EditSettings()
        _format = State(initialValue: settings.format)
        _quality = State(initialValue: settings.quality)
        _gifSize = State(initialValue: settings.effectiveGIFSize)
        _gifFrameRate = State(initialValue: settings.effectiveGIFFrameRate)
        _preserveDate = State(initialValue: settings.preserveDate)
        _preserveLocation = State(initialValue: settings.preserveLocation)
        _muted = State(initialValue: settings.muted)
    }
    private var count: Int { projects.reduce(0) { $0 + $1.clips.count } }

    var body: some View {
        NavigationStack {
            ZStack {
                StudioTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        if started { resultView } else { optionsView }
                    }.frame(maxWidth: 680).frame(maxWidth: .infinity).padding(20)
                }.scrollIndicators(.hidden)
            }
            .navigationTitle(started ? "制作进度" : "制作与导出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !coordinator.running { Button("完成") { dismiss() } }
                }
            }
            .interactiveDismissDisabled(coordinator.running)
            .safeAreaInset(edge: .bottom) {
                if !started {
                    VStack(spacing: 9) {
                        Text(format == .gif ? "GIF · \(gifSize.title) · \(gifFrameRate.title)" : "\(format.title) · \(quality.title)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(StudioTheme.secondary)
                        PrimaryButton(title: "\(saveToPhotos ? "制作并保存" : "制作文件") · \(count) 个作品", symbol: format.symbol) { start() }
                            .disabled(count == 0 || coordinator.running)
                    }.padding(.horizontal, 20).padding(.vertical, 12).background(StudioTheme.surface)
                        .overlay(alignment: .top) { Rectangle().fill(StudioTheme.line).frame(height: 1) }
                }
            }
            .sheet(isPresented: $sharing) {
                ShareSheet(urls: coordinator.completed.flatMap { $0.files.map { store.url(for: $0) } })
            }
            .sheet(isPresented: $showPurchase) { UnlimitedPurchaseView { start() } }
        }
    }

    private var optionsView: some View {
        VStack(spacing: 20) {
            HStack {
                Group {
                    if let project = projects.first {
                        ThumbnailImage(url: store.url(for: project.thumbnailFilename)).frame(width: 48, height: 60).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(projects.count) 个视频 · \(count) 个片段").font(.headline)
                    Text("选择格式，带走这一刻。").font(.caption).foregroundStyle(StudioTheme.secondary)
                }
                Spacer()
            }.padding(.vertical, 5)
            if ExportAccess.requiresUnlimited(projects, format: format) {
                Label(purchases.hasUnlimited ? "不限制时长 · 已解锁" : "超过 3 秒的导出需一次性解锁", systemImage: purchases.hasUnlimited ? "checkmark.circle" : "lock")
                    .font(.caption).foregroundStyle(StudioTheme.peach).accessibilityIdentifier("longExportNotice")
            }
            StudioCard {
                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel(title: "输出格式")
                    StudioGlassGroup(spacing: 10) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(OutputFormat.allCases) { item in
                                Button { format = item } label: {
                                    HStack {
                                        Image(systemName: item.symbol)
                                        Text(item.title).font(.system(size: 13, weight: .medium))
                                        Spacer(minLength: 0)
                                        if format == item { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                                    }.padding(.horizontal, 13).frame(minHeight: 50).foregroundStyle(format == item ? StudioTheme.accent : StudioTheme.ink)
                                        .contentShape(RoundedRectangle(cornerRadius: 12))
                                        .studioGlass(in: RoundedRectangle(cornerRadius: 12), interactive: true, tint: format == item ? StudioTheme.accent.opacity(0.18) : nil)
                                }.buttonStyle(.plain).accessibilityValue(format == item ? "已选择" : "未选择")
                            }
                        }
                    }
                    Text(format == .livePhoto ? "保存到相册后长按播放。分享文件包含 JPG 与 MOV 配对原件。" : format == .gif ? "GIF 循环播放，不含声音。尺寸和帧率可自由选择。" : format == .photo ? "导出所选封面帧，保留裁剪与调色。" : "导出裁剪后的 MOV 视频；可在拍摄信息与隐私中选择是否保留声音。")
                        .font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
                }
            }
            StudioCard {
                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel(title: "保存到")
                    Picker("保存位置", selection: $saveToPhotos) { Text("照片图库").tag(true); Text("本机作品 / 分享文件").tag(false) }.pickerStyle(.segmented)
                    Label("本机始终保留一份，可在「作品」中再次分享。", systemImage: "internaldrive").font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
                }
            }
            if format == .gif {
                StudioCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionLabel(title: "GIF 尺寸", detail: "最大边长 · 不放大原片")
                        StudioGlassGroup(spacing: 8) {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                                ForEach(GIFSize.allCases) { item in
                                    PillButton(title: item.title, selected: gifSize == item) { gifSize = item }
                                        .accessibilityIdentifier("gifSize\(item.rawValue)")
                                        .accessibilityValue(gifSize == item ? "已选择" : "未选择")
                                }
                            }
                        }
                        SectionLabel(title: "GIF 帧率")
                        StudioGlassGroup(spacing: 8) {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                                ForEach(GIFFrameRate.allCases) { item in
                                    PillButton(title: item.title, selected: gifFrameRate == item) { gifFrameRate = item }
                                        .accessibilityIdentifier("gifFPS\(item.rawValue)")
                                        .accessibilityValue(gifFrameRate == item ? "已选择" : "未选择")
                                }
                            }
                        }
                        Text("尺寸越大、帧率越高，文件越大，制作时间越长。低帧率适合轻量分享，高帧率播放更流畅。")
                            .font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
                    }
                }
            } else {
                StudioCard {
                    VStack(alignment: .leading, spacing: 17) {
                        SectionLabel(title: "输出尺寸", detail: "不放大小尺寸原片")
                        StudioGlassGroup(spacing: 8) {
                            HStack(spacing: 8) {
                                ForEach(ExportQuality.allCases) { item in PillButton(title: item.title, selected: quality == item) { quality = item } }
                            }
                        }
                        Text("原始尺寸最大边长 4096 像素；1080p / 720p 的最大边长为 1920 / 1280 像素。").font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
                    }
                }
            }
            StudioCard {
                DisclosureGroup("拍摄信息与隐私") {
                    VStack(alignment: .leading, spacing: 15) {
                        if format == .livePhoto || format == .video {
                            Toggle("静音导出", isOn: $muted)
                                .font(.system(size: 14))
                                .accessibilityIdentifier("exportMute")
                            Text("开启后，导出的视频不包含音轨；原始视频不受影响。")
                                .font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
                            Divider()
                        }
                        Toggle("保留原始拍摄时间", isOn: $preserveDate).font(.system(size: 14))
                        Divider()
                        Toggle("保留原始位置", isOn: $preserveLocation).font(.system(size: 14))
                        Text("仅保留导入文件中已有的信息。缺少拍摄时间时，相册使用导出时间。位置默认关闭。").font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
                    }.padding(.top, 16)
                }.font(.subheadline.weight(.medium))
            }

        }
    }
    @ViewBuilder private var resultView: some View {
        VStack(spacing: 20) {
            if coordinator.running {
                StudioCard {
                    VStack(spacing: 22) {
                        Image(systemName: format.symbol).font(.system(size: 45, weight: .ultraLight)).foregroundStyle(StudioTheme.accent)
                        Text("把片刻，留成实况。").font(.title3.bold())
                        ProgressView(value: coordinator.progress).tint(StudioTheme.accent)
                        Text("\(Int(coordinator.progress * 100))%").font(.system(size: 28, weight: .light, design: .monospaced))
                        Text(coordinator.status).font(.caption).foregroundStyle(StudioTheme.secondary)
                        Button("取消剩余制作", role: .destructive) { coordinator.cancel() }.font(.subheadline)
                    }.padding(.vertical, 24)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: coordinator.errorMessage != nil || coordinator.cancelled ? "exclamationmark.circle" : "checkmark.circle")
                        .font(.system(size: 48, weight: .ultraLight)).foregroundStyle(StudioTheme.accent)
                    Text(coordinator.status).font(.title3.bold())
                }.padding(.vertical, 18)
                if let first = coordinator.completed.first {
                    MediaPreview(record: first).frame(height: 270).clipShape(RoundedRectangle(cornerRadius: 20))
                }
                if let error = coordinator.errorMessage {
                    Text(error).font(.subheadline).foregroundStyle(StudioTheme.peach).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(coordinator.completed) { record in
                    HStack {
                        Image(systemName: record.format.symbol).foregroundStyle(StudioTheme.accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.projectTitle).font(.system(size: 13, weight: .medium))
                            Text(record.savedToPhotos ? "已保存到照片图库及本机" : "已保存到本机作品").font(.caption).foregroundStyle(StudioTheme.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark").foregroundStyle(StudioTheme.accent)
                    }.padding(16).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                }
                if !coordinator.completed.isEmpty {
                    PrimaryButton(title: "分享 / 存储到文件", symbol: "square.and.arrow.up") { sharing = true }
                }
                Button("返回导出设置") { started = false }.font(.subheadline).padding(8)
            }
        }
    }
    private func start() {
        guard !ExportAccess.requiresUnlimited(projects, format: format) || purchases.hasUnlimited else {
            showPurchase = true; return
        }
        for index in projects.indices {
            projects[index].settings.format = format
            projects[index].settings.quality = quality
            projects[index].settings.gifSize = gifSize
            projects[index].settings.gifFrameRate = gifFrameRate
            projects[index].settings.preserveDate = preserveDate
            projects[index].settings.preserveLocation = preserveLocation
            projects[index].settings.muted = muted
            store.update(projects[index])
        }
        store.persist()
        started = coordinator.start(projects: projects, store: store, saveToPhotos: saveToPhotos, purchases: purchases)
        if !started && ExportAccess.requiresUnlimited(projects) { showPurchase = true }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: urls, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct MediaPreview: View {
    @EnvironmentObject private var store: ProjectStore
    let record: ExportRecord
    @State private var player: AVPlayer?
    var body: some View {
        Group {
            if record.format == .livePhoto { LivePhotoPreview(urls: record.files.map { store.url(for: $0) }) }
            else if record.format == .video {
                if let player { VideoPlayer(player: player) } else { ProgressView().tint(.white) }
            } else if record.format == .gif, let file = record.files.first {
                AnimatedGIF(url: store.url(for: file))
            } else {
                if let image = UIImage(contentsOfFile: store.url(for: record.thumbnailFilename).path) { Image(uiImage: image).resizable().scaledToFit() }
            }
        }.frame(maxWidth: .infinity).background(.black)
            .task(id: record.id) {
                if record.format == .video, let file = record.files.first { player = AVPlayer(url: store.url(for: file)) }
            }
            .onDisappear { player?.pause() }
    }
}

struct LivePhotoPreview: View {
    let urls: [URL]
    @State private var photo: PHLivePhoto?
    @State private var request: PHLivePhotoRequestID?
    @State private var error: String?
    @State private var playback = 0
    var body: some View {
        ZStack(alignment: .bottom) {
            if let photo { LivePhotoSurface(photo: photo, playback: playback) }
            else if let error { Text(error).font(.caption).padding().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity) }
            if photo != nil {
                Button { playback += 1 } label: {
                    Label("长按画面，或点此播放实况", systemImage: "livephoto").font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 9).background(.black.opacity(0.65), in: Capsule())
                }.padding(12).foregroundStyle(.white)
            }
        }.foregroundStyle(.white).onAppear {
            request = PHLivePhoto.request(withResourceFileURLs: urls, placeholderImage: nil, targetSize: CGSize(width: 1200, height: 1200), contentMode: .aspectFit) { result, info in
                guard !(info[PHLivePhotoInfoIsDegradedKey] as? Bool ?? false) else { return }
                DispatchQueue.main.async {
                    photo = result
                    if result == nil { error = "系统无法载入这张实况照片。原始配对文件仍可分享。" }
                }
            }
        }.onDisappear {
            if let request { PHLivePhoto.cancelRequest(withRequestID: request) }
        }
    }
}

struct LivePhotoSurface: UIViewRepresentable {
    let photo: PHLivePhoto
    var playback: Int
    final class Coordinator { var token = 0 }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView(); view.contentMode = .scaleAspectFit; view.livePhoto = photo; return view
    }
    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        uiView.livePhoto = photo
        if playback != context.coordinator.token { context.coordinator.token = playback; uiView.startPlayback(with: .full) }
    }
    static func dismantleUIView(_ uiView: PHLivePhotoView, coordinator: Coordinator) { uiView.stopPlayback() }
}
