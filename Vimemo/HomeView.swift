import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var exporter: ExportCoordinator
    @State private var tab = 0
    @State private var selection: [PhotosPickerItem] = []
    @State private var fileImporter = false
    @State private var editing: VideoProject?
    @State private var editingID: UUID?
    @State private var batchMode = false
    @State private var batchIDs: Set<UUID> = []
    @State private var exportProjects: [VideoProject] = []
    @State private var showExport = false
    @State private var deleting: VideoProject?

    var body: some View {
        NavigationStack {
            ZStack {
                StudioTheme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    Group {
                        if tab == 0 { workspace }
                        else if tab == 1 { HistoryView() }
                        else { SettingsView() }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    tabBar
                }
                if store.importing {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    StudioCard {
                        VStack(spacing: 18) { ProgressView(); Text(store.importMessage).font(.subheadline) }
                            .padding(16)
                    }.padding(48)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $fileImporter, allowedContentTypes: [.movie, .video], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): Task {
                    let previous = store.projects.count
                    await store.importFiles(urls)
                    if urls.count == 1, store.projects.count > previous { editing = store.projects.first }
                }
                case .failure(let error): store.errorMessage = error.localizedDescription
                }
            }
            .onChange(of: selection) { _, items in
                Task {
                    let previous = store.projects.count
                    await store.importSelections(items)
                    selection = []
                    if items.count == 1, store.projects.count > previous { editing = store.projects.first }
                }
            }
            .fullScreenCover(item: $editing, onDismiss: {
                if let editingID { store.endEditing(editingID) }
                editingID = nil
            }) { project in
                EditorView(project: project).onAppear { editingID = project.id; store.beginEditing(project.id) }
            }
            .sheet(isPresented: $showExport, onDismiss: { store.endWorkspaceSession(); exportProjects = []; batchIDs = [] }) { ExportSheet(projects: exportProjects) }
            .alert("需要处理", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("知道了") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
            .confirmationDialog("删除这个草稿及其导入视频？已导出的作品会保留。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("删除草稿", role: .destructive) { if let deleting { store.delete(deleting) }; deleting = nil }
            }
            .task {
                if ProcessInfo.processInfo.arguments.contains("--demo-editor"), let demo = await store.importDemo() { editing = demo }
            }
        }
    }

    private var workspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                HStack {
                    HStack(spacing: 10) {
                        Image(systemName: "livephoto").font(.system(size: 29, weight: .light)).foregroundStyle(StudioTheme.accent)
                        Text("Vimemo").font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-1)
                    }
                    Spacer()
                    Text("实 刻").font(.system(size: 12, weight: .medium)).foregroundStyle(StudioTheme.secondary)
                }.padding(.top, 12)
                VStack(alignment: .leading, spacing: 11) {
                    Text("让这一刻，\n继续发生。").font(.system(size: 34, weight: .bold)).tracking(-1).lineSpacing(4)
                    Text("从一段视频，留住一张会动的照片。").font(.system(size: 14)).foregroundStyle(StudioTheme.secondary)
                }
                importCard
                HStack(spacing: 10) {
                    Button { fileImporter = true } label: {
                        Label("从文件导入", systemImage: "folder").font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 15)
                    }.background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    Button {
                        Task { if let demo = await store.importDemo() { editing = demo } }
                    } label: {
                        Label("试试示例", systemImage: "play.rectangle").font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 15)
                    }.background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                }.foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 17) {
                    HStack {
                        Text(store.savesDrafts ? "我的草稿" : "草稿与本次编辑").font(.system(size: 19, weight: .semibold))
                        Text("\(store.projects.count)").font(.caption.monospacedDigit()).foregroundStyle(StudioTheme.secondary)
                        Spacer()
                        if !store.projects.isEmpty {
                            Button(batchMode ? "完成" : "批量制作") {
                                batchMode.toggle(); batchIDs = []
                            }.font(.system(size: 13, weight: .medium))
                        }
                    }
                    if store.projects.isEmpty {
                        HStack(spacing: 16) {
                            Image(systemName: "rectangle.stack").font(.system(size: 28, weight: .ultraLight)).foregroundStyle(StudioTheme.secondary)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("下一张实况，从这里开始").font(.system(size: 14, weight: .medium))
                                Text(store.savesDrafts ? "导入视频后，编辑进度自动保存。" : "未开启保存草稿，返回时清理本次编辑文件。").font(.caption).foregroundStyle(StudioTheme.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(22).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                            ForEach(store.projects) { project in
                                Button {
                                    if batchMode {
                                        if batchIDs.contains(project.id) { batchIDs.remove(project.id) } else { batchIDs.insert(project.id) }
                                    } else { editing = project }
                                } label: { projectCard(project) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("重命名请在编辑器标题中修改", systemImage: "pencil") { editing = project }
                                    Button("删除草稿", systemImage: "trash", role: .destructive) { deleting = project }
                                }
                            }
                        }
                    }
                    if batchMode {
                        PrimaryButton(title: "制作选中的 \(batchIDs.count) 个视频", symbol: "square.stack.3d.up") {
                            exportProjects = store.projects.filter { batchIDs.contains($0.id) }
                            showExport = true
                        }.disabled(batchIDs.isEmpty || exporter.running).opacity(batchIDs.isEmpty ? 0.4 : 1)
                    }
                }
                Label("所有处理都在设备上完成", systemImage: "lock.shield").font(.caption).foregroundStyle(StudioTheme.secondary).frame(maxWidth: .infinity).padding(.bottom, 16)
            }.padding(.horizontal, 24)
        }.scrollIndicators(.hidden)
    }

    private var importCard: some View {
        PhotosPicker(selection: $selection, maxSelectionCount: 20, matching: .videos, preferredItemEncoding: .current) {
            ZStack(alignment: .bottomLeading) {
                GeometryReader { proxy in
                    if let url = Bundle.main.url(forResource: "DemoPoster", withExtension: "jpg"), let image = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped()
                    } else { StudioTheme.raised }
                }
                LinearGradient(colors: [.clear, StudioTheme.background.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 48) {
                    Label("VIDEO → LIVE", systemImage: "livephoto").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2)
                        .padding(.horizontal, 11).padding(.vertical, 7).background(.black.opacity(0.25), in: Capsule())
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("导入视频").font(.system(size: 24, weight: .semibold))
                            Text("挑一段回忆，把它变成实况").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                        }
                        Spacer()
                        Image(systemName: "plus").font(.system(size: 20, weight: .medium)).foregroundStyle(StudioTheme.background)
                            .frame(width: 48, height: 48).background(StudioTheme.accent, in: Circle())
                    }
                }.padding(22)
            }.frame(height: 208).clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.08), lineWidth: 1))
        }.buttonStyle(.plain).foregroundStyle(.white).accessibilityIdentifier("importVideos")
    }

    private func projectCard(_ project: VideoProject) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomLeading) {
                ThumbnailImage(url: store.url(for: project.thumbnailFilename))
                    .frame(height: 132).clipped().clipShape(RoundedRectangle(cornerRadius: 15))
                Text(project.duration.timeLabel).font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 5).background(.black.opacity(0.6), in: Capsule()).padding(9)
                if batchMode {
                    Image(systemName: batchIDs.contains(project.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(StudioTheme.accent).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(9)
                }
            }
            Text(project.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
            Text("\(project.clips.count) 个片段 · \(project.sizeLabel)").font(.system(size: 10)).foregroundStyle(StudioTheme.secondary)
        }.foregroundStyle(.white)
    }

    private var tabBar: some View {
        HStack {
            tabButton("工作台", symbol: "square.grid.2x2", index: 0)
            tabButton("作品", symbol: "livephoto", index: 1)
            tabButton("设置", symbol: "slider.horizontal.3", index: 2)
        }.padding(.top, 13).padding(.bottom, 8).background(StudioTheme.background)
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
    }
    private func tabButton(_ title: String, symbol: String, index: Int) -> some View {
        Button { if tab == 0 && index != 0 { store.endWorkspaceSession(); batchIDs = [] }; tab = index } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 19, weight: tab == index ? .semibold : .regular))
                Text(title).font(.system(size: 10, weight: .medium))
            }.foregroundStyle(tab == index ? StudioTheme.accent : StudioTheme.secondary).frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
    }
}

struct ThumbnailImage: View {
    var url: URL
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else { StudioTheme.raised.overlay { Image(systemName: "photo").foregroundStyle(StudioTheme.secondary) } }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.task(id: url) {
            image = await Task.detached(priority: .utility) { UIImage(contentsOfFile: url.path) }.value
        }
    }
}
