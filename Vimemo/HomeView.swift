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
    @State private var deletingIDs: Set<UUID>?
    @State private var renaming: VideoProject?
    @State private var renameText = ""

    var body: some View {
        ZStack {
            tabs
            if store.importing {
                Color.black.opacity(0.6).ignoresSafeArea()
                StudioCard {
                    VStack(spacing: 18) {
                        if let fraction = store.importFraction { ProgressView(value: fraction) }
                        else { ProgressView() }
                        Text(store.importMessage).font(.subheadline)
                        if store.canCancelPickerImport {
                            Text("iCloud 中的视频需要先下载，下载时间取决于网络和文件大小。")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("取消下载", role: .cancel) { store.cancelPickerImport() }
                        }
                    }
                        .padding(16)
                }.padding(48)
            }
        }
        .background {
            #if DEBUG
            if usesScrollFixture { ScrollPerformanceProbe().frame(width: 1, height: 1) }
            #endif
        }
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
            if !store.retrySelections.isEmpty {
                Button("重试导入") {
                    let items = store.retrySelections
                    Task {
                        let previous = store.projects.count
                        await store.importSelections(items)
                        if items.count == 1, store.projects.count > previous { editing = store.projects.first }
                    }
                }
            }
            Button("知道了") { store.errorMessage = nil; store.dismissPickerRetry() }
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
        .confirmationDialog("删除所选的 \(deletingIDs?.count ?? 0) 个草稿？", isPresented: Binding(get: { deletingIDs != nil }, set: { if !$0 { deletingIDs = nil } }), titleVisibility: .visible, presenting: deletingIDs) { ids in
            Button("删除 \(ids.count) 个草稿", role: .destructive) {
                if store.deleteProjects(ids: ids) { batchIDs = []; batchMode = false }
                deletingIDs = nil
            }.accessibilityIdentifier("confirmDeleteDrafts")
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("将删除所选草稿及其导入副本。已导出的作品和照片图库中的原视频会保留。")
        }
        .onChange(of: store.projects.map(\.id)) { _, ids in batchIDs.formIntersection(Set(ids)) }
        .task {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let libraryIndex = args.firstIndex(of: "--test-library"), libraryIndex + 1 < args.count,
               UUID(uuidString: args[libraryIndex + 1]) != nil,
               let videoIndex = args.firstIndex(of: "--test-editor-video"), videoIndex + 1 < args.count {
                do { editing = try await store.importVideo(URL(fileURLWithPath: args[videoIndex + 1]), title: "声音测试") }
                catch { store.errorMessage = error.localizedDescription }
                return
            }
            await store.prepareBatchDeletionFixture()
            if usesScrollFixture, let demo = await store.importDemo() {
                store.projects = (0..<24).map { i in var item = demo; item.id = UUID(); item.title = "滚动示例 \(i)"; return item }
            }
            #endif
            if ProcessInfo.processInfo.arguments.contains("--demo-editor"), let demo = await store.importDemo() { editing = demo }
        }
    }

    #if DEBUG
    private var usesScrollFixture: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--scroll-fixture"), let index = args.firstIndex(of: "--test-library"),
              args.count > index + 1, UUID(uuidString: args[index + 1]) != nil else { return false }
        return true
    }
    #endif

    private var workspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                importCard
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最近添加").font(.title2.bold())
                            Text(store.savesDrafts ? "\(store.projects.count) 个草稿 · 自动保存已开启" : "草稿与本次编辑 · 自动保存已关闭")
                                .font(.caption).foregroundStyle(StudioTheme.secondary)
                        }
                        Spacer()
                        if !store.projects.isEmpty {
                            Button { batchMode.toggle(); batchIDs = [] } label: {
                                    Text(batchMode ? "完成" : "选择").font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 14).frame(minHeight: 44).contentShape(Capsule())
                                    .studioGlass(in: Capsule(), interactive: false, tint: StudioTheme.accent.opacity(0.14))
                            }.buttonStyle(.plain).accessibilityIdentifier("draftSelectionMode")
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
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 22) {
                            ForEach(store.projects) { project in
                                Button {
                                    if batchMode {
                                        if batchIDs.contains(project.id) { batchIDs.remove(project.id) } else { batchIDs.insert(project.id) }
                                    } else { editing = project }
                                } label: { projectCard(project) }.buttonStyle(.plain)
                                    .accessibilityIdentifier("draft-\(project.id.uuidString)")
                                    .accessibilityValue(batchMode ? (batchIDs.contains(project.id) ? "已选择" : "未选择") : "")
                                    .contextMenu {
                                        if !batchMode {
                                            Button("重命名", systemImage: "pencil") { renameText = project.title; renaming = project }
                                            Button("删除草稿", systemImage: "trash", role: .destructive) { deletingIDs = [project.id] }
                                        }
                                    }
                            }
                        }
                    }
                }
                Label("离线制作，原视频留在你的设备上", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(StudioTheme.secondary).padding(.bottom, 20)
            }.frame(maxWidth: 1000).frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.top, 12)
        }.scrollIndicators(.hidden).foregroundStyle(StudioTheme.ink)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if batchMode {
                    SelectionActions(count: batchIDs.count, total: store.projects.count, identifier: "draft",
                                     onSelectAll: { batchIDs = batchIDs.count == store.projects.count ? [] : Set(store.projects.map(\.id)) },
                                     onDelete: { deletingIDs = batchIDs }, exportDisabled: exporter.running,
                                     onExport: {
                        exportProjects = store.projects.filter { batchIDs.contains($0.id) }
                        exportSelection = ExportSelection(projects: exportProjects)
                    })
                }
            }
            .background(StudioTheme.background)
            .navigationTitle("工作台")
            .navigationBarTitleDisplayMode(.large)
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("视频转实况").font(.subheadline.weight(.semibold)).foregroundStyle(StudioTheme.accent)
            PhotosPicker(selection: $selection, maxSelectionCount: 20, matching: .videos, preferredItemEncoding: .current) {
                ZStack(alignment: .bottomLeading) {
                    if let url = Bundle.main.url(forResource: "DemoPoster", withExtension: "jpg") {
                        ThumbnailImage(url: url, maxPixelSize: 1280)
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("让这一刻，继续发生。")
                            .font(.title2.bold()).foregroundStyle(.white)
                        Label("导入视频", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    }.padding(20)
                }.frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("导入视频").accessibilityIdentifier("importVideos")
            HStack(spacing: 12) {
                Button { fileImporter = true } label: {
                    Label("从文件导入", systemImage: "folder").frame(maxWidth: .infinity).frame(minHeight: 46)
                }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                Button { Task { if let demo = await store.importDemo() { editing = demo } } } label: {
                    Label("试试示例", systemImage: "play.fill").frame(maxWidth: .infinity).frame(minHeight: 46)
                }.buttonStyle(.bordered).buttonBorderShape(.capsule)
            }.font(.subheadline.weight(.semibold)).foregroundStyle(StudioTheme.accent).tint(StudioTheme.accent)
        }
    }

    private func projectCard(_ project: VideoProject) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ThumbnailImage(url: store.url(for: project.thumbnailFilename)).aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottomLeading) {
                    Text(project.duration.timeLabel).font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 9).padding(.vertical, 5).foregroundStyle(.white)
                        .background(.black.opacity(0.5), in: Capsule()).padding(10)
                }
            VStack(alignment: .leading, spacing: 7) {
                Text(project.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text("\(project.clips.count) 个片段 · \(project.sizeLabel)").font(.caption).foregroundStyle(StudioTheme.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).foregroundStyle(StudioTheme.ink)
            .overlay(alignment: .topTrailing) {
                if batchMode {
                    Image(systemName: batchIDs.contains(project.id) ? "checkmark.circle.fill" : "circle").font(.title2)
                        .foregroundStyle(StudioTheme.accent).padding(12)
                }
            }
    }

    private var tabs: some View {
        nativeTabs.studioTabBarBehavior()
            .tint(StudioTheme.accent)
            .onChange(of: tab) { previous, current in
                if previous == 0 && current != 0 {
                    store.endWorkspaceSession(); batchIDs = []; batchMode = false
                }
            }
    }

    private var nativeTabs: some View {
        TabView(selection: $tab) {
            Tab("工作台", systemImage: "house", value: 0) {
                NavigationStack { workspace }
            }
            Tab("作品", systemImage: "square.stack", value: 1) {
                NavigationStack { HistoryView() }
            }
            Tab("设置", systemImage: "gearshape", value: 2) {
                NavigationStack { SettingsView() }
            }
        }
    }

}
