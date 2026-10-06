import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers
import CoreTransferable
import ImageIO

struct ImportedMovie: Transferable {
    let url: URL
    let name: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VimemoImports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: target)
            return ImportedMovie(url: target, name: received.file.deletingPathExtension().lastPathComponent)
        }
    }
}

@MainActor final class ProjectStore: ObservableObject {
    @Published var projects: [VideoProject] = []
    @Published var exports: [ExportRecord] = []
    @Published var importing = false
    @Published var importMessage = ""
    @Published var errorMessage: String?
    let root: URL
    private var saveTask: Task<Void, Never>?
    private struct Library: Codable { var projects: [VideoProject]; var exports: [ExportRecord] }

    init(root: URL? = nil) {
        var defaultRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Vimemo", isDirectory: true)
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--test-library"), arguments.count > index + 1,
           let id = UUID(uuidString: arguments[index + 1]) {
            defaultRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VimemoUITests/\(id.uuidString)", isDirectory: true)
        }
        #endif
        self.root = root ?? defaultRoot
        do {
            try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
            let index = self.root.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath: index.path) {
                let saved = try JSONDecoder().decode(Library.self, from: Data(contentsOf: index))
                projects = saved.projects
                exports = saved.exports
            }
        } catch {
            let index = self.root.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath: index.path) {
                try? FileManager.default.copyItem(at: index, to: self.root.appendingPathComponent("library-recovery-\(UUID().uuidString).json"))
            }
            errorMessage = "草稿库读取失败：\(error.localizedDescription)。原文件已保留为恢复副本。"
        }
    }

    func url(for filename: String) -> URL { root.appendingPathComponent(filename) }
    func setUnlimitedDuration(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "unlimitedDuration")
        for index in projects.indices {
            projects[index].settings.unlimitedDuration = enabled
            for clipIndex in projects[index].clips.indices {
                projects[index].clips[clipIndex].normalize(sourceDuration: projects[index].duration, speed: projects[index].settings.speed, maxOutputDuration: projects[index].settings.maxOutputDuration)
            }
        }
        persist()
    }

    func importCoverPhoto(_ data: Data, project: VideoProject) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 4096] as CFDictionary),
              let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.95) else {
            throw StudioError.message("无法读取这张照片，请选择另一张图片。")
        }
        let filename = "Projects/\(project.id.uuidString)/cover-\(UUID().uuidString).jpg"
        try jpeg.write(to: url(for: filename), options: .atomic)
        return filename
    }
    func persist() {
        do {
            let data = try JSONEncoder().encode(Library(projects: projects, exports: exports))
            try data.write(to: root.appendingPathComponent("library.json"), options: .atomic)
        } catch { errorMessage = "草稿保存失败：\(error.localizedDescription)" }
    }
    func update(_ project: VideoProject) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = project
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.persist()
        }
    }
    func delete(_ project: VideoProject) {
        projects.removeAll { $0.id == project.id }
        persist()
        try? FileManager.default.removeItem(at: url(for: project.filename).deletingLastPathComponent())
    }
    func delete(_ export: ExportRecord) {
        exports.removeAll { $0.id == export.id }
        persist()
        if let first = export.files.first { try? FileManager.default.removeItem(at: url(for: first).deletingLastPathComponent()) }
    }

    func importSelections(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty, !importing else { return }
        importing = true
        defer { importing = false }
        var failures: [String] = []
        for (index, item) in items.enumerated() {
            importMessage = "正在导入 \(index + 1) / \(items.count)…"
            do {
                guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else { throw StudioError.message("无法下载视频，请确认 iCloud 原片可以读取。") }
                defer { try? FileManager.default.removeItem(at: movie.url) }
                _ = try await importVideo(movie.url, title: movie.name.isEmpty ? nil : movie.name)
            } catch { failures.append("第 \(index + 1) 个视频：\(error.localizedDescription)") }
        }
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
    }

    func importFiles(_ urls: [URL]) async {
        guard !importing else { return }
        importing = true
        defer { importing = false }
        var failures: [String] = []
        for (index, source) in urls.enumerated() {
            importMessage = "正在导入 \(index + 1) / \(urls.count)…"
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            do { _ = try await importVideo(source, title: source.deletingPathExtension().lastPathComponent) }
            catch { failures.append("\(source.lastPathComponent)：\(error.localizedDescription)") }
        }
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
    }

    @discardableResult func importDemo() async -> VideoProject? {
        if let existing = projects.first(where: { $0.title == "海边的最后一束光" }) { return existing }
        guard let source = Bundle.main.url(forResource: "Demo", withExtension: "mov") else { errorMessage = "示例视频暂不可用。"; return nil }
        importing = true
        importMessage = "正在准备示例…"
        defer { importing = false }
        do { return try await importVideo(source, title: "海边的最后一束光") }
        catch { errorMessage = error.localizedDescription; return nil }
    }

    @discardableResult func importVideo(_ source: URL, title: String?) async throws -> VideoProject {
        let id = UUID()
        let folder = root.appendingPathComponent("Projects/\(id.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: folder) } }
        let filename = "Projects/\(id.uuidString)/source.\(source.pathExtension.isEmpty ? "mov" : source.pathExtension)"
        try FileManager.default.copyItem(at: source, to: url(for: filename))
        let asset = AVURLAsset(url: url(for: filename))
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration >= 0.1, let track = try await asset.loadTracks(withMediaType: .video).first else { throw StudioError.message("请选择时长至少 0.1 秒、可播放的视频。") }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let oriented = size.applying(transform)
        let rawFrameRate = try await track.load(.nominalFrameRate)
        let frameRate = rawFrameRate.isFinite && rawFrameRate > 0 ? rawFrameRate : 30
        let thumbnailFilename = "Projects/\(id.uuidString)/thumbnail.jpg"
        let frame = try await MediaProcessor.frame(url: url(for: filename), time: min(0.5, duration / 2))
        guard let jpeg = UIImage(cgImage: frame).jpegData(compressionQuality: 0.8) else { throw StudioError.message("无法生成视频缩略图。") }
        try jpeg.write(to: url(for: thumbnailFilename))
        var date: Date?, location: String?
        let metadata = try await asset.load(.metadata)
        for item in metadata {
            if item.identifier == .quickTimeMetadataCreationDate || item.commonKey == .commonKeyCreationDate {
                if let value = try? await item.load(.stringValue) { date = ISO8601DateFormatter().date(from: value) }
            }
            if item.identifier == .quickTimeMetadataLocationISO6709 { location = try? await item.load(.stringValue) }
        }
        let unlimitedDuration = UserDefaults.standard.bool(forKey: "unlimitedDuration")
        let end = unlimitedDuration ? duration : min(3, duration)
        var project = VideoProject(id: id, title: title ?? "视频 · \(Date().formatted(.dateTime.month().day().hour().minute()))", filename: filename, thumbnailFilename: thumbnailFilename, duration: duration, width: abs(oriented.width), height: abs(oriented.height), frameRate: Double(frameRate), originalDate: date, locationISO6709: location, clips: [Clip(start: 0, end: end, cover: end / 2)])
        project.settings.quality = ExportQuality(rawValue: UserDefaults.standard.string(forKey: "defaultQuality") ?? "") ?? .high
        project.settings.preserveDate = UserDefaults.standard.object(forKey: "defaultPreserveDate") as? Bool ?? true
        project.settings.preserveLocation = UserDefaults.standard.bool(forKey: "defaultPreserveLocation")
        project.settings.muted = UserDefaults.standard.bool(forKey: "defaultMuted")
        project.settings.unlimitedDuration = unlimitedDuration
        project.hasAudio = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
        projects.insert(project, at: 0)
        persist()
        completed = true
        return project
    }
    func record(_ media: ExportedMedia, project: VideoProject, saved: Bool) -> ExportRecord {
        func relative(_ url: URL) -> String { String(url.path.dropFirst(root.path.count + 1)) }
        let record = ExportRecord(projectTitle: project.title, format: media.format, files: media.urls.map(relative), thumbnailFilename: relative(media.thumbnailURL), duration: media.duration, savedToPhotos: saved, originalDate: project.settings.preserveDate ? project.originalDate : nil, locationISO6709: project.settings.preserveLocation ? project.locationISO6709 : nil)
        exports.insert(record, at: 0)
        persist()
        return record
    }
    var diskUsage: String {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        var bytes: Int64 = 0
        while let file = enumerator?.nextObject() as? URL {
            if let info = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), info.isRegularFile == true { bytes += Int64(info.fileSize ?? 0) }
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

@MainActor final class ExportCoordinator: ObservableObject {
    @Published var running = false
    @Published var progress: Double = 0
    @Published var status = ""
    @Published var errorMessage: String?
    @Published var completed: [ExportRecord] = []
    @Published var cancelled = false
    private var job: Task<Void, Never>?
    private let exporter = LivePhotoExporter()

    func cancel() { job?.cancel() }

    func start(projects: [VideoProject], store: ProjectStore, saveToPhotos: Bool) {
        guard !running else { return }
        running = true; progress = 0; completed = []; errorMessage = nil; cancelled = false
        let entries = projects.flatMap { project in project.clips.map { (project, $0) } }
        job = Task { [weak self] in
            guard let self else { return }
            let background = UIApplication.shared.beginBackgroundTask(withName: "VimemoExport") { [weak self] in
                Task { @MainActor in self?.cancel() }
            }
            defer {
                if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
                self.running = false
            }
            var saveFailures: [String] = []
            do {
                for (index, entry) in entries.enumerated() {
                    try Task.checkCancellation()
                    let (project, clip) = entry
                    self.status = "正在制作 \(index + 1) / \(entries.count) · \(project.title)"
                    let folder = store.root.appendingPathComponent("Exports/\(UUID().uuidString)", isDirectory: true)
                    let media = try await exporter.export(source: store.url(for: project.filename), project: project, clip: clip, directory: folder) { [weak self] fraction in
                        Task { @MainActor in self?.progress = (Double(index) + fraction) / Double(entries.count) }
                    }
                    var saved = false
                    if saveToPhotos {
                        do { try await exporter.saveToPhotos(media, project: project); saved = true }
                        catch { saveFailures.append(error.localizedDescription) }
                    }
                    self.completed.append(store.record(media, project: project, saved: saved))
                }
                self.progress = 1
                self.status = "已制作 \(self.completed.count) 个作品"
                if !saveFailures.isEmpty { self.errorMessage = "作品已保留在本机，但相册保存失败：\n" + Array(Set(saveFailures)).joined(separator: "\n") }
            } catch is CancellationError {
                self.cancelled = true
                self.status = "已取消，完成的 \(self.completed.count) 个作品已保留"
            } catch {
                self.errorMessage = error.localizedDescription
                self.status = "导出中断，完成的作品已保留"
            }
        }
    }
}
