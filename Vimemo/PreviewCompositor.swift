import AVFoundation
import CoreImage

final class PreviewInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = false
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let trackID: CMPersistentTrackID
    let transform: CGAffineTransform
    let sourceHeight: CGFloat
    let settings: EditSettings
    init(range: CMTimeRange, trackID: CMPersistentTrackID, transform: CGAffineTransform, sourceHeight: CGFloat, settings: EditSettings) {
        timeRange = range; self.trackID = trackID; self.transform = transform; self.sourceHeight = sourceHeight; self.settings = settings
        requiredSourceTrackIDs = [NSNumber(value: trackID)]
    }
}

final class PreviewCompositor: NSObject, AVVideoCompositing {
    var sourcePixelBufferAttributes: [String: any Sendable]? { [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]] }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] { [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]() ] }
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            guard let instruction = request.videoCompositionInstruction as? PreviewInstruction,
                  let source = request.sourceFrame(byTrackID: instruction.trackID),
                  let target = request.renderContext.newPixelBuffer() else {
                request.finish(with: StudioError.message("预览帧读取失败。")); return
            }
            let size = request.renderContext.size
            // AVFoundation layer transforms use a top-left origin; Core Image uses bottom-left.
            let transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: instruction.sourceHeight)
                .concatenating(instruction.transform)
                .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height))
            let image = MediaProcessor.filtered(CIImage(cvPixelBuffer: source).transformed(by: transform), settings: instruction.settings)
            MediaProcessor.context.render(image, to: target, bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpaceCreateDeviceRGB())
            request.finish(withComposedVideoFrame: target)
        }
    }
}

extension MediaProcessor {
    @MainActor static func previewItem(source: URL, clip: Clip, settings: EditSettings) async throws -> AVPlayerItem {
        let (composition, geometry) = try await composition(for: AVURLAsset(url: source), clip: clip, settings: settings)
        guard let track = try await composition.loadTracks(withMediaType: .video).first,
              let base = geometry.instructions.first as? AVMutableVideoCompositionInstruction,
              let layer = base.layerInstructions.first else { throw StudioError.message("无法创建动态预览。") }
        var start = CGAffineTransform.identity, end = CGAffineTransform.identity, range = CMTimeRange.zero
        layer.getTransformRamp(for: .zero, start: &start, end: &end, timeRange: &range)
        let size = try await track.load(.naturalSize)
        let filtered = geometry.mutableCopy() as! AVMutableVideoComposition
        filtered.customVideoCompositorClass = PreviewCompositor.self
        filtered.instructions = [PreviewInstruction(range: base.timeRange, trackID: track.trackID, transform: start, sourceHeight: size.height, settings: settings)]
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = filtered
        item.audioTimePitchAlgorithm = .spectral
        return item
    }
}
