import SwiftUI

struct TimelineView: View {
    @Binding var clip: Clip
    var duration: Double
    var speed: Double
    var maxOutputDuration: Double? = 3
    var sourceURL: URL
    var frameRate: Double = 30
    var onSeek: (Double, Bool) -> Void
    @StateObject private var model = TimelineViewModel()
    @StateObject private var thumbnails = TimelineThumbnailManager()
    private let inset: CGFloat = 22
    private let stripHeight: CGFloat = 58

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let width = max(1, geometry.size.width - 2 * inset)
                let state = model.state
                let selection = TimelineSelectionGeometry(state: state, clip: clip, width: width)
                let plan = TimelineThumbnailPlan(state: state)
                VStack(spacing: 0) {
                    strip(width: width, selection: selection, plan: plan)
                        .padding(.horizontal, inset)
                        .overlay {
                            TimelinePinchGesture(
                                hitTest: { point in target(at: point, selection: selection, width: width) },
                                onBegin: { target in model.begin(target, clip: clip, width: width) },
                                onMove: { translation in move(translation, width: width) },
                                onEnd: { finishDrag() },
                                onPinchBegin: { x in model.beginPinch(x: x - inset, width: width) },
                                onPinch: { scale, x in model.pinch(scale: scale, x: x - inset, width: width) },
                                onPinchEnd: { model.endPinch(clip: clip) },
                                onReset: { withAnimation(.easeOut(duration: 0.3)) { model.reset() } },
                                onFine: { model.setFine($0) }
                            )
                        }
                    HStack {
                        Text(state.visibleStart.timeLabel).accessibilityIdentifier("timelineViewportStart")
                        Spacer()
                        Text(state.visibleEnd.timeLabel).accessibilityIdentifier("timelineViewportEnd")
                    }.font(.system(size: 10, design: .monospaced)).foregroundStyle(StudioTheme.secondary)
                        .padding(.horizontal, inset)
                }
                .onAppear { model.configure(duration: duration, clip: clip, width: width, frameRate: frameRate) }
                .onChange(of: clip) { _, current in
                    model.configure(duration: duration, clip: current, width: width, frameRate: frameRate)
                    model.selectionChanged(current)
                }
                .onChange(of: width) { _, _ in
                    model.configure(duration: duration, clip: clip, width: width, frameRate: frameRate)
                }
                .onChange(of: duration) { _, _ in
                    model.configure(duration: duration, clip: clip, width: width, frameRate: frameRate)
                }
                .task(id: ThumbnailRequest(source: sourceURL, plan: plan)) {
                    await thumbnails.load(source: sourceURL, plan: plan)
                }
            }.frame(height: 132)
            HStack(spacing: 12) {
                Button { withAnimation(.easeOut(duration: 0.3)) { model.zoom(by: 0.5, clip: clip) } } label: {
                    Image(systemName: "minus.magnifyingglass").frame(width: 32, height: 32)
                }.accessibilityLabel("缩小时间轴").accessibilityIdentifier("timelineZoomOut")
                Text(String(format: "%.0f×", model.state.zoomScale))
                    .font(.system(size: 11, design: .monospaced))
                    .accessibilityIdentifier("timelineZoomScale")
                Button { withAnimation(.easeOut(duration: 0.3)) { model.zoom(by: 2, clip: clip) } } label: {
                    Image(systemName: "plus.magnifyingglass").frame(width: 32, height: 32)
                }.accessibilityLabel("放大时间轴").accessibilityIdentifier("timelineZoomIn")
                Spacer(minLength: 0)
                Button("聚焦片段") {
                    withAnimation(.easeOut(duration: 0.3)) { model.focus(clip) }
                }.accessibilityIdentifier("timelineFocusSelection")
                Button("全片") { withAnimation(.easeOut(duration: 0.3)) { model.reset() } }
                    .accessibilityIdentifier("timelineOverview")
            }.font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(StudioTheme.accent)
            HStack {
                Text(clip.start.timeLabel).accessibilityIdentifier("timelineClipStart")
                Spacer()
                Text("封面 \(clip.cover.timeLabel)").foregroundStyle(StudioTheme.peach)
                Spacer()
                Text(clip.end.timeLabel).accessibilityIdentifier("timelineClipEnd")
            }.font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(StudioTheme.secondary)
            Text(model.fineAdjustment ? "精细调整 · 松手锁定" : "双指缩放 · 双击全片 · 拖中间移动 · 长按精调")
                .font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
        }.accessibilityElement(children: .contain).accessibilityLabel("片段裁剪时间轴")
            .onDisappear { finishDrag(); model.endPinch(clip: clip) }
    }

    private struct ThumbnailRequest: Equatable {
        let source: URL
        let plan: TimelineThumbnailPlan
    }

    private func strip(width: CGFloat, selection: TimelineSelectionGeometry, plan: TimelineThumbnailPlan) -> some View {
        let visibleLeft = max(0, selection.left)
        let visibleRight = min(width, selection.right)
        let cellWidth = plan.cellWidth(in: width)
        return ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(plan.times, id: \.self) { time in
                    ZStack {
                        StudioTheme.raised
                        if let image = thumbnails.images[time] {
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                    }.frame(width: cellWidth, height: stripHeight).clipped()
                }
            }.offset(x: model.state.x(for: plan.times.first ?? 0, width: width))
                .frame(width: width, height: stripHeight, alignment: .leading).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10)).offset(y: 8)
                .allowsHitTesting(false)
            if selection.isVisible {
                Rectangle().fill(.black.opacity(0.55)).frame(width: visibleLeft, height: stripHeight).offset(y: 8)
                    .allowsHitTesting(false)
                Rectangle().fill(.black.opacity(0.55)).frame(width: max(0, width - visibleRight), height: stripHeight)
                    .offset(x: visibleRight, y: 8).allowsHitTesting(false)
                RoundedRectangle(cornerRadius: 8).stroke(StudioTheme.accent, lineWidth: 3)
                    .frame(width: visibleRight - visibleLeft, height: 61).offset(x: visibleLeft, y: 6.5).allowsHitTesting(false)
                Color.clear.frame(width: max(1, visibleRight - visibleLeft - 44), height: stripHeight)
                    .offset(x: visibleLeft + 22, y: 8)
                    .accessibilityElement(children: .ignore).accessibilityLabel("整体移动片段")
                    .accessibilityValue("\(clip.start.timeLabel)–\(clip.end.timeLabel)")
                    .accessibilityIdentifier("timelineSelectionBody")
                    .accessibilityAdjustableAction { direction in adjust(.selection, direction: direction, width: width) }
                if (0...width).contains(selection.coverX(for: clip)) { coverHandle(x: selection.coverX(for: clip), width: width) }
                if (0...width).contains(selection.left) { trimHandle(isStart: true, width: width).offset(x: selection.left - 22, y: 2) }
                if (0...width).contains(selection.right) { trimHandle(isStart: false, width: width).offset(x: selection.right - 22, y: 2) }
            }
            if let time = model.feedbackTime {
                Text(time.timeLabel).font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(StudioTheme.background, in: Capsule())
                    .frame(width: width, alignment: .center).offset(y: 18)
                    .allowsHitTesting(false).accessibilityIdentifier("timelineDragTime")
            }
        }.frame(width: width, height: 114, alignment: .topLeading)
            .accessibilityElement(children: .contain).accessibilityIdentifier("timelineTrack")
    }

    private func trimHandle(isStart: Bool, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5).fill(StudioTheme.accent).frame(width: 20, height: 61)
            .overlay { Capsule().fill(StudioTheme.onAccent.opacity(0.8)).frame(width: 2, height: 19) }
            .frame(width: 44, height: 70)
            .accessibilityElement(children: .ignore).accessibilityLabel(isStart ? "裁剪入点" : "裁剪出点")
            .accessibilityValue((isStart ? clip.start : clip.end).timeLabel)
            .accessibilityIdentifier(isStart ? "trimStartHandle" : "trimEndHandle")
            .accessibilityAdjustableAction { direction in adjust(isStart ? .start : .end, direction: direction, width: width) }
    }

    private func coverHandle(x: CGFloat, width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Capsule().fill(StudioTheme.peach).frame(width: model.target == .cover ? 3 : 2, height: 70)
                .offset(y: 11).allowsHitTesting(false).accessibilityHidden(true)
            Image(systemName: "arrow.left.and.right").font(.system(size: 10, weight: .bold))
                .foregroundStyle(StudioTheme.onAccent).frame(width: 30, height: 22)
                .background(StudioTheme.peach, in: Capsule())
                .frame(width: 44, height: 44).offset(y: 68)
                .accessibilityElement(children: .ignore).accessibilityLabel("拖动选择封面帧")
                .accessibilityValue("第 \(Int((clip.cover * max(1, frameRate)).rounded())) 帧")
                .accessibilityHint("左右拖动，向下拉可降低选帧速度")
                .accessibilityIdentifier("coverFrameHandle")
                .accessibilityAdjustableAction { direction in adjust(.cover, direction: direction, width: width) }
        }.frame(width: 44, height: 114, alignment: .top).offset(x: x - 22)
    }

    /// Only handles that are actually drawn may be grabbed, so a touch never edits a target
    /// the user cannot see.
    private func target(at point: CGPoint, selection: TimelineSelectionGeometry, width: CGFloat) -> TimelineViewModel.Target {
        let x = point.x - inset
        guard selection.isVisible else { return .viewport }
        if point.y >= 68, (0...width).contains(selection.coverX(for: clip)),
           abs(x - selection.coverX(for: clip)) <= 22 { return .cover }
        if point.y <= 72 {
            if (0...width).contains(selection.left), abs(x - selection.left) <= 22 { return .start }
            if (0...width).contains(selection.right), abs(x - selection.right) <= 22 { return .end }
            if x > selection.left, x < selection.right { return .selection }
        }
        return .viewport
    }
    private func move(_ translation: CGSize, width: CGFloat) {
        let target = model.target
        let value = model.move(translation: translation, clip: clip, width: width, speed: speed, maxOutputDuration: maxOutputDuration)
        guard let target, target != .viewport else { return }
        clip = value
        let time = target == .start ? value.start : (target == .end ? max(value.start, value.end - 1 / max(1, frameRate)) : value.cover)
        onSeek(time, true)
    }
    private func finishDrag() {
        let editing = model.target != nil && model.target != .viewport
        model.end(clip: clip)
        if editing { onSeek(clip.cover, false) }
    }
    private func adjust(_ target: TimelineViewModel.Target, direction: AccessibilityAdjustmentDirection, width: CGFloat) {
        let sign: CGFloat
        switch direction { case .increment: sign = 1; case .decrement: sign = -1; @unknown default: return }
        model.begin(target, clip: clip, width: width)
        // Ask the model for the same pixels-per-time it gave this drag, so a VoiceOver
        // step is exactly one frame whether the target is measured in real or drawn space.
        let points = CGFloat(1 / max(1, frameRate) / model.dragSecondsPerPoint)
        move(CGSize(width: sign * points, height: 0), width: width)
        finishDrag()
    }
}
