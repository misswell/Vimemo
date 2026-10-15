import XCTest
@testable import Vimemo

final class TimelineTests: XCTestCase {
    private let strip: CGFloat = 300

    func testPinchPreservesOffCenterAnchorIncludingMovingCentroid() {
        var state = TimelineState(duration: 7200)
        let anchor = state.time(at: 90, width: strip)
        state.zoom(to: 10, anchorTime: anchor, anchorFraction: 0.3)
        XCTAssertEqual(state.time(at: 90, width: strip), anchor, accuracy: 0.000001)
        state.zoom(to: 100, anchorTime: anchor, anchorFraction: 0.4)
        XCTAssertEqual(state.time(at: 120, width: strip), anchor, accuracy: 0.000001)
        XCTAssertEqual(state.visibleDuration, 72)
    }

    func testZoomLimitsComeFromTheSourceAndResetStaysGlobal() {
        var state = TimelineState(duration: 7200, frameRate: 30)
        XCTAssertEqual(state.maximumZoomScale, 7200, accuracy: 1, "A two-hour source must be able to open a window of seconds")
        // A sparse or variable-frame file can report a near-zero nominal rate; the ceiling
        // must not fall with it, or a three-second selection can never be drawn at its real width.
        XCTAssertEqual(TimelineState(duration: 7200, frameRate: 0.001).maximumZoomScale, 7200, accuracy: 1)
        XCTAssertEqual(TimelineState(duration: 3).maximumZoomScale, 200)
        state.zoom(to: 5_000, anchorTime: 3600, anchorFraction: 0.5)
        XCTAssertEqual(state.zoomScale, 5_000, accuracy: 1)
        state.zoom(to: .greatestFiniteMagnitude, anchorTime: 3600, anchorFraction: 0.5)
        XCTAssertEqual(state.zoomScale, state.maximumZoomScale, accuracy: 1)
        state.zoom(to: .nan, anchorTime: 1, anchorFraction: 0.5)
        XCTAssertEqual(state.zoomScale, state.maximumZoomScale, accuracy: 1)
        state.center(on: -100)
        XCTAssertEqual(state.visibleStart, 0, accuracy: 0.000001)
        state.center(on: 9000)
        XCTAssertEqual(state.visibleEnd, state.videoDuration, accuracy: 0.000001)
        state.reset()
        XCTAssertEqual(state.visibleStart, 0)
        XCTAssertEqual(state.visibleEnd, 7200)
    }

    func testTrimGrabDrawsTheRealSelectionWidthInsteadOfAWidenedBox() {
        var state = TimelineState(duration: 7200)
        let clip = Clip(start: 3599, end: 3602, cover: 3600.5)
        XCTAssertTrue(TimelineSelectionGeometry(state: state, clip: clip, width: strip).isDisplayClamped)
        state.fit(clip: clip, width: strip)
        let after = TimelineSelectionGeometry(state: state, clip: clip, width: strip)
        XCTAssertFalse(after.isDisplayClamped, "A trim target must never be a widened fake box")
        XCTAssertEqual(after.width, 150, accuracy: 0.01, "Half the strip for the clip, half for room on both sides")
        XCTAssertEqual(state.zoomScale, 1200, accuracy: 1)
        XCTAssertEqual(clip.duration, 3, "Fitting is presentation only")
    }

    func testSelectionAtBothSourceEdgesStaysFullyDrawn() {
        var state = TimelineState(duration: 7200)
        let leading = Clip(start: 0, end: 3, cover: 1.5)
        state.fit(clip: leading, width: strip)
        XCTAssertEqual(TimelineSelectionGeometry(state: state, clip: leading, width: strip).left, 0, accuracy: 0.01)
        let trailing = Clip(start: 7197, end: 7200, cover: 7198.5)
        state.fit(clip: trailing, width: strip)
        let geometry = TimelineSelectionGeometry(state: state, clip: trailing, width: strip)
        XCTAssertEqual(geometry.right, strip, accuracy: 0.01)
        XCTAssertFalse(geometry.isDisplayClamped)
    }

    func testLongSelectionKeepsRealEndpointsOutsideViewport() {
        var state = TimelineState(duration: 120)
        let clip = Clip(start: 10, end: 100, cover: 20)
        state.zoom(to: 10, anchorTime: 60, anchorFraction: 0.5)
        let geometry = TimelineSelectionGeometry(state: state, clip: clip, width: strip)
        XCTAssertLessThan(geometry.left, 0)
        XCTAssertGreaterThan(geometry.right, strip)
        XCTAssertFalse(geometry.isDisplayClamped)
        state.fit(clip: clip, width: strip)
        XCTAssertLessThanOrEqual(state.visibleStart, clip.start)
        XCTAssertGreaterThanOrEqual(state.visibleEnd, clip.end)
    }

