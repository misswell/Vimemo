import SwiftUI
import UIKit

/// Maps the full edited image into the crop window shared by every output.
struct CropPositionGeometry {
    let imageSize: CGSize
    let viewport: CGSize
    var zoom: Double = 1
    var scale: CGFloat { max(viewport.width / max(1, imageSize.width), viewport.height / max(1, imageSize.height)) * EditSettings.clampedCropZoom(zoom) }
    var renderedSize: CGSize { CGSize(width: imageSize.width * scale, height: imageSize.height * scale) }
    var overflow: CGSize { CGSize(width: max(0, renderedSize.width - viewport.width), height: max(0, renderedSize.height - viewport.height)) }
    func position(from origin: CGPoint, translation: CGSize) -> CGPoint {
        CGPoint(x: overflow.width > 0.5 ? min(1, max(0, origin.x - translation.width / overflow.width)) : origin.x,
                y: overflow.height > 0.5 ? min(1, max(0, origin.y - translation.height / overflow.height)) : origin.y)
    }
    func imagePoint(at anchor: CGPoint, position: CGPoint) -> CGPoint {
        CGPoint(x: (overflow.width * position.x + anchor.x) / renderedSize.width,
                y: (overflow.height * position.y + anchor.y) / renderedSize.height)
    }
    func position(keeping imagePoint: CGPoint, at anchor: CGPoint) -> CGPoint {
        CGPoint(x: overflow.width > 0.5 ? min(1, max(0, (imagePoint.x * renderedSize.width - anchor.x) / overflow.width)) : 0.5,
                y: overflow.height > 0.5 ? min(1, max(0, (imagePoint.y * renderedSize.height - anchor.y) / overflow.height)) : 0.5)
    }
}

struct CropPositionPreview: View {
    let image: UIImage
    let x: Double
    let y: Double
    let zoom: Double
    let editing: Bool
    var body: some View {
        GeometryReader { proxy in
            let layout = CropPositionGeometry(imageSize: image.size, viewport: proxy.size, zoom: zoom)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable()
                    .frame(width: layout.renderedSize.width, height: layout.renderedSize.height)
                    .offset(x: -layout.overflow.width * x, y: -layout.overflow.height * y)
                if editing {
                    Path { path in
                        for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
                            path.move(to: CGPoint(x: proxy.size.width * fraction, y: 0))
                            path.addLine(to: CGPoint(x: proxy.size.width * fraction, y: proxy.size.height))
                            path.move(to: CGPoint(x: 0, y: proxy.size.height * fraction))
                            path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height * fraction))
                        }
                    }.stroke(.white.opacity(0.7), lineWidth: 1)
                }
            }.frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading).clipped()
        }.allowsHitTesting(false)
    }
}

/// Persistent gestures retain release events while playback replaces the cover.
struct CropGestureSurface: UIViewRepresentable {
    let imageSize: CGSize
    @Binding var x: Double
    @Binding var y: Double
    @Binding var zoom: Double?
    let canPan: Bool
    let ready: Bool
    var onEditing: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView(); view.backgroundColor = .clear
        context.coordinator.install(on: view)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.pan.isEnabled = canPan && ready
        context.coordinator.pinch.isEnabled = ready
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.finish() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CropGestureSurface
        let pan = UIPanGestureRecognizer()
        let pinch = UIPinchGestureRecognizer()
        private let reset = UITapGestureRecognizer()
        private var origin: CGPoint?
        private var pinchPoint: CGPoint?
        private var initialZoom = 1.0
        private var editing = false
        init(_ parent: CropGestureSurface) { self.parent = parent }
        func install(on view: UIView) {
            pan.maximumNumberOfTouches = 1
            reset.numberOfTapsRequired = 2
            for gesture in [pan, pinch, reset] {
                gesture.delegate = self; view.addGestureRecognizer(gesture)
            }
            pan.addTarget(self, action: #selector(drag(_:)))
            pinch.addTarget(self, action: #selector(magnify(_:)))
            reset.addTarget(self, action: #selector(recenter))
        }
        private func layout(in view: UIView, zoom: Double? = nil) -> CropPositionGeometry {
            CropPositionGeometry(imageSize: parent.imageSize, viewport: view.bounds.size,
                                 zoom: zoom ?? EditSettings.clampedCropZoom(parent.zoom ?? 1))
        }
        private func begin() {
            guard !editing else { return }
            editing = true; parent.onEditing(true)
        }
        func finish() {
            origin = nil; pinchPoint = nil
            guard editing else { return }
            editing = false; parent.onEditing(false)
        }
        @objc private func drag(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            switch gesture.state {
            case .began: origin = CGPoint(x: parent.x, y: parent.y); begin()
            case .changed:
                guard let origin else { return }
                let translation = gesture.translation(in: view)
                let point = layout(in: view).position(from: origin, translation: CGSize(width: translation.x, height: translation.y))
                parent.x = point.x; parent.y = point.y
            case .ended, .cancelled, .failed: finish()
            default: break
            }
        }
        @objc private func magnify(_ gesture: UIPinchGestureRecognizer) {
            guard let view = gesture.view else { return }
            switch gesture.state {
            case .began:
                initialZoom = EditSettings.clampedCropZoom(parent.zoom ?? 1)
                pinchPoint = layout(in: view).imagePoint(at: gesture.location(in: view), position: CGPoint(x: parent.x, y: parent.y))
                begin()
            case .changed:
                guard let pinchPoint else { return }
                let value = EditSettings.clampedCropZoom(initialZoom * gesture.scale)
                let position = layout(in: view, zoom: value).position(keeping: pinchPoint, at: gesture.location(in: view))
                parent.zoom = value; parent.x = position.x; parent.y = position.y
            case .ended, .cancelled, .failed: finish()
            default: break
            }
        }
        @objc private func recenter() {
            begin(); parent.zoom = nil; parent.x = 0.5; parent.y = 0.5; finish()
        }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // The enclosing SwiftUI preview owns hold-to-play; editing pauses it.
            other !== pan && other !== pinch && other !== reset
        }
    }
}
