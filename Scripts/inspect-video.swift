import Foundation
import AVFoundation
import AppKit

@main struct InspectVideo {
    static func main() async throws {
        let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let seconds = try await asset.load(.duration).seconds
        print("Duration: \(seconds)s")
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 420, height: 900)
        let count = 24
        let thumbWidth = 210, thumbHeight = 470
        let sheet = NSImage(size: NSSize(width: thumbWidth * 6, height: thumbHeight * 4))
        var frames: [(CGImage, Double)] = []
        for index in 0..<count {
            let time = min(seconds - 0.1, Double(index) * seconds / Double(count))
            let result = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
            frames.append((result.image, time))
            let rep = NSBitmapImageRep(cgImage: result.image)
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("frame-\(index).png"))
        }
        sheet.lockFocus()
        NSColor.darkGray.setFill()
        NSRect(origin: .zero, size: sheet.size).fill()
        for (index, frame) in frames.enumerated() {
            let x = (index % 6) * thumbWidth
            let y = (3 - index / 6) * thumbHeight
            NSImage(cgImage: frame.0, size: .zero).draw(in: NSRect(x: x, y: y + 24, width: thumbWidth, height: thumbHeight - 24))
            (String(format: "%.1fs", frame.1) as NSString).draw(at: NSPoint(x: x + 8, y: y + 4), withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)])
        }
        sheet.unlockFocus()
        let data = NSBitmapImageRep(data: sheet.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("contact-sheet.png"))
    }
}