    @MainActor func testHandleDragMovesTheDrawnHandleExactlyWithTheFinger() {
        let model = TimelineViewModel()
        var clip = Clip(start: 3599, end: 3602, cover: 3600.5)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        model.begin(.start, clip: clip, width: strip)
        let before = TimelineSelectionGeometry(state: model.state, clip: clip, width: strip)
        clip = model.move(translation: CGSize(width: 20, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        let after = TimelineSelectionGeometry(state: model.state, clip: clip, width: strip)
        XCTAssertEqual(after.left - before.left, 20, accuracy: 0.6, "The grip must stay under the finger")
        XCTAssertEqual(after.right, before.right, accuracy: 0.6, "Trimming the start must not slide the whole box")
        XCTAssertEqual(clip.duration, 2.6, accuracy: 0.01)
    }

    @MainActor func testBodyMovePreservesDurationCoverAndBothSourceBoundaries() {
        let model = TimelineViewModel()
        var clip = Clip(start: 3599, end: 3602, cover: 3600.5)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        let originalDuration = clip.duration, coverOffset = clip.cover - clip.start
        model.begin(.selection, clip: clip, width: strip)
        clip = model.move(translation: CGSize(width: 40, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        XCTAssertGreaterThan(clip.start, 3599)
        XCTAssertEqual(clip.duration, originalDuration, accuracy: 0.000001)
        XCTAssertEqual(clip.cover - clip.start, coverOffset, accuracy: 0.000001)
        model.begin(.selection, clip: clip, width: strip)
        clip = model.move(translation: CGSize(width: -1_000_000, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        XCTAssertEqual(clip.start, 0)
        XCTAssertEqual(clip.duration, 3)
        clip = model.move(translation: CGSize(width: 1_000_000, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        XCTAssertEqual(clip.end, 7200)
        XCTAssertEqual(clip.duration, 3)
    }

    @MainActor func testReleasingABodyDragNeverJumpsScaleOrViewport() {
        let model = TimelineViewModel()
        var clip = Clip(start: 3599, end: 3602, cover: 3600.5)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        let zoom = model.state.zoomScale, center = model.state.viewportCenterTime
        model.begin(.selection, clip: clip, width: strip)
        clip = model.move(translation: CGSize(width: 20, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        let moved = model.state.viewportCenterTime
        model.end(clip: clip)
        XCTAssertEqual(model.state.zoomScale, zoom, "Precision must not hijack a coarse move")
        XCTAssertEqual(model.state.viewportCenterTime, moved, "Releasing must not recenter away from the finger")
        XCTAssertLessThanOrEqual(model.state.visibleStart, clip.start)
        XCTAssertGreaterThanOrEqual(model.state.visibleEnd, clip.end)
        XCTAssertEqual(center, 3600.5, accuracy: 0.001)
    }

    @MainActor func testOverviewBodyReachesTheEndOfATwoHourSourceInOneDrag() {
        let model = TimelineViewModel()
        var clip = Clip()
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        model.reset()
        let zoom = model.state.zoomScale
        XCTAssertEqual(zoom, 1)
        model.begin(.selection, clip: clip, width: strip)
        clip = model.move(translation: CGSize(width: 150, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        XCTAssertEqual(clip.start, 3600, accuracy: 1, "One drag across the strip must reach the 59:59 region")
        XCTAssertEqual(clip.duration, 3)
        XCTAssertEqual(model.state.zoomScale, zoom, "A coarse move keeps its scale so the source stays traversable")
    }

    @MainActor func testHandlesAreDraggableOnTwoHourSourceAndRespectSpeedPolicy() {
        let model = TimelineViewModel()
        var clip = Clip(start: 3599, end: 3602, cover: 3600.5)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        model.begin(.start, clip: clip, width: strip)
        clip = model.move(translation: CGSize(width: 8, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        XCTAssertGreaterThan(clip.start, 3599)
        XCTAssertLessThan(clip.duration, 3)
        model.end(clip: clip)
        let end = clip.end
        model.begin(.end, clip: clip, width: strip)
        clip = model.move(translation: CGSize(width: -8, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        XCTAssertLessThan(clip.end, end)
        model.begin(.end, clip: clip, width: strip)
        clip = model.move(translation: CGSize(width: 1000, height: 0), clip: clip, width: strip, speed: 2, maxOutputDuration: 3)
        XCTAssertEqual(clip.duration, 6, accuracy: 0.000001)
    }

    @MainActor func testFineModeIsExactlyTenthSpeedAndAccumulatesSubFrameMotion() {
        let model = TimelineViewModel()
        let clip = Clip(start: 100, end: 103, cover: 101.5)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        model.begin(.selection, clip: clip, width: strip)
        let rate = model.dragSecondsPerPoint
        let normal = model.move(translation: CGSize(width: 10, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3).start - 100
        model.end(clip: clip)
        model.begin(.selection, clip: clip, width: strip)
        model.setFine(true)
        var value = clip
        for step in 1...10 {
            value = model.move(translation: CGSize(width: CGFloat(step), height: 0), clip: value, width: strip, speed: 1, maxOutputDuration: 3)
        }
        XCTAssertEqual(normal, 10 * rate, accuracy: 0.001)
        XCTAssertEqual(value.start - 100, 10 * rate * 0.1, accuracy: 0.001,
                       "Long-press precision must be one tenth and keep sub-frame motion")
        model.end(clip: value)
        XCTAssertFalse(model.fineAdjustment)
    }

    @MainActor func testViewportAndPinchNeverChangeSelectionAndNeverZoomOnRelease() {
        let model = TimelineViewModel()
        let clip = Clip(start: 3599, end: 3602, cover: 3600.5)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        model.begin(.viewport, clip: clip, width: strip)
        XCTAssertEqual(model.move(translation: CGSize(width: 100, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3), clip)
        model.end()
        model.reset()
        model.beginPinch(x: 90, width: strip)
        model.pinch(scale: 20, x: 90, width: strip)
        model.endPinch(clip: clip)
        XCTAssertEqual(model.state.zoomScale, 20, accuracy: 0.001)
        model.selectionChanged(clip)
        XCTAssertEqual(model.state.zoomScale, 20, accuracy: 0.001, "Keeping a selection visible must not zoom")
        XCTAssertEqual(clip.start, 3599)
        XCTAssertEqual(clip.end, 3602)
        XCTAssertTrue(TimelineSelectionGeometry(state: model.state, clip: clip, width: strip).isVisible,
                      "A finished pinch must leave the selection on screen")
    }

    @MainActor func testPinchReleaseNeverLosesTheSelectionItIsEditing() {
        let model = TimelineViewModel()
        let clip = Clip(start: 600, end: 603, cover: 601.5)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        model.reset()
        model.beginPinch(x: strip, width: strip)
        model.pinch(scale: 20, x: strip, width: strip)
        XCTAssertFalse(TimelineSelectionGeometry(state: model.state, clip: clip, width: strip).isVisible,
                       "A pinch anchored at the far end of the source can move the selection off screen")
        let zoom = model.state.zoomScale
        model.endPinch(clip: clip)
        XCTAssertTrue(TimelineSelectionGeometry(state: model.state, clip: clip, width: strip).isVisible,
                      "Releasing brings the selection back and never re-scales it")
        XCTAssertEqual(model.state.zoomScale, zoom, accuracy: 0.000001)
        let center = model.state.viewportCenterTime
        model.endPinch(clip: clip)
        XCTAssertEqual(model.state.viewportCenterTime, center, "Leaving the editor must not nudge a finished pinch")
    }

    func testThumbnailWorkAndCellWidthStayInsideTheScreenAtEveryZoom() {
        for duration in [3.0, 60.0, 7200.0] {
            var state = TimelineState(duration: duration)
            for zoom in [CGFloat(1), 4, 5, 30, 31, 200, state.maximumZoomScale] {
                state.zoom(to: zoom, anchorTime: duration / 2, anchorFraction: 0.5)
                let plan = TimelineThumbnailPlan(state: state)
                XCTAssertLessThanOrEqual(plan.times.count, 15, "Decoding must stay a screen-sized request")
                XCTAssertGreaterThan(plan.times.count, 0)
                XCTAssertTrue(plan.times.allSatisfy { $0 >= 0 && $0 < duration })
                XCTAssertLessThanOrEqual(plan.cellWidth(in: strip), strip, "A cell must never exceed the strip")
                XCTAssertGreaterThanOrEqual(plan.cellWidth(in: strip), 1)
            }
        }
    }

    func testSelectionNearTheEndOfAZoomedSourceStaysVisible() {
        var state = TimelineState(duration: 7200)
        let clip = Clip(start: 7197, end: 7200, cover: 7198.5)
        state.zoom(to: 200, anchorTime: 100, anchorFraction: 0.5)
        state.keepVisible(clip)
        XCTAssertLessThanOrEqual(state.visibleStart, clip.start)
        XCTAssertGreaterThanOrEqual(state.visibleEnd, clip.end)
    }

    @MainActor func testALayoutResizeNeverLeavesGestureMathOnTheOldStripWidth() {
        let model = TimelineViewModel()
        let clip = Clip(start: 3599, end: 3602, cover: 3600.5)
        // The first layout pass can report a narrower strip than the card finally gets.
        model.configure(duration: 7200, clip: clip, width: 131, frameRate: 30)
        model.configure(duration: 7200, clip: clip, width: strip, frameRate: 30)
        let fitted = TimelineSelectionGeometry(state: model.state, clip: clip, width: strip)
        XCTAssertEqual(fitted.width, strip / 2, accuracy: 0.6, "A re-layout must restore half the strip for the selection")
        model.begin(.start, clip: clip, width: strip)
        let moved = model.move(translation: CGSize(width: 8, height: 0), clip: clip, width: strip, speed: 1, maxOutputDuration: 3)
        let after = TimelineSelectionGeometry(state: model.state, clip: moved, width: strip)
        XCTAssertEqual(after.left - fitted.left, 8, accuracy: 0.6,
                       "Gesture math must use the strip being drawn, not the width cached at launch")
    }
}
