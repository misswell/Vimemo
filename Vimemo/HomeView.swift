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
    @State private var exportSelection: ExportSelection?
    private struct ExportSelection: Identifiable { let id = UUID(); let projects: [VideoProject] }
    @State private var deleting: VideoProject?
    @State private var renaming: VideoProject?
    @State private var renameText = ""

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
            .sheet(item: $exportSelection, onDismiss: { for project in exportProjects { store.endEditing(project.id) }; exportProjects = []; batchIDs = [] }) { selection in ExportSheet(projects: selection.projects) }
            .alert("需要处理", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("知道了") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
            .alert("重命名视频", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("视频名称", text: $renameText)
                Button("取消", role: .cancel) { renaming = nil }
                Button("保存") {
                    let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if var project = renaming, !title.isEmpty { project.title = title; store.update(project); store.persist() }
                    renaming = nil
                }
            }
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
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Vimemo").font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("实刻 · 视频转实况").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(StudioTheme.secondary)
                    }
                    Spacer()
                    Image(systemName: "viewfinder").font(.system(size: 32, weight: .ultraLight)).foregroundStyle(StudioTheme.accent)
                        .accessibilityHidden(true)
                }.padding(.top, 16)
                importCard
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("继续编辑").font(.system(size: 21, weight: .semibold, design: .rounded))
                            Text(store.savesDrafts ? "\(store.projects.count) 个草稿 · 自动保存已开启" : "草稿与本次编辑 · 自动保存已关闭")
                                .font(.caption).foregroundStyle(StudioTheme.secondary)
                        }
                        Spacer()
                        if !store.projects.isEmpty {
                            Button { batchMode.toggle(); batchIDs = [] } label: {
                                    Text(batchMode ? "完成" : "批量制作").font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 14).frame(minHeight: 44).contentShape(Capsule())
                                    .studioGlass(in: Capsule(), interactive: false, tint: StudioTheme.accent.opacity(0.14))
                            }.buttonStyle(.plain)
                        }
                    }
                    if store.projects.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("下一张实况，从这里开始").font(.system(size: 16, weight: .medium))
                            Text(store.savesDrafts ? "导入视频，选好片段。未完成的编辑会留在这里。" : "未开启保存草稿，返回时清理本次编辑文件。")
                                .font(.subheadline).foregroundStyle(StudioTheme.secondary).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 24)
                            .overlay(alignment: .top) { Rectangle().fill(StudioTheme.line).frame(height: 1) }
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(store.projects) { project in
                                ZStack(alignment: .topTrailing) {
                                    Button {
                                        if batchMode {
                                            if batchIDs.contains(project.id) { batchIDs.remove(project.id) } else { batchIDs.insert(project.id) }
                                        } else { editing = project }
                                    } label: { projectCard(project) }.buttonStyle(.plain)
                                        .accessibilityIdentifier("draft-\(project.id.uuidString)")
                                        .contextMenu {
                                            Button("重命名", systemImage: "pencil") { renameText = project.title; renaming = project }
                                            Button("删除草稿", systemImage: "trash", role: .destructive) { deleting = project }
                                        }
                                    if !batchMode {
                                        Button { exportProjects = [project]; exportSelection = ExportSelection(projects: [project]) } label: {
                                            Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44).foregroundStyle(.white).contentShape(Circle())
                                        }.studioGlassButton(circular: true, overImage: true).contentShape(Circle()).padding(8).zIndex(1).accessibilityLabel("导出\(project.title)")
                                    }
                                }.background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(StudioTheme.line.opacity(0.35), lineWidth: 1))
                            }
                        }
                    }
                    if batchMode {
                        PrimaryButton(title: "制作选中的 \(batchIDs.count) 个视频", symbol: "square.stack.3d.up") {
                            exportProjects = store.projects.filter { batchIDs.contains($0.id) }; exportSelection = ExportSelection(projects: exportProjects)
                        }.disabled(batchIDs.isEmpty || exporter.running).opacity(batchIDs.isEmpty ? 0.4 : 1)
                    }
                }
                Label("离线制作，原视频留在你的设备上", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(StudioTheme.secondary).padding(.bottom, 20)
            }.frame(maxWidth: 680).frame(maxWidth: .infinity).padding(.horizontal, 24)
        }.scrollIndicators(.hidden).foregroundStyle(StudioTheme.ink)
    }

    private var importCard: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $selection, maxSelectionCount: 20, matching: .videos, preferredItemEncoding: .current) {
                ZStack(alignment: .bottomLeading) {
                    if let url = Bundle.main.url(forResource: "DemoPoster", withExtension: "jpg"), let image = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: image).resizable().scaledToFill().frame(height: 230).clipped()
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("让这一刻，继续发生。").font(.system(size: 25, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        HStack {
                            Label("导入视频", systemImage: "plus").font(.system(size: 15, weight: .semibold))
                                .padding(.horizontal, 18).frame(height: 44).foregroundStyle(StudioTheme.onAccent)
                                .background(StudioTheme.accent, in: Capsule())
                            Spacer()
                            Text("本地制作 · 无水印").font(.caption).foregroundStyle(.white.opacity(0.8))
                        }
                    }.padding(22)
                }.frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 24))
            }.buttonStyle(.plain).accessibilityLabel("导入视频").accessibilityIdentifier("importVideos")
            HStack(spacing: 12) {
                Button { fileImporter = true } label: {
                    Label("从文件导入", systemImage: "folder").frame(maxWidth: .infinity).frame(minHeight: 46).contentShape(Capsule())
                        .studioGlass(in: Capsule(), interactive: false, tint: StudioTheme.accent.opacity(0.08))
                }.buttonStyle(.plain)
                Button { Task { if let demo = await store.importDemo() { editing = demo } } } label: {
                    Label("试试示例", systemImage: "play.rectangle").frame(maxWidth: .infinity).frame(minHeight: 46).contentShape(Capsule())
                        .studioGlass(in: Capsule(), interactive: false, tint: StudioTheme.accent.opacity(0.08))
                }.buttonStyle(.plain)
            }.font(.system(size: 13, weight: .medium)).foregroundStyle(StudioTheme.accent)
        }
    }

    private func projectCard(_ project: VideoProject) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ThumbnailImage(url: store.url(for: project.thumbnailFilename)).frame(height: 145).clipped()
                .overlay(alignment: .bottomLeading) {
                    Text(project.duration.timeLabel).font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 9).padding(.vertical, 5).foregroundStyle(.white)
                        .background(.black.opacity(0.5), in: Capsule()).padding(10)
                }
            VStack(alignment: .leading, spacing: 7) {
                Text(project.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text("\(project.clips.count) 个片段 · \(project.sizeLabel)").font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
            }.padding(12)
        }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(StudioTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(alignment: .topTrailing) {
                if batchMode {
                    Image(systemName: batchIDs.contains(project.id) ? "checkmark.circle.fill" : "circle").font(.title2)
                        .foregroundStyle(StudioTheme.accent).padding(12)
                }
            }
    }

    private var tabBar: some View {
        StudioGlassGroup(spacing: 4) {
            HStack(spacing: 4) {
                tabButton("工作台", symbol: "viewfinder", index: 0)
                tabButton("作品", symbol: "rectangle.stack", index: 1)
                tabButton("设置", symbol: "slider.horizontal.3", index: 2)
            }.padding(6).studioGlass(in: RoundedRectangle(cornerRadius: 24), interactive: false)
        }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 8)
    }
    private func tabButton(_ title: String, symbol: String, index: Int) -> some View {
        Button { if tab == 0 && index != 0 { store.endWorkspaceSession(); batchIDs = []; batchMode = false }; tab = index } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 16))
                Text(title).font(.system(size: 12, weight: .semibold))
            }.frame(maxWidth: .infinity).frame(minHeight: 54)
                .foregroundStyle(tab == index ? StudioTheme.accent : StudioTheme.secondary)
                .contentShape(RoundedRectangle(cornerRadius: 18))
                .studioGlass(in: RoundedRectangle(cornerRadius: 18), interactive: true, tint: tab == index ? StudioTheme.accent.opacity(0.16) : nil)
        }.buttonStyle(.plain).contentShape(RoundedRectangle(cornerRadius: 18))
            .accessibilityLabel(title)
            .accessibilityValue(tab == index ? "已选择" : "未选择")
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
