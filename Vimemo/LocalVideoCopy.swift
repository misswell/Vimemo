import Foundation

enum LocalVideoCopy {
    /// Coordinated content reads allow iCloud Drive/File Provider to materialize
    /// an offloaded file before copying it. Never use metadata-only read options.
    static func copy(_ source: URL, to destination: URL) async throws {
        try Task.checkCancellation()
        try await Task.detached(priority: .userInitiated) {
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var copyResult: Result<Void, Error>?
            coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { readableURL in
                copyResult = Result { try FileManager.default.copyItem(at: readableURL, to: destination) }
            }
            if let coordinationError { throw coordinationError }
            guard let copyResult else { throw StudioError.message("系统未能提供可读取的视频文件，请确认下载完成后重试。") }
            try copyResult.get()
            let bytes = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes > 0 else { throw StudioError.message("获取的视频文件为空，请确认 iCloud 下载完成后重试。") }
        }.value
        try Task.checkCancellation()
    }
}
