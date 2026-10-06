import Foundation
import CoreGraphics

enum OutputFormat: String, Codable, CaseIterable, Identifiable {
    case livePhoto, video, gif, photo
    var id: String { rawValue }
    var title: String { switch self { case .livePhoto: "实况照片"; case .video: "视频"; case .gif: "GIF 动图"; case .photo: "静态照片" } }
    var symbol: String { switch self { case .livePhoto: "livephoto"; case .video: "video"; case .gif: "sparkles.tv"; case .photo: "photo" } }
}

enum FrameRatio: String, Codable, CaseIterable, Identifiable {
    case original, portrait, square, classic, landscape
    var id: String { rawValue }
    var title: String { switch self { case .original: "原始"; case .portrait: "9:16"; case .square: "1:1"; case .classic: "4:3"; case .landscape: "16:9" } }
    var value: Double? { switch self { case .original: nil; case .portrait: 9 / 16; case .square: 1; case .classic: 4 / 3; case .landscape: 16 / 9 } }
}

enum ColorLook: String, Codable, CaseIterable, Identifiable {
    case original, vivid, film, warm, cool, mono
    var id: String { rawValue }
    var title: String { switch self { case .original: "原片"; case .vivid: "鲜明"; case .film: "胶片"; case .warm: "暖阳"; case .cool: "冷调"; case .mono: "黑白" } }
}

enum ExportQuality: String, Codable, CaseIterable, Identifiable {
    case original, high, compact
    var id: String { rawValue }
    var title: String { switch self { case .original: "原始尺寸"; case .high: "1080p"; case .compact: "720p" } }
    var maxDimension: Double { switch self { case .original: 4096; case .high: 1920; case .compact: 1280 } }
}

struct Clip: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Double = 0
    var end: Double = 3
    var cover: Double = 1.5
    var duration: Double { end - start }

    mutating func normalize(sourceDuration: Double, speed: Double = 1) {
        let total = max(0.1, sourceDuration)
        start = min(max(0, start), max(0, total - 0.1))
        end = min(total, max(start + 0.1, end))
        end = min(end, start + 3 * speed)
        cover = min(max(start, cover), max(start, end - 1.0 / 600))
    }
}

struct EditSettings: Codable, Equatable {
    var ratio: FrameRatio = .original
    var rotation: Int = 0
    var mirrored = false
    var look: ColorLook = .original
    var exposure: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var speed: Double = 1
    var muted = false
    var quality: ExportQuality = .high
    var preserveDate = true
    var preserveLocation = false
    var format: OutputFormat = .livePhoto
    var cropX: Double = 0.5
    var cropY: Double = 0.5
}

struct VideoProject: Codable, Identifiable {
    var id = UUID()
    var title: String
    var filename: String
    var thumbnailFilename: String
    var duration: Double
    var width: Double
    var height: Double
    var frameRate: Double
    var importedAt = Date()
    var originalDate: Date?
    var locationISO6709: String?
    var clips: [Clip]
    var settings = EditSettings()
    var hasAudio = false
    var sizeLabel: String { "\(Int(width)) × \(Int(height))" }
}

struct ExportRecord: Codable, Identifiable {
    var id = UUID()
    var projectTitle: String
    var format: OutputFormat
    var createdAt = Date()
    var files: [String]
    var thumbnailFilename: String
    var duration: Double
    var savedToPhotos = false
    var originalDate: Date? = nil
    var locationISO6709: String? = nil
}

enum StudioError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): text } }
}

extension Double {
    var timeLabel: String { String(format: "%02d:%05.2f", Int(self) / 60, self.truncatingRemainder(dividingBy: 60)) }
}
