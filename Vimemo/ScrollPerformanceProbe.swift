#if DEBUG
import SwiftUI

/// Enabled only by the isolated UI-test scroll fixture. No SwiftUI state changes per frame.
struct ScrollPerformanceProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) {}
    static func dismantleUIView(_ uiView: Probe, coordinator: ()) { uiView.link?.invalidate() }

    final class Probe: UIView {
        var link: CADisplayLink?
        private weak var scroll: UIScrollView?
        private var previous: (time: Double, offset: CGFloat, dragging: Bool)?
        private var movingFrames = 0
        private var largestGap = 0.0

        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = true
            accessibilityIdentifier = "scrollPerformanceReport"
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var accessibilityValue: String? {
            get { "\(movingFrames),\(largestGap * 1000)" }
            set {}
        }
        override func didMoveToWindow() {
            link?.invalidate()
            guard window != nil else { return }
            link = CADisplayLink(target: self, selector: #selector(sample))
            link?.add(to: .main, forMode: .common)
        }
        private func find(_ view: UIView) -> UIScrollView? {
            guard !view.isHidden else { return nil }
            if let s = view as? UIScrollView, s.contentSize.height > s.bounds.height + 100 { return s }
            return view.subviews.lazy.compactMap { self.find($0) }.first
        }
        @objc private func sample(_ link: CADisplayLink) {
            if scroll?.window == nil, let window { scroll = find(window); previous = nil }
            guard let s = scroll else { return }
            if let previous, previous.dragging, s.isDragging, abs(s.contentOffset.y - previous.offset) > 0.5 {
                movingFrames += 1
                largestGap = max(largestGap, link.timestamp - previous.time)
            }
            previous = (link.timestamp, s.contentOffset.y, s.isDragging)
        }
    }
}
#endif
