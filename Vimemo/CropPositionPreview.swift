import SwiftUI

/// Maps movement of the image to the normalized position shared by all outputs.
struct CropPositionGeometry {
    let imageSize: CGSize
    let viewport: CGSize
    var scale: CGFloat { max(viewport.width / max(1, imageSize.width), viewport.height / max(1, imageSize.height)) }
    var renderedSize: CGSize { CGSize(width: imageSize.width * scale, height: imageSize.height * scale) }
    var overflow: CGSize { CGSize(width: max(0, renderedSize.width - viewport.width), height: max(0, renderedSize.height - viewport.height)) }
    func position(from origin: CGPoint, translation: CGSize) -> CGPoint {
        CGPoint(x: overflow.width > 0.5 ? min(1, max(0, origin.x - translation.width / overflow.width)) : origin.x,
                y: overflow.height > 0.5 ? min(1, max(0, origin.y - translation.height / overflow.height)) : origin.y)
    }
}

struct CropPositionPreview: View {
    let image: UIImage
    @Binding var x: Double
    @Binding var y: Double
    var onEditing: (Bool) -> Void
    @State private var origin: CGPoint?
    @GestureState private var dragging = false

    var body: some View {
        GeometryReader { proxy in
            let layout = CropPositionGeometry(imageSize: image.size, viewport: proxy.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable()
                    .frame(width: layout.renderedSize.width, height: layout.renderedSize.height)
                    .offset(x: -layout.overflow.width * x, y: -layout.overflow.height * y)
                if dragging {
                    Path { path in
                        for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
                            path.move(to: CGPoint(x: proxy.size.width * fraction, y: 0))
                            path.addLine(to: CGPoint(x: proxy.size.width * fraction, y: proxy.size.height))
                            path.move(to: CGPoint(x: 0, y: proxy.size.height * fraction))
                            path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height * fraction))
                        }
                    }.stroke(.white.opacity(0.7), lineWidth: 1).allowsHitTesting(false)
                }
            }.frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading).clipped().contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 6)
                    .updating($dragging) { _, active, _ in active = true }
                    .onChanged { value in
                        if origin == nil { origin = CGPoint(x: x, y: y); onEditing(true) }
                        guard let origin else { return }
                        let position = layout.position(from: origin, translation: value.translation)
                        x = position.x; y = position.y
                    }.onEnded { _ in finish() })
                .onChange(of: dragging) { _, active in if !active { finish() } }
                .onDisappear { finish() }
        }
    }
    private func finish() {
        guard origin != nil else { return }
        origin = nil
        onEditing(false)
    }
}
