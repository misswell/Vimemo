import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum MediaProcessor {
    static let context = CIContext(options: [.cacheIntermediates: false])
    static let videoColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    static func filtered(_ source: CIImage, settings: EditSettings) -> CIImage {
        var image = source
        switch settings.look {
        case .original: break
        case .vivid: image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.3, kCIInputContrastKey: 1.08])
        case .film: image = image.applyingFilter("CIPhotoEffectFade")
        case .warm: image = image.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 5300, y: 0)])
        case .cool: image = image.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 8200, y: 0)])
        case .mono: image = image.applyingFilter("CIPhotoEffectMono")
        }
        image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: settings.exposure])
        return image.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: settings.contrast, kCIInputSaturationKey: settings.saturation])
    }

    static func dimensions(_ size: CGSize, settings: EditSettings) -> CGSize {
        var width = size.width, height = size.height
        if settings.rotation % 2 != 0 { swap(&width, &height) }
        if let ratio = settings.ratio.value {
            if width / height > ratio { width = height * ratio } else { height = width / ratio }
        }
        let scale = min(1, settings.quality.maxDimension / max(width, height))
        return CGSize(width: max(2, floor(width * scale / 2) * 2), height: max(2, floor(height * scale / 2) * 2))
    }

    /// Position is measured from the left/top; Core Image uses a bottom-left origin.
    static func cropRect(_ extent: CGRect, settings: EditSettings, ratio: Double? = nil, topOrigin: Bool = false) -> CGRect {
        var size = extent.size
        if let ratio = ratio ?? settings.ratio.value {
            if size.width / size.height > ratio { size.width = size.height * ratio }
            else { size.height = size.width / ratio }
        }
        size.width /= settings.effectiveCropZoom; size.height /= settings.effectiveCropZoom
        return CGRect(x: extent.minX + (extent.width - size.width) * min(1, max(0, settings.cropX)),
                      y: extent.minY + (extent.height - size.height) * min(1, max(0, topOrigin ? settings.cropY : 1 - settings.cropY)),
                      width: size.width, height: size.height)
    }

    /// Maps an AVFoundation (top-left origin) track transform into Core Image's
    /// bottom-left space, matching the layer geometry the movie export composes.
    static func displayOriented(_ source: CIImage, _ trackTransform: CGAffineTransform) -> CIImage {
        guard trackTransform != .identity else { return source }
        let natural = source.extent
        let display = CGRect(origin: .zero, size: natural.size).applying(trackTransform)
        let flipIn = CGAffineTransform(1, 0, 0, -1, 0, natural.height)
        let flipOut = CGAffineTransform(1, 0, 0, -1, 0, display.height)
        return source.transformed(by: flipIn.concatenating(trackTransform)
            .concatenating(CGAffineTransform(translationX: -display.minX, y: -display.minY))
            .concatenating(flipOut))
    }

    /// Upright frame for callers outside the shared edit pipeline, e.g. import thumbnails.
    static func oriented(_ image: CGImage, transform: CGAffineTransform) throws -> CGImage {
        guard transform != .identity else { return image }
        let source = displayOriented(CIImage(cgImage: image), transform)
        guard let rendered = context.createCGImage(source, from: source.extent) else { throw StudioError.message("无法读取这一帧。") }
        return rendered
    }

    static func transformed(_ source: CIImage, settings: EditSettings, outputSize: CGSize? = nil, cropRatio: Double? = nil, sourceTransform: CGAffineTransform = .identity) -> CIImage {
        var image = displayOriented(source, sourceTransform)
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        if settings.rotation != 0 {
            image = image.transformed(by: CGAffineTransform(rotationAngle: -CGFloat(settings.rotation) * .pi / 2))
            image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        }
        if settings.mirrored { image = image.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: image.extent.width, ty: 0)) }
        let extent = image.extent
        let crop = cropRect(extent, settings: settings, ratio: cropRatio)
        image = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        let target = outputSize ?? dimensions(source.extent.size, settings: settings)
        image = image.transformed(by: CGAffineTransform(scaleX: target.width / crop.width, y: target.height / crop.height))
        return filtered(image, settings: settings).cropped(to: CGRect(origin: .zero, size: target))
    }

    static func cover(source: URL, project: VideoProject, clip: Clip, photo: URL?, maxSize: CGSize = CGSize(width: 800, height: 800)) async throws -> CGImage {
        guard let photo else { return try await frame(url: source, time: clip.cover, settings: project.settings, maxSize: maxSize) }
        guard let image = CIImage(contentsOf: photo, options: [.applyOrientationProperty: true]) else {
            throw StudioError.message("封面照片无法读取，请重新选择。")
        }
        let size = dimensions(CGSize(width: project.width, height: project.height), settings: project.settings)
        let scale = min(1, maxSize.width / size.width, maxSize.height / size.height)
        let target = CGSize(width: max(2, floor(size.width * scale)), height: max(2, floor(size.height * scale)))
        let result = transformed(image, settings: project.settings, outputSize: target, cropRatio: size.width / size.height)
        guard let rendered = context.createCGImage(result, from: CGRect(origin: .zero, size: target)) else {
            throw StudioError.message("无法生成封面照片。")
        }
        return rendered
    }

    /// Full edited image for interactive crop positioning, decoded only once.
    static func uncroppedCover(source: URL, project: VideoProject, clip: Clip, photo: URL?) async throws -> CGImage {
        var full = project
        full.settings.ratio = .original
        full.settings.cropX = 0.5; full.settings.cropY = 0.5
        full.settings.cropZoom = nil
        if let photo {
            guard let image = CIImage(contentsOf: photo, options: [.applyOrientationProperty: true]) else {
                throw StudioError.message("封面照片无法读取，请重新选择。")
            }
            full.width = Double(image.extent.width); full.height = Double(image.extent.height)
        }
        return try await cover(source: source, project: full, clip: clip, photo: photo)
    }

    /// Composition handles geometry; the reader and preview apply the same color pipeline.
    static func composition(for asset: AVAsset, clip: Clip, settings: EditSettings) async throws -> (AVMutableComposition, AVMutableVideoComposition) {
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .video).first else { throw StudioError.message("这个文件没有可用的视频轨道。") }
        let sourceSize = try await sourceTrack.load(.naturalSize)
        let sourceTransform = try await sourceTrack.load(.preferredTransform)
        let comp = AVMutableComposition()
        guard let track = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw StudioError.message("无法创建视频轨道。") }
        let range = CMTimeRange(start: CMTime(seconds: clip.start, preferredTimescale: 600), duration: CMTime(seconds: clip.duration, preferredTimescale: 600))
        try track.insertTimeRange(range, of: sourceTrack, at: .zero)
        if !settings.muted, let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
           let audio = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let audioRange = try await sourceAudio.load(.timeRange)
            let available = CMTimeRangeGetIntersection(range, otherRange: audioRange)
            if available.duration.seconds > 0 { try audio.insertTimeRange(available, of: sourceAudio, at: CMTimeSubtract(available.start, range.start)) }
        }
        let outputDuration = CMTime(seconds: clip.duration / settings.speed, preferredTimescale: 600)
        comp.scaleTimeRange(CMTimeRange(start: .zero, duration: range.duration), toDuration: outputDuration)
        var transform = sourceTransform
        var rect = CGRect(origin: .zero, size: sourceSize).applying(transform)
        transform = transform.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        rect = CGRect(origin: .zero, size: rect.size)
        if settings.rotation != 0 {
            let rotation = CGAffineTransform(rotationAngle: CGFloat(settings.rotation) * .pi / 2)
            let rotated = rect.applying(rotation)
            transform = transform.concatenating(rotation).concatenating(CGAffineTransform(translationX: -rotated.minX, y: -rotated.minY))
            rect = CGRect(origin: .zero, size: rotated.size)
        }
        if settings.mirrored { transform = transform.concatenating(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.width, ty: 0)) }
        let crop = cropRect(rect, settings: settings, topOrigin: true)
        let oriented = CGRect(origin: .zero, size: sourceSize).applying(sourceTransform).size
        let outputSize = dimensions(oriented, settings: settings)
        transform = transform.concatenating(CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .concatenating(CGAffineTransform(scaleX: outputSize.width / crop.width, y: outputSize.height / crop.height))
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: outputDuration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layer]
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = outputSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]
        return (comp, videoComposition)
    }

    static func frame(url: URL, time: Double, settings: EditSettings? = nil, maxSize: CGSize = CGSize(width: 800, height: 800)) async throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        // Decode stored pixels only. iOS 27 routes the track transform (and HDR
        // tone mapping) through its composited decoder, which fails with -12784
        // on some sources; the transform is applied in Core Image instead.
        generator.appliesPreferredTrackTransform = false
        var layout: NativeFrameLayout?
        var sourceTransform = CGAffineTransform.identity
        if let settings {
            layout = try await nativeFrameLayout(asset: asset, settings: settings, maxSize: maxSize)
            sourceTransform = layout?.sourceTransform ?? .identity
        } else if let track = try await asset.loadTracks(withMediaType: .video).first {
            sourceTransform = try await track.load(.preferredTransform)
        }
        generator.maximumSize = layout?.decodeSize ?? maxSize
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // Decode the native source first. Applying a composition here made both
        // cover preview and the first export step depend on the composition decoder.
        let image: CGImage
        do {
            image = try await decodedFrame(generator, at: CMTime(seconds: max(0, time), preferredTimescale: 600))
        } catch {
            guard let settings, let layout, !Task.isCancelled else { throw error }
            DiagnosticLog.shared.record("frame.reader-fallback", "time=\(time)", error: error)
            return try await composedFrame(source: url, time: time, settings: settings, outputSize: layout.outputSize)
        }
        guard let settings else { return try oriented(image, transform: sourceTransform) }
        return try renderNativeFrame(image, settings: settings, outputSize: layout?.outputSize, sourceTransform: sourceTransform)
    }

    /// Single-frame grab through the composition reader — the same geometry the
    /// movie export renders — for sources the system image generator refuses.
    static func composedFrame(source: URL, time: Double, settings: EditSettings, outputSize: CGSize) async throws -> CGImage {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        let start = max(0, min(time - 0.2, max(0, duration - 0.4)))
        let end = min(duration, max(time + 0.2, start + 0.4))
        let clip = Clip(start: start, end: max(end, min(max(0, duration - start), start + 0.1)), cover: time)
        let (composition, geometry) = try await composition(for: asset, clip: clip, settings: settings)
        let reader = try AVAssetReader(asset: composition)
        let tracks = try await composition.loadTracks(withMediaType: .video)
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: tracks, videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.videoComposition = geometry
        guard reader.canAdd(output) else { throw StudioError.message("无法解码这个视频。") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? StudioError.message("无法解码这个视频。") }
        defer { if reader.status == .reading { reader.cancelReading() } }
        let target = CMTime(seconds: (time - clip.start) / settings.speed, preferredTimescale: 600)
        var best: CIImage?
        var bestDistance = Double.infinity
        while let sample = output.copyNextSampleBuffer() {
            let distance = abs(CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(sample), target).seconds)
            if distance < bestDistance, let buffer = CMSampleBufferGetImageBuffer(sample) {
                bestDistance = distance
                best = CIImage(cvPixelBuffer: buffer)
            }
        }
        guard reader.status == .completed, var image = best else { throw reader.error ?? StudioError.message("无法读取这一帧。") }
        image = filtered(image, settings: settings)
        image = image.transformed(by: CGAffineTransform(scaleX: outputSize.width / image.extent.width, y: outputSize.height / image.extent.height))
        image = image.cropped(to: CGRect(origin: .zero, size: outputSize))
        guard let rendered = context.createCGImage(image, from: CGRect(origin: .zero, size: outputSize), format: .RGBA8, colorSpace: videoColorSpace) else {
            throw StudioError.message("无法读取这一帧。")
        }
        return rendered
    }

    struct NativeFrameLayout {
        let decodeSize: CGSize
        let outputSize: CGSize
        let sourceTransform: CGAffineTransform
        func scaled(by scale: CGFloat) -> NativeFrameLayout {
            NativeFrameLayout(decodeSize: CGSize(width: decodeSize.width * scale, height: decodeSize.height * scale),
                              outputSize: CGSize(width: max(2, floor(outputSize.width * scale / 2) * 2), height: max(2, floor(outputSize.height * scale / 2) * 2)),
                              sourceTransform: sourceTransform)
        }
    }

    static func nativeFrameLayout(asset: AVAsset, settings: EditSettings, maxSize: CGSize) async throws -> NativeFrameLayout {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw StudioError.message("这个文件没有可用的视频轨道。") }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let oriented = CGRect(origin: .zero, size: natural).applying(transform).size
        let fullOutput = dimensions(oriented, settings: settings)
        let scale = min(1, maxSize.width / fullOutput.width, maxSize.height / fullOutput.height)
        let output = CGSize(width: max(2, floor(fullOutput.width * scale / 2) * 2), height: max(2, floor(fullOutput.height * scale / 2) * 2))
        let rotated = settings.rotation % 2 == 0 ? oriented : CGSize(width: oriented.height, height: oriented.width)
        let crop = cropRect(CGRect(origin: .zero, size: rotated), settings: settings)
        // Decode enough native pixels for the chosen crop, rather than magnifying
        // a thumbnail that was scaled down before cropping/zooming.
        let decodeScale = min(1, max(output.width / crop.width, output.height / crop.height))
        // maximumSize now bounds the stored frame; the track transform is applied
        // later in Core Image, so the decode target follows the natural size.
        return NativeFrameLayout(decodeSize: CGSize(width: natural.width * decodeScale, height: natural.height * decodeScale), outputSize: output, sourceTransform: transform)
    }

    static func decodedFrame(_ generator: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        let operation = UUID().uuidString
        DiagnosticLog.shared.record("frame.begin", "op=\(operation) time=\(time.seconds)")
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard !Task.isCancelled else { return }
            DiagnosticLog.shared.record("frame.timeout", "op=\(operation)")
            generator.cancelAllCGImageGeneration()
        }
        defer { timeout.cancel() }
        return try await withTaskCancellationHandler {
            do {
                let result = try await generator.image(at: time)
                try Task.checkCancellation()
                DiagnosticLog.shared.record("frame.completed", "op=\(operation) actual=\(result.actualTime.seconds)")
                return result.image
            } catch {
                try Task.checkCancellation()
                DiagnosticLog.shared.record("frame.failed", "op=\(operation)", error: error)
                throw MediaStageError(stage: "读取视频帧", underlying: error)
            }
        } onCancel: { generator.cancelAllCGImageGeneration() }
    }

    static func renderNativeFrame(_ source: CGImage, settings: EditSettings, outputSize: CGSize? = nil, sourceTransform: CGAffineTransform = .identity) throws -> CGImage {
        let image = transformed(CIImage(cgImage: source), settings: settings, outputSize: outputSize, sourceTransform: sourceTransform)
        guard let rendered = context.createCGImage(image, from: image.extent) else { throw StudioError.message("无法读取这一帧。") }
        return rendered
    }

    static func renderFrame(_ source: CGImage, settings: EditSettings) throws -> CGImage {
        var image = filtered(CIImage(cgImage: source), settings: settings)
        // AVAssetImageGenerator may round one scaled edge down; keep the chosen aspect ratio exact.
        let rawSize = image.extent.size
        var target = rawSize
        if let ratio = settings.ratio.value {
            if rawSize.width / rawSize.height > ratio { target.width = rawSize.height * ratio }
            else { target.height = rawSize.width / ratio }
        }
        target = CGSize(width: max(1, floor(target.width)), height: max(1, floor(target.height)))
        image = image.transformed(by: CGAffineTransform(scaleX: target.width / rawSize.width, y: target.height / rawSize.height))
        guard let cg = context.createCGImage(image, from: CGRect(origin: .zero, size: target)) else { throw StudioError.message("无法读取这一帧。") }
        return cg
    }
}
