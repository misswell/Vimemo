import SwiftUI

@MainActor final class TimelineViewModel: ObservableObject {
    enum Target { case start, end, selection, viewport, cover }
    @Published private(set) var state = TimelineState(duration: 0.1)
    @Published private(set) var target: Target?
    @Published private(set) var fineAdjustment = false
    @Published private(set) var feedbackTime: Double?
    private var clipID: UUID?
    private var configuredWidth: CGFloat = 0
    private var frameRate: Double = 30
    private var previousTranslation: CGFloat = 0
    private var secondsPerPoint: Double = 0
    private var scrub: FrameScrubSession?
    private var pinchState: TimelineState?
    private var pinchAnchor: Double = 0

    func configure(duration: Double, clip: Clip, width: CGFloat, frameRate: Double = 30) {
        let strip = max(1, width)
        self.frameRate = max(1, frameRate)
        if state.videoDuration != max(0.1, duration) {
            state = TimelineState(duration: duration, frameRate: self.frameRate); clipID = nil
        }
        let resized = strip != configuredWidth
        configuredWidth = strip
        // An in-flight drag must never re-scale under the finger.
        guard target == nil, pinchState == nil else { return }
        if clipID != clip.id {
            clipID = clip.id
            state.reset()
            ensureTrimmable(clip: clip, width: strip)
        } else if resized {
            // A re-layout hands the strip a different width than the one the current fit used.
            state.fit(clip: clip, width: strip)
        }
    }

    /// The drawn selection must be the real trim window, so a selection too small to grab
    /// at its true width makes the viewport fit instead of widening a fake box.
    private func ensureTrimmable(clip: Clip, width: CGFloat) {
        guard state.realWidth(of: clip, width: width) < min(120, width) else { return }
        state.fit(clip: clip, width: width)
    }

    /// Uses the width the last layout handed `configure`, so a button press fits the strip
    /// the user is actually looking at.
    func focus(_ clip: Clip) { state.fit(clip: clip, width: configuredWidth) }
    func reset() { state.reset() }
    func zoom(by factor: CGFloat, clip: Clip) {
        state.zoom(to: state.zoomScale * factor, anchorTime: (clip.start + clip.end) / 2, anchorFraction: 0.5)
    }
    func selectionChanged(_ clip: Clip) {
        guard target == nil, pinchState == nil else { return }
        state.keepVisible(clip)
    }

    func beginPinch(x: CGFloat, width: CGFloat) {
        end()
        pinchState = state
        pinchAnchor = state.time(at: x, width: max(1, width))
    }
    func pinch(scale: CGFloat, x: CGFloat, width: CGFloat) {
        guard let initial = pinchState else { return }
        state.zoom(to: initial.zoomScale * scale, anchorTime: pinchAnchor, anchorFraction: x / max(1, width))
    }
    /// Releasing a pinch keeps the zoom the fingers chose, but never leaves the selection
    /// off-screen: a hidden endpoint cannot be trimmed, and its handle is deliberately not drawn.
    func endPinch(clip: Clip) {
        guard pinchState != nil else { return }
        state.keepVisible(clip); pinchState = nil
    }

    func begin(_ target: Target, clip: Clip, width: CGFloat) {
        let strip = max(1, width)
        self.target = target; previousTranslation = 0
        // Trimming needs the handles at their real width; panning the whole selection
        // deliberately keeps the current scale so a long source can be traversed in one drag.
        if target == .start || target == .end { ensureTrimmable(clip: clip, width: strip) }
        let geometry = TimelineSelectionGeometry(state: state, clip: clip, width: strip)
        switch target {
        case .cover: secondsPerPoint = clip.duration / max(1, geometry.width)
        case .start, .end where geometry.isDisplayClamped: secondsPerPoint = clip.duration / max(1, geometry.width)
        default: secondsPerPoint = state.secondsPerPoint(width: strip)
        }
        if target == .cover {
            scrub = FrameScrubSession(time: clip.cover, range: clip.start...max(clip.start, clip.end - 1 / frameRate), frameRate: frameRate)
        }
    }
    func setFine(_ enabled: Bool) { fineAdjustment = enabled }
    var dragSecondsPerPoint: Double { max(0.000_001, secondsPerPoint) }

    func move(translation: CGSize, clip: Clip, width: CGFloat, speed: Double, maxOutputDuration: Double?) -> Clip {
        guard let target else { return clip }
        var result = clip
        let incremental = Double(translation.width - previousTranslation) * secondsPerPoint
        previousTranslation = translation.width
        if target == .viewport {
            state.center(on: state.viewportCenterTime - incremental)
            return clip
        }
        if target == .cover {
            // The session itself applies the pull-down gain for slow frame selection.
            result.cover = scrub?.move(translation: translation, secondsPerPoint: secondsPerPoint) ?? clip.cover
            result.coverPhotoFilename = nil
            feedbackTime = result.cover
            return result
        }
        // Pull-down slow scrubbing belongs to the cover line; a trim handle only has the
        // long-press precision mode.
        let delta = incremental * (fineAdjustment ? 0.1 : 1)
        switch target {
        case .selection:
            let start = min(max(0, clip.start + delta), max(0, state.videoDuration - clip.duration))
            let shift = start - clip.start
            result.start = start; result.end += shift; result.cover += shift
            feedbackTime = result.start
        case .start:
            result.start = min(clip.end - min(0.1, state.videoDuration), max(0, clip.start + delta))
            if let maximum = maxOutputDuration { result.start = max(result.start, clip.end - maximum * speed) }
            result.normalize(sourceDuration: state.videoDuration, speed: speed, maxOutputDuration: maxOutputDuration)
            feedbackTime = result.start
        case .end:
            result.end = min(state.videoDuration, max(clip.start + min(0.1, state.videoDuration), clip.end + delta))
            result.normalize(sourceDuration: state.videoDuration, speed: speed, maxOutputDuration: maxOutputDuration)
            feedbackTime = result.end
        case .viewport, .cover: break
        }
        state.keepVisible(result)
        return result
    }

    /// Releasing never jumps the viewport; it only guarantees the selection stays on screen.
    func end(clip: Clip? = nil) {
        if let clip, let target, target != .viewport, target != .cover { state.keepVisible(clip) }
        target = nil; fineAdjustment = false; feedbackTime = nil; scrub = nil
    }
}
