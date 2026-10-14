import SwiftUI

@MainActor final class TimelineViewModel: ObservableObject {
    enum Target { case start, end, selection, viewport, cover }
    @Published private(set) var state = TimelineState(duration: 0.1)
    @Published private(set) var target: Target?
    @Published private(set) var fineAdjustment = false
    @Published private(set) var feedbackTime: Double?
    private var clipID: UUID?
    private var previousTranslation: CGFloat = 0
    private var secondsPerPoint: Double = 0
    private var scrub: FrameScrubSession?
    private var pinchState: TimelineState?
    private var pinchAnchor: Double = 0
    private var timelineWidth: CGFloat = 300

    func configure(duration: Double, clip: Clip, width: CGFloat) {
        timelineWidth = max(1, width)
        if state.videoDuration != max(0.1, duration) {
            state = TimelineState(duration: duration); clipID = nil
        }
        if clipID != clip.id {
            clipID = clip.id
            state.reset()
            autoFocus(clip: clip, width: width)
        }
    }

    func autoFocus(clip: Clip, width: CGFloat) {
        if CGFloat(clip.duration / state.visibleDuration) * width < 80 { state.focus(on: clip, width: width) }
    }
    func focus(_ clip: Clip, width: CGFloat) { state.focus(on: clip, width: width) }
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
        pinchAnchor = state.time(at: x, width: width)
    }
    func pinch(scale: CGFloat, x: CGFloat, width: CGFloat) {
        guard let initial = pinchState else { return }
        state.zoom(to: initial.zoomScale * scale, anchorTime: pinchAnchor, anchorFraction: x / max(1, width))
    }
    func endPinch() { pinchState = nil }

    func begin(_ target: Target, clip: Clip, width: CGFloat, frameRate: Double) {
        self.target = target; previousTranslation = 0
        // In overview, moving the body must retain the coarse scale so a long
        // source can be traversed in one drag. Handles still enter precision mode.
        if target == .start || target == .end { autoFocus(clip: clip, width: width) }
        secondsPerPoint = state.visibleDuration / Double(max(1, width))
        if target == .cover {
            let selection = TimelineSelectionGeometry(state: state, clip: clip, width: width)
            secondsPerPoint = clip.duration / Double(max(1, selection.width))
            scrub = FrameScrubSession(time: clip.cover, range: clip.start...max(clip.start, clip.end - 1 / max(1, frameRate)), frameRate: frameRate)
        }
    }
    func setFine(_ enabled: Bool) { fineAdjustment = enabled }

    func move(translation: CGSize, clip: Clip, speed: Double, maxOutputDuration: Double?, frameRate: Double) -> Clip {
        guard let target else { return clip }
        var result = clip
        let incremental = Double(translation.width - previousTranslation) * secondsPerPoint
        previousTranslation = translation.width
        let gain = fineAdjustment ? 0.1 : FrameScrubSession.gain(for: translation.height)
        if target == .viewport {
            state.center(on: state.viewportCenterTime - incremental)
            return clip
        }
        if target == .cover {
            result.cover = scrub?.move(translation: translation, secondsPerPoint: secondsPerPoint) ?? clip.cover
            result.coverPhotoFilename = nil
            feedbackTime = result.cover
            return result
        }
        // Keep continuous trim times, as in the existing Clip model. Only the
        // cover snaps to frames; tiny handle movements must not be discarded.
        let delta = incremental * gain
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

    func end(clip: Clip? = nil) {
        if let clip, let target, target != .viewport, target != .cover {
            autoFocus(clip: clip, width: timelineWidth)
            state.center(on: (clip.start + clip.end) / 2)
        }
        target = nil; fineAdjustment = false; feedbackTime = nil; scrub = nil
    }
}
