import SwiftUI

/// Arrow taps and the center scrub pad share the same frame-aligned selection.
struct FrameSelectionControl: View {
    @Binding var time: Double
    let range: ClosedRange<Double>
    let frameRate: Double
    var photoCover = false
    var identifierPrefix = "cover"
    var onScrub: (Double, Bool) -> Void = { _, _ in }
    @State private var drag: FrameScrubSession?

    var body: some View {
        HStack(spacing: 8) {
            stepButton("上一帧", symbol: "backward.end.fill", delta: -1, id: "\(identifierPrefix)PreviousFrame")
            Text(photoCover ? "照片封面" : "第 \(Int((time * max(1, frameRate)).rounded())) 帧")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(drag == nil ? StudioTheme.secondary : StudioTheme.accent)
                .frame(minWidth: 76, minHeight: 44).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                    if drag == nil { drag = FrameScrubSession(time: time, range: range, frameRate: frameRate) }
                    guard var session = drag else { return }
                    let selected = session.move(translation: value.translation, secondsPerPoint: 1 / max(1, frameRate) / 12)
                    time = selected
                    drag = session
                    onScrub(selected, true)
                }.onEnded { _ in drag = nil; onScrub(time, false) })
                .accessibilityLabel("封面逐帧微调").accessibilityValue(photoCover ? "照片封面" : "第 \(Int((time * max(1, frameRate)).rounded())) 帧")
                .accessibilityHint("左右拖动逐帧挑选，或使用两侧按钮")
                .accessibilityAdjustableAction { direction in
                    switch direction { case .increment: step(1); case .decrement: step(-1); @unknown default: break }
                }
                .accessibilityIdentifier("\(identifierPrefix)FineScrubber")
            stepButton("下一帧", symbol: "forward.end.fill", delta: 1, id: "\(identifierPrefix)NextFrame")
        }
    }

    private func step(_ delta: Double) {
        let selected = min(range.upperBound, max(range.lowerBound, time + delta / max(1, frameRate)))
        time = selected
        onScrub(selected, false)
    }

    private func stepButton(_ title: String, symbol: String, delta: Double, id: String) -> some View {
        Button { step(delta) } label: {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Capsule())
        }.studioGlassButton(tint: StudioTheme.accent.opacity(0.08))
            .accessibilityIdentifier(id)
    }
}
