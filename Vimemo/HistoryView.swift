import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var selected: ExportRecord?
    @State private var deleting: ExportRecord?
    @State private var filter: OutputFormat?
    private var filtered: [ExportRecord] { store.exports.filter { filter == nil || $0.format == filter } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("\(store.exports.count) 个作品").font(.subheadline).foregroundStyle(StudioTheme.secondary)
                ScrollView(.horizontal) {
                    StudioGlassGroup(spacing: 8) {
                        HStack(spacing: 8) {
                            PillButton(title: "全部", selected: filter == nil) { filter = nil }
                            ForEach(OutputFormat.allCases) { item in PillButton(title: item.title, selected: filter == item) { filter = item } }
                        }
                    }
                }.scrollIndicators(.hidden)
                if filtered.isEmpty {
                    StudioCard {
                        VStack(spacing: 15) {
                            Image(systemName: "livephoto").font(.system(size: 46, weight: .ultraLight)).foregroundStyle(StudioTheme.accent)
                            Text(store.exports.isEmpty ? "第一张实况，等你来制作" : "这个格式还没有作品").font(.headline)
                            Text("在工作台导入视频，选好片段后制作。\n导出的作品会自动收藏在这里。").font(.caption).multilineTextAlignment(.center).foregroundStyle(StudioTheme.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 22) {
                        ForEach(filtered) { item in
                            Button { selected = item } label: {
                                VStack(alignment: .leading, spacing: 9) {
                                    ZStack(alignment: .bottomLeading) {
                                        ThumbnailImage(url: store.url(for: item.thumbnailFilename)).aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10))
                                        Label(item.format.title, systemImage: item.format.symbol).font(.system(size: 10, weight: .medium)).padding(7).foregroundStyle(.white).background(.black.opacity(0.6), in: Capsule()).padding(8)
                                    }
                                    Text(item.projectTitle).font(.subheadline.weight(.medium)).lineLimit(1)
                                    Text(item.createdAt.formatted(.dateTime.month().day().hour().minute())).font(.caption).foregroundStyle(StudioTheme.secondary)
                                }.foregroundStyle(StudioTheme.ink)
                            }.buttonStyle(.plain).contextMenu {
                                Button("查看 / 分享", systemImage: "square.and.arrow.up") { selected = item }
                                Button("删除本机作品", systemImage: "trash", role: .destructive) { deleting = item }
                            }
                        }
                    }
                }
            }.frame(maxWidth: 1000).frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
        }.scrollIndicators(.hidden).background(StudioTheme.background)
            .navigationTitle("片刻收藏").navigationBarTitleDisplayMode(.large)
            .sheet(item: $selected) { record in ExportDetailView(record: record) }
            .confirmationDialog("删除本机作品？照片图库中的作品不受影响。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("删除本机作品", role: .destructive) { if let deleting { store.delete(deleting) }; deleting = nil }
            }
    }
}

struct ExportDetailView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State var record: ExportRecord
    @State private var sharing = false
    @State private var saving = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            ZStack {
                StudioTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        MediaPreview(record: record).frame(height: 380).clipShape(RoundedRectangle(cornerRadius: 22))
                        VStack(alignment: .leading, spacing: 12) {
                            Text(record.projectTitle).font(.title3.bold())
                            Label(record.format.title, systemImage: record.format.symbol).font(.subheadline).foregroundStyle(StudioTheme.accent)
                            Text("\(record.createdAt.formatted()) · \(String(format: "%.2f", record.duration)) 秒").font(.caption).foregroundStyle(StudioTheme.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        PrimaryButton(title: "分享 / 存储到文件", symbol: "square.and.arrow.up") { sharing = true }
                        Button {
                            saving = true
                            Task {
                                defer { saving = false }
                                let media = ExportedMedia(directory: store.url(for: record.thumbnailFilename).deletingLastPathComponent(), urls: record.files.map { store.url(for: $0) }, thumbnailURL: store.url(for: record.thumbnailFilename), format: record.format, duration: record.duration)
                                var project = VideoProject(title: record.projectTitle, filename: "", thumbnailFilename: "", duration: record.duration, width: 0, height: 0, frameRate: 30, clips: [])
                                project.originalDate = record.originalDate
                                project.locationISO6709 = record.locationISO6709
                                project.settings.preserveDate = record.originalDate != nil
                                project.settings.preserveLocation = record.locationISO6709 != nil
                                do {
                                    try await LivePhotoExporter().saveToPhotos(media, project: project)
                                    record.savedToPhotos = true
                                    if let index = store.exports.firstIndex(where: { $0.id == record.id }) { store.exports[index] = record; store.persist() }
                                    message = "已保存到照片图库。"
                                } catch { message = error.localizedDescription }
                            }
                        } label: {
                            HStack { if saving { ProgressView() }; Label(record.savedToPhotos ? "再次保存到照片图库" : "保存到照片图库", systemImage: "square.and.arrow.down") }.font(.subheadline)
                        }.disabled(saving)
                    }.padding(20)
                }
            }.navigationTitle("作品").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
                .sheet(isPresented: $sharing) { ShareSheet(urls: record.files.map { store.url(for: $0) }) }
                .alert("照片图库", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("知道了") { message = nil } } message: { Text(message ?? "") }
        }
    }
}
