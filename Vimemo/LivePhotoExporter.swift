import AVFoundation
import Photos
import CoreImage
import ImageIO
import CoreLocation
import UniformTypeIdentifiers

struct ExportedMedia {
    let directory: URL
    let urls: [URL]
    let thumbnailURL: URL
    let format: OutputFormat
    let duration: Double
}

actor LivePhotoExporter {
    func export(source: URL, project: VideoProject, clip: Clip, directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> ExportedMedia {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: directory) } }
        let settings = project.settings
        var clip = clip
        clip.normalize(sourceDuration: project.duration, speed: settings.speed, maxOutputDuration: settings.maxOutputDuration)
        let thumbnail = directory.appendingPathComponent("cover.jpg")
        let identifier = UUID().uuidString
        // Cover photos live alongside the project's source, including in restored drafts.
        let photo = clip.coverPhotoFilename.map { source.deletingLastPathComponent().appendingPathComponent(URL(fileURLWithPath: $0).lastPathComponent) }
        let coverImage = try await MediaProcessor.cover(source: source, project: project, clip: clip, photo: photo, maxSize: CGSize(width: 4096, height: 4096))
        try writeJPEG(coverImage, to: thumbnail, identifier: settings.format == .livePhoto ? identifier : nil, date: settings.preserveDate ? project.originalDate : nil, location: settings.preserveLocation ? project.locationISO6709 : nil)
        progress(0.05)
        if settings.format == .photo {
            completed = true
            progress(1)
            return ExportedMedia(directory: directory, urls: [thumbnail], thumbnailURL: thumbnail, format: .photo, duration: 0)
        }
        let asset = AVURLAsset(url: source)
        let (composition, geometry) = try await MediaProcessor.composition(for: asset, clip: clip, settings: settings)
        let duration = clip.duration / settings.speed
        let movie = directory.appendingPathComponent("motion.mov")
        try await writeMovie(composition: composition, geometry: geometry, url: movie, settings: settings, identifier: settings.format == .livePhoto ? identifier : nil, coverTime: (clip.cover - clip.start) / settings.speed, duration: duration, project: project, progress: progress)
        try Task.checkCancellation()
        var urls = settings.format == .livePhoto ? [thumbnail, movie] : [movie]
        if settings.format == .gif {
            let gif = directory.appendingPathComponent("animation.gif")
            try await writeGIF(movie: movie, url: gif, duration: duration, size: settings.effectiveGIFSize, frameRate: settings.effectiveGIFFrameRate, progress: progress)
            try FileManager.default.removeItem(at: movie)
            urls = [gif]
        }
        completed = true
        progress(1)
        return ExportedMedia(directory: directory, urls: urls, thumbnailURL: thumbnail, format: settings.format, duration: duration)
    }

    private func writeJPEG(_ image: CGImage, to url: URL, identifier: String?, date: Date?, location: String?) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw StudioError.message("无法写入封面照片，请检查剩余空间。") }
        var properties: [String: Any] = [kCGImageDestinationLossyCompressionQuality as String: 0.96]
        if let identifier { properties[kCGImagePropertyMakerAppleDictionary as String] = ["17": identifier] }
        if let date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            properties[kCGImagePropertyExifDictionary as String] = [kCGImagePropertyExifDateTimeOriginal as String: formatter.string(from: date)]
        }
        if let location, let coordinate = Self.parseLocation(location)?.coordinate {
            properties[kCGImagePropertyGPSDictionary as String] = [
                kCGImagePropertyGPSLatitude as String: abs(coordinate.latitude),
                kCGImagePropertyGPSLatitudeRef as String: coordinate.latitude < 0 ? "S" : "N",
                kCGImagePropertyGPSLongitude as String: abs(coordinate.longitude),
                kCGImagePropertyGPSLongitudeRef as String: coordinate.longitude < 0 ? "W" : "E"
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw StudioError.message("封面照片写入失败。") }
    }

    private func writeMovie(composition: AVAsset, geometry: AVVideoComposition, url: URL, settings: EditSettings, identifier: String?, coverTime: Double, duration: Double, project: VideoProject, progress: @escaping @Sendable (Double) -> Void) async throws {
        let reader = try AVAssetReader(asset: composition)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let tracks = try await composition.loadTracks(withMediaType: .video)
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: tracks, videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        videoOutput.videoComposition = geometry
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw StudioError.message("无法解码这个视频。") }
        reader.add(videoOutput)
        let size = geometry.renderSize
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(2_000_000, Int(size.width * size.height * 5)), AVVideoExpectedSourceFrameRateKey: 30, AVVideoMaxKeyFrameIntervalKey: 30]
        ])
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height), kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        guard writer.canAdd(videoInput) else { throw StudioError.message("无法编码这个视频。") }
        writer.add(videoInput)

        var audioOutput: AVAssetReaderAudioMixOutput?
        var audioInput: AVAssetWriterInput?
        let audioTracks = try await composition.loadTracks(withMediaType: .audio)
        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128000])
            guard reader.canAdd(output), writer.canAdd(input) else { throw StudioError.message("这个视频的音频无法转换，请尝试开启静音。") }
            reader.add(output)
            writer.add(input)
            audioOutput = output
            audioInput = input
        }
        var metadata: [AVMetadataItem] = []
        if let identifier {
            let item = AVMutableMetadataItem()
            item.keySpace = .quickTimeMetadata
            item.key = "com.apple.quicktime.content.identifier" as NSString
            item.value = identifier as NSString
            item.dataType = kCMMetadataBaseDataType_UTF8 as String
            metadata.append(item)
        }
        if settings.preserveDate, let date = project.originalDate {
            let item = AVMutableMetadataItem()
            item.identifier = .quickTimeMetadataCreationDate
            item.value = ISO8601DateFormatter().string(from: date) as NSString
            metadata.append(item)
        }
        if settings.preserveLocation, let location = project.locationISO6709 {
            let item = AVMutableMetadataItem()
            item.identifier = .quickTimeMetadataLocationISO6709
            item.value = location as NSString
            metadata.append(item)
        }
        writer.metadata = metadata
        var metadataInput: AVAssetWriterInput?
        var metadataAdaptor: AVAssetWriterInputMetadataAdaptor?
        if identifier != nil {
            var description: CMFormatDescription?
            let specification: [String: Any] = [kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.apple.quicktime.still-image-time", kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: kCMMetadataBaseDataType_SInt8]
            let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed, metadataSpecifications: [specification] as CFArray, formatDescriptionOut: &description)
            guard status == noErr, let description else { throw StudioError.message("无法创建实况照片标记。") }
            let input = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: description)
            guard writer.canAdd(input) else { throw StudioError.message("无法写入实况照片标记。") }
            writer.add(input)
            metadataInput = input
            metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: input)
        }
        guard writer.startWriting(), reader.startReading() else { throw writer.error ?? reader.error ?? StudioError.message("转换无法开始。") }
        writer.startSession(atSourceTime: .zero)
        var success = false
        defer { if !success { reader.cancelReading(); writer.cancelWriting() } }
        if let metadataAdaptor {
            let stillTime = AVMutableMetadataItem()
            stillTime.keySpace = .quickTimeMetadata
            stillTime.key = "com.apple.quicktime.still-image-time" as NSString
            stillTime.value = NSNumber(value: Int8(0))
            stillTime.dataType = kCMMetadataBaseDataType_SInt8 as String
            let time = CMTime(seconds: min(max(0, coverTime), max(0, duration - 1.0 / 30)), preferredTimescale: 600)
            let group = AVTimedMetadataGroup(items: [stillTime], timeRange: CMTimeRange(start: time, duration: CMTime(value: 1, timescale: 30)))
            guard metadataAdaptor.append(group) else { throw writer.error ?? StudioError.message("实况照片标记写入失败。") }
            metadataInput?.markAsFinished()
        }
        var videoDone = false, audioDone = audioInput == nil
        // Drain both streams together so neither encoder can deadlock waiting for the other.
        while !videoDone || !audioDone {
            try Task.checkCancellation()
            if writer.status == .failed { throw writer.error ?? StudioError.message("视频编码失败。") }
            var madeProgress = false
            if !videoDone, videoInput.isReadyForMoreMediaData {
                if let sample = videoOutput.copyNextSampleBuffer(), let sourceBuffer = CMSampleBufferGetImageBuffer(sample) {
                    guard let pool = adaptor.pixelBufferPool else { throw StudioError.message("无法分配视频缓存。") }
                    var buffer: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess, let buffer else { throw StudioError.message("可用内存不足，请降低导出尺寸。") }
                    let image = MediaProcessor.filtered(CIImage(cvPixelBuffer: sourceBuffer), settings: settings)
                    MediaProcessor.context.render(image, to: buffer, bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpaceCreateDeviceRGB())
                    let time = CMSampleBufferGetPresentationTimeStamp(sample)
                    guard adaptor.append(buffer, withPresentationTime: time) else { throw writer.error ?? StudioError.message("视频帧写入失败。") }
                    progress(0.05 + 0.8 * min(1, time.seconds / duration))
                } else { videoDone = true; videoInput.markAsFinished() }
                madeProgress = true
            }
            if !audioDone, let audioInput, let audioOutput, audioInput.isReadyForMoreMediaData {
                if let sample = audioOutput.copyNextSampleBuffer() {
                    guard audioInput.append(sample) else { throw writer.error ?? StudioError.message("音频写入失败。") }
                } else { audioDone = true; audioInput.markAsFinished() }
                madeProgress = true
            }
            if !madeProgress { try await Task.sleep(for: .milliseconds(2)) }
        }
        guard reader.status != .failed else { throw reader.error ?? StudioError.message("视频读取失败。") }
        writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: 600))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? StudioError.message("视频保存失败。") }
        success = true
    }

    private func writeGIF(movie: URL, url: URL, duration: Double, size: GIFSize, frameRate: GIFFrameRate, progress: @escaping @Sendable (Double) -> Void) async throws {
        let fps = Double(frameRate.rawValue)
        let count = max(1, Int(ceil(duration * fps - 1e-9)))
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, count, nil) else { throw StudioError.message("无法创建 GIF 文件。") }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: size.rawValue, height: size.rawValue)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for index in 0..<count {
            try Task.checkCancellation()
            let result = try await generator.image(at: CMTime(seconds: Double(index) / fps, preferredTimescale: 600))
            // GIF stores hundredths of a second. Round cumulative boundaries so
            // rates such as 12/24/30 fps retain the correct overall playback speed.
            let begin = (Double(index) / fps * 100).rounded()
            let end = (min(duration, Double(index + 1) / fps) * 100).rounded()
            let delay = max(1, end - begin) / 100
            CGImageDestinationAddImage(destination, result.image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
            progress(0.85 + 0.14 * Double(index + 1) / Double(count))
        }
        guard CGImageDestinationFinalize(destination) else { throw StudioError.message("GIF 写入失败。") }
    }

    func saveToPhotos(_ media: ExportedMedia, project: VideoProject) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw StudioError.message("无法保存到相册。请在「设置 → 实刻 → 照片」中允许添加照片，或使用「分享文件」。") }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            if project.settings.preserveDate, let date = project.originalDate { request.creationDate = date }
            if project.settings.preserveLocation, let location = project.locationISO6709 { request.location = Self.parseLocation(location) }
            if media.format == .livePhoto {
                request.addResource(with: .photo, fileURL: media.urls[0], options: nil)
                request.addResource(with: .pairedVideo, fileURL: media.urls[1], options: nil)
            } else {
                request.addResource(with: media.format == .video ? .video : .photo, fileURL: media.urls[0], options: nil)
            }
        }
    }

    nonisolated static func parseLocation(_ text: String) -> CLLocation? {
        guard let regex = try? NSRegularExpression(pattern: "^([+-][0-9]+(?:\\.[0-9]+)?)([+-][0-9]+(?:\\.[0-9]+)?)"),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let latRange = Range(match.range(at: 1), in: text), let lonRange = Range(match.range(at: 2), in: text),
              let latitude = Double(text[latRange]), let longitude = Double(text[lonRange]),
              abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude)
    }
}
