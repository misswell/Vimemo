import CoreGraphics

/// Presentation only: changing the viewport never changes a Clip.
struct TimelineState: Equatable {
    let videoDuration: Double
    private(set) var zoomScale: CGFloat = 1
    private(set) var viewportCenterTime: Double
    static let minZoomScale: CGFloat = 1
    static let maxZoomScale: CGFloat = 200

    init(duration: Double) {
        videoDuration = duration.isFinite ? max(0.1, duration) : 0.1
        viewportCenterTime = videoDuration / 2
    }

    var visibleDuration: Double { videoDuration / Double(zoomScale) }
    var visibleStart: Double { viewportCenterTime - visibleDuration / 2 }
    var visibleEnd: Double { visibleStart + visibleDuration }
    func contentOffset(width: CGFloat) -> CGFloat { -CGFloat(visibleStart / visibleDuration) * width }
    func x(for time: Double, width: CGFloat) -> CGFloat { CGFloat((time - visibleStart) / visibleDuration) * width }
    func time(at x: CGFloat, width: CGFloat) -> Double { visibleStart + Double(x / max(1, width)) * visibleDuration }

    mutating func center(on time: Double) {
        let half = visibleDuration / 2
        viewportCenterTime = min(videoDuration - half, max(half, time))
    }

    /// Keep the time under the pinch centroid at the same fractional screen position.
    mutating func zoom(to scale: CGFloat, anchorTime: Double, anchorFraction: CGFloat) {
        guard scale.isFinite, anchorTime.isFinite, anchorFraction.isFinite else { return }
        zoomScale = min(Self.maxZoomScale, max(Self.minZoomScale, scale))
        let fraction = min(1, max(0, anchorFraction))
        center(on: anchorTime + (0.5 - Double(fraction)) * visibleDuration)
    }

    mutating func reset() { zoomScale = 1; viewportCenterTime = videoDuration / 2 }

    mutating func focus(on clip: Clip, width: CGFloat) {
        // Room on both sides; minimum display geometry handles the 200x limit.
        let target = CGFloat(videoDuration / max(0.1, clip.duration * 3))
        zoom(to: target, anchorTime: (clip.start + clip.end) / 2, anchorFraction: 0.5)
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
    var width: CGFloat { right - left }

    init(state: TimelineState, clip: Clip, width: CGFloat, minimumWidth: CGFloat = 120) {
        let rawLeft = state.x(for: clip.start, width: width)
        let rawRight = state.x(for: clip.end, width: width)
        isVisible = clip.end >= state.visibleStart && clip.start <= state.visibleEnd
        if rawRight - rawLeft >= min(minimumWidth, width) {
            left = rawLeft; right = rawRight
        } else {
            let displayWidth = min(width, minimumWidth)
            let midpoint = (rawLeft + rawRight) / 2
            left = min(max(0, midpoint - displayWidth / 2), max(0, width - displayWidth))
            right = left + displayWidth
        }
    }

    func coverX(for clip: Clip) -> CGFloat {
        left + CGFloat(min(1, max(0, (clip.cover - clip.start) / max(0.1, clip.duration)))) * width
    }
}

/// A screen-sized request, never an array proportional to source duration or zoom.
struct TimelineThumbnailPlan: Equatable {
    let interval: Double
    let times: [Double]
    init(state: TimelineState) {
        let minimum = state.zoomScale < 5 ? 60.0 : (state.zoomScale <= 30 ? 10.0 : 1.0)
        // Short videos still need several thumbnails in overview.
        let tier = min(minimum, state.videoDuration / 12)
        let interval = max(1.0 / 30, max(tier, ceil(state.visibleDuration / 12)))
        self.interval = interval
        let first = max(0, floor(state.visibleStart / interval) * interval)
        let last = min(state.videoDuration, state.visibleEnd + interval)
        times = (0..<15).map { first + Double($0) * interval }.filter { $0 < last }
    }
}
