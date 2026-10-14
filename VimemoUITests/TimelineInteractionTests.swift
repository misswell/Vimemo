import XCTest
import AVFoundation
import UIKit

final class TimelineInteractionTests: XCTestCase {
    @MainActor private func revealTimeline(_ app: XCUIApplication) -> XCUIElement {
        let body = app.descendants(matching: .any)["timelineSelectionBody"]
        XCTAssertTrue(body.waitForExistence(timeout: 20))
        for _ in 0..<8 {
            if app.buttons["timelineOverview"].isHittable,
               app.buttons["timelineOverview"].frame.maxY < app.buttons["editorTool0"].frame.minY - 8 { break }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let height = app.frame.height
            origin.withOffset(CGVector(dx: app.frame.width * 0.85, dy: height * 0.65))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.85, dy: height * 0.4)))
        }
        XCTAssertTrue(body.isHittable)
        return body
    }

    @MainActor private func seconds(_ element: XCUIElement) -> Double {
        let value = element.value as? String
        let label = value?.isEmpty == false ? value! : element.label
        let parts = label.split(separator: ":")
        return parts.count == 2 ? (Double(parts[0]) ?? 0) * 60 + (Double(parts[1]) ?? 0) : -1
    }
    @MainActor private func scale(_ app: XCUIApplication) -> Double {
        Double(app.staticTexts["timelineZoomScale"].label.replacingOccurrences(of: "×", with: "")) ?? -1
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testPinchOverviewBodyMovementAndFineAdjustment() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--demo-editor", "-unlimitedDuration", "NO"]
        app.launch()
        let body = revealTimeline(app)
        let start = app.descendants(matching: .any)["trimStartHandle"]
        let end = app.descendants(matching: .any)["trimEndHandle"]
        let initialDuration = seconds(end) - seconds(start)
        let initialScale = scale(app)
        body.pinch(withScale: 2, velocity: 1)
        XCTAssertGreaterThan(scale(app), initialScale)
        XCTAssertEqual(seconds(app.staticTexts["timelineClipEnd"]) - seconds(app.staticTexts["timelineClipStart"]), initialDuration, accuracy: 0.02)
        app.buttons["timelineFocusSelection"].tap()
        let grip = body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let before = seconds(start)
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: 25, dy: 0)))
        XCTAssertGreaterThan(seconds(start), before)
        XCTAssertEqual(seconds(end) - seconds(start), initialDuration, accuracy: 0.02)
        app.buttons["timelineOverview"].tap()
        XCTAssertEqual(scale(app), 1)
        app.buttons["timelineZoomIn"].tap()
        XCTAssertGreaterThan(scale(app), 1)
        body.doubleTap()
        XCTAssertEqual(scale(app), 1, "Double tap must restore the complete source viewport")
        app.buttons["timelineFocusSelection"].tap()
        let fineStart = seconds(start)
        let fineGrip = body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        fineGrip.press(forDuration: 0.6, thenDragTo: fineGrip.withOffset(CGVector(dx: 25, dy: 0)))
        XCTAssertGreaterThan(seconds(start), fineStart)
        XCTAssertEqual(seconds(end) - seconds(start), initialDuration, accuracy: 0.02)
        attach(app, "timeline-zoom-body-fine")
    }

    @MainActor func testTwoHourSourceThreeSecondHandlesBodyAndOverview() async throws {
        let source = try await twoHourVideo()
        defer { try? FileManager.default.removeItem(at: source) }
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--test-editor-video", source.path, "-unlimitedDuration", "NO"]
        app.launch()
        let body = revealTimeline(app)
        let start = app.descendants(matching: .any)["trimStartHandle"]
        let end = app.descendants(matching: .any)["trimEndHandle"]
        XCTAssertEqual(scale(app), 200)
        XCTAssertGreaterThanOrEqual(end.frame.midX - start.frame.midX, 119)
        XCTAssertEqual(seconds(end) - seconds(start), 3, accuracy: 0.02)
        let beforeStart = seconds(start)
        var grip = start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: 8, dy: 0)))
        XCTAssertGreaterThan(seconds(start), beforeStart)
        let beforeEnd = seconds(end)
        grip = end.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: -8, dy: 0)))
        XCTAssertLessThan(seconds(end), beforeEnd)
        let length = seconds(end) - seconds(start), beforeMove = seconds(start)
        grip = body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: 35, dy: 0)))
        XCTAssertGreaterThan(seconds(start), beforeMove)
        XCTAssertEqual(seconds(end) - seconds(start), length, accuracy: 0.02)
        attach(app, "two-hour-source-operable-selection")
        app.buttons["timelineOverview"].tap()
        XCTAssertEqual(scale(app), 1)
        XCTAssertEqual(seconds(app.staticTexts["timelineViewportStart"]), 0, accuracy: 0.02)
        XCTAssertEqual(seconds(app.staticTexts["timelineViewportEnd"]), 7200, accuracy: 1)
        let trackWidth = app.staticTexts["timelineViewportEnd"].frame.maxX - app.staticTexts["timelineViewportStart"].frame.minX
        grip = body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let coarseDistance = (3599 - seconds(start)) / 7200 * trackWidth
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: coarseDistance, dy: 0)))
        XCTAssertEqual(seconds(start), 3599, accuracy: 25, "Overview should reach the 59:59 region in a single body drag")
        XCTAssertEqual(seconds(end) - seconds(start), length, accuracy: 0.02)
        XCTAssertEqual(scale(app), 200, "Releasing a coarse move must refocus the selected clip")
        XCTAssertLessThanOrEqual(seconds(app.staticTexts["timelineViewportStart"]), seconds(start))
        XCTAssertGreaterThanOrEqual(seconds(app.staticTexts["timelineViewportEnd"]), seconds(end))
        attach(app, "two-hour-source-at-5959")
        app.buttons["timelineFocusSelection"].tap()
        XCTAssertEqual(scale(app), 200)
    }

    /// A real two-hour H.264 track with sparse static samples keeps the fixture tiny.
    private func twoHourVideo() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("timeline-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 96, AVVideoHeightKey: 96,
            AVVideoCompressionPropertiesKey: [AVVideoExpectedSourceFrameRateKey: 30]
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 96, kCVPixelBufferHeightKey as String: 96
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 96, 96, kCVPixelFormatType_32ARGB, nil, &pixelBuffer), kCVReturnSuccess)
        let buffer = try XCTUnwrap(pixelBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 128, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for time in [0.0, 1.0 / 30, 3598, 3599, 7198, 7199, 7200 - 1.0 / 30] {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw try XCTUnwrap(writer.error) }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600)))
        }
        writer.endSession(atSourceTime: CMTime(seconds: 7200, preferredTimescale: 600))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        let duration = try await AVURLAsset(url: url).load(.duration)
        XCTAssertEqual(duration.seconds, 7200, accuracy: 0.1)
        return url
    }
}
