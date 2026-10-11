import AVFoundation
import CoreImage

/// One native source decoder per picker, with a bounded cache of exact frames.
actor CoverFrameRenderer {
    private let source: URL
    private let project: VideoProject
    private var generator: AVAssetImageGenerator?
    private var layout: MediaProcessor.NativeFrameLayout?
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
            layout = try await MediaProcessor.nativeFrameLayout(asset: asset, settings: project.settings, maxSize: maxSize)
            try Task.checkCancellation()
            generator = prepared
            decoder = prepared
        }
        // A small tolerance avoids frame-accurate random seeks on every drag event.
        // Releasing the slider and frame-step buttons always request an exact frame.
        let tolerance = exact ? CMTime.zero : CMTime(seconds: 1.0 / 15, preferredTimescale: 600)
        let requestedLayout = exact ? layout : layout?.scaled(by: 0.6)
        decoder.maximumSize = requestedLayout?.decodeSize ?? maxSize
        decoder.requestedTimeToleranceBefore = tolerance
        decoder.requestedTimeToleranceAfter = tolerance
        let result = try await MediaProcessor.decodedFrame(decoder, at: requested)
        try Task.checkCancellation()
        let rendered = try MediaProcessor.renderNativeFrame(result, settings: project.settings, outputSize: requestedLayout?.outputSize)
        if exact { cache.setObject(rendered, forKey: key, cost: rendered.bytesPerRow * rendered.height) }
        return rendered
    }

    func cancel() { generator?.cancelAllCGImageGeneration() }
}
