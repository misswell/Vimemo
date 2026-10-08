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

    static func transformed(_ source: CIImage, settings: EditSettings, outputSize: CGSize? = nil, cropRatio: Double? = nil) -> CIImage {
        var image = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY))
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
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        if let settings {
            let total = try await asset.load(.duration).seconds
            let clip = Clip(start: 0, end: total, cover: time)
            var stillSettings = settings
            stillSettings.speed = 1
            let (_, videoComposition) = try await composition(for: asset, clip: clip, settings: stillSettings)
            generator.videoComposition = videoComposition
        }
        let result = try await generator.image(at: CMTime(seconds: max(0, time), preferredTimescale: 600))
        guard let settings else { return result.image }
        return try renderFrame(result.image, settings: settings)
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
