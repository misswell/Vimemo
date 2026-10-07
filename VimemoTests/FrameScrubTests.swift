import XCTest
@testable import Vimemo

final class FrameScrubTests: XCTestCase {
    func testCoverDragAlignsToFramesAndStaysInsideClip() {
        var drag = FrameScrubSession(time: 2, range: 1...2.9666666667, frameRate: 30)
        XCTAssertEqual(drag.move(translation: CGSize(width: 13, height: 0), secondsPerPoint: 0.01), 64.0 / 30, accuracy: 0.0001)
        XCTAssertEqual(drag.move(translation: CGSize(width: 2000, height: 0), secondsPerPoint: 0.01), 2.9666666667, accuracy: 0.0001)
        XCTAssertEqual(drag.move(translation: CGSize(width: -2000, height: 0), secondsPerPoint: 0.01), 1)
    }

    func testLoweringScrubSpeedDoesNotJumpPosition() {
        var drag = FrameScrubSession(time: 1, range: 0...10, frameRate: 30)
        let normal = drag.move(translation: CGSize(width: 100, height: 0), secondsPerPoint: 0.01)
        XCTAssertEqual(normal, 2)
        XCTAssertEqual(drag.move(translation: CGSize(width: 100, height: 60), secondsPerPoint: 0.01), normal)
        XCTAssertEqual(drag.move(translation: CGSize(width: 140, height: 60), secondsPerPoint: 0.01), 2.1, accuracy: 0.0001)
        XCTAssertEqual(drag.move(translation: CGSize(width: 140, height: 110), secondsPerPoint: 0.01), 2.1, accuracy: 0.0001)
        XCTAssertEqual(drag.move(translation: CGSize(width: 240, height: 110), secondsPerPoint: 0.01), 2.2, accuracy: 0.0001)
    }

    func testCenterScrubberAccumulatesSmallMovesIntoOneFrame() {
        var drag = FrameScrubSession(time: 1, range: 0...3, frameRate: 60)
        for x in 1...12 { _ = drag.move(translation: CGSize(width: x, height: 0), secondsPerPoint: 1.0 / 60 / 12) }
        XCTAssertEqual(drag.move(translation: CGSize(width: 12, height: 0), secondsPerPoint: 1.0 / 60 / 12), 61.0 / 60, accuracy: 0.0001)
        XCTAssertEqual(drag.move(translation: .zero, secondsPerPoint: 1.0 / 60 / 12), 1)
    }
}
