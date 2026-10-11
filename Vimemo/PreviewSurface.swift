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
    var onFailure: (String) -> Void = { _ in }

    final class Surface: UIView, MTKViewDelegate {
        private let metalView: MTKView
        private let queue: MTLCommandQueue?
        private let context: CIContext?
        private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        private var displayLink: CADisplayLink?
        private var item: AVPlayerItem?
        private var output: AVPlayerItemVideoOutput?
        private var ready = false
        private var firstFramePending = false
        private var pendingFrame: CIImage?
        private var waitingSince: Date?
        private var reportedFailure = false
        var isPlaying = false
        var player: AVPlayer?
        var preview: VideoPreview?
        var onReady: ((Bool) -> Void)?
        var onFailure: ((String) -> Void)?

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
                firstFramePending = false
                waitingSince = nil; reportedFailure = false
                onReady?(false)
            }
            guard !reportedFailure else { return }
            if item?.status == .failed { fail("preview.item-failed", error: item?.error); return }
            if isPlaying && !ready {
                if waitingSince == nil { waitingSince = Date(); DiagnosticLog.shared.record("preview.waiting-first-frame") }
                if let waitingSince, Date().timeIntervalSince(waitingSince) > 10 {
                    fail("preview.first-frame-timeout", error: item?.error); return
                }
            }
            guard let preview, let output else { return }
            let time = player.rate == 0 ? player.currentTime() : output.itemTime(forHostTime: CACurrentMediaTime())
            guard output.hasNewPixelBuffer(forItemTime: time),
                  let pixels = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
            pendingFrame = preview.render(CIImage(cvPixelBuffer: pixels))
            metalView.draw()
        }

        private func fail(_ event: String, error: Error?) {
            guard !reportedFailure else { return }
            reportedFailure = true
            DiagnosticLog.shared.record(event, "status=\(item?.status.rawValue ?? -1) time=\(player?.currentTime().seconds ?? -1)", error: error)
            displayLink?.isPaused = true
            onFailure?("视频预览未能读取画面，请重试；若仍失败，请在设置中导出诊断日志。")
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        func draw(in view: MTKView) {
            guard context != nil, queue != nil else { fail("preview.metal-unavailable", error: nil); return }
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
            if !ready && !firstFramePending {
                firstFramePending = true
                let renderedItem = item
                commands.addCompletedHandler { [weak self] completed in
                    Task { @MainActor in
                        guard let self, self.item === renderedItem, !self.reportedFailure else { return }
                        self.firstFramePending = false
                        guard completed.status == .completed else { self.fail("preview.render-failed", error: completed.error); return }
                        self.ready = true
                        DiagnosticLog.shared.record("preview.first-frame")
                        self.onReady?(true)
                        self.updateActivity()
                    }
                }
            }
            commands.commit()
        }

        func updateActivity() {
            if !isPlaying { waitingSince = nil }
            displayLink?.isPaused = preview == nil || !isPlaying
        }
        func stop() {
            displayLink?.invalidate(); displayLink = nil
            if let output { item?.remove(output) }
            output = nil; item = nil; player = nil; onReady = nil; onFailure = nil; pendingFrame = nil
            metalView.delegate = nil
        }
    }
    func makeUIView(context: Context) -> Surface { let view = Surface(frame: .zero); updateUIView(view, context: context); return view }
    func updateUIView(_ view: Surface, context: Context) { view.player = player; view.preview = preview; view.isPlaying = playing; view.onReady = onReady; view.onFailure = onFailure; view.updateActivity() }
    static func dismantleUIView(_ view: Surface, coordinator: ()) { view.stop() }
}
