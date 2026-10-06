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
                        Text("实刻").font(.system(size: 36, weight: .semibold, design: .rounded)).tracking(2)
                        Text("VIMEMO / 视频转实况").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(StudioTheme.secondary)
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
                            Button(batchMode ? "完成" : "批量制作") { batchMode.toggle(); batchIDs = [] }
                                .font(.system(size: 13, weight: .semibold)).frame(minHeight: 44)
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
                        LazyVStack(spacing: 12) {
                            ForEach(store.projects) { project in
                                HStack(spacing: 0) {
                                    Button {
                                        if batchMode {
                                            if batchIDs.contains(project.id) { batchIDs.remove(project.id) } else { batchIDs.insert(project.id) }
                                        } else { editing = project }
                                    } label: { projectCard(project) }.buttonStyle(.plain)
                                    if !batchMode {
                                        Button { exportProjects = [project]; exportSelection = ExportSelection(projects: [project]) } label: {
                                            Image(systemName: "square.and.arrow.up").frame(width: 48, height: 64)
                                        }.accessibilityLabel("导出\(project.title)")
                                    }
                                }.padding(10).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(StudioTheme.line.opacity(0.6), lineWidth: 1))
                                    .contextMenu {
                                        Button("重命名", systemImage: "pencil") { renameText = project.title; renaming = project }
                                        Button("删除草稿", systemImage: "trash", role: .destructive) { deleting = project }
                                    }
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
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 18) {
                contactFrames
                VStack(alignment: .leading, spacing: 7) {
                    Text("新建作品").font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text("从一段视频，\n留下一张会动的照片。")
                        .font(.subheadline).foregroundStyle(StudioTheme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            PhotosPicker(selection: $selection, maxSelectionCount: 20, matching: .videos, preferredItemEncoding: .current) {
                HStack { Image(systemName: "plus"); Text("导入视频"); Spacer(); Image(systemName: "arrow.up.right") }
                    .font(.system(size: 16, weight: .semibold)).padding(.horizontal, 18).frame(minHeight: 54)
                    .foregroundStyle(.white).background(StudioTheme.accent, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityIdentifier("importVideos")
            HStack {
                Button { fileImporter = true } label: { Label("从文件导入", systemImage: "folder") }
                Spacer()
                Button { Task { if let demo = await store.importDemo() { editing = demo } } } label: { Label("试试示例", systemImage: "play.rectangle") }
            }.font(.system(size: 13, weight: .medium)).buttonStyle(.plain).frame(minHeight: 44)
        }.padding(20).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(StudioTheme.line, lineWidth: 1))
    }

    private var contactFrames: some View {
        HStack(spacing: 3) {
            ForEach(1...3, id: \.self) { index in
                if let url = Bundle.main.url(forResource: "Paywall-\(index)", withExtension: "jpg"), let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 24, height: 84).clipped()
                }
            }
        }.padding(5).background(StudioTheme.ink, in: RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .bottom) { Text("MOTION").font(.system(size: 6, design: .monospaced)).tracking(1).foregroundStyle(.white).offset(y: 12) }
            .padding(.bottom, 8).accessibilityHidden(true)
    }

    private func projectCard(_ project: VideoProject) -> some View {
        HStack(spacing: 14) {
            ThumbnailImage(url: store.url(for: project.thumbnailFilename)).frame(width: 76, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 8) {
                Text(project.title).font(.system(size: 15, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Text("\(project.clips.count) 个片段 · \(project.sizeLabel)").font(.caption).foregroundStyle(StudioTheme.secondary)
                Text(project.duration.timeLabel).font(.system(size: 11, design: .monospaced)).foregroundStyle(StudioTheme.accent)
            }
            Spacer(minLength: 0)
            if batchMode {
                Image(systemName: batchIDs.contains(project.id) ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(StudioTheme.accent)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(StudioTheme.ink)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton("工作台", symbol: "viewfinder", index: 0)
            tabButton("作品", symbol: "rectangle.stack", index: 1)
            tabButton("设置", symbol: "slider.horizontal.3", index: 2)
        }.padding(6).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(StudioTheme.line.opacity(0.7), lineWidth: 1))
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 8)
    }
    private func tabButton(_ title: String, symbol: String, index: Int) -> some View {
        Button { if tab == 0 && index != 0 { store.endWorkspaceSession(); batchIDs = []; batchMode = false }; tab = index } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 16))
                Text(title).font(.system(size: 12, weight: .semibold))
            }.frame(maxWidth: .infinity).frame(minHeight: 44)
                .foregroundStyle(tab == index ? .white : StudioTheme.secondary)
                .background(tab == index ? StudioTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityValue(tab == index ? "已选择" : "未选择")
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
