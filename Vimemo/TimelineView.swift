import SwiftUI

struct TimelineView: View {
    @Binding var clip: Clip
    var duration: Double
    var speed: Double
    var maxOutputDuration: Double? = 3
    var thumbnails: [UIImage]
    var onSeek: (Double) -> Void
    @State private var dragStart: Clip?

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let total = max(0.1, duration)
                let left = width * clip.start / total
                let right = width * clip.end / total
                let cover = width * clip.cover / total
                ZStack(alignment: .leading) {
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
                            onSeek(clip.cover)
                        }.onEnded { _ in dragStart = nil })
                    handle.offset(x: left - 22).simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { value in
                        guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                        if dragStart == nil { dragStart = clip }
                        let start = (dragStart?.start ?? clip.start) + value.translation.width / width * total
                        clip.start = min(max(0, start), clip.end - min(0.1, total))
                        if let maximum = maxOutputDuration { clip.start = max(clip.start, clip.end - maximum * speed) }
                        clip.normalize(sourceDuration: duration, speed: speed, maxOutputDuration: maxOutputDuration)
                        onSeek(clip.start)
                    }.onEnded { _ in dragStart = nil; onSeek(clip.cover) })
                    handle.offset(x: right - 22).simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { value in
                        guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                        if dragStart == nil { dragStart = clip }
                        let end = (dragStart?.end ?? clip.end) + value.translation.width / width * total
                        clip.end = min(total, max(clip.start + min(0.1, total), end))
                        clip.normalize(sourceDuration: duration, speed: speed, maxOutputDuration: maxOutputDuration)
                        onSeek(clip.end - 1 / 30)
                    }.onEnded { _ in dragStart = nil; onSeek(clip.cover) })
                    Rectangle().fill(StudioTheme.peach).frame(width: 2, height: 70).offset(x: cover - 1).allowsHitTesting(false)
                }
            }.frame(height: 70)
            HStack {
                Text(clip.start.timeLabel)
                Spacer()
                Text("封面 \(clip.cover.timeLabel)").foregroundStyle(StudioTheme.peach)
                Spacer()
                Text(clip.end.timeLabel)
            }.font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(StudioTheme.secondary)
            Text("拖动两端裁剪 · 拖动中间移动片段").font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
        }.accessibilityElement(children: .contain).accessibilityLabel("片段裁剪时间轴")
    }
    private var handle: some View {
        RoundedRectangle(cornerRadius: 5).fill(StudioTheme.accent).frame(width: 20, height: 61)
            .overlay { Capsule().fill(.white.opacity(0.8)).frame(width: 2, height: 19) }
            .frame(width: 44, height: 70).contentShape(Rectangle())
    }
}
