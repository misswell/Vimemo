import AVFoundation
import SwiftUI

@MainActor final class TimelineThumbnailManager: ObservableObject {
    /// Keyed by the source frame, so every viewport that asks for the same frame reuses the
    /// decode instead of asking for it again at a new pixel position.
    @Published private(set) var images: [Int: UIImage] = [:]
    private let cache = NSCache<NSNumber, UIImage>()
    private let maximumSize = CGSize(width: 160, height: 160)
    private var source: URL?
    private var asset: AVURLAsset?
    private var transform: CGAffineTransform?
    private var generation = UUID()

    init() {
        cache.totalCostLimit = 16 * 1024 * 1024
        cache.countLimit = 120
    }

    func load(source: URL, plan: TimelineThumbnailPlan) async {
        let request = UUID(); generation = request
        if self.source != source {
            self.source = source
            // One asset per clip: a two-hour file re-opens its moov atom on every instance.
            asset = AVURLAsset(url: source); transform = nil
            cache.removeAllObjects(); images = [:]
        }
        let keep = Set(plan.times.map { plan.key(for: $0) })
        var loaded = images
        for key in keep {
            if let image = cache.object(forKey: NSNumber(value: key)) { loaded[key] = image }
        }
        // A pinch rewrites the request every frame. Cells the new viewport no longer asks for
        // stay until the strip is full again, so the row never blinks mid-gesture.
        images = loaded.count > 60 ? loaded.filter { keep.contains($0.key) } : loaded
        do {
            // Debounce moving viewports, then decode only the visible screen plus one cell.
            try await Task.sleep(for: .milliseconds(100))
            guard let asset else { return }
            if transform == nil {
                transform = try await asset.loadTracks(withMediaType: .video).first?.load(.preferredTransform) ?? .identity
            }
            let generator = AVAssetImageGenerator(asset: asset)
            // Stored pixels plus a Core Image orientation: iOS 27's composited decoder can fail.
            generator.appliesPreferredTrackTransform = false
            generator.maximumSize = maximumSize
            let tolerance = CMTime(seconds: min(0.5, plan.interval / 4), preferredTimescale: 600)
            generator.requestedTimeToleranceBefore = tolerance
            generator.requestedTimeToleranceAfter = tolerance
            let upright = transform ?? .identity
            try await withTaskCancellationHandler {
                for time in plan.times {
                    let key = plan.key(for: time)
                    if loaded[key] != nil { continue }
                    try Task.checkCancellation()
                    guard generation == request else { return }
                    let requested = CMTime(seconds: time, preferredTimescale: 600)
                    var frame: CGImage?
                    if let decoded = try? await MediaProcessor.decodedFrame(generator, at: requested) {
                        frame = try? MediaProcessor.oriented(decoded, transform: upright)
                    }
                    if frame == nil, let recovered = try? await MediaProcessor.composedFrame(
                        source: source, time: time, settings: EditSettings(), outputSize: maximumSize) {
                        frame = recovered
                    }
                    guard let frame else { continue }
                    try Task.checkCancellation()
                    guard generation == request else { return }
                    let image = UIImage(cgImage: frame)
                    cache.setObject(image, forKey: NSNumber(value: key), cost: frame.bytesPerRow * frame.height)
                    loaded[key] = image
                    images = loaded
                }
            } onCancel: { generator.cancelAllCGImageGeneration() }
        } catch { /* A stale viewport or unreadable thumbnail must not interrupt editing. */ }
    }
}
