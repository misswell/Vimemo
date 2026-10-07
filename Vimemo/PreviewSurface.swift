import SwiftUI
import AVFoundation
import MetalKit
import CoreImage

/// Pulls native, geometrically composed frames and applies the shared color pipeline.
/// This avoids iOS 27's failing custom AVVideoCompositing playback path.
struct PreviewSurface: UIViewRepresentable {
    let player: AVPlayer
    let preview: VideoPreview?
    let playing: Bool
    var onReady: (Bool) -> Void

    final class Surface: UIView, MTKViewDelegate {
        private let metalView: MTKView
        private let queue: MTLCommandQueue?
        private let context: CIContext?
        private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        private var displayLink: CADisplayLink?
        private var item: AVPlayerItem?
        private var output: AVPlayerItemVideoOutput?
        private var ready = false
        private var pendingFrame: CIImage?
        var isPlaying = false
        var player: AVPlayer?
        var preview: VideoPreview?
        var onReady: ((Bool) -> Void)?

        override init(frame: CGRect) {
            let device = MTLCreateSystemDefaultDevice()
            metalView = MTKView(frame: frame, device: device)
            queue = device?.makeCommandQueue()
            context = device.map { CIContext(mtlDevice: $0, options: [.cacheIntermediates: false]) }
            super.init(frame: frame)
            backgroundColor = .black
            metalView.delegate = self
            metalView.framebufferOnly = false
            metalView.isPaused = true
            metalView.enableSetNeedsDisplay = false
            metalView.colorPixelFormat = .bgra8Unorm
            metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(metalView)
            let link = CADisplayLink(target: self, selector: #selector(displayFrame))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 60, preferred: 30)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() { super.layoutSubviews(); metalView.frame = bounds }

        @objc private func displayFrame() {
            guard let player else { return }
            if item !== player.currentItem {
                if let output { item?.remove(output) }
                item = player.currentItem
                let next = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferMetalCompatibilityKey as String: true
                ])
                item?.add(next)
                output = next
                ready = false
                onReady?(false)
            }
            guard let preview, let output else { return }
            let time = player.rate == 0 ? player.currentTime() : output.itemTime(forHostTime: CACurrentMediaTime())
            guard output.hasNewPixelBuffer(forItemTime: time),
                  let pixels = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
            pendingFrame = preview.render(CIImage(cvPixelBuffer: pixels))
            metalView.draw()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        func draw(in view: MTKView) {
            guard let frame = pendingFrame, let context, let queue,
                  let drawable = view.currentDrawable, let commands = queue.makeCommandBuffer() else { return }
            let size = metalView.drawableSize
            guard size.width > 0, size.height > 0 else { return }
            let scale = min(size.width / frame.extent.width, size.height / frame.extent.height)
            let fitted = frame.transformed(by: CGAffineTransform(translationX: -frame.extent.minX, y: -frame.extent.minY))
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: (size.width - frame.extent.width * scale) / 2,
                                                  y: (size.height - frame.extent.height * scale) / 2))
            let bounds = CGRect(origin: .zero, size: size)
            let image = fitted.composited(over: CIImage(color: .black).cropped(to: bounds))
            context.render(image, to: drawable.texture, commandBuffer: commands, bounds: bounds, colorSpace: colorSpace)
            commands.present(drawable)
            if !ready {
                ready = true
                let renderedItem = item
                commands.addCompletedHandler { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.item === renderedItem else { return }
                        self.onReady?(true)
                        self.updateActivity()
                    }
                }
            }
            commands.commit()
        }

        func updateActivity() {
            displayLink?.isPaused = preview == nil || (!isPlaying && ready && item === player?.currentItem)
        }
        func stop() {
            displayLink?.invalidate(); displayLink = nil
            if let output { item?.remove(output) }
            output = nil; item = nil; player = nil; onReady = nil; pendingFrame = nil
            metalView.delegate = nil
        }
    }
    func makeUIView(context: Context) -> Surface { let view = Surface(frame: .zero); updateUIView(view, context: context); return view }
    func updateUIView(_ view: Surface, context: Context) { view.player = player; view.preview = preview; view.isPlaying = playing; view.onReady = onReady; view.updateActivity() }
    static func dismantleUIView(_ view: Surface, coordinator: ()) { view.stop() }
}
