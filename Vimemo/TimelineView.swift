import SwiftUI

struct TimelineView: View {
    @Binding var clip: Clip
    var duration: Double
    var speed: Double
    var maxOutputDuration: Double? = 3
    var thumbnails: [UIImage]
    var frameRate: Double = 30
    var onSeek: (Double, Bool) -> Void
    @State private var dragStart: Clip?
    @State private var coverDrag: FrameScrubSession?
    @State private var fineScrubbing = false

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let total = max(0.1, duration)
                let left = width * clip.start / total
                let right = width * clip.end / total
                let cover = width * clip.cover / total
                // The marker moves; its gesture must measure against the stationary timeline.
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 1) {
                        ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image).resizable().scaledToFill().frame(width: max(1, width / CGFloat(max(1, thumbnails.count)) - 1), height: 58).clipped()
                        }
                    }.frame(width: width, height: 58).background(StudioTheme.raised).clipShape(RoundedRectangle(cornerRadius: 10))
                    Rectangle().fill(.black.opacity(0.55)).frame(width: left, height: 58).allowsHitTesting(false)
                    Rectangle().fill(.black.opacity(0.55)).frame(width: max(0, width - right), height: 58).offset(x: right).allowsHitTesting(false)
                    RoundedRectangle(cornerRadius: 8).stroke(StudioTheme.accent, lineWidth: 3).frame(width: max(8, right - left), height: 61).offset(x: left).allowsHitTesting(false)
                    Rectangle().fill(.clear).contentShape(Rectangle()).frame(width: max(8, right - left), height: 58).offset(x: left)
                        .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { value in
                            guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                            if dragStart == nil { dragStart = clip }
                            guard let original = dragStart else { return }
                            let delta = value.translation.width / width * total
                            let newStart = min(max(0, original.start + delta), max(0, total - original.duration))
                            let shift = newStart - original.start
                            clip.start = newStart; clip.end = original.end + shift; clip.cover = original.cover + shift
                            onSeek(clip.cover, true)
                        }.onEnded { _ in dragStart = nil; onSeek(clip.cover, false) })
                    coverHandle(width: width, duration: total).offset(x: cover - 22)
                    handle.offset(x: left - 22).simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { value in
                        guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                        if dragStart == nil { dragStart = clip }
                        let start = (dragStart?.start ?? clip.start) + value.translation.width / width * total
                        clip.start = min(max(0, start), clip.end - min(0.1, total))
                        if let maximum = maxOutputDuration { clip.start = max(clip.start, clip.end - maximum * speed) }
                        clip.normalize(sourceDuration: duration, speed: speed, maxOutputDuration: maxOutputDuration)
                        onSeek(clip.start, true)
                    }.onEnded { _ in dragStart = nil; onSeek(clip.cover, false) })
                    handle.offset(x: right - 22).simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { value in
                        guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                        if dragStart == nil { dragStart = clip }
                        let end = (dragStart?.end ?? clip.end) + value.translation.width / width * total
                        clip.end = min(total, max(clip.start + min(0.1, total), end))
                        clip.normalize(sourceDuration: duration, speed: speed, maxOutputDuration: maxOutputDuration)
                        onSeek(max(clip.start, clip.end - 1 / max(1, frameRate)), true)
                    }.onEnded { _ in dragStart = nil; onSeek(clip.cover, false) })
                }.coordinateSpace(name: "coverTimeline")
            }.frame(height: 96)
            HStack {
                Text(clip.start.timeLabel)
                Spacer()
                Text("封面 \(clip.cover.timeLabel)").foregroundStyle(StudioTheme.peach)
                Spacer()
                Text(clip.end.timeLabel)
            }.font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(StudioTheme.secondary)
            Text(fineScrubbing ? "慢速选帧 · 松手锁定封面" : "拖动封面线选帧，向下拉精调 · 两端裁剪")
                .font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
        }.accessibilityElement(children: .contain).accessibilityLabel("片段裁剪时间轴")
    }

    private func coverHandle(width: CGFloat, duration: Double) -> some View {
        VStack(spacing: -2) {
            Capsule().fill(StudioTheme.peach).frame(width: coverDrag == nil ? 2 : 3, height: 70)
            Image(systemName: "arrow.left.and.right").font(.system(size: 10, weight: .bold))
                .foregroundStyle(StudioTheme.onAccent).frame(width: 30, height: 22)
                .background(StudioTheme.peach, in: Capsule())
        }.frame(width: 44, height: 96).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("coverTimeline")).onChanged { value in
                if coverDrag == nil {
                    let end = max(clip.start, clip.end - 1 / max(1, frameRate))
                    coverDrag = FrameScrubSession(time: clip.cover, range: clip.start...end, frameRate: frameRate)
                }
                guard var session = coverDrag else { return }
                fineScrubbing = FrameScrubSession.gain(for: value.translation.height) < 1
                clip.cover = session.move(translation: value.translation, secondsPerPoint: duration / max(1, width))
                clip.coverPhotoFilename = nil
                coverDrag = session
                onSeek(clip.cover, true)
            }.onEnded { _ in coverDrag = nil; fineScrubbing = false; onSeek(clip.cover, false) })
            .accessibilityElement(children: .ignore).accessibilityLabel("拖动选择封面帧")
            .accessibilityValue("第 \(Int((clip.cover * max(1, frameRate)).rounded())) 帧")
            .accessibilityHint("左右拖动，向下拉可降低选帧速度")
            .accessibilityAdjustableAction { direction in
                let delta: Double
                switch direction { case .increment: delta = 1; case .decrement: delta = -1; @unknown default: return }
                clip.cover = min(max(clip.start, clip.end - 1 / max(1, frameRate)), max(clip.start, clip.cover + delta / max(1, frameRate)))
                clip.coverPhotoFilename = nil
                onSeek(clip.cover, false)
            }.accessibilityIdentifier("coverFrameHandle")
    }
    private var handle: some View {
        RoundedRectangle(cornerRadius: 5).fill(StudioTheme.accent).frame(width: 20, height: 61)
            .overlay { Capsule().fill(StudioTheme.onAccent.opacity(0.8)).frame(width: 2, height: 19) }
            .frame(width: 44, height: 70).contentShape(Rectangle())
    }
}
