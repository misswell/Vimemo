import SwiftUI
import AVKit

struct EditorView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var exporter: ExportCoordinator
    @Environment(\.dismiss) private var dismiss
    @State var project: VideoProject
    @State private var activeClipID: UUID
    @State private var thumbnails: [UIImage] = []
    @StateObject private var framePreview = CoverPreview()
    @StateObject private var cropPreview = CoverPreview()
    @State private var cropDragging = false
    @State private var frameSettings: EditSettings?
    @State private var timelineSeeking = false
    @State private var player = AVPlayer()
    @State private var preparedPreview: VideoPreview?
    @State private var playerFrameReady = false
    @State private var playing = false
    @GestureState private var previewHeld = false
    @State private var accessiblePlayback = false
    @State private var playbackGeneration = UUID()
    @State private var tool = 0
    @State private var showExport = false
    @State private var showRename = false
    @State private var showReset = false
    @State private var showCoverPicker = false
    @State private var titleDraft = ""
    @State private var previewTask: Task<Void, Never>?
    @State private var playerObserver: NSObjectProtocol?
    @State private var previewGeneration = UUID()
    #if DEBUG
    @State private var holdPlaybackCount = 0
    @State private var countedHoldGeneration: UUID?
    @State private var gestureObserver: Any?
    private var testsPreviewGestures: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--test-preview-gestures"), let index = args.firstIndex(of: "--test-library"), index + 1 < args.count else { return false }
        return UUID(uuidString: args[index + 1]) != nil
    }
    #endif

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

    private var croppingEnabled: Bool { tool == 1 || project.settings.effectiveCropZoom > 1 }
    private struct CropSource: Equatable {
        let settings: EditSettings
        let time: Double
        let photo: String?
        let seeking: Bool
    }
    private var cropSource: CropSource {
        var settings = project.settings
        settings.ratio = .original; settings.cropX = 0.5; settings.cropY = 0.5; settings.cropZoom = nil
        return CropSource(settings: settings, time: timelineSeeking ? 0 : clip.cover, photo: clip.coverPhotoFilename, seeking: timelineSeeking)
    }
    private var cropPositionDescription: String {
        "水平 \(Int((project.settings.cropX * 100).rounded()))%，垂直 \(Int((project.settings.cropY * 100).rounded()))%，缩放 \(String(format: "%.2f", project.settings.effectiveCropZoom))倍"
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
                        let canvasWidth = geometry.size.width * 0.46
                        let canvasSize = CGSize(width: canvasWidth,
                                                height: max(canvasWidth * 9 / 16, min(520, max(260, geometry.size.height - 92))))
                        let previewSize = previewSize(availableWidth: canvasSize.width, maxHeight: canvasSize.height)
                        HStack(alignment: .top, spacing: 24) {
                            VStack(spacing: 12) {
                                preview(imageSize: previewSize, canvasSize: canvasSize)
                                coverControls
                            }.frame(width: geometry.size.width * 0.46)
                            editorPanels
                        }.padding(.horizontal, 24).padding(.vertical, 12)
                    } else {
                        let canvasWidth = geometry.size.width - 32
                        let canvasSize = CGSize(width: canvasWidth,
                                                height: max(canvasWidth * 9 / 16, min(320, max(160, geometry.size.height * 0.38))))
                        let previewSize = previewSize(availableWidth: canvasSize.width, maxHeight: canvasSize.height)
                        VStack(spacing: 0) {
                            preview(imageSize: previewSize, canvasSize: canvasSize)
                                .padding(.top, 6)
                            coverControls.padding(.horizontal, 20).padding(.vertical, 8)
                            editorPanels
                        }
                    }
                }
                #if DEBUG
                if testsPreviewGestures {
                    Text("预览播放检测").font(.system(size: 1)).frame(width: 1, height: 1).opacity(0.01)
                        .accessibilityIdentifier("holdPreviewReport").accessibilityValue(String(holdPlaybackCount)).allowsHitTesting(false)
                }
                #endif
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
                        stopPlayback(); store.update(project); store.persist(); showExport = true
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
                #if DEBUG
                if testsPreviewGestures, gestureObserver == nil {
                    gestureObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { time in
                        Task { @MainActor in
                            if previewHeld && playing && playerFrameReady && player.rate > 0,
                               time.seconds > clip.start + 0.1, countedHoldGeneration != playbackGeneration {
                                countedHoldGeneration = playbackGeneration; holdPlaybackCount += 1
                            }
                        }
                    }
                }
                #endif
                await loadThumbnails()
                refreshPreview()
            }
            .onChange(of: project.settings) { previous, current in
                for index in project.clips.indices { project.clips[index].normalize(sourceDuration: project.duration, speed: project.settings.speed, maxOutputDuration: project.settings.maxOutputDuration) }
                store.update(project)
                player.isMuted = current.muted
                var previousPicture = previous
                previousPicture.muted = current.muted
                if previousPicture != current && !cropDragging { refreshPreview() }
            }
            .task(id: cropSource) {
                let selection = cropSource
                if selection.seeking { cropPreview.stop(); return }
                var snapshot = project; snapshot.settings = selection.settings
                let source = sourceURL, selectedClip = clip
                cropPreview.configure { _, photo, _ in
                    try await MediaProcessor.uncroppedCover(source: source, project: snapshot, clip: selectedClip, photo: photo)
                }
                cropPreview.request(time: selection.time, photo: selection.photo.map { store.url(for: $0) })
            }
            .onChange(of: tool) { _, _ in
                if cropDragging { cropDragging = false; refreshPreview() }
            }
            .onChange(of: cropPreview.errorMessage) { _, message in
                if let message { store.errorMessage = "构图预览失败：\(message)" }
            }
            .onChange(of: project.clips) { previous, _ in
                store.update(project)
                let oldClip = previous.first { $0.id == activeClipID }
                if oldClip?.start == clip.start, oldClip?.end == clip.end {
                    if !timelineSeeking { seekFrame(clip.cover) }
                } else { refreshPreview(seekCover: !timelineSeeking) }
            }
            .onChange(of: framePreview.errorMessage) { _, message in
                if let message { store.errorMessage = "封面预览失败：\(message)" }
            }
            .onChange(of: previewHeld) { _, held in
                accessiblePlayback = false
                if held && !cropDragging { startPlayback() } else { stopPlayback() }
            }
            .onChange(of: project.title) { _, _ in store.update(project) }
            .onChange(of: activeClipID) { _, _ in refreshPreview() }
            .onDisappear {
                #if DEBUG
                if let gestureObserver { player.removeTimeObserver(gestureObserver); self.gestureObserver = nil }
                #endif
                stopPlayback(); previewTask?.cancel(); framePreview.stop(); cropPreview.stop()
                previewGeneration = UUID(); preparedPreview = nil
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
                } else { toolPanel }
            }.frame(maxWidth: 680).frame(maxWidth: .infinity)
                .padding(.horizontal, 16).padding(.vertical, 12)
        }.scrollIndicators(.hidden).accessibilityIdentifier("editorScroll")
    }

    private func preview(imageSize: CGSize, canvasSize: CGSize) -> some View {
        let badgesOverImage = imageSize.width >= canvasSize.width - 1 && imageSize.height >= canvasSize.height - 26
        let badgeColor: Color = badgesOverImage ? .white : StudioTheme.ink
        return ZStack {

            ZStack(alignment: .topLeading) {
                Color.black
                PreviewSurface(player: player, preview: preparedPreview, playing: playing) { ready in playerFrameReady = ready }
                if !playing || !playerFrameReady {
                    if cropPreview.isSettled, let image = cropPreview.image {
                        CropPositionPreview(image: image, x: project.settings.cropX, y: project.settings.cropY,
                                            zoom: project.settings.effectiveCropZoom, editing: cropDragging)
                    } else if let coverImage = framePreview.image {
                        Image(uiImage: coverImage).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else { ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
            }.frame(width: imageSize.width, height: imageSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(StudioTheme.line, lineWidth: 1))
                .contentShape(Rectangle())
                .overlay {
                    CropGestureSurface(imageSize: cropPreview.image?.size ?? previewDimensions,
                                       x: $project.settings.cropX, y: $project.settings.cropY, zoom: $project.settings.cropZoom,
                                       canPan: croppingEnabled, ready: cropPreview.isSettled,
                                       onEditing: { editing in
                                           cropDragging = editing
                                           if editing { stopPlayback() } else { refreshPreview() }
                                       })
                }
                .accessibilityElement(children: .ignore).accessibilityAddTraits(.isButton)
                .accessibilityLabel(playing ? "松手返回封面" : (croppingEnabled ? "拖动调整裁剪位置" : "按住预览实况"))
                .accessibilityValue(playing ? "正在播放" : (croppingEnabled ? (cropPreview.isSettled ? cropPositionDescription : "正在准备裁剪画面") : "封面"))
                .accessibilityHint("双指缩放，双击居中并恢复1倍；构图时可拖动，按住播放，松手停止。使用旁白时双击切换播放。")
                .accessibilityAction(named: Text("回正画面")) { recenterPicture() }
                .accessibilityAction {
                    if playing { stopPlayback() }
                    else { accessiblePlayback = true; startPlayback() }
                }.accessibilityIdentifier("previewPlayback")
            Label("LIVE", systemImage: playing ? "livephoto.play" : "livephoto")
                .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1)
                .foregroundStyle(badgeColor).shadow(color: badgesOverImage ? .black.opacity(0.65) : .clear, radius: 3, y: 1)
                .padding(13).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false).accessibilityIdentifier("previewLiveBadge")
            Text(String(format: "%.2f s", clip.duration / project.settings.speed))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(badgeColor).shadow(color: badgesOverImage ? .black.opacity(0.65) : .clear, radius: 3, y: 1)
                .padding(13).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .allowsHitTesting(false).accessibilityIdentifier("previewDurationBadge")
            Button {
                project.settings.muted.toggle()
                player.isMuted = project.settings.muted
            } label: {
                Image(systemName: project.settings.muted || !project.hasAudio ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 17)).foregroundStyle(badgeColor)
                    .shadow(color: badgesOverImage ? .black.opacity(0.65) : .clear, radius: 3, y: 1)
                    .frame(width: 44, height: 44).contentShape(Circle())
            }.buttonStyle(.plain).padding(13)
                .highPriorityGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in })
                .disabled(!project.hasAudio)
                .accessibilityLabel(project.hasAudio ? (project.settings.muted ? "开启作品声音" : "静音作品") : "原视频没有声音")
                .accessibilityValue(project.settings.muted || !project.hasAudio ? "静音" : "有声")
                .accessibilityHint("轻点切换作品声音，按住预览实况")
                .accessibilityIdentifier("previewSound")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }.frame(width: canvasSize.width, height: canvasSize.height)
            .contentShape(Rectangle())
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.35, maximumDistance: 6)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .updating($previewHeld) { value, held, _ in
                    if case .second(true, _) = value { held = true }
                })
            .accessibilityElement(children: .contain).accessibilityIdentifier("editorPreview")
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
                TimelineView(clip: clipBinding, duration: project.duration, speed: project.settings.speed, maxOutputDuration: project.settings.maxOutputDuration, thumbnails: thumbnails, frameRate: project.frameRate) { time, editing in
                    timelineSeeking = editing
                    seekFrame(time, scrubbing: editing)
                }
                if project.settings.maxOutputDuration == nil {
                    Button("使用整段视频") {
                        var value = clip; value.start = 0; value.end = project.duration
                        value.normalize(sourceDuration: project.duration, speed: project.settings.speed, maxOutputDuration: nil)
                        project.clips[clipIndex] = value
                    }.font(.system(size: 12, weight: .medium)).accessibilityIdentifier("useFullVideo")
                }
                FrameSelectionControl(time: Binding(get: { clip.cover }, set: { time in
                    project.clips[clipIndex].coverPhotoFilename = nil
                    project.clips[clipIndex].cover = time
                }), range: clip.start...max(clip.start, clip.end - 1 / max(1, project.frameRate)), frameRate: project.frameRate, photoCover: clip.coverPhotoFilename != nil, identifierPrefix: "timeline") { time, editing in
                    timelineSeeking = editing
                    seekFrame(time, scrubbing: editing)
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
                } label: {
                    Image(systemName: direction == -1 ? "minus" : "plus")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(StudioTheme.accent)
                        .frame(width: 28, height: 28)
                        .background(StudioTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(isStart ? "入点" : "出点")\(direction == -1 ? "前移" : "后移")一帧")
            }
        }.buttonStyle(.plain)
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
                    stopPlayback(); showCoverPicker = true
                } label: {
                    Label("选择封面", systemImage: "photo.on.rectangle").font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16).frame(minHeight: 44).contentShape(Capsule())
                }.studioGlassButton().accessibilityIdentifier("chooseCover")
                Spacer(minLength: 0)
                if clip.coverPhotoFilename != nil {
                    Text("已使用相册照片作为封面").font(.system(size: 10)).foregroundStyle(StudioTheme.secondary).lineLimit(2)
                }
            }.buttonStyle(.plain)
        }
    }
    private func resetPicture() {
        project.settings.ratio = .original; project.settings.rotation = 0; project.settings.mirrored = false
        project.settings.look = .original; project.settings.exposure = 0; project.settings.contrast = 1; project.settings.saturation = 1
        recenterPicture()
    }
    private func recenterPicture() {
        stopPlayback(); project.settings.cropX = 0.5; project.settings.cropY = 0.5; project.settings.cropZoom = nil
    }
    @ViewBuilder private var toolPanel: some View {
        switch tool {
        case 1: cropPanel
        case 2: colorPanel
        default: playbackPanel
        }
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
                Text("双指缩放 · 双击回正 · 拖动构图 · 按住预览")
                        .font(.caption).foregroundStyle(StudioTheme.secondary)
                    DisclosureGroup("精确位置") {
                        adjustment("水平位置", value: $project.settings.cropX, range: 0...1).padding(.top, 8)
                        adjustment("垂直位置", value: $project.settings.cropY, range: 0...1)
                    }.font(.caption)
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
    private func seekFrame(_ time: Double, scrubbing: Bool = false) {
        stopPlayback()
        if frameSettings != project.settings {
            let renderer = CoverFrameRenderer(source: sourceURL, project: project)
            framePreview.configure(cancel: { Task { await renderer.cancel() } }) { time, photo, exact in
                try await renderer.frame(time: time, photo: photo, exact: exact)
            }
            frameSettings = project.settings
        }
        framePreview.request(time: time, photo: clip.coverPhotoFilename.map { store.url(for: $0) }, exact: !scrubbing)
    }
    private func refreshPreview(seekCover: Bool = true) {
        stopPlayback()
        if seekCover { seekFrame(clip.cover) }
        previewTask?.cancel()
        preparedPreview = nil
        let generation = UUID(); previewGeneration = generation
        let source = sourceURL, currentClip = clip
        var settings = project.settings
        settings.muted = false // Keep the source track; the project's speaker control mutes the player.
        previewTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(180))
                let prepared = try await MediaProcessor.previewItem(source: source, clip: currentClip, settings: settings)
                let item = prepared.item
                guard !Task.isCancelled, previewGeneration == generation else { return }
                player.replaceCurrentItem(with: item)
                player.isMuted = project.settings.muted
                preparedPreview = prepared
                if previewHeld && !cropDragging { startPlayback() }
                if let playerObserver { NotificationCenter.default.removeObserver(playerObserver) }
                playerObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                    Task { @MainActor in
                        guard previewGeneration == generation else { return }
                        if previewHeld && !cropDragging { startPlayback() } else { stopPlayback() }
                    }
                }
            } catch is CancellationError {} catch { store.errorMessage = "动态预览失败：\(error.localizedDescription)" }
        }
    }
    private func startPlayback() {
        guard let prepared = preparedPreview, player.currentItem === prepared.item else { return }
        let generation = UUID(); playbackGeneration = generation
        player.isMuted = project.settings.muted
        playing = true
        player.seek(to: prepared.start, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            Task { @MainActor in
                guard playbackGeneration == generation, playing, previewHeld || accessiblePlayback else { return }
                guard finished, player.currentItem?.status != .failed else {
                    stopPlayback()
                    if let error = player.currentItem?.error { store.errorMessage = "预览播放失败：\(error.localizedDescription)" }
                    return
                }
                player.playImmediately(atRate: prepared.rate)
            }
        }
    }
    private func stopPlayback() {
        playbackGeneration = UUID()
        accessiblePlayback = false
        playing = false
        player.pause()
    }
}
