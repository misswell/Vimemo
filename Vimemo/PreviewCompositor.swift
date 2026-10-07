import AVFoundation
import CoreImage

/// Native file playback with an immutable presentation for GPU frame rendering.
struct VideoPreview {
    let item: AVPlayerItem
    let start: CMTime
    let rate: Float
    let size: CGSize
    let transform: CGAffineTransform
    let settings: EditSettings

    func render(_ source: CIImage) -> CIImage {
        MediaProcessor.filtered(source.transformed(by: transform), settings: settings)
            .cropped(to: CGRect(origin: .zero, size: size))
    }
}

extension MediaProcessor {
    @MainActor static func previewItem(source: URL, clip: Clip, settings: EditSettings) async throws -> VideoPreview {
        let asset = AVURLAsset(url: source)
        let (composition, geometry) = try await composition(for: asset, clip: clip, settings: settings)
        guard let track = try await composition.loadTracks(withMediaType: .video).first,
              let base = geometry.instructions.first as? AVMutableVideoCompositionInstruction,
              let layer = base.layerInstructions.first else { throw StudioError.message("无法创建动态预览。") }
        var start = CGAffineTransform.identity, end = CGAffineTransform.identity, range = CMTimeRange.zero
        layer.getTransformRamp(for: .zero, start: &start, end: &end, timeRange: &range)
        let sourceSize = try await track.load(.naturalSize)
        let size = geometry.renderSize
        let transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: sourceSize.height)
            .concatenating(start)
            .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height))
        // iOS 27 currently fails to prepare composition-backed video playback.
        // Play the source file directly and transform its frames in PreviewSurface.
        let item = AVPlayerItem(asset: asset)
        item.forwardPlaybackEndTime = CMTime(seconds: clip.end, preferredTimescale: 600)
        item.reversePlaybackEndTime = CMTime(seconds: clip.start, preferredTimescale: 600)
        item.audioTimePitchAlgorithm = .spectral
        if settings.muted, let audio = try await asset.loadTracks(withMediaType: .audio).first {
            let parameters = AVMutableAudioMixInputParameters(track: audio)
            parameters.setVolume(0, at: .zero)
            let mix = AVMutableAudioMix(); mix.inputParameters = [parameters]; item.audioMix = mix
        }
        return VideoPreview(item: item, start: item.reversePlaybackEndTime, rate: Float(settings.speed), size: size, transform: transform, settings: settings)
    }
}
