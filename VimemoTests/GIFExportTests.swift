import XCTest
import ImageIO
@testable import Vimemo

final class GIFExportTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("GIFTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    private func export(size: GIFSize, fps: GIFFrameRate, duration: Double = 0.7, square: Bool = false, speed: Double = 1) async throws -> CGImageSource {
        let source = try XCTUnwrap(Bundle(for: ProjectStore.self).url(forResource: "Demo", withExtension: "mov"))
        var project = VideoProject(title: "GIF", filename: "source.mov", thumbnailFilename: "cover.jpg", duration: 6, width: 960, height: 1280, frameRate: 30, clips: [Clip(start: 1, end: 1 + duration, cover: 1.2)])
        project.settings.format = .gif
        project.settings.gifSize = size
        project.settings.gifFrameRate = fps
        project.settings.speed = speed
        if square { project.settings.ratio = .square; project.settings.rotation = 1; project.settings.mirrored = true }
        let output = try await LivePhotoExporter().export(source: source, project: project, clip: project.clips[0], directory: folder.appendingPathComponent(UUID().uuidString)) { _ in }
        XCTAssertEqual(output.urls.map(\.pathExtension), ["gif"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.directory.appendingPathComponent("motion.mov").path))
        return try XCTUnwrap(CGImageSourceCreateWithURL(output.urls[0] as CFURL, nil))
    }

    func testAllSizesPreserveAspectRatioAndDoNotEnlargeSource() async throws {
        for size in GIFSize.allCases {
            let gif = try await export(size: size, fps: .five)
            let frame = try XCTUnwrap(CGImageSourceCreateImageAtIndex(gif, 0, nil))
            XCTAssertEqual(frame.height, size.rawValue)
            XCTAssertEqual(Double(frame.width) / Double(frame.height), 0.75, accuracy: 0.005)
        }
        let square = try await export(size: .medium, fps: .ten, square: true)
        let frame = try XCTUnwrap(CGImageSourceCreateImageAtIndex(square, 0, nil))
        XCTAssertEqual(frame.width, 480); XCTAssertEqual(frame.height, 480)
        let originalSquare = try await export(size: .extraLarge, fps: .five, square: true)
        let originalFrame = try XCTUnwrap(CGImageSourceCreateImageAtIndex(originalSquare, 0, nil))
        XCTAssertEqual(originalFrame.width, 960)
        XCTAssertEqual(originalFrame.height, 960, "1280 preset must not enlarge a 960-pixel crop")
    }

    func testEveryFrameRateHasCorrectFrameCountLoopAndPlaybackDuration() async throws {
        for fps in GIFFrameRate.allCases {
            // Non-integral last frame, plus speed scaling; duration must not drift.
            let duration = 1.46 / 2
            let gif = try await export(size: .small, fps: fps, duration: 1.46, speed: 2)
            XCTAssertEqual(CGImageSourceGetCount(gif), Int(ceil(duration * Double(fps.rawValue))))
            let properties = try XCTUnwrap(CGImageSourceCopyProperties(gif, nil) as? [String: Any])
            let dictionary = try XCTUnwrap(properties[kCGImagePropertyGIFDictionary as String] as? [String: Any])
            XCTAssertEqual(dictionary[kCGImagePropertyGIFLoopCount as String] as? Int, 0)
            var playbackDuration = 0.0
            for index in 0..<CGImageSourceGetCount(gif) {
                let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(gif, index, nil) as? [String: Any])
                let frame = try XCTUnwrap(properties[kCGImagePropertyGIFDictionary as String] as? [String: Any])
                let delay = try XCTUnwrap(frame[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                XCTAssertGreaterThanOrEqual(delay, 0.01)
                playbackDuration += delay
            }
            XCTAssertEqual(playbackDuration, duration, accuracy: 0.011)
        }
    }

    func testShortestClipDoesNotRequestAFramePastTheEnd() async throws {
        let gif = try await export(size: .small, fps: .thirty, duration: 0.1)
        XCTAssertEqual(CGImageSourceGetCount(gif), 3)
    }

    func testOldDraftDefaultsAndNewSelectionsRoundTrip() throws {
        let oldData = try JSONEncoder().encode(EditSettings())
        var dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: oldData) as? [String: Any])
        dictionary.removeValue(forKey: "gifSize"); dictionary.removeValue(forKey: "gifFrameRate")
        let restored = try JSONDecoder().decode(EditSettings.self, from: JSONSerialization.data(withJSONObject: dictionary))
        XCTAssertEqual(restored.effectiveGIFSize, .standard)
        XCTAssertEqual(restored.effectiveGIFFrameRate, .twelve)
        for size in GIFSize.allCases {
            for fps in GIFFrameRate.allCases {
                var settings = restored; settings.gifSize = size; settings.gifFrameRate = fps
                XCTAssertEqual(try JSONDecoder().decode(EditSettings.self, from: JSONEncoder().encode(settings)), settings)
            }
        }
    }
}
