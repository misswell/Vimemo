import SwiftUI

/// A single UIKit arbitration layer keeps two-finger zoom ahead of one-finger edits.
/// Drawing and accessibility remain in SwiftUI; all coordinates use this fixed view.
struct TimelinePinchGesture: UIViewRepresentable {
    var hitTest: (CGPoint) -> TimelineViewModel.Target
    var onBegin: (TimelineViewModel.Target) -> Void
    var onMove: (CGSize) -> Void
    var onEnd: () -> Void
    var onPinchBegin: (CGFloat) -> Void
    var onPinch: (CGFloat, CGFloat) -> Void
    var onPinchEnd: () -> Void
    var onReset: () -> Void
    var onFine: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        let coordinator = context.coordinator
        let pan = TimelinePanRecognizer(target: coordinator, action: #selector(Coordinator.pan(_:)))
        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinch(_:)))
        let doubleTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.reset(_:)))
        doubleTap.numberOfTapsRequired = 2
        let hold = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.45
        hold.allowableMovement = 12
        for gesture in [pan, pinch, doubleTap, hold] {
            gesture.delegate = coordinator
            view.addGestureRecognizer(gesture)
        }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.owner = self }
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.owner.onEnd()
        coordinator.owner.onPinchEnd()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var owner: TimelinePinchGesture
        private var panning = false
        private var pinching = false
        private var fine = false
        private let feedback = UIImpactFeedbackGenerator(style: .light)
        init(_ owner: TimelinePinchGesture) { self.owner = owner }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            if let pan = recognizer as? TimelinePanRecognizer {
                guard !pinching else { return false }
                let velocity = pan.velocity
                let target = owner.hitTest(pan.origin)
                return target == .cover || abs(velocity.x) >= abs(velocity.y)
            }
            return true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // Only our long press and pan cooperate; a parent ScrollView handles vertical movement.
            guard gestureRecognizer.view === other.view else { return false }
            if (gestureRecognizer is UIPinchGestureRecognizer && other is TimelinePanRecognizer)
                || (gestureRecognizer is TimelinePanRecognizer && other is UIPinchGestureRecognizer) { return true }
            return (gestureRecognizer is UILongPressGestureRecognizer && other is TimelinePanRecognizer)
                || (gestureRecognizer is TimelinePanRecognizer && other is UILongPressGestureRecognizer)
        }

        @objc func pan(_ recognizer: TimelinePanRecognizer) {
            switch recognizer.state {
            case .began:
                guard !pinching else { return }
                panning = true
                let translation = recognizer.translation
                owner.onBegin(owner.hitTest(recognizer.origin))
                owner.onFine(fine)
                feedback.impactOccurred(); feedback.prepare()
                owner.onMove(CGSize(width: translation.x, height: translation.y))
            case .changed:
                guard panning, !pinching else { return }
                let translation = recognizer.translation
                owner.onMove(CGSize(width: translation.x, height: translation.y))
            case .ended, .cancelled, .failed:
                if panning {
                    if recognizer.state == .ended, !pinching {
                        owner.onMove(CGSize(width: recognizer.translation.x, height: recognizer.translation.y))
                    }
                    owner.onEnd(); feedback.impactOccurred(intensity: 0.5)
                }
                panning = false; fine = false
            default: break
            }
        }
        @objc func pinch(_ recognizer: UIPinchGestureRecognizer) {
            let x = recognizer.location(in: recognizer.view).x
            switch recognizer.state {
            case .began:
                if panning { owner.onEnd(); panning = false }
                fine = false; owner.onFine(false); pinching = true
                owner.onPinchBegin(x)
            case .changed: owner.onPinch(recognizer.scale, x)
            case .ended, .cancelled, .failed: owner.onPinchEnd(); pinching = false
            default: break
            }
        }
        @objc func reset(_ recognizer: UITapGestureRecognizer) {
            if recognizer.state == .ended { owner.onReset() }
        }
        @objc func hold(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                guard !pinching else { return }
                fine = true; owner.onFine(true); feedback.impactOccurred(intensity: 0.5)
            case .ended, .cancelled, .failed:
                fine = false; owner.onFine(false)
            default: break
            }
        }
    }
}

/// Preserve the initial pixels of a precision drag. UIPanGestureRecognizer's
/// recognition threshold is too large for small, frame-level timeline edits.
final class TimelinePanRecognizer: UIGestureRecognizer {
    private(set) var origin = CGPoint.zero
    private(set) var translation = CGPoint.zero
    private(set) var velocity = CGPoint.zero
    private var trackedTouch: UITouch?
    private var previousPoint = CGPoint.zero
    private var previousTimestamp: TimeInterval = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, touches.count == 1, let touch = touches.first else {
            state = state == .possible ? .failed : .cancelled
            return
        }
        trackedTouch = touch
        origin = touch.location(in: view); previousPoint = origin; previousTimestamp = touch.timestamp
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        update(touch)
        if state == .possible {
            if hypot(translation.x, translation.y) >= 2 { state = .began }
        } else if state == .began || state == .changed { state = .changed }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        update(touch)
        // Deliver the final location, including motion since the last move event.
        if state == .began || state == .changed { state = .changed; state = .ended }
        else { state = .failed }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = state == .possible ? .failed : .cancelled
    }
    override func reset() {
        super.reset()
        trackedTouch = nil; translation = .zero; velocity = .zero
    }
    private func update(_ touch: UITouch) {
        let point = touch.location(in: view)
        let elapsed = max(0.001, touch.timestamp - previousTimestamp)
        velocity = CGPoint(x: (point.x - previousPoint.x) / elapsed, y: (point.y - previousPoint.y) / elapsed)
        translation = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        previousPoint = point; previousTimestamp = touch.timestamp
    }
}
