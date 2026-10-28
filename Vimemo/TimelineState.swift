import CoreGraphics

/// The timeline's single coordinate system: a viewport over the source, described by where it
/// starts and how long it is. Every pixel a control draws or reads derives from these two.
struct TimelineState: Equatable {
    let videoDuration: Double
    let minimumVisibleDuration: Double
    let maximumZoomScale: CGFloat
    private(set) var zoomScale: CGFloat = 1
    private(set) var viewportCenterTime: Double
    static let minZoomScale: CGFloat = 1
    /// Precision mode makes the selection half the strip and leaves a quarter either side.
    static let precisionSelectionFraction: Double = 0.5

    init(duration: Double, frameRate: Double = 30) {
        videoDuration = duration.isFinite ? max(0.1, duration) : 0.1
        // The finest useful window is two real frames, so it comes from the frame grid rather
        // than a fixed second: a 0.1 s clip must still be displayable at half the strip. Rates
        // outside the plausible video range come from sparse or variable-frame files and are
        // ignored, because they would otherwise move the ceiling.
        let rate = frameRate.isFinite ? min(240, max(24, frameRate)) : 30
        minimumVisibleDuration = min(videoDuration, 2 / rate)
        maximumZoomScale = max(200, CGFloat(videoDuration / minimumVisibleDuration))
        viewportCenterTime = videoDuration / 2
    }

    var visibleDuration: Double { videoDuration / Double(zoomScale) }
    var visibleStart: Double { viewportCenterTime - visibleDuration / 2 }
    var visibleEnd: Double { visibleStart + visibleDuration }
    var canScroll: Bool { visibleDuration < videoDuration - 0.000_001 }
    func x(for time: Double, width: CGFloat) -> CGFloat { CGFloat((time - visibleStart) / visibleDuration) * width }
    func time(at x: CGFloat, width: CGFloat) -> Double { visibleStart + Double(x / max(1, width)) * visibleDuration }
    func secondsPerPoint(width: CGFloat) -> Double { visibleDuration / Double(max(1, width)) }
    func pixelsPerSecond(width: CGFloat) -> Double { Double(max(1, width)) / visibleDuration }

    mutating func center(on time: Double) {
        let half = visibleDuration / 2
        viewportCenterTime = min(videoDuration - half, max(half, time))
    }

    mutating func setViewportStart(_ start: Double) {
        let span = max(0, videoDuration - visibleDuration)
        viewportCenterTime = min(max(0, start), span) + visibleDuration / 2
    }

    /// Returns the seconds actually moved: at either end of the source there is nothing left.
    @discardableResult
    mutating func pan(seconds: Double) -> Double {
        let before = visibleStart
        setViewportStart(before + seconds)
        return visibleStart - before
    }

    /// Keep the time under the pinch centroid at the same fractional screen position.
    mutating func zoom(to scale: CGFloat, anchorTime: Double, anchorFraction: CGFloat) {
        guard scale.isFinite, anchorTime.isFinite, anchorFraction.isFinite else { return }
        zoomScale = min(maximumZoomScale, max(Self.minZoomScale, scale))
        let fraction = min(1, max(0, anchorFraction))
        center(on: anchorTime + (0.5 - Double(fraction)) * visibleDuration)
    }

    mutating func reset() { zoomScale = 1; viewportCenterTime = videoDuration / 2 }

    func realWidth(of clip: Clip, width: CGFloat) -> CGFloat {
        x(for: clip.end, width: width) - x(for: clip.start, width: width)
    }

    mutating func fit(clip: Clip, width: CGFloat) {
        applyPrecisionZoom(for: clip)
        center(on: (clip.start + clip.end) / 2)
    }

    /// Precision fit that leaves the grabbed edge under the finger. The head and tail of the
    /// source clamp naturally, so an edge already at the boundary simply stops there.
    mutating func fit(clip: Clip, width: CGFloat, edgeTime: Double, fingerX: CGFloat) {
        applyPrecisionZoom(for: clip)
        setViewportStart(edgeTime - Double(fingerX) * secondsPerPoint(width: width))
    }

    private mutating func applyPrecisionZoom(for clip: Clip) {
        let window = min(videoDuration, max(clip.duration / Self.precisionSelectionFraction, minimumVisibleDuration))
        zoomScale = min(maximumZoomScale, max(Self.minZoomScale, CGFloat(videoDuration / window)))
    }

    mutating func keepVisible(_ clip: Clip) {
        let margin = visibleDuration * 0.12
        if clip.duration > visibleDuration - 2 * margin {
            center(on: (clip.start + clip.end) / 2)
        } else if clip.start < visibleStart + margin {
            center(on: clip.start - margin + visibleDuration / 2)
        } else if clip.end > visibleEnd - margin {
            center(on: clip.end + margin - visibleDuration / 2)
        }
    }
}

/// Where the selection actually is. It is always drawn at its true time ratio, never widened
/// into a placeholder box: a box the user cannot trust is not trimmable.
struct TimelineSelectionGeometry {
    /// Trim handles and the selection body each need a 44 pt band. When the endpoints are closer
    /// than that, the three bands are laid out as one cluster on the selection's midpoint and the
    /// cluster is slid along the strip, so a sub-pixel selection in Overview can still be grabbed,
    /// moved and trimmed even when it sits at the very head or tail of the source.
    static let controlBand: CGFloat = 44
    static let minimumZone: CGFloat = 4

