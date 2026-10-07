import Foundation

/// Incremental movement lets the user change scrub speed without jumping frames.
struct FrameScrubSession {
    private var position: Double
    private var previousX: Double = 0
    let range: ClosedRange<Double>
    let frameRate: Double

    init(time: Double, range: ClosedRange<Double>, frameRate: Double) {
        position = time; self.range = range; self.frameRate = max(1, frameRate)
    }

    mutating func move(translation: CGSize, secondsPerPoint: Double) -> Double {
        let gain = Self.gain(for: translation.height)
        let delta = Double(translation.width) - previousX
        previousX = Double(translation.width)
        position = min(range.upperBound, max(range.lowerBound, position + delta * secondsPerPoint * gain))
        return min(range.upperBound, max(range.lowerBound, (position * frameRate).rounded() / frameRate))
    }

    static func gain(for verticalOffset: CGFloat) -> Double {
        if verticalOffset > 90 { return 0.1 }
        if verticalOffset > 40 { return 0.25 }
        return 1
    }
}
