import XCTest
@testable import Vimemo

final class TimelineTests: XCTestCase {
    func testPinchPreservesOffCenterAnchorIncludingMovingCentroid() {
        var state = TimelineState(duration: 7200)
        let anchor = state.time(at: 90, width: 300)
        state.zoom(to: 10, anchorTime: anchor, anchorFraction: 0.3)
        XCTAssertEqual(state.time(at: 90, width: 300), anchor, accuracy: 0.000001)
        state.zoom(to: 100, anchorTime: anchor, anchorFraction: 0.4)
        XCTAssertEqual(state.time(at: 120, width: 300), anchor, accuracy: 0.000001)
        XCTAssertEqual(state.visibleDuration, 72)
    }

    func testZoomLimitsResetAndViewportBoundaries() {
        var state = TimelineState(duration: 7200)
        state.zoom(to: 999, anchorTime: 3600, anchorFraction: 0.5)
        XCTAssertEqual(state.zoomScale, 200)
        state.center(on: -100)
        XCTAssertEqual(state.visibleStart, 0, accuracy: 0.000001)
        state.center(on: 9000)
        XCTAssertEqual(state.visibleEnd, 7200, accuracy: 0.000001)
        state.zoom(to: .nan, anchorTime: 1, anchorFraction: 0.5)
        XCTAssertEqual(state.zoomScale, 200)
        state.reset()
        XCTAssertEqual(state.visibleStart, 0)
        XCTAssertEqual(state.visibleEnd, 7200)
    }

    func testTwoHourThreeSecondSelectionHasSeparateUsableTargets() {
        var state = TimelineState(duration: 7200)
        var clip = Clip(); clip.start = 3599; clip.end = 3602; clip.cover = 3600.5
        state.focus(on: clip, width: 300)
        let geometry = TimelineSelectionGeometry(state: state, clip: clip, width: 300)
        XCTAssertEqual(state.zoomScale, 200)
        XCTAssertEqual(geometry.width, 120, accuracy: 0.000001)
        XCTAssertEqual(geometry.coverX(for: clip), (geometry.left + geometry.right) / 2, accuracy: 0.000001)
        XCTAssertGreaterThan(geometry.width - 44, 44)
        XCTAssertEqual(clip.duration, 3)
        clip.start = 0; clip.end = 3; clip.cover = 1.5
        state.focus(on: clip, width: 300)
        XCTAssertEqual(TimelineSelectionGeometry(state: state, clip: clip, width: 300).left, 0)
        clip.start = 7197; clip.end = 7200; clip.cover = 7198.5
        state.focus(on: clip, width: 300)
        XCTAssertEqual(TimelineSelectionGeometry(state: state, clip: clip, width: 300).right, 300)
    }

    func testLongSelectionKeepsRealEndpointsOutsideViewport() {
        var state = TimelineState(duration: 120)
        var clip = Clip(); clip.start = 10; clip.end = 100; clip.cover = 20
        state.zoom(to: 10, anchorTime: 60, anchorFraction: 0.5)
        let geometry = TimelineSelectionGeometry(state: state, clip: clip, width: 300)
        XCTAssertLessThan(geometry.left, 0)
        XCTAssertGreaterThan(geometry.right, 300)
        XCTAssertLessThan(geometry.coverX(for: clip), 0)
        state.focus(on: clip, width: 300)
        XCTAssertLessThanOrEqual(state.visibleStart, clip.start)
        XCTAssertGreaterThanOrEqual(state.visibleEnd, clip.end)
    }

    @MainActor func testBodyMovePreservesDurationCoverAndBothSourceBoundaries() {
        let model = TimelineViewModel()
        var clip = Clip(); clip.start = 3599; clip.end = 3602; clip.cover = 3600.5
        model.configure(duration: 7200, clip: clip, width: 300)
        let originalDuration = clip.duration, coverOffset = clip.cover - clip.start
        model.begin(.selection, clip: clip, width: 300, frameRate: 30)
        clip = model.move(translation: CGSize(width: 40, height: 0), clip: clip, speed: 1, maxOutputDuration: 3, frameRate: 30)
        XCTAssertGreaterThan(clip.start, 3599)
        XCTAssertEqual(clip.duration, originalDuration, accuracy: 0.000001)
        XCTAssertEqual(clip.cover - clip.start, coverOffset, accuracy: 0.000001)
        model.end(clip: clip)
        XCTAssertEqual(model.state.viewportCenterTime, (clip.start + clip.end) / 2, accuracy: 0.000001)
        model.begin(.selection, clip: clip, width: 300, frameRate: 30)
        clip = model.move(translation: CGSize(width: -100000, height: 0), clip: clip, speed: 1, maxOutputDuration: 3, frameRate: 30)
        XCTAssertEqual(clip.start, 0)
        XCTAssertEqual(clip.duration, 3)
        clip = model.move(translation: CGSize(width: 100000, height: 0), clip: clip, speed: 1, maxOutputDuration: 3, frameRate: 30)
        XCTAssertEqual(clip.end, 7200)
        XCTAssertEqual(clip.duration, 3)
    }

