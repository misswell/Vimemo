import XCTest
@testable import Vimemo

final class TimelineTests: XCTestCase {
    private let strip: CGFloat = 300

    // MARK: - One coordinate system

    func testTimeAndPixelsRoundTripAtEveryScaleAndSource() {
        for duration in [3.0, 180.0, 7200.0] {
            var state = TimelineState(duration: duration, frameRate: 30)
            for zoom in [CGFloat(1), 2, 7, 60, state.maximumZoomScale] {
                state.zoom(to: zoom, anchorTime: duration / 2, anchorFraction: 0.5)
                XCTAssertGreaterThanOrEqual(state.visibleStart, -0.000001)
                XCTAssertLessThanOrEqual(state.visibleEnd, duration + 0.000001)
                XCTAssertEqual(state.pixelsPerSecond(width: strip) * state.secondsPerPoint(width: strip), 1, accuracy: 0.000001)
                for x in stride(from: CGFloat(0), through: strip, by: 10) {
                    XCTAssertEqual(state.x(for: state.time(at: x, width: strip), width: strip), x, accuracy: 0.0001,
                                   "\(duration)s at ×\(zoom): one pixel must mean one instant")
                }
            }
        }
    }

    @MainActor func testOpeningAClipShowsTheWholeSourceNotAWindowAroundTheSelection() {
        let model = TimelineViewModel()
        let clip = Clip(start: 6, end: 9, cover: 7.5)
        model.configure(duration: 180, clip: clip, width: strip, frameRate: 30)
        XCTAssertEqual(model.state.zoomScale, 1, "A three-minute source must open in Overview")
        XCTAssertEqual(model.state.visibleStart, 0)
        XCTAssertEqual(model.state.visibleEnd, 180)
        let geometry = TimelineSelectionGeometry(state: model.state, clip: clip, width: strip)
        XCTAssertEqual(geometry.left, 10, accuracy: 0.0001)
        XCTAssertEqual(geometry.width, 5, accuracy: 0.0001, "The selection is drawn at its true time ratio")
    }

    func testTheCeilingComesFromTheFrameGridNotAFixedSecond() {
        for rate in [24.0, 30.0, 60.0, 120.0] {
            let state = TimelineState(duration: 7200, frameRate: rate)
            XCTAssertEqual(state.minimumVisibleDuration, 2 / rate, accuracy: 0.000001,
                           "The finest window is two real frames, so a tenth-of-a-second clip is operable")
            XCTAssertEqual(state.maximumZoomScale, CGFloat(7200 / (2 / rate)), accuracy: 1)
        }
        // Sparse or variable-frame files report an unusable rate; it must not collapse the ceiling.
        XCTAssertEqual(TimelineState(duration: 7200, frameRate: 0.001).maximumZoomScale, 86_400, accuracy: 1)
        XCTAssertEqual(TimelineState(duration: 7200, frameRate: .nan).maximumZoomScale, 108_000, accuracy: 1)
        XCTAssertEqual(TimelineState(duration: 7200, frameRate: 100_000).maximumZoomScale, 864_000, accuracy: 1)
    }

    func testPrecisionModeFitsEveryClipWidthIncludingASubFrameOne() {
        for duration in [3.0, 6.0, 30.0, 180.0, 600.0, 3600.0, 7200.0] {
            for rate in [24.0, 30.0, 60.0, 120.0] {
                for seconds in [0.1, 0.3, 1.0, 3.0, 6.0] {
                    let length = min(seconds, duration)
                    let clip = Clip(start: 0, end: length, cover: length / 2)
                    var state = TimelineState(duration: duration, frameRate: rate)
                    state.fit(clip: clip, width: strip)
                    let geometry = TimelineSelectionGeometry(state: state, clip: clip, width: strip)
                    XCTAssertGreaterThanOrEqual(geometry.width, strip / 2 - 0.01,
                                               "\(duration)s/\(rate)/\(seconds)s: fitting must never shrink the target")
                    if length < duration * 0.4 {
                        XCTAssertEqual(geometry.width, strip / 2, accuracy: 0.01,
                                       "\(duration)s/\(rate)/\(seconds)s: the selection takes half the strip, a quarter each side")
                    }
                    XCTAssertLessThanOrEqual(state.visibleDuration, length / TimelineState.precisionSelectionFraction + 0.000001)
                }
            }
        }
    }

    // MARK: - Selection drawing and touch bands

