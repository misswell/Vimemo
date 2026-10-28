import XCTest
import AVFoundation
import UIKit

/// The timeline's contract, measured the way a finger experiences it: the strip always draws the
/// real trim window, the camera only moves when the user moves it, and a control the user grabbed
/// stays under that finger through every refit.
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
    /// The strip is the same padded width as the viewport label row, so the row tells the test
    /// where the strip begins and how wide it is.
    @MainActor private func stripGeometry(_ app: XCUIApplication) -> (x: CGFloat, width: CGFloat) {
        let start = app.staticTexts["timelineViewportStart"].frame
        let end = app.staticTexts["timelineViewportEnd"].frame
        return (start.minX, end.maxX - start.minX)
    }
    @MainActor private func viewport(_ app: XCUIApplication) -> (start: Double, end: Double) {
        (seconds(app.staticTexts["timelineViewportStart"]), seconds(app.staticTexts["timelineViewportEnd"]))
    }
    @MainActor private func selection(_ app: XCUIApplication) -> (start: Double, end: Double) {
        (seconds(app.staticTexts["timelineClipStart"]), seconds(app.staticTexts["timelineClipEnd"]))
    }
    @MainActor private func secondsPerPoint(_ app: XCUIApplication) -> Double {
        let window = viewport(app)
        return (window.end - window.start) / Double(max(1, stripGeometry(app).width))
    }
    /// Every drawn pixel comes from the viewport the labels report, so the test predicts the box
    /// instead of trusting a screenshot. The stroke is drawn inside the shape, which extends the
    /// element's bounds by its own width.
    @MainActor private func assertBoxIsTheRealWindow(_ app: XCUIApplication, _ label: String) {
        let (origin, strip) = stripGeometry(app)
        let window = viewport(app), clip = selection(app)
        XCTAssertGreaterThan(window.end - window.start, 0.001, "\(label): the viewport must have width")
        let left = CGFloat((clip.start - window.start) / (window.end - window.start)) * strip
        let right = CGFloat((clip.end - window.start) / (window.end - window.start)) * strip
        let box = app.descendants(matching: .any)["timelineSelectionFrame"].firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 20), "\(label): the selection must be drawn")
        XCTAssertEqual(box.frame.minX, origin + max(0, left) - Self.stroke / 2, accuracy: 3,
                       "\(label): the box must start where its real seconds are")
        XCTAssertEqual(box.frame.width, max(3, min(strip, right) - max(0, left)) + Self.stroke, accuracy: 3,
                       "\(label): the box is the real trim window, never a widened placeholder")
    }
    /// The selection frame's stroke width, which the element bounds include.
    private static let stroke: CGFloat = 3
    /// A sub-pixel selection still has to hand the user three separate targets, each 44 points
    /// wherever the strip has room for them.
    @MainActor private func assertFortyFourPointBands(_ app: XCUIApplication, _ label: String) {
        let (_, strip) = stripGeometry(app)
        let start = handle(app, "trimStartHandle")
        let body = handle(app, "timelineSelectionBody")
        let end = handle(app, "trimEndHandle")
        for (element, name) in [(start, "入点"), (body, "选区"), (end, "出点")] {
            XCTAssertGreaterThanOrEqual(element.frame.width, min(44, strip / 3) - 1,
                                        "\(label): \(name) must be a real touch band, not a hairline")
            XCTAssertTrue(element.isHittable, "\(label): \(name) must be reachable")
        }
        XCTAssertLessThanOrEqual(start.frame.maxX, body.frame.minX + 1, "\(label): bands must not fight over one touch")
        XCTAssertLessThanOrEqual(body.frame.maxX, end.frame.minX + 1, "\(label): bands must not fight over one touch")
    }
    @MainActor private func assertOpensInOverview(_ app: XCUIApplication, _ label: String, duration: Double? = nil) {
        XCTAssertEqual(scale(app), 1, accuracy: 0.001, "\(label): a clip must open on the whole source")
        let window = viewport(app)
        XCTAssertEqual(window.start, 0, accuracy: 0.05, "\(label): overview starts at the head of the source")
        if let duration {
            XCTAssertEqual(window.end, duration, accuracy: max(0.5, duration * 0.005),
                           "\(label): overview must reach the tail of the source")
        }
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    // MARK: - Opening and drawing

    @MainActor func testOpeningAThreeMinuteSourceShowsTheWholeTimelineAndStillGrabsEverything() async throws {
        let source = try await syntheticVideo(duration: 180)
        defer { try? FileManager.default.removeItem(at: source) }
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--test-editor-video", source.path, "-unlimitedDuration", "NO"]
        app.launch()
        _ = revealTimeline(app)
        assertOpensInOverview(app, "At launch", duration: 180)
        assertBoxIsTheRealWindow(app, "A three-second window in overview")
        let clip = selection(app)
        XCTAssertEqual(clip.end - clip.start, 3, accuracy: 0.02, "A fresh import trims three seconds")
        assertFortyFourPointBands(app, "A sliver of a three-minute source")
        attach(app, "overview-sliver-with-bands")

        app.buttons["timelineFocusSelection"].tap()
        XCTAssertGreaterThan(scale(app), 20, "聚焦片段 must open precision")
        let strip = stripGeometry(app).width
        assertBoxIsTheRealWindow(app, "After 聚焦片段")
        XCTAssertEqual(app.descendants(matching: .any)["timelineSelectionFrame"].firstMatch.frame.width,
                       strip / 2 + Self.stroke, accuracy: 3, "Precision gives the selection half the strip")
        let focused = selection(app)
        XCTAssertEqual(focused.start, clip.start, accuracy: 0.001, "Focusing must not move the trim")
        XCTAssertEqual(focused.end, clip.end, accuracy: 0.001, "Focusing must not move the trim")
        attach(app, "precision-half-strip")
    }

    // MARK: - The camera belongs to the fingers

    @MainActor func testMovingTheCameraNeverEditsTheTrimAndNeverYanksItBackOnRelease() async throws {
        let source = try await syntheticVideo(duration: 180)
        defer { try? FileManager.default.removeItem(at: source) }
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--test-editor-video", source.path, "-unlimitedDuration", "NO"]
        app.launch()
        let body = revealTimeline(app)
        app.buttons["timelineFocusSelection"].tap()
        let clip = selection(app)
        let (origin, strip) = stripGeometry(app)
        // Drag empty strip: the camera moves, the trim does not.
        let blank = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: origin + strip - 20, dy: body.frame.midY))
        blank.press(forDuration: 0.05, thenDragTo: blank.withOffset(CGVector(dx: -200, dy: 0)))
        let panned = selection(app)
        XCTAssertEqual(panned.start, clip.start, accuracy: 0.001, "Panning the viewport must never move the trim")
        XCTAssertEqual(panned.end, clip.end, accuracy: 0.001, "Panning the viewport must never move the trim")
        XCTAssertGreaterThan(viewport(app).start, clip.end, "The finger should have carried the camera past the selection")
        XCTAssertTrue(app.descendants(matching: .any)["timelineSelectionOffscreen"].waitForExistence(timeout: 10),
                      "A selection outside the viewport is a legal state and the strip must say so")
        XCTAssertEqual(app.buttons["timelineFocusSelection"].label, "片段在视野外 · 定位",
                       "The only way back has to be visible where the selection is not")
        attach(app, "selection-off-screen-after-pan")

        // Pinch in, then let go. Releasing must keep the zoom and anchor the fingers chose, so the
        // selection stays off screen instead of being dragged back into view.
        let beforePinch = scale(app)
        app.descendants(matching: .any)["timelineTrack"].pinch(withScale: 2, velocity: 1)
        XCTAssertGreaterThan(scale(app), beforePinch, "A pinch must zoom")
        let pinched = selection(app)
        XCTAssertEqual(pinched.start, clip.start, accuracy: 0.001, "Zooming must never change the trim data")
        XCTAssertEqual(pinched.end, clip.end, accuracy: 0.001, "Zooming must never change the trim data")
        XCTAssertTrue(app.descendants(matching: .any)["timelineSelectionOffscreen"].exists,
                      "Releasing a pinch may leave the selection off screen; it must not re-aim the camera")
        XCTAssertGreaterThan(viewport(app).start, clip.end, "The viewport must stay where the fingers left it")
        attach(app, "pinch-release-keeps-the-camera")

        app.buttons["timelineFocusSelection"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["timelineSelectionOffscreen"].exists)
        let located = selection(app)
        XCTAssertEqual(located.start, clip.start, accuracy: 0.001, "定位 only moves the camera")
        XCTAssertEqual(located.end, clip.end, accuracy: 0.001, "定位 only moves the camera")
        assertBoxIsTheRealWindow(app, "After 定位")
    }

    // MARK: - Long sources stay operable

    @MainActor func testTwoHourSourceTracksTheFingerThroughPrecisionAndTravelsInOverview() async throws {
        let source = try await syntheticVideo(duration: 7200)
        defer { try? FileManager.default.removeItem(at: source) }
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--test-editor-video", source.path, "-unlimitedDuration", "NO"]
        app.launch()
        let body = revealTimeline(app)
        assertOpensInOverview(app, "A two-hour source at launch", duration: 7200)
        let strip = stripGeometry(app).width
        assertBoxIsTheRealWindow(app, "Three seconds of two hours")
        XCTAssertLessThan(app.descendants(matching: .any)["timelineSelectionFrame"].firstMatch.frame.width, 8,
                          "Two hours cannot show a three-second window wider than a few points")
        assertFortyFourPointBands(app, "A sliver of a two-hour source")

        // One overview drag is a coarse move at the true scale: half the strip is half the source.
        let beforeMove = selection(app)
        var grip = body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: 60, dy: 0)))
        XCTAssertEqual(scale(app), 1, "A coarse move keeps its scale so the source stays traversable")
        let moved = selection(app)
        let coarse = 60 * (7200 / Double(strip))
        XCTAssertEqual(moved.start - beforeMove.start, coarse, accuracy: coarse * 0.05,
                       "Overview drags measure against the whole source, not against a refitted box")
        XCTAssertEqual(moved.end - moved.start, beforeMove.end - beforeMove.start, accuracy: 0.02)

        // One continuous drag smoothly increases zoom; the handle remains under the
        // moving finger, and stationary pauses do not cause additional zoom steps.
        var end = handle(app, "trimEndHandle")
        let beforeEndGripX = end.frame.midX
        grip = end.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: 150, dy: 0)))
        XCTAssertEqual(scale(app), 1200, accuracy: 1, "A continuous drag reaches the precision fit smoothly")
        end = handle(app, "trimEndHandle")
        XCTAssertEqual(end.frame.midX, beforeEndGripX + 150, accuracy: 4,
                       "The round grip tracks the finger through continuous zoom")
        assertBoxIsTheRealWindow(app, "After one continuous zooming drag")

        end = handle(app, "trimEndHandle")
        let beforeX = end.frame.midX, beforeEnd = seconds(end)
        grip = end.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: -8, dy: 0)))
        end = handle(app, "trimEndHandle")
        XCTAssertEqual(scale(app), 1200, accuracy: 1, "A precision drag keeps the reached fit scale")
        XCTAssertEqual(end.frame.midX, beforeX - 8, accuracy: 3, "The grip must stay under the finger through the refit")
        XCTAssertEqual(beforeEnd - seconds(end), 8 * secondsPerPoint(app), accuracy: 0.05,
                       "Eight points of precision trim is eight points, not minutes")
        assertBoxIsTheRealWindow(app, "After grabbing the end grip")
        attach(app, "two-hour-precision-from-overview")

        // A second drag trims the same way, and the start of the window does not move.
        let startSeconds = seconds(app.staticTexts["timelineClipStart"])
        let secondX = end.frame.midX, secondEnd = seconds(end)
        grip = end.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: -8, dy: 0)))
        end = handle(app, "trimEndHandle")
        XCTAssertEqual(end.frame.midX, secondX - 8, accuracy: 3, "In precision the grip tracks the finger pixel for pixel")
        XCTAssertEqual(secondEnd - seconds(end), 8 * secondsPerPoint(app), accuracy: 0.05)
        XCTAssertEqual(seconds(app.staticTexts["timelineClipStart"]), startSeconds, accuracy: 0.001,
                       "Trimming the end must not slide the start")

        app.buttons["timelineOverview"].tap()
        assertOpensInOverview(app, "After 全片", duration: 7200)
        var drags = 0
        while selection(app).end < 7199, drags < 6 {
            grip = handle(app, "timelineSelectionBody").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: 70, dy: 0)))
            drags += 1
        }
        XCTAssertLessThan(drags, 6, "A handful of overview drags must be enough to cross two hours")
        XCTAssertEqual(selection(app).end, 7200, accuracy: 0.05, "The selection must reach the tail of the source")
        XCTAssertEqual(scale(app), 1, accuracy: 0.001, "Traversing the source must never force a zoom")
        app.buttons["timelineFocusSelection"].tap()
        XCTAssertGreaterThanOrEqual(viewport(app).start, 7100, "定位 must bring the camera to the selection")
        assertBoxIsTheRealWindow(app, "A selection at the very end of the source")
        XCTAssertEqual(app.descendants(matching: .any)["timelineSelectionFrame"].firstMatch.frame.width,
                       strip / 2 + Self.stroke, accuracy: 3)
        attach(app, "two-hour-tail-precision")
    }

    // MARK: - Zoom controls, double tap and fine mode

    @MainActor func testZoomButtonsWorkOnTheViewportAndFineModeIsATenthSpeed() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--demo-editor", "-unlimitedDuration", "NO"]
        app.launch()
        let body = revealTimeline(app)
        let duration = viewport(app).end
        assertOpensInOverview(app, "The demo clip at launch", duration: duration)
        assertBoxIsTheRealWindow(app, "The demo selection in overview")

        let initialScale = scale(app), initial = selection(app)
        body.pinch(withScale: 2, velocity: 1)
        XCTAssertGreaterThan(scale(app), initialScale, "A pinch zooms in")
        let pinched = selection(app)
        XCTAssertEqual(pinched.start, initial.start, accuracy: 0.001, "A pinch must never change the trim")
        XCTAssertEqual(pinched.end, initial.end, accuracy: 0.001, "A pinch must never change the trim")
        assertBoxIsTheRealWindow(app, "After a pinch")

        body.doubleTap()
        assertOpensInOverview(app, "After a double tap", duration: duration)

        // The buttons aim at the camera the user is looking at, not at the selection.
        app.buttons["timelineZoomIn"].tap()
        let window = viewport(app)
        XCTAssertEqual(window.end - window.start, duration / 2, accuracy: max(0.1, duration * 0.02),
                       "One zoom step must halve the visible window")
        XCTAssertEqual((window.start + window.end) / 2, duration / 2, accuracy: 0.1,
                       "Zoom must stay anchored on the viewport centre, not on the clip")
        app.buttons["timelineZoomOut"].tap()
        XCTAssertEqual(scale(app), 1, accuracy: 0.001, "缩小 must return to the whole source")
        let stepped = selection(app)
        XCTAssertEqual(stepped.start, initial.start, accuracy: 0.001, "Zoom buttons must never change the trim")
        XCTAssertEqual(stepped.end, initial.end, accuracy: 0.001, "Zoom buttons must never change the trim")
        attach(app, "zoom-buttons-on-viewport")

        // Fine mode: a long press makes the same finger travel ten times smaller.
        app.buttons["timelineFocusSelection"].tap()
        var end = handle(app, "trimEndHandle")
        let beforeNormal = seconds(end)
        var grip = end.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: -25, dy: 0)))
        end = handle(app, "trimEndHandle")
        let normal = beforeNormal - seconds(end)
        XCTAssertGreaterThan(normal, 0.05, "A plain drag must trim")
        let beforeFine = seconds(end)
        grip = end.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grip.press(forDuration: 0.6, thenDragTo: grip.withOffset(CGVector(dx: -25, dy: 0)))
        let fine = beforeFine - seconds(handle(app, "trimEndHandle"))
        XCTAssertGreaterThan(fine, 0, "精细调整 must still trim")
        XCTAssertLessThan(fine, normal / 3, "精细调整 must be roughly a tenth of the travel")
        XCTAssertEqual(selection(app).end - selection(app).start, initial.end - initial.start - normal - fine,
                       accuracy: 0.06, "Both trims must add up on the real window")
        attach(app, "fine-mode-tenth-speed")
    }

    /// A real H.264 track with sparse static samples keeps the fixture tiny while still reporting
    /// the requested duration, which is what a long source looks like to this UI.
    private func syntheticVideo(duration total: Double) async throws -> URL {
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
        for time in [0.0, 1.0 / 30, total / 2 - 1, total / 2, total - 2, total - 1, total - 1.0 / 30] {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw try XCTUnwrap(writer.error) }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600)))
        }
        writer.endSession(atSourceTime: CMTime(seconds: total, preferredTimescale: 600))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        let duration = try await AVURLAsset(url: url).load(.duration)
        XCTAssertEqual(duration.seconds, total, accuracy: 0.1)
        return url
    }
}
