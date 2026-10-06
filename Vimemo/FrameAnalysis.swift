import Foundation
import CoreGraphics

enum FrameAnalysis {
    /// Compare actual frames, favoring visible detail and avoiding heavily clipped exposures.
    static func score(_ image: CGImage) -> Double {
        let size = 96
        var pixels = [UInt8](repeating: 0, count: size * size)
        let result: Double = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0 }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            let values = bytes.bindMemory(to: UInt8.self)
            var sum = 0.0, squares = 0.0, clipped = 0.0
            for y in 1..<(size - 1) {
                for x in 1..<(size - 1) {
                    let index = y * size + x
                    let value = Double(values[index])
                    let laplacian = Double(values[index - 1]) + Double(values[index + 1]) + Double(values[index - size]) + Double(values[index + size]) - 4 * value
                    sum += laplacian; squares += laplacian * laplacian
                    if value < 8 || value > 247 { clipped += 1 }
                }
            }
            let count = Double((size - 2) * (size - 2))
            return max(0, squares / count - pow(sum / count, 2)) * (1 - 0.8 * clipped / count)
        }
        return result
    }

    static func bestCover(source: URL, clip: Clip, settings: EditSettings) async throws -> Double {
        var bestTime = clip.cover, bestScore = -Double.infinity
        let count = 15
        for index in 0..<count {
            try Task.checkCancellation()
            let time = clip.start + (clip.duration - min(1 / 30, clip.duration / 2)) * Double(index) / Double(count - 1)
            let frame = try await MediaProcessor.frame(url: source, time: time, settings: settings, maxSize: CGSize(width: 192, height: 192))
            let value = score(frame)
            if value > bestScore { bestScore = value; bestTime = time }
        }
        return bestTime
    }
}