    func testASubPixelSelectionInOverviewStillGivesEveryControlAFortyFourPointBand() throws {
        let state = TimelineState(duration: 7200, frameRate: 30)
        let clip = Clip(start: 3600, end: 3603, cover: 3601.5)
        let geometry = TimelineSelectionGeometry(state: state, clip: clip, width: strip)
        XCTAssertEqual(geometry.width, 0.125, accuracy: 0.0001, "Overview must not widen the window into a fake box")
        let start = try XCTUnwrap(geometry.handleZone(isStart: true, width: strip))
        let end = try XCTUnwrap(geometry.handleZone(isStart: false, width: strip))
        let body = try XCTUnwrap(geometry.bodyZone(width: strip))
        XCTAssertEqual(start.upperBound - start.lowerBound, 44, accuracy: 0.001)
        XCTAssertEqual(end.upperBound - end.lowerBound, 44, accuracy: 0.001)
        XCTAssertEqual(body.upperBound - body.lowerBound, 44, accuracy: 0.001)
        XCTAssertLessThanOrEqual(start.upperBound, body.lowerBound + 0.0001, "Bands must never fight over one touch")
        XCTAssertLessThanOrEqual(body.upperBound, end.lowerBound + 0.0001)
        XCTAssertEqual(geometry.midpoint, (start.upperBound + end.lowerBound) / 2, accuracy: 0.0001)
        XCTAssertLessThan(try XCTUnwrap(geometry.handleGripX(isStart: true, width: strip)),
                          try XCTUnwrap(geometry.handleGripX(isStart: false, width: strip)),
                          "The separated joystick grips must remain independently addressable")
    }

    func testWideSelectionPlacesRoundJoystickGripsOutsideTheirTrueEdges() throws {
        let state = TimelineState(duration: 30, frameRate: 30)
        let clip = Clip(start: 10, end: 20, cover: 15)
        let geometry = TimelineSelectionGeometry(state: state, clip: clip, width: strip)
        let startGrip = try XCTUnwrap(geometry.handleGripX(isStart: true, width: strip))
        let endGrip = try XCTUnwrap(geometry.handleGripX(isStart: false, width: strip))
        XCTAssertLessThan(startGrip, geometry.left)
        XCTAssertGreaterThan(endGrip, geometry.right)
        let radius = TimelineSelectionGeometry.joystickBallDiameter / 2
        let expectedCenterOffset = radius
        XCTAssertEqual(geometry.left - startGrip, expectedCenterOffset, accuracy: 0.001)
        XCTAssertEqual(endGrip - geometry.right, expectedCenterOffset, accuracy: 0.001)
        XCTAssertEqual(geometry.left, startGrip + radius, accuracy: 0.001,
                       "The start joystick ball edge must touch the true selection edge")
        XCTAssertEqual(geometry.right, endGrip - radius, accuracy: 0.001,
                       "The end joystick ball edge must touch the true selection edge")
    }

    func testJoystickTouchBandsExtendIntoTheSideGutterAtSourceBoundaries() throws {
        let state = TimelineState(duration: 30, frameRate: 30)
        let clip = Clip(start: 0, end: 10, cover: 5)
        let geometry = TimelineSelectionGeometry(state: state, clip: clip, width: strip)
        let start = try XCTUnwrap(geometry.handleZone(isStart: true, width: strip))
        let grip = try XCTUnwrap(geometry.handleGripX(isStart: true, width: strip))
        XCTAssertEqual(start.lowerBound, -TimelineSelectionGeometry.controlOverhang, accuracy: 0.001)
        XCTAssertEqual(start.upperBound - start.lowerBound, TimelineSelectionGeometry.controlBand, accuracy: 0.001)
        XCTAssertEqual(geometry.left, grip + TimelineSelectionGeometry.joystickBallDiameter / 2, accuracy: 0.001,
                       "The ball keeps touching the true endpoint while it overhangs the strip")
        XCTAssertLessThan(start.lowerBound, 0)
        XCTAssertLessThanOrEqual(start.upperBound, strip)
    }

    @MainActor func testTryingToTrimPastOneTenthSecondShowsTheMinimumNoticeAndKeepsTheClipValid() {
        let width: CGFloat = 300
        let endModel = TimelineViewModel()
        let original = Clip(start: 20, end: 20.2, cover: 20.1)
        endModel.configure(duration: 60, clip: original, width: width, frameRate: 30)
        let endGeometry = TimelineSelectionGeometry(state: endModel.state, clip: original, width: width)
        endModel.begin(.end, clip: original, width: width, at: endGeometry.handleGripX(isStart: false, width: width)!)
        let shortenedAtEnd = endModel.move(translation: CGSize(width: -width, height: 0), clip: original,
                                           width: width, speed: 1, maxOutputDuration: nil)
        XCTAssertTrue(endModel.minimumDurationReached)
        XCTAssertEqual(shortenedAtEnd.duration, 0.1, accuracy: 0.000_001)
        endModel.end()

        let startModel = TimelineViewModel()
        startModel.configure(duration: 60, clip: original, width: width, frameRate: 30)
        let startGeometry = TimelineSelectionGeometry(state: startModel.state, clip: original, width: width)
        startModel.begin(.start, clip: original, width: width, at: startGeometry.handleGripX(isStart: true, width: width)!)
        let shortenedAtStart = startModel.move(translation: CGSize(width: width, height: 0), clip: original,
                                               width: width, speed: 1, maxOutputDuration: nil)
        XCTAssertTrue(startModel.minimumDurationReached)
        XCTAssertEqual(shortenedAtStart.duration, 0.1, accuracy: 0.000_001)
        startModel.end()
    }

