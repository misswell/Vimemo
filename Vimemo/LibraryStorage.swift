import Foundation

/// Cleans only app-owned media folders. Referenced files and recovery copies are never candidates.
enum LibraryStorage {
    private static let manager = FileManager.default
    static func clean(root: URL, projects: [VideoProject], exports: [ExportRecord], editingIDs: Set<UUID>, exportFolders: Set<URL>) {
        let projectParent = root.appendingPathComponent("Projects")
        let exportParent = root.appendingPathComponent("Exports")
        let projectFolders = Set(projects.map { root.appendingPathComponent($0.filename).deletingLastPathComponent().standardizedFileURL })
        let outputFolders = Set(exports.flatMap { $0.files + [$0.thumbnailFilename] }.map {
            root.appendingPathComponent($0).deletingLastPathComponent().standardizedFileURL
        }).union(exportFolders.map(\.standardizedFileURL))
        removeOrphans(parent: projectParent, retained: projectFolders)
        removeOrphans(parent: exportParent, retained: outputFolders)
        let covers = Set(projects.flatMap { $0.clips.compactMap(\.coverPhotoFilename) }.map { root.appendingPathComponent($0).standardizedFileURL })
        // A cover picker may hold a new photo before committing it to a clip.
        for folder in projectFolders {
            guard let id = UUID(uuidString: folder.lastPathComponent), !editingIDs.contains(id),
                  isOwned(folder, parent: projectParent),
                  let files = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for file in files where isCover(file) && !covers.contains(file.standardizedFileURL) {
                // Refuse symlinks and unexpected descendants.
                guard isOwned(file, parent: folder) else { continue }
                try? manager.removeItem(at: file)
            }
        }
    }
    private static func isCover(_ file: URL) -> Bool {
        let name = file.deletingPathExtension().lastPathComponent
        return file.pathExtension == "jpg" && name.hasPrefix("cover-") && UUID(uuidString: String(name.dropFirst(6))) != nil
    }
    private static func removeOrphans(parent: URL, retained: Set<URL>) {
        guard let folders = try? manager.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for folder in folders where UUID(uuidString: folder.lastPathComponent) != nil && !retained.contains(folder.standardizedFileURL) {
            removeOwnedFolder(folder, parent: parent)
        }
    }
    static func removeOwnedFolder(_ folder: URL, parent: URL) {
        guard isOwned(folder, parent: parent),
              (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return }
        try? manager.removeItem(at: folder)
    }
    private static func isOwned(_ item: URL, parent: URL) -> Bool {
        let path = item.standardizedFileURL
        let owner = parent.standardizedFileURL
        return path.deletingLastPathComponent() == owner
            && (try? path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
            && (try? owner.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
            && path.resolvingSymlinksInPath().deletingLastPathComponent() == owner.resolvingSymlinksInPath()
    }
    static func bytes(at root: URL) -> Int64 {
        let files = manager.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        var total: Int64 = 0
        while let file = files?.nextObject() as? URL {
            if let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
               values.isRegularFile == true, values.isSymbolicLink != true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }
    static func usage(root: URL, savedProjects: [VideoProject]) -> String {
        func formatted(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        let savedFolders = Set(savedProjects.map { root.appendingPathComponent($0.filename).deletingLastPathComponent() })
        let draftBytes = savedFolders.reduce(Int64(0)) { $0 + bytes(at: $1) }
        let sourceBytes = bytes(at: root.appendingPathComponent("Projects"))
        return "草稿 \(formatted(draftBytes)) · 作品 \(formatted(bytes(at: root.appendingPathComponent("Exports")))) · 临时文件 \(formatted(max(0, sourceBytes - draftBytes)))"
    }
}
