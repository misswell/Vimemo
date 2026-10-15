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
    /// Only handles that are actually drawn may be grabbed, so a hidden endpoint is a real
    /// failure. `waitForExistence` intermittently reports false here while the same query
    /// resolves on demand, so the presence check itself is polled.
    @MainActor private func handle(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let element = app.descendants(matching: .any)[name].firstMatch
        let deadline = Date().addingTimeInterval(20)
        while !element.exists, Date() < deadline { usleep(200_000) }
        XCTAssertTrue(element.exists, "\(name) must be drawn and grabbable")
        return element
    }
    /// The strip is the same padded width as the viewport label row.
    @MainActor private func stripWidth(_ app: XCUIApplication) -> CGFloat {
        app.staticTexts["timelineViewportEnd"].frame.maxX - app.staticTexts["timelineViewportStart"].frame.minX
    }
    /// The selection as drawn on screen, next to the same window measured from its real seconds.
    @MainActor private func drawnAndReal(_ app: XCUIApplication) -> (drawn: CGFloat, real: CGFloat) {
        let start = handle(app, "trimStartHandle"), end = handle(app, "trimEndHandle")
        let visible = seconds(app.staticTexts["timelineViewportEnd"]) - seconds(app.staticTexts["timelineViewportStart"])
        let duration = seconds(app.staticTexts["timelineClipEnd"]) - seconds(app.staticTexts["timelineClipStart"])
        return (end.frame.midX - start.frame.midX, CGFloat(duration / max(0.001, visible) * Double(stripWidth(app))))
    }
    @MainActor private func assertDrawnAtRealWidth(_ app: XCUIApplication, _ label: String) {
        let (drawn, real) = drawnAndReal(app)
        XCTAssertGreaterThan(real, 1, "\(label): the real window must be wide enough to draw")
        XCTAssertEqual(drawn, real, accuracy: 3, "\(label): the box must be the real trim window, not a widened placeholder")
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
        let start = handle(app, "trimStartHandle"), end = handle(app, "trimEndHandle")
        let initialDuration = seconds(end) - seconds(start)
        let initialScale = scale(app)
        assertDrawnAtRealWidth(app, "At launch")
        body.pinch(withScale: 2, velocity: 1)
        XCTAssertGreaterThan(scale(app), initialScale)
        XCTAssertEqual(seconds(app.staticTexts["timelineClipEnd"]) - seconds(app.staticTexts["timelineClipStart"]), initialDuration, accuracy: 0.02)
        assertDrawnAtRealWidth(app, "After a pinch")
        app.buttons["timelineFocusSelection"].tap()
        let grip = body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let before = seconds(start), beforeX = start.frame.midX
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: 25, dy: 0)))
        XCTAssertGreaterThan(seconds(start), before)
        XCTAssertEqual(start.frame.midX - beforeX, 25, accuracy: 4, "The selection must follow the finger")
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
        let start = handle(app, "trimStartHandle"), end = handle(app, "trimEndHandle")
        XCTAssertGreaterThan(scale(app), 200, "A two-hour source must open a window of seconds, not stop at a fixed ceiling")
        assertDrawnAtRealWidth(app, "A three-second selection on a two-hour source")
        XCTAssertEqual(drawnAndReal(app).drawn, stripWidth(app) / 2, accuracy: 3,
                       "Half the strip holds the selection, half leaves room on both sides")
        XCTAssertEqual(seconds(end) - seconds(start), 3, accuracy: 0.02)
        let beforeStart = seconds(start), beforeStartX = start.frame.midX, beforeEndX = end.frame.midX
        var grip = start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: 8, dy: 0)))
        XCTAssertGreaterThan(seconds(start), beforeStart)
        XCTAssertEqual(start.frame.midX - beforeStartX, 8, accuracy: 3, "The start grip must stay under the finger")
        XCTAssertEqual(end.frame.midX, beforeEndX, accuracy: 2, "Trimming the start must not slide the end grip")
        let beforeEnd = seconds(end), endX = end.frame.midX, startAgainX = start.frame.midX
        grip = end.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: -8, dy: 0)))
        XCTAssertLessThan(seconds(end), beforeEnd)
        XCTAssertEqual(end.frame.midX - endX, -8, accuracy: 3, "The end grip must stay under the finger")
        XCTAssertEqual(start.frame.midX, startAgainX, accuracy: 2, "Trimming the end must not slide the start grip")
        let length = seconds(end) - seconds(start), beforeMove = seconds(start), beforeBodyX = body.frame.midX
        grip = body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: 35, dy: 0)))
        XCTAssertGreaterThan(seconds(start), beforeMove)
        XCTAssertEqual(body.frame.midX - beforeBodyX, 35, accuracy: 4, "The whole selection must ride with the finger")
        XCTAssertEqual(seconds(end) - seconds(start), length, accuracy: 0.02)
        attach(app, "two-hour-source-operable-selection")

        app.buttons["timelineOverview"].tap()
        XCTAssertEqual(scale(app), 1)
        XCTAssertEqual(seconds(app.staticTexts["timelineViewportStart"]), 0, accuracy: 0.02)
        XCTAssertEqual(seconds(app.staticTexts["timelineViewportEnd"]), 7200, accuracy: 1)
        let (clamped, tiny) = drawnAndReal(app)
        XCTAssertLessThan(tiny, 1, "The real window is a sub-pixel sliver at full-source scale")
        XCTAssertEqual(clamped, min(120, stripWidth(app)), accuracy: 3, "The display floor keeps it grabbable in overview")

        let strip = stripWidth(app)
        for _ in 0..<2 {
            let gripAtMid = body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            gripAtMid.press(forDuration: 0.05, thenDragTo: gripAtMid.withOffset(CGVector(dx: strip / 2, dy: 0)))
        }
        XCTAssertEqual(seconds(start), 7197, accuracy: 2, "Two drags across the strip must reach the end of a two-hour source")
        XCTAssertEqual(seconds(end), 7200, accuracy: 2)
        XCTAssertEqual(scale(app), 1, "A coarse move keeps its scale so the source stays traversable")
        app.buttons["timelineFocusSelection"].tap()
        XCTAssertGreaterThanOrEqual(seconds(app.staticTexts["timelineViewportStart"]), 7100)
        assertDrawnAtRealWidth(app, "A selection at the very end of the source")
        attach(app, "two-hour-source-at-the-end")

        let precisionStart = seconds(start)
        grip = handle(app, "trimStartHandle").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: 8, dy: 0)))
        XCTAssertGreaterThan(seconds(start) - precisionStart, 0.05, "Grabbing a handle must trim in real seconds")
        XCTAssertLessThan(seconds(start) - precisionStart, 0.3)
        attach(app, "two-hour-source-handle-precision")
    }

    @MainActor func testOverviewHandleGrabRestoresRealWidthPrecision() async throws {
        let source = try await twoHourVideo()
        defer { try? FileManager.default.removeItem(at: source) }
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--test-editor-video", source.path, "-unlimitedDuration", "NO"]
        app.launch()
        let body = revealTimeline(app)
        app.buttons["timelineOverview"].tap()
        XCTAssertEqual(scale(app), 1)
        let start = handle(app, "trimStartHandle")
        let beforeSeconds = seconds(start), beforeX = start.frame.midX
        let grip = start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: 8, dy: 0)))
        XCTAssertGreaterThan(scale(app), 200, "Grabbing a trim handle must widen the viewport to the real window")
        assertDrawnAtRealWidth(app, "After grabbing a handle in overview")
        XCTAssertEqual(start.frame.midX - beforeX, 8, accuracy: 4, "The grip still tracks the finger through the refit")
        XCTAssertLessThan(seconds(start) - beforeSeconds, 0.5, "Refit precision must not turn 8 points into minutes")
        attach(app, "overview-to-real-width-on-grab")
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
