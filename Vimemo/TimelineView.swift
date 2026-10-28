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
                let plan = TimelineThumbnailPlan(state: state, frameRate: frameRate)
                VStack(spacing: 0) {
                    strip(width: width, selection: selection, plan: plan)
                        .padding(.horizontal, inset)
                        .overlay {
                            TimelinePinchGesture(
                                hitTest: { point in target(at: point, selection: selection, width: width) },
                                onBegin: { target, x in model.begin(target, clip: clip, width: width, at: x - inset) },
                                onMove: { translation in move(translation, width: width) },
                                onEnd: { finishDrag() },
                                onCancel: { model.end() },
                                onPinchBegin: { x in model.beginPinch(x: x - inset, width: width) },
                                onPinch: { scale, x in model.pinch(scale: scale, x: x - inset, width: width) },
                                onPinchEnd: { model.endPinch() },
                                onReset: { withAnimation(.easeOut(duration: 0.3)) { model.reset() } },
                                onFine: { model.setFine($0) },
                                scrollRate: { model.autoScrollRate },
                                onAutoScroll: { seconds in autoScroll(seconds, width: width) }
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
                Button { withAnimation(.easeOut(duration: 0.3)) { model.zoom(by: 0.5) } } label: {
                    Image(systemName: "minus.magnifyingglass").frame(width: 32, height: 32)
                }.accessibilityLabel("缩小时间轴").accessibilityIdentifier("timelineZoomOut")
                Text(model.state.zoomScale < 10 ? String(format: "%.1f×", model.state.zoomScale) : String(format: "%.0f×", model.state.zoomScale))
                    .font(.system(size: 11, design: .monospaced))
                    .accessibilityIdentifier("timelineZoomScale")
                Button { withAnimation(.easeOut(duration: 0.3)) { model.zoom(by: 2) } } label: {
                    Image(systemName: "plus.magnifyingglass").frame(width: 32, height: 32)
                }.accessibilityLabel("放大时间轴").accessibilityIdentifier("timelineZoomIn")
                Spacer(minLength: 0)
                Button(model.selectionIsOffScreen(clip) ? "片段在视野外 · 定位" : "聚焦片段") {
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
            Text(model.fineAdjustment ? "精细调整 · 松手锁定" : "双指缩放 · 双击全片 · 抓柄进精度 · 拖边缘自动滚动")
                .font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
                .lineLimit(1).minimumScaleFactor(0.85)
        }.accessibilityElement(children: .contain).accessibilityLabel("片段裁剪时间轴")
            .onDisappear { finishDrag(); model.endPinch() }
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
                        if let image = thumbnails.images[plan.key(for: time)] {
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
                let drawnWidth = max(0.5, visibleRight - visibleLeft)
                RoundedRectangle(cornerRadius: 8).stroke(StudioTheme.accent, lineWidth: 3)
                    .frame(width: drawnWidth, height: 61)
                    .offset(x: visibleLeft, y: 6.5).allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("选区 \(clip.start.timeLabel) 至 \(clip.end.timeLabel)")
                    .accessibilityIdentifier("timelineSelectionFrame")
                if let body = selection.bodyZone(width: width) {
                    selectionBody(body, width: width)
                }
                if let start = selection.handleZone(isStart: true, width: width) {
                    trimHandle(isStart: true, zone: start, selection: selection, width: width)
                }
                if let end = selection.handleZone(isStart: false, width: width) {
                    trimHandle(isStart: false, zone: end, selection: selection, width: width)
                }
            }
            if !selection.isVisible { offScreenMarker(width: width) }
            if (0...width).contains(selection.coverX(for: clip)) { coverHandle(x: selection.coverX(for: clip), width: width) }
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

    private func selectionBody(_ zone: ClosedRange<CGFloat>, width: CGFloat) -> some View {
        Color.clear.frame(width: max(1, zone.upperBound - zone.lowerBound), height: stripHeight)
            .offset(x: zone.lowerBound, y: 8)
            .accessibilityElement(children: .ignore).accessibilityLabel("整体移动片段")
            .accessibilityValue("\(clip.start.timeLabel)–\(clip.end.timeLabel)")
            .accessibilityIdentifier("timelineSelectionBody")
            .accessibilityAdjustableAction { direction in adjust(.selection, direction: direction, width: width) }
    }

    /// The 44 pt touch band remains available in overview. The visible selection outline is the
    /// endpoint cue there, because drawing a full-size bar at a displaced touch band lies about time.
    private func trimHandle(isStart: Bool, zone: ClosedRange<CGFloat>, selection: TimelineSelectionGeometry, width: CGFloat) -> some View {
        let bar = RoundedRectangle(cornerRadius: 5).fill(StudioTheme.accent).frame(width: 20, height: 61)
            .overlay { Capsule().fill(StudioTheme.onAccent.opacity(0.8)).frame(width: 2, height: 19) }
        return Color.clear
            .frame(width: max(1, zone.upperBound - zone.lowerBound), height: 70)
            // In overview the selection can be narrower than a pixel. Its red outline shows
            // the true endpoints; don't draw large handles elsewhere and imply false times.
            .overlay {
                if !selection.isNarrow { bar }
            }
            .offset(x: zone.lowerBound, y: 2)
            .accessibilityElement(children: .ignore).accessibilityLabel(isStart ? "裁剪入点" : "裁剪出点")
            .accessibilityValue((isStart ? clip.start : clip.end).timeLabel)
            .accessibilityIdentifier(isStart ? "trimStartHandle" : "trimEndHandle")
            .accessibilityAdjustableAction { direction in adjust(isStart ? .start : .end, direction: direction, width: width) }
    }

    /// A pinch can legally walk the viewport away from the selection. The strip then says so
    /// instead of dragging the camera back behind the user's fingers; 聚焦片段 brings it back.
    private func offScreenMarker(width: CGFloat) -> some View {
        Text("\(clip.start.timeLabel)–\(clip.end.timeLabel) 在视野外")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(StudioTheme.raised, in: Capsule())
            .frame(width: width, alignment: .trailing).offset(y: 46)
            .allowsHitTesting(false)
            .accessibilityIdentifier("timelineSelectionOffscreen")
    }

    private func coverHandle(x: CGFloat, width: CGFloat) -> some View {
        let selection = TimelineSelectionGeometry(state: model.state, clip: clip, width: width)
        let gripX = selection.coverGripX(for: clip, stripWidth: width)
        return ZStack {
            Capsule().fill(StudioTheme.peach).frame(width: model.target == .cover ? 3 : 2, height: 70)
                .position(x: x, y: 46).allowsHitTesting(false).accessibilityHidden(true)
            Image(systemName: "arrow.left.and.right").font(.system(size: 10, weight: .bold))
                .foregroundStyle(StudioTheme.onAccent).frame(width: 30, height: 22)
                .background(StudioTheme.peach, in: Capsule())
                .frame(width: 44, height: 44)
                .accessibilityElement(children: .ignore).accessibilityLabel("拖动选择封面帧")
                .accessibilityValue("第 \(Int((clip.cover * max(1, frameRate)).rounded())) 帧")
                .accessibilityHint("左右拖动，向下拉可降低选帧速度")
                .accessibilityIdentifier("coverFrameHandle")
                .accessibilityAdjustableAction { direction in adjust(.cover, direction: direction, width: width) }
                .position(x: gripX, y: 90)
        }.frame(width: width, height: 114)
    }

    /// Only controls that are actually drawn may be grabbed, so a touch never edits a target
    /// the user cannot see.
    private func target(at point: CGPoint, selection: TimelineSelectionGeometry, width: CGFloat) -> TimelineViewModel.Target {
        let x = point.x - inset
        guard selection.isVisible else { return .viewport }
        let coverX = selection.coverX(for: clip)
        let coverGripX = selection.coverGripX(for: clip, stripWidth: width)
        if point.y >= 68, (0...width).contains(coverX),
           abs(x - coverGripX) <= 22 { return .cover }
        guard point.y <= 72 else { return .viewport }
        if let start = selection.handleZone(isStart: true, width: width), start.contains(x) { return .start }
        if let end = selection.handleZone(isStart: false, width: width), end.contains(x) { return .end }
        if let body = selection.bodyZone(width: width), body.contains(x) { return .selection }
        return .viewport
    }
    private func move(_ translation: CGSize, width: CGFloat) {
        apply(model.move(translation: translation, clip: clip, width: width, speed: speed, maxOutputDuration: maxOutputDuration))
    }
    private func autoScroll(_ deltaTime: Double, width: CGFloat) {
        guard let value = model.autoScroll(deltaTime: deltaTime, clip: clip) else { return }
        apply(value)
    }
    private func apply(_ value: Clip) {
        guard let target = model.target, target != .viewport else { return }
        clip = value
        let time = target == .start ? value.start : (target == .end ? max(value.start, value.end - 1 / max(1, frameRate)) : value.cover)
        onSeek(time, true)
    }
    private func finishDrag() {
        let editing = model.target != nil && model.target != .viewport
        model.end()
        if editing { onSeek(clip.cover, false) }
    }
    private func adjust(_ target: TimelineViewModel.Target, direction: AccessibilityAdjustmentDirection, width: CGFloat) {
        let sign: CGFloat
        switch direction { case .increment: sign = 1; case .decrement: sign = -1; @unknown default: return }
        let selection = TimelineSelectionGeometry(state: model.state, clip: clip, width: width)
        let x: CGFloat
        switch target {
        case .start: x = selection.left
        case .end: x = selection.right
        case .cover: x = selection.coverX(for: clip)
        case .selection, .viewport: x = selection.midpoint
        }
        model.begin(target, clip: clip, width: width, at: x)
        // Ask the model for the same pixels-per-time it gave this drag, so a VoiceOver
        // step is exactly one frame whether the target is a handle or the selection body.
        let points = CGFloat(1 / max(1, frameRate) / model.dragSecondsPerPoint)
        apply(model.move(translation: CGSize(width: sign * points, height: 0), clip: clip, width: width,
                         speed: speed, maxOutputDuration: maxOutputDuration))
        finishDrag()
    }
}
