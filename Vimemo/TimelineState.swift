import CoreGraphics

/// Presentation only: changing the viewport never changes a Clip.
struct TimelineState: Equatable {
    let videoDuration: Double
    let maximumZoomScale: CGFloat
    private(set) var zoomScale: CGFloat = 1
    private(set) var viewportCenterTime: Double
    static let minZoomScale: CGFloat = 1

    init(duration: Double, frameRate: Double = 30) {
        videoDuration = duration.isFinite ? max(0.1, duration) : 0.1
        // A ceiling derived from the source: deep enough that a short selection can be shown
        // at its true width. The window never resolves finer than a second; the frame grid only
        // lowers it for high frame-rate sources. Sparsely sampled or variable-frame files report
        // an unreliable nominal rate, so it must never collapse the ceiling.
        let minimumVisible = min(1.0, max(0.5, 30 / max(1, frameRate)))
        maximumZoomScale = max(200, videoDuration / minimumVisible)
        viewportCenterTime = videoDuration / 2
    }

    var visibleDuration: Double { videoDuration / Double(zoomScale) }
    var visibleStart: Double { viewportCenterTime - visibleDuration / 2 }
    var visibleEnd: Double { visibleStart + visibleDuration }
    func x(for time: Double, width: CGFloat) -> CGFloat { CGFloat((time - visibleStart) / visibleDuration) * width }
    func time(at x: CGFloat, width: CGFloat) -> Double { visibleStart + Double(x / max(1, width)) * visibleDuration }
    func secondsPerPoint(width: CGFloat) -> Double { visibleDuration / Double(max(1, width)) }

    mutating func center(on time: Double) {
        let half = visibleDuration / 2
        viewportCenterTime = min(videoDuration - half, max(half, time))
    }

    /// Keep the time under the pinch centroid at the same fractional screen position.
    mutating func zoom(to scale: CGFloat, anchorTime: Double, anchorFraction: CGFloat) {
        guard scale.isFinite, anchorTime.isFinite, anchorFraction.isFinite else { return }
        zoomScale = min(maximumZoomScale, max(Self.minZoomScale, scale))
        let fraction = min(1, max(0, anchorFraction))
        center(on: anchorTime + (0.5 - Double(fraction)) * visibleDuration)
    }

    mutating func reset() { zoomScale = 1; viewportCenterTime = videoDuration / 2 }

    /// Trim targets must be drawn at their real width, so make the viewport fit the
    /// selection with half the strip on each side instead of widening a fake box.
    mutating func fit(clip: Clip, width: CGFloat, minimumWidth: CGFloat = 120) {
        let seconds = max(0.1, clip.duration)
        let room = min(2.0, Double(max(1, width)) / Double(max(1, minimumWidth)))
        zoomScale = min(maximumZoomScale, max(Self.minZoomScale, videoDuration / (seconds * max(1, room))))
        center(on: (clip.start + clip.end) / 2)
    }

    func realWidth(of clip: Clip, width: CGFloat) -> CGFloat {
        x(for: clip.end, width: width) - x(for: clip.start, width: width)
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

struct TimelineSelectionGeometry {
    let left: CGFloat
    let right: CGFloat
    let isVisible: Bool
    /// True only when the source is too long for any viewport to show the selection at
    /// its real width; drag deltas are then measured against the drawn box.
    let isDisplayClamped: Bool
    var width: CGFloat { right - left }

    init(state: TimelineState, clip: Clip, width: CGFloat, minimumWidth: CGFloat = 120) {
        let rawLeft = state.x(for: clip.start, width: width)
        let rawRight = state.x(for: clip.end, width: width)
        isVisible = clip.end >= state.visibleStart && clip.start <= state.visibleEnd
        if rawRight - rawLeft >= min(minimumWidth, width) {
            left = rawLeft; right = rawRight; isDisplayClamped = false
        } else {
            let displayWidth = min(width, minimumWidth)
            let midpoint = (rawLeft + rawRight) / 2
            left = min(max(0, midpoint - displayWidth / 2), max(0, width - displayWidth))
            right = left + displayWidth
            isDisplayClamped = true
        }
    }

    func coverX(for clip: Clip) -> CGFloat {
        left + CGFloat(min(1, max(0, (clip.cover - clip.start) / max(0.1, clip.duration)))) * width
    }
}

/// A screen-sized request, never an array proportional to source duration or zoom.
struct TimelineThumbnailPlan: Equatable {
    let interval: Double
    let visibleDuration: Double
    let times: [Double]
    init(state: TimelineState) {
        // Twelve cells always fill the viewport, so the request never grows with the source
        // length or the zoom. The frame-rate floor avoids pointless seeks when the viewport
        // is narrower than twelve frames.
        let densest = min(1.0 / 30, state.videoDuration / 12)
        let interval = max(state.visibleDuration / 12, densest)
        self.interval = interval
        self.visibleDuration = state.visibleDuration
        let first = max(0, floor(state.visibleStart / interval) * interval)
        let last = min(state.videoDuration, state.visibleEnd + interval)
        times = (0..<15).map { first + Double($0) * interval }.filter { $0 < last }
    }

    /// A cell narrower than one viewport slice is wasted work; one wider than the strip
    /// would push the row off screen, so the row always stays inside the visible frame.
    func cellWidth(in width: CGFloat) -> CGFloat {
        min(width, max(1, CGFloat(interval / max(0.000_001, visibleDuration)) * width))
    }
}
