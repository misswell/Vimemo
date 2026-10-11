import Foundation
import AVFoundation
import UIKit

/// Local, bounded diagnostics. Never pass titles, URLs, metadata or error descriptions here.
final class DiagnosticLog: @unchecked Sendable {
    static let shared = DiagnosticLog(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("VimemoDiagnostics"))
    private let directory: URL
    private let limit: Int
    private let queue = DispatchQueue(label: "com.vimemo.diagnostics")
    private var current: URL { directory.appendingPathComponent("current.log") }
    private var previous: URL { directory.appendingPathComponent("previous.log") }

    init(directory: URL, limit: Int = 256 * 1024) { self.directory = directory; self.limit = limit }

    static func codes(_ error: Error) -> String {
        if let staged = error as? MediaStageError { return codes(staged.underlying) }
        func collect(_ error: NSError, depth: Int) -> [String] {
            guard depth < 8 else { return [] }
            let domain = String(error.domain.filter { $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }.prefix(80))
            var result = ["\(domain)(\(error.code))"]
            if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { result += collect(underlying, depth: depth + 1) }
            return result
        }
        return collect(error as NSError, depth: 0).joined(separator: " > ")
    }

    func record(_ event: String, _ detail: String = "", error: Error? = nil) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(event) \(detail)\(error.map { " error=" + Self.codes($0) } ?? "")\n"
        queue.async { [self] in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = Data(line.utf8.prefix(min(limit, 4096)))
                let size = (try? current.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size + data.count > limit {
                    try? FileManager.default.removeItem(at: previous)
                    if FileManager.default.fileExists(atPath: current.path) { try FileManager.default.moveItem(at: current, to: previous) }
                }
                if !FileManager.default.fileExists(atPath: current.path) { try Data().write(to: current) }
                let handle = try FileHandle(forWritingTo: current)
                defer { try? handle.close() }
                try handle.seekToEnd(); try handle.write(contentsOf: data)
            } catch { /* Diagnostic failure must never interrupt media work. */ }
        }
    }

    func snapshot() async throws -> URL {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let system = await MainActor.run { UIDevice.current.systemVersion }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    var data = Data("Vimemo diagnostics v1\nApp \(version) (\(build)), iOS \(system)\nOnly technical events; no media, titles, paths, location or account data.\n".utf8)
                    for file in [previous, current] { if let part = try? Data(contentsOf: file) { data.append(part) } }
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("VimemoDiagnosticShare-\(UUID().uuidString)")
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let url = folder.appendingPathComponent("Vimemo-diagnostics.txt")
                    try data.write(to: url, options: .atomic)
                    continuation.resume(returning: url)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func asset(_ asset: AVAsset, operation: String) async {
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { record("asset", "op=\(operation) no-video"); return }
            let size = try await track.load(.naturalSize)
            let fps = try await track.load(.nominalFrameRate)
            let formats = try await track.load(.formatDescriptions)
            let codecs = formats.map { String(CMFormatDescriptionGetMediaSubType($0), radix: 16) }.joined(separator: ",")
            let audioCount = try await asset.loadTracks(withMediaType: .audio).count
            record("asset", "op=\(operation) trackID=\(track.trackID) size=\(size.width)x\(size.height) fps=\(fps) codec=\(codecs) audio=\(audioCount)")
        } catch { record("asset.failed", "op=\(operation)", error: error) }
    }
}

struct MediaStageError: LocalizedError {
    let stage: String
    let underlying: Error
    var errorDescription: String? {
        if let message = underlying as? StudioError { return "\(stage)失败：\(message.localizedDescription)" }
        return "\(stage)失败（\(DiagnosticLog.codes(underlying))）。请重试；若仍失败，请在设置中导出诊断日志。"
    }
}
