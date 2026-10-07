import AVFoundation
import CoreImage

/// One decoder/composition per picker, with a bounded cache of exact frames.
actor CoverFrameRenderer {
    private let source: URL
    private let project: VideoProject
    private var generator: AVAssetImageGenerator?
    private let cache = NSCache<NSNumber, CGImage>()
    private let maxSize = CGSize(width: 800, height: 800)

    init(source: URL, project: VideoProject) {
        self.source = source; self.project = project
        cache.totalCostLimit = 24 * 1024 * 1024
        cache.countLimit = 24
    }

    func frame(time: Double, photo: URL?, exact: Bool) async throws -> CGImage {
        try Task.checkCancellation()
        if let photo {
            var clip = Clip(); clip.cover = time
            return try await MediaProcessor.cover(source: source, project: project, clip: clip, photo: photo)
        }
        let requested = CMTime(seconds: max(0, time), preferredTimescale: 600)
        let key = NSNumber(value: requested.value)
        if let cached = cache.object(forKey: key) { return cached }
        let decoder: AVAssetImageGenerator
        if let generator { decoder = generator }
        else {
            let asset = AVURLAsset(url: source)
            let prepared = AVAssetImageGenerator(asset: asset)
            prepared.appliesPreferredTrackTransform = true
            prepared.maximumSize = maxSize
            let total = try await asset.load(.duration).seconds
            var settings = project.settings; settings.speed = 1
            let (_, composition) = try await MediaProcessor.composition(for: asset, clip: Clip(start: 0, end: total), settings: settings)
            try Task.checkCancellation()
            prepared.videoComposition = composition
            generator = prepared
            decoder = prepared
        }
        // A small tolerance avoids frame-accurate random seeks on every drag event.
        // Releasing the slider and frame-step buttons always request an exact frame.
        let tolerance = exact ? CMTime.zero : CMTime(seconds: 1.0 / 15, preferredTimescale: 600)
        decoder.maximumSize = exact ? maxSize : CGSize(width: 480, height: 480)
        decoder.requestedTimeToleranceBefore = tolerance
        decoder.requestedTimeToleranceAfter = tolerance
        let result = try await decoder.image(at: requested)
        try Task.checkCancellation()
        let rendered = try MediaProcessor.renderFrame(result.image, settings: project.settings)
        if exact { cache.setObject(rendered, forKey: key, cost: rendered.bytesPerRow * rendered.height) }
        return rendered
    }

    func cancel() { generator?.cancelAllCGImageGeneration() }
}