    let left: CGFloat
    let right: CGFloat
    let isVisible: Bool
    var width: CGFloat { right - left }
    var midpoint: CGFloat { (left + right) / 2 }
    var isNarrow: Bool { width < Self.controlBand }

    init(state: TimelineState, clip: Clip, width: CGFloat) {
        left = state.x(for: clip.start, width: width)
        right = state.x(for: clip.end, width: width)
        isVisible = clip.end >= state.visibleStart && clip.start <= state.visibleEnd
    }

    func coverX(for clip: Clip) -> CGFloat {
        left + CGFloat(min(1, max(0, (clip.cover - clip.start) / max(0.1, clip.duration)))) * width
    }

    /// The cover line stays on its real time. Only the arrow grip is clamped so its full
    /// 44 pt touch target remains inside the strip at the source boundaries.
    func coverGripX(for clip: Clip, stripWidth: CGFloat) -> CGFloat {
        let x = coverX(for: clip)
        let inset = min(22, stripWidth / 2)
        return min(max(inset, x), stripWidth - inset)
    }

    func handleZone(isStart: Bool, width: CGFloat) -> ClosedRange<CGFloat>? {
        guard isVisible, let edge = grabbableEdge(isStart, width: width) else { return nil }
        if let cluster = cluster(in: width) {
            let unit = cluster.unit, origin = cluster.origin
            return isStart ? origin ... origin + unit : origin + 2 * unit ... origin + 3 * unit
        }
        // Put each joystick outside its true edge. The horizontal shaft then reaches inward
        // from the ball to the exact trim boundary, leaving the two controls easy to distinguish.
        let reach = Self.controlBand
        let zone = isStart
            ? (edge - 1.5 * reach ... edge - 0.5 * reach)
            : (edge + 0.5 * reach ... edge + 1.5 * reach)
        return clamped(zone, width: width)
    }

    /// The joystick stays centered in its own hit band. In Overview the connecting leader
    /// makes its relationship to the true (possibly sub-pixel) endpoint explicit.
    func handleGripX(isStart: Bool, width: CGFloat) -> CGFloat? {
        guard let zone = handleZone(isStart: isStart, width: width) else { return nil }
        return (zone.lowerBound + zone.upperBound) / 2
    }

    func bodyZone(width: CGFloat) -> ClosedRange<CGFloat>? {
        guard isVisible else { return nil }
        if let cluster = cluster(in: width) {
            let unit = cluster.unit
            return cluster.origin + unit ... cluster.origin + 2 * unit
        }
        return clamped(left + Self.controlBand / 2 ... right - Self.controlBand / 2, width: width)
    }

    private func grabbableEdge(_ isStart: Bool, width: CGFloat) -> CGFloat? {
        let edge = isStart ? left : right
        return (0...width).contains(edge) ? edge : nil
    }

    /// A sub-44 pt selection still needs a start, a body and an end, so the three bands are laid
    /// out as one cluster centred on it and slid along the strip when the selection sits at its
    /// head or tail. Dropping the band that had no room outside would leave an endpoint that is
    /// drawn but untrimmable.
    private func cluster(in width: CGFloat) -> (origin: CGFloat, unit: CGFloat)? {
        guard isNarrow else { return nil }
        let unit = min(Self.controlBand, width / 3)
        guard unit * 3 <= width else { return nil }
        return (min(max(0, midpoint - 1.5 * unit), max(0, width - unit * 3)), unit)
    }

    private func clamped(_ zone: ClosedRange<CGFloat>, width: CGFloat) -> ClosedRange<CGFloat>? {
        let lower = max(0, min(zone.lowerBound, width))
        let upper = min(width, max(zone.upperBound, 0))
        return upper - lower >= Self.minimumZone ? lower...upper : nil
    }
}

/// A screen-sized request, never an array proportional to source duration or zoom.
struct TimelineThumbnailPlan: Equatable {
    let frameRate: Double
    let interval: Double
    let visibleDuration: Double
    let times: [Double]

    init(state: TimelineState, frameRate: Double = 30) {
        let rate = frameRate.isFinite ? min(240, max(1, frameRate)) : 30
        self.frameRate = rate
        // Twelve cells always fill the viewport, so the request never grows with the source
        // length or the zoom. The frame grid is the densest cell worth decoding.
        let interval = max(state.visibleDuration / 12, 1 / rate)
        self.interval = interval
        self.visibleDuration = state.visibleDuration
        let first = max(0, floor(state.visibleStart / interval) * interval)
        let last = min(state.videoDuration, state.visibleEnd + interval)
        var collected: [Double] = []
        for index in 0..<15 {
            let time = Self.snap(first + Double(index) * interval, rate: rate)
            if time >= last { break }
            if collected.last != time { collected.append(time) }
        }
        times = collected
    }

    /// Cells sit on real frames, which is also what makes one cache entry serve every zoom
    /// level that asks for the same frame.
    static func snap(_ time: Double, rate: Double) -> Double { (time * rate).rounded() / rate }
    func key(for time: Double) -> Int { Int((time * frameRate).rounded()) }

    /// A cell narrower than one viewport slice is wasted work; one wider than the strip
    /// would push the row off screen, so the row always stays inside the visible frame.
    func cellWidth(in width: CGFloat) -> CGFloat {
        min(width, max(1, CGFloat(interval / max(0.000_001, visibleDuration)) * width))
    }
}
