import AVFoundation
import SwiftUI

@MainActor final class TimelineThumbnailManager: ObservableObject {
    @Published private(set) var images: [Double: UIImage] = [:]
    private let cache = NSCache<NSNumber, UIImage>()
    private var source: URL?
    private var generation = UUID()

    init() {
        cache.totalCostLimit = 16 * 1024 * 1024
        cache.countLimit = 120
    }

    func load(source: URL, plan: TimelineThumbnailPlan) async {
        let request = UUID(); generation = request
        if self.source != source { self.source = source; cache.removeAllObjects(); images = [:] }
        var loaded: [Double: UIImage] = [:]
        for time in plan.times {
            if let image = cache.object(forKey: NSNumber(value: time)) { loaded[time] = image }
        }
        images = loaded
        do {
            // Debounce moving viewports, then decode only the visible screen plus one cell.
            try await Task.sleep(for: .milliseconds(100))
            let asset = AVURLAsset(url: source)
            let transform = try await asset.loadTracks(withMediaType: .video).first?.load(.preferredTransform) ?? .identity
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = false
            generator.maximumSize = CGSize(width: 160, height: 160)
            let tolerance = CMTime(seconds: min(0.5, plan.interval / 4), preferredTimescale: 600)
            generator.requestedTimeToleranceBefore = tolerance
            generator.requestedTimeToleranceAfter = tolerance
            try await withTaskCancellationHandler {
                for time in plan.times where loaded[time] == nil {
                    try Task.checkCancellation()
                    guard generation == request else { return }
                    if let frame = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)),
                       let upright = try? MediaProcessor.oriented(frame.image, transform: transform) {
                        try Task.checkCancellation()
                        guard generation == request else { return }
                        let image = UIImage(cgImage: upright)
                        cache.setObject(image, forKey: NSNumber(value: time), cost: upright.bytesPerRow * upright.height)
                        loaded[time] = image
                        images = loaded
                    }
                }
            } onCancel: { generator.cancelAllCGImageGeneration() }
        } catch { /* A stale viewport or unreadable thumbnail must not interrupt editing. */ }
    }
}
