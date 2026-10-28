import SwiftUI

@MainActor final class TimelineViewModel: ObservableObject {
    enum Target { case start, end, selection, viewport, cover }

    @Published private(set) var state = TimelineState(duration: 0.1)
    @Published private(set) var target: Target?
    @Published private(set) var fineAdjustment = false
    @Published private(set) var feedbackTime: Double?
    @Published private(set) var minimumDurationReached = false
    /// Viewport widths per second the strip wants to scroll while a finger parks in an edge zone.
    @Published private(set) var autoScrollRate: Double = 0
    private(set) var isFittedToSelection = false

    private struct Drag {
        var target: Target
        var originX: CGFloat
        var width: CGFloat
        var secondsPerPoint: Double
        /// The difference between the grabbed control's time and the time under the finger. It
        /// absorbs whatever the precision fit could not do at the head or tail of the source, so
        /// the control then tracks the finger exactly.
        var timeOffset: Double
        var baselineCenter: Double
        var duration: Double
        var coverOffset: Double
        var speed: Double = 1
        var maxOutputDuration: Double?
        var translation: CGSize = .zero
    }

    private var drag: Drag?
    private var scrub: FrameScrubSession?
    /// The clip value the last drag or auto-scroll produced. SwiftUI reports a binding write from
    /// `onChange` after the gesture has already ended, so the model has to remember which edits
    /// came from the timeline itself: a release must never be followed by a camera nudge.
    private var produced: Clip?
    private var frameRate: Double = 30
    private var clipID: UUID?
    private var configuredWidth: CGFloat = 0
    private var pinchState: TimelineState?
    private var pinchAnchor: Double = 0
    private var minimumNoticeTask: Task<Void, Never>?

    func configure(duration: Double, clip: Clip, width: CGFloat, frameRate: Double = 30) {
        let strip = max(1, width)
        self.frameRate = max(1, frameRate)
        if state.videoDuration != max(0.1, duration) {
            state = TimelineState(duration: duration, frameRate: self.frameRate)
            clipID = nil
            isFittedToSelection = false
        }
        let resized = strip != configuredWidth
        configuredWidth = strip
        // An in-flight drag or pinch must never re-scale under the finger.
        guard target == nil, pinchState == nil else { return }
        if clipID != clip.id {
            clipID = clip.id
            // A clip opens in Overview: the whole source, with the selection drawn at its true
            // ratio. Zooming in is the user's decision, made by grabbing a handle or 聚焦片段.
            state.reset()
            isFittedToSelection = false
        } else if resized, isFittedToSelection {
            // A re-layout hands the strip a different width than the one the fit used.
            state.fit(clip: clip, width: strip)
        }
    }

    func focus(_ clip: Clip) {
        state.fit(clip: clip, width: configuredWidth)
        isFittedToSelection = true
    }

    func reset() {
        state.reset()
        isFittedToSelection = false
    }

    /// The buttons work on the viewport the user is looking at, not on the selection.
    func zoom(by factor: CGFloat) {
        state.zoom(to: state.zoomScale * factor, anchorTime: state.viewportCenterTime, anchorFraction: 0.5)
    }

    /// Follows a clip the user changed somewhere else, e.g. the 精确裁剪 steppers, so the camera
    /// shows the result. A value the timeline just produced is its own edit: the fingers already
    /// decided where the camera is, so this returns without moving it.
    func selectionChanged(_ clip: Clip) {
        guard target == nil, pinchState == nil else { return }
        if produced == clip { produced = nil; return }
        state.keepVisible(clip)
    }

