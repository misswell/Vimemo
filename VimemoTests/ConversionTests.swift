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

    func testUnreadableSourceReportsCoverStageAndRemovesPartialExport() async throws {
        let outputFolder = folder.appendingPathComponent("FailedExport")
        do {
            _ = try await LivePhotoExporter().export(source: folder.appendingPathComponent("missing.mov"), project: project(), clip: project().clips[0], directory: outputFolder) { _ in }
            XCTFail("Missing source must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("读取封面"))
            XCTAssertTrue(error.localizedDescription.contains("诊断日志"))
            XCTAssertFalse(error.localizedDescription.contains(folder.path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputFolder.path))
    }

    func testNativeCoverDecodesEnoughPixelsForZoomedCrop() async throws {
        var settings = EditSettings()
        settings.ratio = .square; settings.cropZoom = 2
        let asset = AVURLAsset(url: source)
        let layout = try await MediaProcessor.nativeFrameLayout(asset: asset, settings: settings, maxSize: CGSize(width: 800, height: 800))
        XCTAssertEqual(layout.outputSize, CGSize(width: 800, height: 800))
        XCTAssertEqual(layout.decodeSize, CGSize(width: 960, height: 1280), "A zoomed crop must decode native pixels instead of enlarging a small full-frame thumbnail")
        let image = try await MediaProcessor.frame(url: source, time: 2.25, settings: settings)
        XCTAssertEqual(image.width, 800); XCTAssertEqual(image.height, 800)
    }

    func testNonDefaultSourceTrackIDCanRenderCoverAndExport() async throws {
        // The original cover path applied composition-track instructions (ID 1)
        // to the source asset. A valid movie is allowed to use any track ID.
        var data = try Data(contentsOf: source)
        func read32(_ offset: Int) -> UInt32 {
            (0..<4).reduce(UInt32(0)) { ($0 << 8) | UInt32(data[offset + $1]) }
        }
        func write32(_ value: UInt32, at offset: Int) {
            for index in 0..<4 { data[offset + index] = UInt8((value >> (8 * (3 - index))) & 0xff) }
        }
        var changed = false
        func visit(_ lower: Int, _ upper: Int) throws {
            var offset = lower
            while offset + 8 <= upper {
                var header = 8, size = Int(read32(offset))
                if size == 1 {
                    guard offset + 16 <= upper else { throw StudioError.message("Invalid test movie atom") }
                    header = 16
                    size = Int((UInt64(read32(offset + 8)) << 32) | UInt64(read32(offset + 12)))
                } else if size == 0 { size = upper - offset }
                guard size >= header, size <= upper - offset else { throw StudioError.message("Invalid test movie atom") }
                let type = String(bytes: data[(offset + 4)..<(offset + 8)], encoding: .ascii)
                if type == "moov" || type == "trak" { try visit(offset + header, offset + size) }
                if type == "tkhd" {
                    let field = offset + header + (data[offset + header] == 1 ? 20 : 12)
                    guard field + 4 <= offset + size else { throw StudioError.message("Invalid test track header") }
                    write32(42, at: field); changed = true
                }
                if type == "mvhd" { write32(43, at: offset + size - 4) }
                offset += size
            }
        }
        try visit(0, data.count)
        XCTAssertTrue(changed)
        let differentID = folder.appendingPathComponent("track42.mov")
        try data.write(to: differentID)
        let asset = AVURLAsset(url: differentID)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(try XCTUnwrap(tracks.first).trackID, 42)
        let image = try await MediaProcessor.frame(url: differentID, time: 2.25, settings: EditSettings())
        XCTAssertGreaterThan(image.width, 0)
        let renderer = CoverFrameRenderer(source: differentID, project: project())
        let selected = try await renderer.frame(time: 2.25, photo: nil, exact: true)
        XCTAssertEqual(selected.width, image.width); XCTAssertEqual(selected.height, image.height)
        let output = try await LivePhotoExporter().export(source: differentID, project: project(), clip: project().clips[0], directory: folder.appendingPathComponent("Track42Export")) { _ in }
        let movie = AVURLAsset(url: output.urls[1])
        let duration = try await movie.load(.duration).seconds
        XCTAssertEqual(duration, 3, accuracy: 0.05)
    }

    func testLivePhotoPairIsRecognizedAndMetadataMatches() async throws {
        var settings = EditSettings()
        settings.preserveLocation = true; settings.cropZoom = 1.8; settings.cropX = 0.35
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
        settings.cropZoom = 2.25; settings.cropX = 0.3
        let project = project(settings: settings)
        let prepared = try await MediaProcessor.previewItem(source: source, clip: project.clips[0], settings: settings)
        let previewGenerator = AVAssetImageGenerator(asset: prepared.item.asset)
        previewGenerator.requestedTimeToleranceBefore = .zero
        previewGenerator.requestedTimeToleranceAfter = .zero
        let rawPreview = try await previewGenerator.image(at: CMTime(seconds: 2.25, preferredTimescale: 600)).image
        let rendered = prepared.render(CIImage(cgImage: rawPreview))
        let preview = try XCTUnwrap(MediaProcessor.context.createCGImage(rendered, from: rendered.extent))
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
        let output = try await LivePhotoExporter().export(source: source, project: project, clip: project.clips[0], directory: folder.appendingPathComponent("ZoomedPreview")) { _ in }
        let movie = try XCTUnwrap(output.urls.first { $0.pathExtension.lowercased() == "mov" })
        let exported = try await MediaProcessor.frame(url: movie, time: 2.25 - project.clips[0].start, maxSize: CGSize(width: 4096, height: 4096))
        XCTAssertEqual(exported.width, preview.width); XCTAssertEqual(exported.height, preview.height)
        for x in 0..<2 {
            for y in 0..<2 {
                let region = CGRect(x: x * preview.width / 2, y: y * preview.height / 2, width: preview.width / 2, height: preview.height / 2)
                let a = average(preview.cropping(to: region)!), b = average(exported.cropping(to: region)!)
                for channel in 0..<3 { XCTAssertEqual(Double(a[channel]), Double(b[channel]), accuracy: 8, "Zoomed exported video must match preview") }
            }
        }
    }

    @MainActor func testVideoPreviewCanActuallyPlay() async throws {
        let prepared = try await MediaProcessor.previewItem(source: source, clip: project().clips[0], settings: EditSettings())
        let item = prepared.item
        let player = AVPlayer(playerItem: item)
        let layer = AVPlayerLayer(player: player)
        layer.frame = CGRect(x: 0, y: 0, width: 240, height: 320)
        player.isMuted = true
        await player.seek(to: prepared.start, toleranceBefore: .zero, toleranceAfter: .zero)
        player.playImmediately(atRate: prepared.rate)
        defer { player.pause(); layer.player = nil }
        for _ in 0..<100 {
            if item.status != .unknown { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(item.status, .readyToPlay, "\(String(describing: item.error))")
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertGreaterThan(player.currentTime().seconds, prepared.start.seconds + 0.1)
    }

    @MainActor func testPreviewStopsAtClipEndWithSelectedSpeed() async throws {
        var settings = EditSettings(); settings.speed = 2
        let prepared = try await MediaProcessor.previewItem(source: source, clip: Clip(start: 1, end: 2.5, cover: 1.5), settings: settings)
        let player = AVPlayer(playerItem: prepared.item)
        player.isMuted = true
        defer { player.pause() }
        let ended = expectation(forNotification: .AVPlayerItemDidPlayToEndTime, object: prepared.item)
        let seeked = await player.seek(to: prepared.start, toleranceBefore: .zero, toleranceAfter: .zero)
        XCTAssertTrue(seeked)
        player.playImmediately(atRate: prepared.rate)
        XCTAssertEqual(player.rate, 2)
        await fulfillment(of: [ended], timeout: 3)
        XCTAssertEqual(player.currentTime().seconds, 2.5, accuracy: 0.06, "Preview must stop at the clip boundary")
    }

    @MainActor func testProjectSoundSettingPersistsAndPreviewRetainsAudio() async throws {
        let source = try XCTUnwrap(Bundle(for: ConversionTests.self).url(forResource: "AudioFixture", withExtension: "mov"))
        let root = folder.appendingPathComponent("SoundLibrary")
        let store = ProjectStore(root: root)
        var project = try await store.importVideo(source, title: "Sound")
        XCTAssertTrue(project.hasAudio)
        XCTAssertFalse(project.settings.muted)
        for muted in [true, false] {
            project.settings.muted = muted
            store.update(project)
            XCTAssertTrue(store.persist())
            let restored = try XCTUnwrap(ProjectStore(root: root).projects.first)
            XCTAssertEqual(restored.settings.muted, muted)
            var previewSettings = restored.settings
            previewSettings.muted = false
            let item = try await MediaProcessor.previewItem(source: source, clip: restored.clips[0], settings: previewSettings).item
            let tracks = try await item.asset.loadTracks(withMediaType: .audio)
            XCTAssertFalse(tracks.isEmpty, "Retain audio so the project speaker can toggle without rebuilding")
            let player = AVPlayer(playerItem: item)
            player.isMuted = restored.settings.muted
            XCTAssertEqual(player.isMuted, muted)
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
        let exportFolder = root.appendingPathComponent("Exports/\(UUID().uuidString)")
        let output = try await LivePhotoExporter().export(source: store.url(for: imported.filename), project: imported, clip: imported.clips[0], directory: exportFolder) { _ in }
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

    /// A copy of the demo source carrying 90° rotation metadata, the shape of
    /// real camera recordings that iOS 27 must not decode through its compositor.
    private func rotatedSource() async throws -> URL {
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
        return rotatedURL
    }

    private func quadrantAverages(_ image: CGImage) -> [[UInt8]] {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        var result: [[UInt8]] = []
        for y in 0..<2 {
            for x in 0..<2 {
                let offsetX = CGFloat(x) * width / 2
                let offsetY = CGFloat(y) * height / 2
                var pixel = [UInt8](repeating: 0, count: 4)
                let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.interpolationQuality = .none
                context.translateBy(x: -offsetX, y: -offsetY)
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                result.append(pixel)
            }
        }
        return result
    }

    func testRotatedSourceStillFramesMatchExportedComposition() async throws {
        let rotatedURL = try await rotatedSource()
        let settings = EditSettings()
        let frame = try await MediaProcessor.frame(url: rotatedURL, time: 2.25, settings: settings, maxSize: CGSize(width: 4096, height: 4096))
        XCTAssertEqual(frame.width, 1280, "The stored-orientation decode must be oriented upright in Core Image")
        XCTAssertEqual(frame.height, 960)
        let renderer = CoverFrameRenderer(source: rotatedURL, project: project())
        let cover = try await renderer.frame(time: 2.25, photo: nil, exact: true)
        XCTAssertEqual(cover.width, 800, "The editor cover keeps its 800-pixel bound but must be upright")
        XCTAssertEqual(cover.height, 600)
        // The rotated display is the stored frame turned 90° clockwise: display
        // top-left shows the stored bottom-left quadrant, etc.
        let stored = try await MediaProcessor.frame(url: source, time: 2.25, settings: settings, maxSize: CGSize(width: 4096, height: 4096))
        XCTAssertEqual(stored.width, 960); XCTAssertEqual(stored.height, 1280)
        let displayQuadrants = quadrantAverages(frame)
        let storedQuadrants = quadrantAverages(stored)
        // display[y][x] == stored[x][1 - y] for this clockwise transform
        for y in 0..<2 {
            for x in 0..<2 {
                let display = displayQuadrants[y * 2 + x]
                let expected = storedQuadrants[x * 2 + (1 - y)]
                for channel in 0..<3 {
                    XCTAssertEqual(Double(display[channel]), Double(expected[channel]), accuracy: 12,
                                   "Display quadrant (\(x),\(y)) must show the rotated stored quadrant")
                }
            }
        }
    }

    func testComposedFrameFallbackMatchesGeneratorGeometry() async throws {
        let settings = EditSettings()
        let reference = try await MediaProcessor.frame(url: source, time: 2.25, settings: settings)
        let layout = try await MediaProcessor.nativeFrameLayout(asset: AVURLAsset(url: source), settings: settings, maxSize: CGSize(width: 800, height: 800))
        let fallback = try await MediaProcessor.composedFrame(source: source, time: 2.25, settings: settings, outputSize: layout.outputSize)
        XCTAssertEqual(fallback.width, reference.width)
        XCTAssertEqual(fallback.height, reference.height)
        for (index, (a, b)) in zip(quadrantAverages(fallback), quadrantAverages(reference)).enumerated() {
            for channel in 0..<3 {
                XCTAssertEqual(Double(a[channel]), Double(b[channel]), accuracy: 12,
                               "Reader-fallback quadrant \(index) must match the generator geometry")
            }
        }
    }

    func testSourceWithRotationMetadataExportsUpright() async throws {
        let rotatedURL = try await rotatedSource()
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