    func testASliverAtTheHeadOrTailOfTheStripStillLosesNoControl() throws {
        for clip in [Clip(start: 0, end: 3, cover: 1.5), Clip(start: 7197, end: 7200, cover: 7198.5)] {
            let state = TimelineState(duration: 7200, frameRate: 30)
            let geometry = TimelineSelectionGeometry(state: state, clip: clip, width: strip)
            XCTAssertTrue(geometry.isNarrow, "A three-second window across two hours is a sub-pixel sliver")
            let start = try XCTUnwrap(geometry.handleZone(isStart: true, width: strip),
                                      "An endpoint drawn at the strip edge must still be trimmable")
            let body = try XCTUnwrap(geometry.bodyZone(width: strip), "Sliding the cluster must not drop the far handle")
            let end = try XCTUnwrap(geometry.handleZone(isStart: false, width: strip))
            XCTAssertEqual(start.upperBound - start.lowerBound, 44, accuracy: 0.001)
            XCTAssertEqual(body.upperBound - body.lowerBound, 44, accuracy: 0.001)
            XCTAssertEqual(end.upperBound - end.lowerBound, 44, accuracy: 0.001)
            XCTAssertLessThanOrEqual(start.upperBound, body.lowerBound + 0.0001)
            XCTAssertLessThanOrEqual(body.upperBound, end.lowerBound + 0.0001)
            let gutter = TimelineSelectionGeometry.controlOverhang
            XCTAssertTrue((-gutter...strip + gutter).contains(start.lowerBound)
                          && (-gutter...strip + gutter).contains(end.upperBound))
        }
    }

    func testBandsStaySeparateAndAreOnlyOfferedWhereTheControlIsDrawn() {
        for duration in [3.0, 180.0, 7200.0] {
            for zoom in [CGFloat(1), 3, 40, 900] {
                var state = TimelineState(duration: duration, frameRate: 30)
                state.zoom(to: zoom, anchorTime: duration / 2, anchorFraction: 0.5)
                for start in [0.0, duration * 0.2, duration * 0.5, duration - 3] {
                    let clip = Clip(start: start, end: min(duration, start + 3), cover: start + 1.5)
                    let geometry = TimelineSelectionGeometry(state: state, clip: clip, width: strip)
                    guard geometry.isVisible else { continue }
                    if let zone = geometry.handleZone(isStart: true, width: strip) {
                        XCTAssertTrue((0...strip).contains(geometry.left), "A hidden endpoint may not be grabbed")
                        XCTAssertTrue(zone.lowerBound >= -TimelineSelectionGeometry.controlOverhang
                                      && zone.upperBound <= strip + TimelineSelectionGeometry.controlOverhang)
                        XCTAssertGreaterThanOrEqual(zone.upperBound - zone.lowerBound, TimelineSelectionGeometry.minimumZone)
                        if let body = geometry.bodyZone(width: strip) {
                            XCTAssertLessThanOrEqual(zone.upperBound, body.lowerBound + 0.0001)
                        }
                    }
                    if let zone = geometry.handleZone(isStart: false, width: strip),
                       let body = geometry.bodyZone(width: strip) {
                        XCTAssertLessThanOrEqual(body.upperBound, zone.lowerBound + 0.0001)
                    }
                }
            }
        }
    }

    func testCoverLineSitsWhereTheCoverReallyIsInsideTheSelection() {
        let state = TimelineState(duration: 60, frameRate: 30)
        let clip = Clip(start: 10, end: 20, cover: 12.5)
        let geometry = TimelineSelectionGeometry(state: state, clip: clip, width: strip)
        XCTAssertEqual(geometry.coverX(for: clip), geometry.left + geometry.width * 0.25, accuracy: 0.0001)
        let biased = Clip(start: 10, end: 20, cover: 19)
        XCTAssertEqual(TimelineSelectionGeometry(state: state, clip: biased, width: strip)
                            .coverX(for: biased), geometry.right - geometry.width / 10, accuracy: 0.0001)
    }