    func selectionIsOffScreen(_ clip: Clip) -> Bool {
        !TimelineSelectionGeometry(state: state, clip: clip, width: configuredWidth).isVisible
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

    /// Releasing a pinch must not undo what the fingers did. The viewport keeps exactly the zoom
    /// and anchor they chose; a selection that ends up outside it is a legal state, and the strip
    /// says so instead of dragging the camera back.
    func endPinch() { pinchState = nil }

    func begin(_ target: Target, clip: Clip, width: CGFloat, at fingerX: CGFloat) {
        minimumNoticeTask?.cancel()
        minimumDurationReached = false
        let strip = max(1, width)
        let x = fingerX
        self.target = target
        produced = nil
        autoScrollRate = 0
        if target != .viewport && target != .selection {
            enterPrecision(target: target, clip: clip, edgeTime: grabbedTime(for: target, clip: clip),
                           fingerX: x, width: strip)
        }
        let perPoint = target == .cover
            ? clip.duration / max(1, state.realWidth(of: clip, width: strip))
            : state.secondsPerPoint(width: strip)
        drag = Drag(
            target: target, originX: x, width: strip, secondsPerPoint: perPoint,
            timeOffset: grabbedTime(for: target, clip: clip) - state.time(at: x, width: strip),
            baselineCenter: state.viewportCenterTime, duration: clip.duration,
            coverOffset: clip.cover - clip.start
        )
        if target == .cover {
            scrub = FrameScrubSession(time: clip.cover, range: clip.start...max(clip.start, clip.end - 1 / max(1, frameRate)), frameRate: frameRate)
        }
    }

    /// Trimming needs the endpoints far enough apart to be real targets, so grabbing one that is
    /// drawn narrower than half the strip opens the precision viewport with that edge under the
    /// finger. Moving the whole selection deliberately keeps the current scale, so a long source
    /// stays traversable in one drag.
    private func enterPrecision(target: Target, clip: Clip, edgeTime: Double, fingerX: CGFloat, width: CGFloat) {
        guard state.realWidth(of: clip, width: width) < width * TimelineState.precisionSelectionFraction else { return }
        let nextScaleLimit = min(state.maximumZoomScale, max(state.zoomScale, state.zoomScale * 2))
        var anchorX = fingerX
        if target == .start || target == .end {
            let geometry = TimelineSelectionGeometry(state: state, clip: clip, width: width)
            let isStart = target == .start
            if let zone = geometry.handleZone(isStart: isStart, width: width),
               let gripX = geometry.handleGripX(isStart: isStart, width: width), zone.contains(fingerX) {
                let grabOffset = fingerX - gripX
                let desiredGripX = fingerX - grabOffset
                let projectedWidth = width * clip.duration * nextScaleLimit / CGFloat(state.videoDuration)
                if projectedWidth < TimelineSelectionGeometry.controlBand {
                    // In the overview the start and end grips live in a separated three-control
                    // cluster. Keep the cluster grip under the finger during each zoom step.
                    let unit = min(TimelineSelectionGeometry.controlBand, width / 3)
                    anchorX = desiredGripX + (isStart ? unit : -unit) - projectedWidth / 2
                } else {
                    // Once the selection is wide enough, the ball sits against its real edge.
                    anchorX = desiredGripX + (isStart ? Self.joystickRadius : -Self.joystickRadius)
                }
            }
        }
        // Enter precision progressively. A long source can need a very large fit scale, but
        // jumping there on the first touch makes the timeline appear to teleport. Each new
        // handle grab advances by at most one doubling until the clip is easy to work with.
        withAnimation(.easeInOut(duration: 0.22)) {
            state.fit(clip: clip, width: width, edgeTime: edgeTime, fingerX: anchorX,
                      maximumScale: nextScaleLimit)
        }
        isFittedToSelection = true
    }

    private static let joystickRadius = TimelineSelectionGeometry.joystickBallDiameter / 2

    private func grabbedTime(for target: Target, clip: Clip) -> Double {
        switch target {
        case .start: return clip.start
        case .end: return clip.end
        case .cover: return clip.cover
        case .selection, .viewport: return clip.start
        }
    }

    func setFine(_ enabled: Bool) { fineAdjustment = enabled }
    var dragSecondsPerPoint: Double { max(0.000_001, drag?.secondsPerPoint ?? state.secondsPerPoint(width: configuredWidth)) }

    func move(translation: CGSize, clip: Clip, width: CGFloat, speed: Double, maxOutputDuration: Double?) -> Clip {
        guard var current = drag else { return clip }
        current.width = max(1, width)
        current.translation = translation
        current.speed = speed
        current.maxOutputDuration = maxOutputDuration
        // Gesture math always uses the strip being drawn and the viewport as it now stands.
        if current.target != .cover { current.secondsPerPoint = state.secondsPerPoint(width: current.width) }
        drag = current
        return derive(clip)
    }

    /// A finger parked in an edge zone scrolls the viewport beneath it, so one continuous drag can
    /// take a trim from 00:00 to the end of the source without releasing.
    func autoScroll(deltaTime: Double, clip: Clip) -> Clip? {
        guard drag != nil, abs(autoScrollRate) > 0.0001 else { return nil }
        guard state.pan(seconds: autoScrollRate * deltaTime * state.visibleDuration) != 0 else { return nil }
        return derive(clip)
    }

    private func derive(_ clip: Clip) -> Clip {
        guard let drag else { return clip }
        var result = clip
        switch drag.target {
        case .viewport:
            state.center(on: drag.baselineCenter - Double(drag.translation.width) * drag.secondsPerPoint)
            autoScrollRate = 0
            return clip
        case .cover:
            autoScrollRate = 0
            result.cover = scrub?.move(translation: drag.translation, secondsPerPoint: drag.secondsPerPoint) ?? clip.cover
            result.coverPhotoFilename = nil
            feedbackTime = result.cover
            produced = result
            return result
        case .start, .end, .selection:
            // Pull-down slow scrubbing belongs to the cover line; a trim target only has the
            // long-press precision mode.
            let gain = fineAdjustment ? 0.1 : 1
            let virtualX = drag.originX + drag.translation.width * gain
            let time = state.time(at: virtualX, width: drag.width) + drag.timeOffset
            switch drag.target {
            case .start:
                let minimumDuration = min(0.1, state.videoDuration)
                let latestStart = clip.end - minimumDuration
                if time > latestStart + 0.000_001 { showMinimumDurationNotice() }
                result.start = min(latestStart, max(0, time))
                if let maximum = drag.maxOutputDuration { result.start = max(result.start, clip.end - maximum * drag.speed) }
                result.normalize(sourceDuration: state.videoDuration, speed: drag.speed, maxOutputDuration: drag.maxOutputDuration)
                feedbackTime = result.start
            case .end:
                let minimumDuration = min(0.1, state.videoDuration)
                let earliestEnd = clip.start + minimumDuration
                if time < earliestEnd - 0.000_001 { showMinimumDurationNotice() }
                result.end = min(state.videoDuration, max(earliestEnd, time))
                result.normalize(sourceDuration: state.videoDuration, speed: drag.speed, maxOutputDuration: drag.maxOutputDuration)
                feedbackTime = result.end
            case .selection:
                let start = min(max(0, time), max(0, state.videoDuration - drag.duration))
                let shift = start - clip.start
                result.start = start
                result.end = start + drag.duration
                result.cover = clip.cover + shift
                feedbackTime = result.start
            case .viewport, .cover: break
            }
            autoScrollRate = scrollRate(fingerX: drag.originX + drag.translation.width, width: drag.width)
            produced = result
            return result
        }
    }

    private func showMinimumDurationNotice() {
        guard !minimumDurationReached else { return }
        minimumDurationReached = true
        minimumNoticeTask?.cancel()
        minimumNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.minimumDurationReached = false
        }
    }

    /// Zero when the viewport is the whole source or the requested direction has no room left.
    private func scrollRate(fingerX: CGFloat, width: CGFloat) -> Double {
        guard let drag, state.canScroll, drag.target == .start || drag.target == .end || drag.target == .selection else { return 0 }
        let zone = min(56, max(24, width * 0.18))
        let x = min(max(fingerX, 0), width)
        if x < zone, state.visibleStart > 0 { return -pow(Double((zone - x) / zone), 2) }
        if x > width - zone, state.visibleEnd < state.videoDuration { return pow(Double((x - (width - zone)) / zone), 2) }
        return 0
    }

    /// Releasing never jumps the viewport and never re-scales: the fingers or the buttons that
    /// moved it are the only things allowed to.
    func end() {
        drag = nil
        target = nil
        fineAdjustment = false
        feedbackTime = nil
        scrub = nil
        autoScrollRate = 0
    }
}
