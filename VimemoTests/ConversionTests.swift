import XCTest
import AVFoundation
import Photos
import ImageIO
@testable import Vimemo

final class ConversionTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("VimemoTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    private var source: URL { Bundle(for: ProjectStore.self).url(forResource: "Demo", withExtension: "mov")! }
    private func project(settings: EditSettings = EditSettings()) -> VideoProject {
        var project = VideoProject(title: "Test", filename: "source.mov", thumbnailFilename: "cover.jpg", duration: 6, width: 960, height: 1280, frameRate: 30, originalDate: Date(timeIntervalSince1970: 1_700_000_000), locationISO6709: "+31.2304+121.4737/", clips: [Clip(start: 1, end: 4, cover: 2.25)])
        project.settings = settings
        return project
    }

    func testClipNormalizationAndOutputDimensions() {
        var clip = Clip(start: -1, end: 20, cover: 19)
        clip.normalize(sourceDuration: 6, speed: 0.5)
        XCTAssertEqual(clip.start, 0)
        XCTAssertEqual(clip.end, 1.5)
        XCTAssertLessThan(clip.cover, clip.end)
        var settings = EditSettings()
        settings.ratio = .landscape
        settings.rotation = 1
        let size = MediaProcessor.dimensions(CGSize(width: 960, height: 1280), settings: settings)
        XCTAssertEqual(size.width, 1280)
        XCTAssertEqual(size.height, 720)
        XCTAssertNotNil(LivePhotoExporter.parseLocation("+31.2304+121.4737/"))
        XCTAssertNil(LivePhotoExporter.parseLocation("+99.0+181.0/"))
    }

    func testLivePhotoPairIsRecognizedAndMetadataMatches() async throws {
        var settings = EditSettings()
        settings.preserveLocation = true
        let project = project(settings: settings)
        let output = try await LivePhotoExporter().export(source: source, project: project, clip: project.clips[0], directory: folder.appendingPathComponent("Live")) { _ in }
        XCTAssertEqual(output.urls.count, 2)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(output.urls[0] as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any])
        let maker = try XCTUnwrap(properties[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any])
        let photoID = try XCTUnwrap(maker["17"] as? String)
        let gps = try XCTUnwrap(properties[kCGImagePropertyGPSDictionary as String] as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(gps[kCGImagePropertyGPSLatitude as String] as? Double), 31.2304, accuracy: 0.0001)
        let movie = AVURLAsset(url: output.urls[1])
        let metadata = try await movie.load(.metadata)
        let idItem = try XCTUnwrap(metadata.first { $0.identifier == .quickTimeMetadataContentIdentifier })
        let movieID = try await idItem.load(.stringValue)
        XCTAssertEqual(photoID, movieID)
        let dateItem = try XCTUnwrap(metadata.first { $0.identifier == .quickTimeMetadataCreationDate })
        let dateString = try await dateItem.load(.stringValue)
        XCTAssertNotNil(dateString)
        let duration = try await movie.load(.duration).seconds
        XCTAssertEqual(duration, 3, accuracy: 0.05)
        let metadataTracks = try await movie.loadTracks(withMediaType: .metadata)
        let track = try XCTUnwrap(metadataTracks.first)
        let reader = try AVAssetReader(asset: movie)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(readerOutput)
        let metadataReader = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: readerOutput)
        XCTAssertTrue(reader.startReading())
        var stillImageTime: Double?
        while let group = metadataReader.nextTimedMetadataGroup() {
            if group.items.contains(where: { ($0.key as? String) == "com.apple.quicktime.still-image-time" }) { stillImageTime = group.timeRange.start.seconds }
        }
        XCTAssertEqual(try XCTUnwrap(stillImageTime), 1.25, accuracy: 0.05)
        reader.cancelReading()
        let recognized = expectation(description: "Photos recognizes the generated Live Photo")
        var actual: PHLivePhoto?
        let request = PHLivePhoto.request(withResourceFileURLs: output.urls, placeholderImage: nil, targetSize: CGSize(width: 300, height: 300), contentMode: .aspectFit) { photo, info in
            if info[PHLivePhotoInfoIsDegradedKey] as? Bool == true { return }
            actual = photo
            recognized.fulfill()
        }
        await fulfillment(of: [recognized], timeout: 20)
        PHLivePhoto.cancelRequest(withRequestID: request)
        XCTAssertNotNil(actual, "JPEG + MOV must be accepted as an actual Live Photo")
    }

    func testAllExportFormatsAndCropSpeedFilter() async throws {
        for format in [OutputFormat.video, .gif, .photo] {
            var settings = EditSettings()
            settings.format = format; settings.ratio = .square; settings.rotation = 1
            settings.mirrored = true; settings.look = .mono; settings.speed = 2
            let project = project(settings: settings)
            let output = try await LivePhotoExporter().export(source: source, project: project, clip: project.clips[0], directory: folder.appendingPathComponent(format.rawValue)) { _ in }
            XCTAssertEqual(output.urls.count, 1)
            if format == .video {
                let movie = AVURLAsset(url: output.urls[0])
                let actualDuration = try await movie.load(.duration).seconds
                XCTAssertEqual(actualDuration, 1.5, accuracy: 0.05)
                let videoTracks = try await movie.loadTracks(withMediaType: .video)
                let track = try XCTUnwrap(videoTracks.first)
                let size = try await track.load(.naturalSize)
                XCTAssertEqual(size.width, size.height)
                let frame = try await MediaProcessor.frame(url: output.urls[0], time: 0.5)
                XCTAssertEqual(Double(frame.width), Double(frame.height), accuracy: 1)
            } else {
                let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(output.urls[0] as CFURL, nil))
                let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
                XCTAssertEqual(image.width, image.height)
                if format == .gif { XCTAssertGreaterThan(CGImageSourceGetCount(imageSource), 10) }
            }
        }
    }

    @MainActor func testPreviewMatchesExportGeometryAndColor() async throws {
        var settings = EditSettings()
        settings.rotation = 1; settings.mirrored = true; settings.ratio = .landscape
        settings.cropY = 0.8; settings.look = .warm; settings.exposure = 0.3
        let project = project(settings: settings)
        let item = try await MediaProcessor.previewItem(source: source, clip: project.clips[0], settings: settings)
        let previewGenerator = AVAssetImageGenerator(asset: item.asset)
        previewGenerator.videoComposition = item.videoComposition
        previewGenerator.requestedTimeToleranceBefore = .zero
        previewGenerator.requestedTimeToleranceAfter = .zero
        let preview = try await previewGenerator.image(at: CMTime(seconds: 1.25, preferredTimescale: 600)).image
        let cover = try await MediaProcessor.frame(url: source, time: 2.25, settings: settings, maxSize: CGSize(width: 4096, height: 4096))
        XCTAssertEqual(preview.width, cover.width)
        XCTAssertEqual(preview.height, cover.height)
        func average(_ image: CGImage) -> [UInt8] {
            var pixel = [UInt8](repeating: 0, count: 4)
            let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return pixel
        }
        let lhs = average(preview), rhs = average(cover)
        for index in 0..<3 { XCTAssertEqual(Double(lhs[index]), Double(rhs[index]), accuracy: 6, "Preview and exported still must agree") }
        for x in 0..<2 {
            for y in 0..<2 {
                let region = CGRect(x: x * preview.width / 2, y: y * preview.height / 2, width: preview.width / 2, height: preview.height / 2)
                let a = average(preview.cropping(to: region)!), b = average(cover.cropping(to: region)!)
                for channel in 0..<3 { XCTAssertEqual(Double(a[channel]), Double(b[channel]), accuracy: 6) }
            }
        }
    }

    func testAudioPreservedAndMuted() async throws {
        let combinedURL = try XCTUnwrap(Bundle(for: ConversionTests.self).url(forResource: "AudioFixture", withExtension: "mov"))
        for muted in [false, true] {
            var settings = EditSettings(); settings.muted = muted; settings.speed = 1.5
            let project = project(settings: settings)
            let output = try await LivePhotoExporter().export(source: combinedURL, project: project, clip: project.clips[0], directory: folder.appendingPathComponent(muted ? "muted" : "audio")) { _ in }
            let asset = AVURLAsset(url: output.urls[1])
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertEqual(tracks.isEmpty, muted)
            let duration = try await asset.load(.duration).seconds
            XCTAssertEqual(duration, 2, accuracy: 0.05)
        }
    }

    @MainActor func testBatchExportCompletesAllClips() async throws {
        let store = ProjectStore(root: folder.appendingPathComponent("BatchLibrary"))
        var imported = try await store.importVideo(source, title: "Batch test")
        imported.clips = [Clip(start: 0, end: 2, cover: 1), Clip(start: 3, end: 6, cover: 4.5)]
        let coordinator = ExportCoordinator()
        coordinator.start(projects: [imported], store: store, saveToPhotos: false, purchases: PurchaseStore(observeTransactions: false))
        let deadline = Date().addingTimeInterval(30)
        while coordinator.running && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(coordinator.running)
        XCTAssertNil(coordinator.errorMessage)
        XCTAssertEqual(coordinator.completed.count, 2)
        XCTAssertEqual(store.exports.count, 2)
        XCTAssertEqual(coordinator.progress, 1)
    }

    @MainActor func testImportPersistenceAndIndependentExportHistory() async throws {
        let root = folder.appendingPathComponent("Library")
        let store = ProjectStore(root: root)
        var imported = try await store.importVideo(source, title: "Persistent draft")
        imported.settings.ratio = .square
        imported.clips.append(Clip(start: 3, end: 6, cover: 4))
        store.update(imported); store.persist()
        let reloaded = ProjectStore(root: root)
        XCTAssertEqual(reloaded.projects.first?.clips.count, 2)
        XCTAssertEqual(reloaded.projects.first?.settings.ratio, .square)
        let output = try await LivePhotoExporter().export(source: store.url(for: imported.filename), project: imported, clip: imported.clips[0], directory: root.appendingPathComponent("Exports/test")) { _ in }
        _ = store.record(output, project: imported, saved: false)
        store.delete(imported)
        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertEqual(store.exports.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.urls[0].path))
        store.delete(store.exports[0])
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.urls[0].path))
    }

    func testCancellationRemovesPartialOutput() async throws {
        let directory = folder.appendingPathComponent("Cancelled")
        let project = project()
        let task = Task {
            try await LivePhotoExporter().export(source: source, project: project, clip: project.clips[0], directory: directory) { _ in }
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled export must not succeed") }
        catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testClearCoverSelectionStaysInsideTrimAndDetectsDetail() async throws {
        let clip = Clip(start: 2, end: 4, cover: 3)
        let time = try await FrameAnalysis.bestCover(source: source, clip: clip, settings: EditSettings())
        XCTAssertGreaterThanOrEqual(time, clip.start)
        XCTAssertLessThan(time, clip.end)
        let frame = try await MediaProcessor.frame(url: source, time: time)
        let flat = CGContext(data: nil, width: 192, height: 192, bitsPerComponent: 8, bytesPerRow: 192 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        flat.setFillColor(CGColor(gray: 0.5, alpha: 1)); flat.fill(CGRect(x: 0, y: 0, width: 192, height: 192))
        XCTAssertGreaterThan(FrameAnalysis.score(frame), FrameAnalysis.score(flat.makeImage()!))
    }

    func testSourceWithRotationMetadataExportsUpright() async throws {
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let descriptions = try await track.load(.formatDescriptions)
        let rotatedURL = folder.appendingPathComponent("rotated-source.mov")
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        let writer = try AVAssetWriter(outputURL: rotatedURL, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: descriptions.first)
        input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1280, ty: 0)
        writer.add(input)
        XCTAssertTrue(writer.startWriting()); XCTAssertTrue(reader.startReading()); writer.startSession(atSourceTime: .zero)
        while let sample = output.copyNextSampleBuffer() {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            XCTAssertTrue(input.append(sample))
        }
        input.markAsFinished(); await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        let project = project()
        let result = try await LivePhotoExporter().export(source: rotatedURL, project: project, clip: project.clips[0], directory: folder.appendingPathComponent("RotatedExport")) { _ in }
        let movie = AVURLAsset(url: result.urls[1])
        let finalTracks = try await movie.loadTracks(withMediaType: .video)
        let finalTrack = try XCTUnwrap(finalTracks.first)
        let size = try await finalTrack.load(.naturalSize)
        let transform = try await finalTrack.load(.preferredTransform)
        XCTAssertEqual(size.width, 1280)
        XCTAssertEqual(size.height, 960)
        XCTAssertEqual(transform, .identity)
        let photoSource = try XCTUnwrap(CGImageSourceCreateWithURL(result.urls[0] as CFURL, nil))
        let cover = try XCTUnwrap(CGImageSourceCreateImageAtIndex(photoSource, 0, nil))
        XCTAssertEqual(cover.width, 1280)
        XCTAssertEqual(cover.height, 960)
    }
}