    @MainActor func testHandlesAreDraggableOnTwoHourSourceAndRespectSpeedPolicy() {
        let model = TimelineViewModel()
        var clip = Clip(); clip.start = 3599; clip.end = 3602; clip.cover = 3600.5
        model.configure(duration: 7200, clip: clip, width: 300)
        model.begin(.start, clip: clip, width: 300, frameRate: 30)
        clip = model.move(translation: CGSize(width: 8, height: 0), clip: clip, speed: 1, maxOutputDuration: 3, frameRate: 30)
        XCTAssertGreaterThan(clip.start, 3599)
        XCTAssertLessThan(clip.duration, 3)
        model.end(clip: clip)
        let end = clip.end
        model.begin(.end, clip: clip, width: 300, frameRate: 30)
        clip = model.move(translation: CGSize(width: -8, height: 0), clip: clip, speed: 1, maxOutputDuration: 3, frameRate: 30)
        XCTAssertLessThan(clip.end, end)
        model.end(clip: clip)
        model.begin(.end, clip: clip, width: 300, frameRate: 30)
        clip = model.move(translation: CGSize(width: 1000, height: 0), clip: clip, speed: 2, maxOutputDuration: 3, frameRate: 30)
        XCTAssertEqual(clip.duration, 6, accuracy: 0.000001)
    }

    @MainActor func testFineModeIsIncrementalAndAccumulatesSubFrameMotion() {
        let model = TimelineViewModel()
        var clip = Clip(); clip.start = 100; clip.end = 103; clip.cover = 101.5
        model.configure(duration: 7200, clip: clip, width: 300)
        model.begin(.selection, clip: clip, width: 300, frameRate: 30)
        clip = model.move(translation: CGSize(width: 10, height: 0), clip: clip, speed: 1, maxOutputDuration: 3, frameRate: 30)
        let normal = clip.start
        model.setFine(true)
        clip = model.move(translation: CGSize(width: 10, height: 0), clip: clip, speed: 1, maxOutputDuration: 3, frameRate: 30)
        XCTAssertEqual(clip.start, normal)
        for x in 11...20 {
            clip = model.move(translation: CGSize(width: x, height: 0), clip: clip, speed: 1, maxOutputDuration: 3, frameRate: 30)
        }
        XCTAssertEqual(clip.start - normal, 0.12, accuracy: 1.0 / 30)
        model.end(clip: clip)
        XCTAssertFalse(model.fineAdjustment)
    }

    @MainActor func testViewportAndPinchNeverChangeSelectionAndResetStaysGlobal() {
        let model = TimelineViewModel()
        var clip = Clip(); clip.start = 3599; clip.end = 3602; clip.cover = 3600.5
        model.configure(duration: 7200, clip: clip, width: 300)
        model.begin(.viewport, clip: clip, width: 300, frameRate: 30)
        XCTAssertEqual(model.move(translation: CGSize(width: 100, height: 0), clip: clip, speed: 1, maxOutputDuration: 3, frameRate: 30), clip)
        model.end()
        model.beginPinch(x: 90, width: 300)
        model.pinch(scale: 0.1, x: 90, width: 300)
        model.endPinch()
        XCTAssertEqual(model.state.zoomScale, 20)
        model.reset(); model.configure(duration: 7200, clip: clip, width: 300)
        model.selectionChanged(clip)
        XCTAssertEqual(model.state.zoomScale, 1)
        XCTAssertEqual(model.state.visibleDuration, 7200)
    }

    func testSelectionAt5959RemainsVisibleAndThumbnailWorkIsBounded() {
        var state = TimelineState(duration: 7200)
        var clip = Clip(); clip.start = 3599; clip.end = 3602; clip.cover = 3600
        state.zoom(to: 200, anchorTime: 100, anchorFraction: 0.5)
        state.keepVisible(clip)
        XCTAssertLessThanOrEqual(state.visibleStart, clip.start)
        XCTAssertGreaterThanOrEqual(state.visibleEnd, clip.end)
        for zoom in [CGFloat(1), 4, 5, 30, 31, 100, 200] {
            state.zoom(to: zoom, anchorTime: 3600, anchorFraction: 0.5)
            let plan = TimelineThumbnailPlan(state: state)
            XCTAssertLessThanOrEqual(plan.times.count, 15)
            XCTAssertGreaterThan(plan.times.count, 0)
            XCTAssertTrue(plan.times.allSatisfy { $0 >= 0 && $0 < 7200 })
        }
    }

    @MainActor func testOverviewBodyCanMoveTo5959ThenAutomaticallyFocus() {
        let model = TimelineViewModel()
        var clip = Clip()
        model.configure(duration: 7200, clip: clip, width: 300)
        model.reset()
        model.begin(.selection, clip: clip, width: 300, frameRate: 30)
        clip = model.move(translation: CGSize(width: 3599.0 / 7200 * 300, height: 0), clip: clip,
                          speed: 1, maxOutputDuration: 3, frameRate: 30)
        XCTAssertEqual(clip.start, 3599, accuracy: 0.000001)
        XCTAssertEqual(clip.duration, 3)
        model.end(clip: clip)
        XCTAssertEqual(model.state.zoomScale, 200)
        XCTAssertEqual(model.state.viewportCenterTime, 3600.5, accuracy: 0.000001)
        XCTAssertLessThan(model.state.visibleStart, clip.start)
        XCTAssertGreaterThan(model.state.visibleEnd, clip.end)
    }
}
