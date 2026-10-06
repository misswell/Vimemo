import SwiftUI
import UIKit
import ImageIO

struct AnimatedGIF: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> GIFPlaybackView { GIFPlaybackView() }
    func updateUIView(_ uiView: GIFPlaybackView, context: Context) { uiView.load(url) }
    static func dismantleUIView(_ uiView: GIFPlaybackView, coordinator: ()) { uiView.stop() }
}

// Decode only the displayed frame, rather than retaining every full-size frame
// of an unlimited-duration GIF. Honor each frame's encoded delay.
final class GIFPlaybackView: UIImageView {
    private var loadedURL: URL?
    private var source: CGImageSource?
    private var delays: [Double] = []
    private var index = 0
    private var remaining = 0.0
    private var previousTimestamp: CFTimeInterval?
    private var displayLink: CADisplayLink?

    func load(_ url: URL) {
        guard loadedURL != url else { return }
        stop()
        loadedURL = url
        source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        delays = []
        index = 0
        image = nil
        contentMode = .scaleAspectFit
        guard let source else { return }
        for frame in 0..<CGImageSourceGetCount(source) {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, frame, nil) as? [String: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let delay = gif?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double
                ?? gif?[kCGImagePropertyGIFDelayTime as String] as? Double ?? 1 / 12
            delays.append(max(0.01, delay))
        }
        guard !delays.isEmpty else { return }
        remaining = delays[0]
        showFrame()
        start()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() } else { start() }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        previousTimestamp = nil
    }

    private func start() {
        guard window != nil, delays.count > 1, displayLink == nil else { return }
        let link = CADisplayLink(target: GIFDisplayLinkTarget(self), selector: #selector(GIFDisplayLinkTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    fileprivate func advance(_ link: CADisplayLink) {
        defer { previousTimestamp = link.timestamp }
        guard let previousTimestamp, !delays.isEmpty else { return }
        // Pause across background suspension instead of decoding missed loops.
        remaining -= min(link.timestamp - previousTimestamp, 0.25)
        let previousIndex = index
        while remaining <= 0 {
            index = (index + 1) % delays.count
            remaining += delays[index]
        }
        if previousIndex != index { showFrame() }
    }

    private func showFrame() {
        guard let source, let frame = CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCache: false] as CFDictionary) else { return }
        image = UIImage(cgImage: frame)
    }
}

private final class GIFDisplayLinkTarget: NSObject {
    weak var view: GIFPlaybackView?
    init(_ view: GIFPlaybackView) { self.view = view }
    @objc func tick(_ link: CADisplayLink) { view?.advance(link) }
}