    func testCoverGripStaysAlignedWithItsLineInTheSideGutter() {
        let state = TimelineState(duration: 7200, frameRate: 30)
        for clip in [Clip(start: 0, end: 3, cover: 0), Clip(start: 7197, end: 7200, cover: 7200)] {
            let geometry = TimelineSelectionGeometry(state: state, clip: clip, width: strip)
            let lineX = geometry.coverX(for: clip)
            let gripX = geometry.coverGripX(for: clip, stripWidth: strip)
            XCTAssertEqual(lineX, clip.start == 0 ? 0 : strip, accuracy: 0.001)
            XCTAssertEqual(gripX, lineX, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(gripX - 22, -TimelineSelectionGeometry.controlOverhang)
            XCTAssertLessThanOrEqual(gripX + 22, strip + TimelineSelectionGeometry.controlOverhang)
        }
    }

    func testTrimAndCoverControlsShareTheExpandedCanvasAtViewportEdges() throws {
        let state = TimelineState(duration: 180, frameRate: 30)
        let width: CGFloat = 240
        for clip in [Clip(start: 0, end: 60, cover: 0.1), Clip(start: 120, end: 180, cover: 179.9)] {
            let geometry = TimelineSelectionGeometry(state: state, clip: clip, width: width)
            let isAtHead = clip.start == 0
            let endpoint = isAtHead ? geometry.left : geometry.right
            let grip = try XCTUnwrap(geometry.handleGripX(isStart: isAtHead, width: width))
            let zone = try XCTUnwrap(geometry.handleZone(isStart: isAtHead, width: width))
            let cover = geometry.coverGripX(for: clip, stripWidth: width)
            let overhang = TimelineSelectionGeometry.controlOverhang

            XCTAssertEqual(abs(endpoint - grip), TimelineSelectionGeometry.joystickCenterOffset, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(zone.lowerBound, -overhang)
            XCTAssertLessThanOrEqual(zone.upperBound, width + overhang)
            XCTAssertEqual(cover, geometry.coverX(for: clip), accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(cover - 22, -overhang)
            XCTAssertLessThanOrEqual(cover + 22, width + overhang)
        }
    }

    // MARK: - Precision entry keeps the grip under the finger

    @MainActor func testHandleGrabsIncreasePrecisionByAtMostTwoTimesUntilTheSelectionFits() throws {
        let model = TimelineViewModel()
        let clip = Clip(start: 89, end: 92, cover: 90.5)
        model.configure(duration: 180, clip: clip, width: strip, frameRate: 30)
        let overview = TimelineSelectionGeometry(state: model.state, clip: clip, width: strip)
        let zone = try XCTUnwrap(overview.handleZone(isStart: true, width: strip))
        var fingerX = (zone.lowerBound + zone.upperBound) / 2
        var previousScale = model.state.zoomScale
        var grabs = 0
        while model.state.zoomScale < 30 {
            model.begin(.start, clip: clip, width: strip, at: fingerX)
            XCTAssertLessThanOrEqual(model.state.zoomScale, previousScale * 2 + 0.0001,
                                     "A handle grab must never jump more than one doubling")
            XCTAssertEqual(try XCTUnwrap(TimelineSelectionGeometry(state: model.state, clip: clip, width: strip)
                                            .handleGripX(isStart: true, width: strip)), fingerX, accuracy: 0.01,
                           "The round grip must stay under the finger as the viewport zooms")
            previousScale = model.state.zoomScale
            grabs += 1
            model.end()
            let geometry = TimelineSelectionGeometry(state: model.state, clip: clip, width: strip)
            fingerX = try XCTUnwrap(geometry.handleGripX(isStart: true, width: strip))
        }
        XCTAssertEqual(model.state.zoomScale, 30, accuracy: 0.001,
                       "Repeated grabs reach the six-second precision window for this source")
        XCTAssertEqual(grabs, 5, "The 1× overview should progress through 2×, 4×, 8×, 16× and 30×")
    }

    @MainActor func testHandleDragTracksTheFingerPixelForPixelAfterTheRefit() {
        let model = TimelineViewModel()
        let clip = Clip(start: 3599, end: 3602, cover: 3601)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        model.begin(.start, clip: clip, width: strip, at: 106)
        let before = TimelineSelectionGeometry(state: model.state, clip: clip, width: strip)
        let moved = model.move(translation: CGSize(width: 0.02, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        let after = TimelineSelectionGeometry(state: model.state, clip: moved, width: strip)
        XCTAssertEqual(after.left - before.left, 0.02, accuracy: 0.001, "The grip must stay exactly under the finger")
        XCTAssertEqual(after.right - before.right, 0, accuracy: 0.001, "Trimming the start must not slide the whole box")
        XCTAssertEqual(moved.start, 3599.24, accuracy: 0.001,
                       "At 2×, a small finger movement uses the matching current viewport scale")
    }

    @MainActor func testPrecisionFitClampsAtTheHeadInsteadOfTeleportingTheIntent() {
        let model = TimelineViewModel()
        let clip = Clip(start: 0.05, end: 3.05, cover: 1.5)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        model.begin(.start, clip: clip, width: strip, at: 100)
        XCTAssertEqual(model.state.visibleStart, 0, "The viewport cannot start before the source")
        let before = TimelineSelectionGeometry(state: model.state, clip: clip, width: strip)
        XCTAssertEqual(before.left, 0.05 / 3600 * strip, accuracy: 0.001,
                       "At the first 2× step, the edge stays at its true near-source time")
        let moved = model.move(translation: CGSize(width: 0.001, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        let after = TimelineSelectionGeometry(state: model.state, clip: moved, width: strip)
        XCTAssertEqual(after.left - before.left, 0.001, accuracy: 0.001, "From there the grip still tracks the finger exactly")
        XCTAssertEqual(moved.start - clip.start, 0.012, accuracy: 0.001)
    }

    @MainActor func testReleasingNeverJumpsScaleOrViewport() {
        let model = TimelineViewModel()
        let clip = Clip(start: 3599, end: 3602, cover: 3601)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        model.begin(.start, clip: clip, width: strip, at: 106)
        let moved = model.move(translation: CGSize(width: 20, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        let zoom = model.state.zoomScale, start = model.state.visibleStart, end = model.state.visibleEnd
        model.end()
        XCTAssertNotEqual(moved.start, clip.start, "The drag itself did trim")
        XCTAssertEqual(model.state.zoomScale, zoom, "Release must not re-scale what the finger left")
        XCTAssertEqual(model.state.visibleStart, start, accuracy: 0.000001)
        XCTAssertEqual(model.state.visibleEnd, end, accuracy: 0.000001)
    }

    // MARK: - Moving the selection

    @MainActor func testBodyMovePreservesDurationCoverAndBothSourceBoundaries() {
        let model = TimelineViewModel()
        var clip = Clip(start: 3599, end: 3602, cover: 3601)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        model.begin(.selection, clip: clip, width: strip, at: 150)
        let duration = clip.duration, coverOffset = clip.cover - clip.start
        clip = model.move(translation: CGSize(width: 40, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        XCTAssertGreaterThan(clip.start, 3599)
        XCTAssertEqual(clip.duration, duration, accuracy: 0.000001)
        XCTAssertEqual(clip.cover - clip.start, coverOffset, accuracy: 0.000001)
        let before = TimelineSelectionGeometry(state: model.state, clip: clip, width: strip)
        clip = model.move(translation: CGSize(width: 48, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        XCTAssertEqual(TimelineSelectionGeometry(state: model.state, clip: clip, width: strip).left - before.left, 8,
                       accuracy: 0.001, "Eight more pixels is eight more pixels of travel")
        model.begin(.selection, clip: clip, width: strip, at: 150)
        clip = model.move(translation: CGSize(width: -1_000_000, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        XCTAssertEqual(clip.start, 0)
        XCTAssertEqual(clip.duration, 3)
        model.begin(.selection, clip: clip, width: strip, at: 150)
        clip = model.move(translation: CGSize(width: 1_000_000, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        XCTAssertEqual(clip.end, 7200)
        XCTAssertEqual(clip.duration, 3)
    }

    @MainActor func testOneOverviewDragCarriesTheSelectionAcrossTheWholeSource() {
        let model = TimelineViewModel()
        var clip = Clip(start: 3600, end: 3603, cover: 3601.5)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        model.begin(.selection, clip: clip, width: strip, at: 150)
        clip = model.move(translation: CGSize(width: 100, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        XCTAssertEqual(clip.start, 3600 + 100 * 24, accuracy: 1, "Overview keeps its true scale, so a strip is half a source")
        XCTAssertEqual(clip.duration, 3)
        XCTAssertEqual(model.autoScrollRate, 0, "Nothing may scroll when the viewport already is the source")
    }

    // MARK: - Edge auto-scroll

    @MainActor func testAParkedFingerScrollsTheTimelineUnderItWhileTheGripStaysPut() {
        let model = TimelineViewModel()
        let clip = Clip(start: 3600, end: 3603, cover: 3601.5)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        model.begin(.end, clip: clip, width: strip, at: 194)
        let held = model.move(translation: CGSize(width: 95, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: nil)
        XCTAssertGreaterThan(model.autoScrollRate, 0.3, "A finger near the right edge must start the scroll")
        let gripX = TimelineSelectionGeometry(state: model.state, clip: held, width: strip).right
        let viewport = model.state.visibleStart
        var current = held
        for _ in 0..<60 {
            guard let scrolled = model.autoScroll(deltaTime: 1 / 60, clip: current) else { continue }
            current = scrolled
        }
        XCTAssertGreaterThan(current.end, held.end, "One drag can trim past the screen without releasing")
        XCTAssertGreaterThan(model.state.visibleStart, viewport, "The viewport must travel under the finger")
        XCTAssertEqual(TimelineSelectionGeometry(state: model.state, clip: current, width: strip).right, gripX, accuracy: 0.001,
                       "The grip stays under a stationary finger while the timeline scrolls beneath it")
    }

    @MainActor func testAutoScrollStopsWhereTheSourceEndsAndNeverRunsInOverview() {
        let model = TimelineViewModel()
        let clip = Clip(start: 7197, end: 7200, cover: 7198.5)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        model.begin(.end, clip: clip, width: strip, at: 194)
        _ = model.move(translation: CGSize(width: 95, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 6)
        XCTAssertEqual(model.state.visibleEnd, 7200, accuracy: 0.000001, "The tail is the tail")
        XCTAssertEqual(model.autoScrollRate, 0, "There is nothing to the right of the end of the source")
        XCTAssertNil(model.autoScroll(deltaTime: 1 / 60, clip: clip))
        model.end()
        model.reset()
        model.begin(.selection, clip: clip, width: strip, at: 290)
        _ = model.move(translation: CGSize(width: 10, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        XCTAssertEqual(model.autoScrollRate, 0, "Overview already shows the whole source")
    }

    // MARK: - Pinch and zoom buttons

    @MainActor func testPinchKeepsTheAnchorUnderTheFingersAndReleaseKeepsTheViewport() {
        let model = TimelineViewModel()
        let clip = Clip(start: 3600, end: 3603, cover: 3601.5)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        model.beginPinch(x: 90, width: strip)
        model.pinch(scale: 12, x: 90, width: strip)
        XCTAssertEqual(model.state.time(at: 90, width: strip), 2160, accuracy: 0.01,
                       "The instant under the centroid stays under the centroid")
        let zoom = model.state.zoomScale, center = model.state.viewportCenterTime
        model.endPinch()
        XCTAssertEqual(model.state.zoomScale, zoom, "Releasing may not re-scale what the fingers chose")
        XCTAssertEqual(model.state.viewportCenterTime, center, accuracy: 0.000001)
    }

    @MainActor func testReleasingAPinchMayLeaveTheSelectionOffScreenAndSaysSo() {
        let model = TimelineViewModel()
        let clip = Clip(start: 600, end: 603, cover: 601.5)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        model.beginPinch(x: strip, width: strip)
        model.pinch(scale: 20, x: strip, width: strip)
        XCTAssertTrue(model.selectionIsOffScreen(clip), "A pinch anchored at the far end may walk away from the selection")
        model.endPinch()
        XCTAssertTrue(model.selectionIsOffScreen(clip),
                      "Letting go must not drag the camera back: the viewport is exactly what the fingers left")
        XCTAssertEqual(model.state.zoomScale, 20, accuracy: 0.001)
        model.focus(clip)
        XCTAssertFalse(model.selectionIsOffScreen(clip), "聚焦片段 is the way back")
        XCTAssertEqual(TimelineSelectionGeometry(state: model.state, clip: clip, width: strip).width, strip / 2, accuracy: 0.01)
    }

    @MainActor func testZoomButtonsWorkOnTheViewportCentreAndNeverOnTheSelection() {
        let model = TimelineViewModel()
        let clip = Clip(start: 6, end: 9, cover: 7.5)
        model.configure(duration: 180, clip: clip, width: strip, frameRate: 30)
        model.zoom(by: 2)
        XCTAssertEqual(model.state.visibleStart, 45, accuracy: 0.000001)
        XCTAssertEqual(model.state.visibleEnd, 135, accuracy: 0.000001)
        XCTAssertEqual(model.state.zoomScale, 2, accuracy: 0.000001)
        model.zoom(by: 0.5)
        XCTAssertEqual(model.state.visibleStart, 0, accuracy: 0.000001, "Zooming back out may not stop at the old ceiling")
        XCTAssertEqual(model.state.visibleEnd, 180, accuracy: 0.000001)
    }

    @MainActor func testPanningTheViewportNeverTouchesTheClip() {
        let model = TimelineViewModel()
        let clip = Clip(start: 3600, end: 3603, cover: 3601.5)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        model.focus(clip)
        let center = model.state.viewportCenterTime
        model.begin(.viewport, clip: clip, width: strip, at: 200)
        let unchanged = model.move(translation: CGSize(width: 100, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        XCTAssertEqual(unchanged, clip, "A blank-area pan is navigation, never an edit")
        XCTAssertEqual(model.state.viewportCenterTime, center - 100 * model.state.secondsPerPoint(width: strip), accuracy: 0.000001)
        XCTAssertEqual(model.autoScrollRate, 0, "Panning the viewport must not start an auto-scroll")
        model.end()
    }

    // MARK: - Precision mode and accessibility steps

    @MainActor func testFineModeIsExactlyTenthSpeedAndAccumulatesSubFrameMotion() {
        let model = TimelineViewModel()
        let clip = Clip(start: 100, end: 103, cover: 101.5)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        let grip = TimelineSelectionGeometry(state: model.state, clip: clip, width: strip).midpoint
        model.begin(.selection, clip: clip, width: strip, at: grip)
        let rate = model.dragSecondsPerPoint
        let normal = model.move(translation: CGSize(width: 10, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3).start - 100
        model.end()
        model.begin(.selection, clip: clip, width: strip, at: grip)
        model.setFine(true)
        var value = clip
        for step in 1...10 {
            value = model.move(translation: CGSize(width: CGFloat(step), height: 0), clip: value, width: strip, speed: 1, maxOutputDuration: 3)
        }
        XCTAssertEqual(normal, 10 * rate, accuracy: 0.001)
        XCTAssertEqual(value.start - 100, 10 * rate * 0.1, accuracy: 0.001,
                       "Long-press precision must be one tenth and keep sub-frame motion")
        model.end()
        XCTAssertFalse(model.fineAdjustment)
    }

    @MainActor func testOneFrameIsTheSamePhysicalDistanceForEveryZoomTarget() {
        for duration in [60.0, 7200.0] {
            for seconds in [0.3, 3.0] {
                let model = TimelineViewModel()
                let clip = Clip(start: duration / 2, end: duration / 2 + seconds, cover: duration / 2 + seconds / 2)
                model.configure(duration: duration, clip: clip, width: strip, frameRate: 30)
                model.begin(.start, clip: clip, width: strip, at: TimelineSelectionGeometry(state: model.state, clip: clip, width: strip).left)
                let points = CGFloat(1 / 30 / model.dragSecondsPerPoint)
                let moved = model.move(translation: CGSize(width: points, height: 0), clip: clip, width: strip,
                                       speed: 1, maxOutputDuration: nil)
                XCTAssertEqual(moved.start - clip.start, 1 / 30, accuracy: 0.000001,
                               "\(duration)s/\(seconds)s: one VoiceOver step is one frame")
            }
        }
    }

    @MainActor func testSelectionChangedFromOutsideOnlyMovesTheCamera() {
        let model = TimelineViewModel()
        let clip = Clip(start: 3599, end: 3602, cover: 3601)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        model.focus(clip)
        let zoom = model.state.zoomScale
        let moved = Clip(start: 3599, end: 3602, cover: 3601)
        model.beginPinch(x: 0, width: strip)
        model.pinch(scale: 40, x: 0, width: strip)
        model.endPinch()
        XCTAssertEqual(model.state.zoomScale, zoom * 40, accuracy: 0.001)
        model.selectionChanged(moved)
        XCTAssertEqual(model.state.zoomScale, zoom * 40, accuracy: 0.001, "Keeping a selection visible must not zoom")
        XCTAssertTrue(TimelineSelectionGeometry(state: model.state, clip: moved, width: strip).isVisible)
    }

    @MainActor func testTheTimelinesOwnEditNeverNudgesTheCameraButAnExternalOneStillDoes() {
        let model = TimelineViewModel()
        let clip = Clip(start: 3599, end: 3602, cover: 3601)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        model.begin(.end, clip: clip, width: strip, at: 110)
        let trimmed = model.move(translation: CGSize(width: -8, height: 0), clip: clip, width: strip,
                                 speed: 1, maxOutputDuration: 3)
        model.end()
        let camera = model.state
        // SwiftUI only reports the binding write once the gesture has already finished, so this
        // is the exact moment a release used to jump the camera.
        model.selectionChanged(trimmed)
        XCTAssertEqual(model.state.zoomScale, camera.zoomScale, "The timeline's own trim must not re-scale")
        XCTAssertEqual(model.state.visibleStart, camera.visibleStart, accuracy: 0.000_001,
                       "The timeline's own trim must not drag the camera back after the finger left")

        model.begin(.viewport, clip: trimmed, width: strip, at: 200)
        _ = model.move(translation: CGSize(width: -120, height: 0), clip: trimmed, width: strip,
                       speed: 1, maxOutputDuration: 3)
        model.end()
        let panned = model.state
        model.selectionChanged(Clip(start: 100, end: 103, cover: 101))
        XCTAssertNotEqual(model.state.visibleStart, panned.visibleStart, accuracy: 0.000_001,
                          "A clip changed elsewhere still gets the camera")
    }

    // MARK: - Layout changes

    @MainActor func testALayoutResizeNeverLeavesGestureMathOnTheOldStripWidth() {
        let model = TimelineViewModel()
        let clip = Clip(start: 3599, end: 3602, cover: 3601)
        // The first layout pass can report a narrower strip than the card finally gets.
        model.configure(duration: 7200, clip: clip, width: 131, frameRate: 30)
        model.focus(clip)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        let fitted = TimelineSelectionGeometry(state: model.state, clip: clip, width: strip)
        XCTAssertEqual(fitted.width, strip / 2, accuracy: 0.6, "A re-layout must restore half the strip for the selection")
        model.begin(.start, clip: clip, width: strip, at: fitted.left)
        let moved = model.move(translation: CGSize(width: 8, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        let after = TimelineSelectionGeometry(state: model.state, clip: moved, width: strip)
        XCTAssertEqual(after.left - fitted.left, 8, accuracy: 0.6,
                       "Gesture math must use the strip being drawn, not the width cached at launch")
    }

    @MainActor func testOpeningANewClipAlwaysReturnsToOverview() {
        let model = TimelineViewModel()
        let first = Clip(start: 3599, end: 3602, cover: 3601)
        model.configure(duration: 7200, clip: first, width: strip, frameRate: 30)
        model.focus(first)
        XCTAssertGreaterThan(model.state.zoomScale, 1)
        model.configure(duration: 7200, clip: Clip(start: 100, end: 103, cover: 101.5), width: strip, frameRate: 30)
        XCTAssertEqual(model.state.zoomScale, 1, "A new clip is a new decision, not the last one's zoom")
    }

    // MARK: - Thumbnails

    func testThumbnailWorkAndCellWidthStayInsideTheScreenAtEveryZoomAndRate() {
        for duration in [3.0, 60.0, 7200.0] {
            for rate in [24.0, 30.0, 60.0, 120.0] {
                var state = TimelineState(duration: duration, frameRate: rate)
                for zoom in [CGFloat(1), 4, 5, 30, 31, 200, state.maximumZoomScale] {
                    state.zoom(to: zoom, anchorTime: duration / 2, anchorFraction: 0.5)
                    let plan = TimelineThumbnailPlan(state: state, frameRate: rate)
                    XCTAssertLessThanOrEqual(plan.times.count, 15, "Decoding must stay a screen-sized request")
                    XCTAssertGreaterThan(plan.times.count, 0)
                    XCTAssertTrue(plan.times.allSatisfy { $0 >= 0 && $0 < duration })
                    XCTAssertGreaterThanOrEqual(plan.interval, 1 / rate - 0.0000001,
                                               "\(duration)s/\(rate): a cell finer than one real frame is wasted decoding")
                    XCTAssertLessThanOrEqual(plan.cellWidth(in: strip), strip, "A cell must never exceed the strip")
                    XCTAssertGreaterThanOrEqual(plan.cellWidth(in: strip), 1)
                    XCTAssertTrue(plan.times.allSatisfy { abs($0 - TimelineThumbnailPlan.snap($0, rate: rate)) < 0.0000001 },
                                  "Cells sit on real frames")
                }
            }
        }
    }

    func testTheSameFrameAsksForTheSameThumbnailAtEveryZoom() {
        var state = TimelineState(duration: 7200, frameRate: 30)
        state.zoom(to: 30, anchorTime: 180, anchorFraction: 0.5)
        let wide = TimelineThumbnailPlan(state: state, frameRate: 30)
        state.zoom(to: 120, anchorTime: 180, anchorFraction: 0.5)
        let tight = TimelineThumbnailPlan(state: state, frameRate: 30)
        let shared = Set(wide.times.map(wide.key(for:))).intersection(tight.times.map(tight.key(for:)))
        XCTAssertFalse(shared.isEmpty, "Zooming must reuse the frames already decoded, not re-ask for new pixels")
        for time in wide.times where time >= 0 {
            XCTAssertEqual(wide.key(for: time), Int((time * 30).rounded()))
        }
    }
}
