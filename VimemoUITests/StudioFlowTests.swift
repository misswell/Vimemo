import XCTest
import StoreKitTest
import UIKit

final class StudioFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func screenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func selectTab(_ app: XCUIApplication, title: String) {
        let tab = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        // Music-style navigation minimizes after scrolling; tap the active tab to expand it.
        if !tab.exists { app.tabBars.buttons.firstMatch.tap() }
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
    }
    private func scrollEditor(_ app: XCUIApplication) {
        let scroll = app.scrollViews["editorScroll"]
        // The scroll view's accessibility frame extends behind the fixed tools.
        let visibleBottom = min(scroll.frame.maxY, app.buttons["editorTool0"].frame.minY - 10)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: scroll.frame.maxX - 12, dy: visibleBottom - 18))
        let end = origin.withOffset(CGVector(dx: scroll.frame.maxX - 12, dy: scroll.frame.minY + 25))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func scrollExport(_ app: XCUIApplication, to element: XCUIElement) {
        let action = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "制作并保存", "制作文件")).firstMatch
        for _ in 0..<6 {
            if element.isHittable && element.frame.maxY < action.frame.minY - 8 { return }
            app.scrollViews["exportOptionsScroll"].swipeUp()
        }
    }

    @MainActor func testNativeTabBarContinuousScrolling() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--scroll-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "draft-")).firstMatch.waitForExistence(timeout: 15))
        let scroll = app.scrollViews.firstMatch
        for i in 0..<8 {
            scroll.swipeUp(velocity: .slow)
            if i == 0 { screenshot(app, name: "native-tab-minimized") }
            scroll.swipeDown(velocity: .slow)
        }
        screenshot(app, name: "native-tab-scroll")
        XCTAssertTrue(app.tabBars.firstMatch.exists)
        let report = app.descendants(matching: .any)["scrollPerformanceReport"].firstMatch
        XCTAssertTrue(report.exists)
        let values = (report.value as? String ?? "").split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(values.count, 2)
        guard values.count == 2 else { return }
        XCTAssertGreaterThan(values[0], 100, "Must sample actual moving frames")
        XCTAssertLessThan(values[1], 100, "Tab transitions must not stall scrolling for 100 ms")
        selectTab(app, title: "作品")
        selectTab(app, title: "工作台")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "draft-")).firstMatch.exists)
    }

    @MainActor func testNativeMusicStyleNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString]
        app.launch()
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        if isPhone {
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5), "Navigation must use the system tab bar")
            XCTAssertTrue(app.tabBars.buttons["工作台"].isSelected)
        } else {
            XCTAssertTrue(app.buttons["工作台"].waitForExistence(timeout: 5))
        }
        screenshot(app, name: "music-home")
        selectTab(app, title: "作品")
        XCTAssertTrue(app.navigationBars["片刻收藏"].waitForExistence(timeout: 5))
        if isPhone { XCTAssertTrue(app.tabBars.buttons["作品"].isSelected) }
        screenshot(app, name: "music-library")
        selectTab(app, title: "设置")
        XCTAssertTrue(app.buttons["appearance-dark"].waitForExistence(timeout: 5))
        screenshot(app, name: "music-settings")
        selectTab(app, title: "工作台")
        app.buttons["试试示例"].tap()
        XCTAssertTrue(app.buttons["makeLivePhotos"].waitForExistence(timeout: 10))
        app.buttons["返回工作台"].tap()
        XCTAssertTrue(app.buttons["工作台"].waitForExistence(timeout: 5))
        if isPhone { XCTAssertTrue(app.tabBars.buttons["工作台"].isSelected) }
        screenshot(app, name: "music-drafts")
        selectTab(app, title: "作品")
        selectTab(app, title: "工作台")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "draft-")).firstMatch.exists)
    }

    @MainActor func testPortraitPreviewUsesSourceAspectRatio() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--demo-editor"]
        app.launch()
        XCTAssertTrue(app.buttons["makeLivePhotos"].waitForExistence(timeout: 10))

        let preview = app.buttons["previewPlayback"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        screenshot(app, name: "portrait-preview")
        let bounds = preview.frame
        XCTAssertGreaterThan(bounds.height, 0)
        XCTAssertEqual(bounds.width / bounds.height, 0.75, accuracy: 0.08,
                       "Portrait video preview should use the source aspect ratio instead of a landscape frame.")
    }

    @MainActor func testPreviewBadgesStayAtCanvasCornersAcrossRatios() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--demo-editor"]
        app.launch()
        XCTAssertTrue(app.buttons["editorTool1"].waitForExistence(timeout: 10))
        app.buttons["editorTool1"].tap()
        let live = app.descendants(matching: .any).matching(identifier: "previewLiveBadge").firstMatch
        let duration = app.descendants(matching: .any).matching(identifier: "previewDurationBadge").firstMatch
        let sound = app.buttons["previewSound"]
        let originalCorners = [live.frame, duration.frame, sound.frame]
        for ratio in ["9:16", "1:1", "16:9"] {
            app.buttons[ratio].tap()
            // A containing AX element reports the union of its visible children,
            // including the video. Measure the corner badges themselves.
            for (element, frame) in zip([live, duration, sound], originalCorners) {
                XCTAssertEqual(element.frame.midX, frame.midX, accuracy: 1)
                XCTAssertEqual(element.frame.midY, frame.midY, accuracy: 1)
            }
            screenshot(app, name: "fixed-preview-corners-" + ratio.replacingOccurrences(of: ":", with: "-"))
        }
    }

    @MainActor func testShortClipTrimmingAndCoverGripHaveSeparateTargets() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--demo-editor"]
        app.launch()
        let cover = app.descendants(matching: .any)["coverFrameHandle"]
        let start = app.descendants(matching: .any)["trimStartHandle"]
        let end = app.descendants(matching: .any)["trimEndHandle"]
        XCTAssertTrue(cover.waitForExistence(timeout: 10))
        for _ in 0..<5 {
            if cover.isHittable && cover.frame.maxY < app.buttons["editorTool0"].frame.minY - 8 { break }
            scrollEditor(app)
        }
        let oldStart = start.value as? String
        let oldEnd = end.value as? String
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let line = origin.withOffset(CGVector(dx: cover.frame.midX, dy: start.frame.midY))
        line.press(forDuration: 0.05, thenDragTo: line.withOffset(CGVector(dx: 26, dy: 0)))
        XCTAssertNotEqual(start.value as? String, oldStart, "Dragging the upper line must move the clip")
        XCTAssertNotEqual(end.value as? String, oldEnd)
        let right = end.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        right.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: start.frame.midX + 12, dy: end.frame.midY)))
        XCTAssertLessThan(end.frame.midX - start.frame.midX, 44, "The clip must be narrower than the original 44-point trim targets")
        let shortStart = start.value as? String
        let left = start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        left.press(forDuration: 0.05, thenDragTo: left.withOffset(CGVector(dx: -8, dy: 0)))
        XCTAssertNotEqual(start.value as? String, shortStart, "A short clip's start must remain draggable")
        let shortEnd = end.value as? String
        let endGrip = end.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        endGrip.press(forDuration: 0.05, thenDragTo: endGrip.withOffset(CGVector(dx: 24, dy: 0)))
        XCTAssertNotEqual(end.value as? String, shortEnd, "The cover line must not intercept the end")
        let beforeCover = cover.value as? String
        let clipStart = start.value as? String, clipEnd = end.value as? String
        let arrow = cover.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        arrow.press(forDuration: 0.05, thenDragTo: arrow.withOffset(CGVector(dx: -8, dy: 0)))
        XCTAssertNotEqual(cover.value as? String, beforeCover)
        XCTAssertEqual(start.value as? String, clipStart)
        XCTAssertEqual(end.value as? String, clipEnd)
        screenshot(app, name: "short-clip-separate-cover-grip")
    }

    @MainActor func testCoverScrubbingKeepsPreviewAndSettlesBeforeSaving() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--demo-editor"]
        app.launch()
        XCTAssertTrue(app.buttons["chooseCover"].waitForExistence(timeout: 10))
        app.buttons["chooseCover"].tap()
        let preview = app.images["coverPreviewImage"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        let slider = app.sliders["手动封面时间"]
        for position in [0.1, 0.9, 0.2, 0.8] {
            slider.adjust(toNormalizedSliderPosition: position)
            XCTAssertTrue(preview.exists, "Scrubbing must keep the displayed frame")
            XCTAssertFalse(app.activityIndicators["coverPreviewLoading"].exists)
        }
        let confirm = app.buttons["confirmCover"]
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: confirm)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        app.buttons["coverNextFrame"].tap()
        XCTAssertTrue(preview.exists)
        let stepped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: confirm)
        XCTAssertEqual(XCTWaiter.wait(for: [stepped], timeout: 5), .completed)
        screenshot(app, name: "continuous-cover-scrubbing")
        confirm.tap()
        XCTAssertTrue(app.buttons["chooseCover"].waitForExistence(timeout: 5))
    }

    @MainActor func testTimelineCoverHandleAndCenterFrameScrubber() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--demo-editor"]
        app.launch()
        let handle = app.descendants(matching: .any)["coverFrameHandle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        for _ in 0..<3 {
            if handle.isHittable && handle.frame.maxY < app.buttons["editorTool0"].frame.minY - 8 { break }
            scrollEditor(app)
        }
        screenshot(app, name: "timeline-before-drag")
        func frame(_ element: XCUIElement) -> Int {
            Int((element.value as? String ?? "").filter(\.isNumber)) ?? -1
        }
        let original = frame(handle)
        XCTAssertGreaterThanOrEqual(original, 0)
        let grip = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: 40, dy: 0)))
        let dragged = frame(handle)
        XCTAssertGreaterThan(dragged, original)
        XCTAssertLessThan(dragged, 90, "Cover must remain inside the original three-second clip")
        let fine = app.descendants(matching: .any)["timelineFineScrubber"]
        for _ in 0..<3 {
            if fine.isHittable && fine.frame.maxY < app.buttons["editorTool0"].frame.minY - 8 { break }
            scrollEditor(app)
        }
        let fineStart = fine.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        fineStart.press(forDuration: 0.05, thenDragTo: fineStart.withOffset(CGVector(dx: -36, dy: 0)))
        let refined = frame(handle)
        XCTAssertEqual(Double(dragged - refined), 3, accuracy: 1)
        app.buttons["timelineNextFrame"].tap()
        XCTAssertEqual(frame(handle), refined + 1)
        app.buttons["chooseCover"].tap()
        let pickerFrame = app.descendants(matching: .any)["coverFineScrubber"]
        XCTAssertTrue(pickerFrame.waitForExistence(timeout: 5))
        XCTAssertEqual(frame(pickerFrame), refined + 1, "Picker and timeline must share the selected cover")
        screenshot(app, name: "draggable-timeline-cover")
    }

    @MainActor func testCoverLineRemainsVisibleDuringContinuousDragging() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--demo-editor"]
        app.launch()
        let handle = app.descendants(matching: .any)["coverFrameHandle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        for _ in 0..<3 {
            if handle.isHittable && handle.frame.maxY < app.buttons["editorTool0"].frame.minY - 8 { break }
            scrollEditor(app)
        }
        screenshot(app, name: "cover-line-before-continuous-drag")
        for direction in [CGFloat(1), -1, 1, -1] {
            let startX = handle.frame.midX
            let grip = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: 40 * direction, dy: 0)),
                       withVelocity: XCUIGestureVelocity(rawValue: 24), thenHoldForDuration: 0.4)
            XCTAssertTrue(handle.exists)
            XCTAssertEqual(handle.frame.midX, startX + 40 * direction, accuracy: 3,
                           "The cover line must follow the finger, without feedback from its own movement")
        }
        let beforeFine = handle.frame.midX
        let fineGrip = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        fineGrip.press(forDuration: 0.05, thenDragTo: fineGrip.withOffset(CGVector(dx: 40, dy: 60)),
                       withVelocity: XCUIGestureVelocity(rawValue: 24), thenHoldForDuration: 0.4)
        XCTAssertGreaterThan(handle.frame.midX, beforeFine)
        XCTAssertLessThan(handle.frame.midX, beforeFine + 40, "Pulling down must retain slow frame selection")
        screenshot(app, name: "cover-line-after-continuous-drag")
    }

    @MainActor func testHoldPreviewReleasesAndSoundIcon() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--demo-editor"]
        app.launch()
        let preview = app.buttons["previewPlayback"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        preview.press(forDuration: 2.5)
        XCTAssertEqual(preview.value as? String, "封面", "Releasing a hold must return to the cover")
        preview.press(forDuration: 0.5)
        XCTAssertEqual(preview.label, "按住预览实况")
        let sound = app.buttons["previewSound"]
        XCTAssertTrue(sound.isHittable)
        XCTAssertEqual(sound.value as? String, sound.isEnabled ? "有声" : "静音")
        if sound.isEnabled {
            sound.tap()
            XCTAssertEqual(sound.value as? String, "静音")
            XCTAssertEqual(preview.value as? String, "封面", "Sound control must not start playback")
            preview.press(forDuration: 0.8)
            XCTAssertEqual(sound.value as? String, "静音")
            sound.tap()
            XCTAssertEqual(sound.value as? String, "有声")
        } else { XCTAssertEqual(sound.label, "原视频没有声音") }
        screenshot(app, name: "hold-live-preview-and-sound")
    }

    @MainActor func testDragPreviewRepositionsCropAndPersists() throws {
        let library = UUID().uuidString
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", library, "--demo-editor"]
        app.launch()
        XCTAssertTrue(app.buttons["editorTool1"].waitForExistence(timeout: 10))
        app.buttons["editorTool1"].tap()
        app.buttons["1:1"].tap()
        let preview = app.buttons["previewPlayback"]
        func waitForCrop() {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "水平"), object: preview)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        }
        waitForCrop()
        XCTAssertEqual(preview.value as? String, "水平 50%，垂直 50%")
        let verticalTravel = preview.frame.height * 0.4
        let center = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45))
        center.press(forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: 0, dy: verticalTravel)))
        XCTAssertEqual(preview.value as? String, "水平 50%，垂直 0%")
        app.buttons["精确位置"].tap()
        XCTAssertEqual(app.sliders["垂直位置"].value as? String, "0%")
        let up = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.65))
        up.press(forDuration: 0.05, thenDragTo: up.withOffset(CGVector(dx: 0, dy: -verticalTravel)))
        XCTAssertEqual(preview.value as? String, "水平 50%，垂直 100%")
        app.buttons["旋转 90°"].tap()
        waitForCrop()
        let right = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45))
        right.press(forDuration: 0.05, thenDragTo: right.withOffset(CGVector(dx: preview.frame.width * 0.4, dy: 0)))
        XCTAssertEqual(preview.value as? String, "水平 0%，垂直 100%")
        preview.press(forDuration: 0.7)
        XCTAssertEqual(preview.value as? String, "水平 0%，垂直 100%", "Holding must preview without changing the crop")
        screenshot(app, name: "drag-to-position-crop")
        app.buttons["返回工作台"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["editorTool1"].waitForExistence(timeout: 10))
        app.buttons["editorTool1"].tap()
        waitForCrop()
        XCTAssertEqual(preview.value as? String, "水平 0%，垂直 100%")
    }

    @MainActor func testAppearanceSwitchingAndPersistence() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--test-purchase-unavailable"]
        app.launch()
        screenshot(app, name: "20-system-workspace")
        selectTab(app, title: "设置")
        XCTAssertEqual(app.buttons["appearance-system"].value as? String, "已选择")
        app.buttons["appearance-dark"].tap()
        XCTAssertTrue(app.staticTexts["当前深色"].waitForExistence(timeout: 5))
        screenshot(app, name: "21-dark-settings")
        selectTab(app, title: "工作台")
        screenshot(app, name: "22-dark-workspace")
        app.buttons["试试示例"].tap()
        XCTAssertTrue(app.buttons["makeLivePhotos"].waitForExistence(timeout: 10))
        screenshot(app, name: "26-dark-editor")
        let playback = app.buttons["previewPlayback"]
        XCTAssertTrue(playback.isHittable)
        playback.press(forDuration: 0.7)
        XCTAssertEqual(playback.label, "按住预览实况")
        XCTAssertEqual(playback.value as? String, "封面")
        XCTAssertTrue(app.buttons["previewSound"].exists)
        app.buttons["chooseCover"].tap()
        XCTAssertTrue(app.buttons["confirmCover"].waitForExistence(timeout: 5))
        app.buttons["confirmCover"].tap()
        XCTAssertTrue(app.buttons["chooseCover"].waitForExistence(timeout: 5))
        app.buttons["makeLivePhotos"].tap()
        XCTAssertTrue(app.staticTexts["制作与导出"].waitForExistence(timeout: 5))
        screenshot(app, name: "27-dark-export")
        app.buttons["完成"].tap()
        app.buttons["返回工作台"].tap()
        screenshot(app, name: "28-dark-drafts")
        app.terminate(); app.launch()
        selectTab(app, title: "设置")
        XCTAssertEqual(app.buttons["appearance-dark"].value as? String, "已选择")
        XCTAssertTrue(app.staticTexts["当前深色"].exists)
        app.buttons["appearance-light"].tap()
        XCTAssertTrue(app.staticTexts["当前浅色"].waitForExistence(timeout: 5))
        screenshot(app, name: "23-light-settings")
        let unlock = app.buttons["unlockUnlimited"]
        for _ in 0..<3 where !unlock.isHittable { app.swipeUp() }
        unlock.tap()
        XCTAssertTrue(app.buttons["reloadPurchase"].waitForExistence(timeout: 5))
        screenshot(app, name: "29-light-purchase")
        app.buttons["continueFree"].tap()
        selectTab(app, title: "工作台")
        screenshot(app, name: "24-light-workspace")
        app.buttons["试试示例"].tap()
        XCTAssertTrue(app.buttons["makeLivePhotos"].waitForExistence(timeout: 10))
        screenshot(app, name: "25-light-editor")
        app.buttons["返回工作台"].tap()
        selectTab(app, title: "设置")
        for _ in 0..<3 where !app.buttons["appearance-system"].isHittable { app.swipeDown() }
        app.buttons["appearance-system"].tap()
        XCTAssertEqual(app.buttons["appearance-system"].value as? String, "已选择")
    }

    @MainActor func testPersistentToolsCoverResetAndDraftExport() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString]
        app.launch()
        app.buttons["试试示例"].tap()
        XCTAssertTrue(app.buttons["makeLivePhotos"].waitForExistence(timeout: 10))
        app.buttons["editorTool1"].tap()
        XCTAssertTrue(app.buttons["1:1"].waitForExistence(timeout: 5))
        app.buttons["1:1"].tap()
        XCTAssertEqual(app.buttons["1:1"].value as? String, "已选择")
        XCTAssertTrue(app.buttons["chooseCover"].isHittable)
        XCTAssertTrue(app.buttons["makeLivePhotos"].isHittable)
        app.buttons["重置画面编辑"].tap()
        app.buttons["取消"].tap()
        XCTAssertEqual(app.buttons["1:1"].value as? String, "已选择", "Cancelling reset must keep edits")
        app.buttons["editorTool2"].tap()
        app.buttons["胶片"].tap()
        XCTAssertTrue(app.buttons["chooseCover"].isHittable)
        screenshot(app, name: "18-persistent-editor-tools")
        app.buttons["返回工作台"].tap()
        let draft = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "draft-", "海边的最后一束光")).firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.press(forDuration: 1)
        let rename = app.buttons["重命名"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "海边的最后一束光".count) + "重新命名")
        app.alerts.buttons["保存"].tap()
        XCTAssertFalse(app.buttons["导出重新命名"].exists)
        let renamed = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "draft-", "重新命名")).firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        renamed.tap()
        XCTAssertTrue(app.buttons["makeLivePhotos"].waitForExistence(timeout: 5))
        app.buttons["makeLivePhotos"].tap()
        XCTAssertTrue(app.staticTexts["制作与导出"].waitForExistence(timeout: 5))
        screenshot(app, name: "draft-editor-export")
        scrollExport(app, to: app.buttons["静态照片"])
        app.buttons["静态照片"].tap()
        scrollExport(app, to: app.buttons["本机作品 / 分享文件"])
        app.buttons["本机作品 / 分享文件"].tap()
        app.buttons["制作文件 · 1 个作品"].tap()
        XCTAssertTrue(app.staticTexts["已制作 1 个作品"].waitForExistence(timeout: 30))
    }

    @MainActor func testDraftSavingToggleAndTemporaryExportLifecycle() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "-unlimitedDuration", "NO"]
        app.launch()
        selectTab(app, title: "设置")
        let toggle = app.switches["saveDrafts"]
        for _ in 0..<4 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
        screenshot(app, name: "17-draft-storage-setting")
        selectTab(app, title: "工作台")
        app.buttons["试试示例"].tap()
        XCTAssertTrue(app.buttons["makeLivePhotos"].waitForExistence(timeout: 10))
        app.buttons["makeLivePhotos"].tap()
        app.buttons["静态照片"].tap()
        app.swipeUp()
        app.buttons["本机作品 / 分享文件"].tap()
        app.buttons["制作文件 · 1 个作品"].tap()
        XCTAssertTrue(app.staticTexts["已制作 1 个作品"].waitForExistence(timeout: 30))
        app.buttons["完成"].tap()
        app.buttons["返回工作台"].tap()
        XCTAssertTrue(app.staticTexts["下一张实况，从这里开始"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        selectTab(app, title: "作品")
        XCTAssertTrue(app.staticTexts["海边的最后一束光"].waitForExistence(timeout: 5))
        selectTab(app, title: "设置")
        for _ in 0..<4 where !toggle.isHittable { app.swipeUp() }
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["clearTemporaryCache"].tap()
        XCTAssertTrue(app.alerts["临时缓存已检查"].waitForExistence(timeout: 5))
        app.alerts.buttons["好"].tap()
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        selectTab(app, title: "工作台")
        app.buttons["试试示例"].tap()
        XCTAssertTrue(app.buttons["返回工作台"].waitForExistence(timeout: 10))
        app.buttons["返回工作台"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["海边的最后一束光"].waitForExistence(timeout: 5))
    }

    @MainActor func testGIFOptionsExportAndRestoreDraft() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--demo-editor", "-unlimitedDuration", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["makeLivePhotos"].waitForExistence(timeout: 10))
        app.buttons["makeLivePhotos"].tap()
        app.buttons["GIF 动图"].tap()
        let size = app.buttons["gifSize480"]
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        size.tap()
        XCTAssertEqual(size.value as? String, "已选择")
        app.swipeUp()
        let fps = app.buttons["gifFPS24"]
        XCTAssertTrue(fps.waitForExistence(timeout: 5))
        fps.tap()
        XCTAssertEqual(fps.value as? String, "已选择")
        screenshot(app, name: "15-gif-size-and-frame-rate")
        app.swipeUp()
        app.buttons["本机作品 / 分享文件"].tap()
        app.buttons["制作文件 · 1 个作品"].tap()
        XCTAssertTrue(app.staticTexts["已制作 1 个作品"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["已保存到本机作品"].exists)
        screenshot(app, name: "16-gif-result")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["makeLivePhotos"].waitForExistence(timeout: 10))
        app.buttons["makeLivePhotos"].tap()
        XCTAssertTrue(app.buttons["gifSize480"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["gifSize480"].value as? String, "已选择")
        app.swipeUp()
        XCTAssertEqual(app.buttons["gifFPS24"].value as? String, "已选择")
    }

    @MainActor func testExportPreviewUsesEditsPlaysAndEnlarges() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--demo-editor"]
        app.launch()
        XCTAssertTrue(app.buttons["editorTool1"].waitForExistence(timeout: 10))
        app.buttons["editorTool1"].tap()
        app.buttons["1:1"].tap()
        app.buttons["editorTool2"].tap()
        app.buttons["胶片"].tap()
        app.buttons["editorTool3"].tap()
        app.buttons["2×"].tap()
        app.buttons["makeLivePhotos"].tap()
        let preview = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "exportClipPreview-")).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertTrue((preview.value as? String ?? "").contains("胶片"))
        XCTAssertTrue((preview.value as? String ?? "").contains("2×"))
        XCTAssertTrue((preview.value as? String ?? "").contains("1.50秒"))
        XCTAssertEqual(preview.frame.width / preview.frame.height, 1, accuracy: 0.05)
        preview.tap()
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "正在播放"), object: preview)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 10), .completed)
        screenshot(app, name: "real-edited-export-preview")
        let inlineWidth = preview.frame.width
        preview.press(forDuration: 0.8)
        let enlarged = app.descendants(matching: .any)["expandedClipPreview"]
        XCTAssertTrue(enlarged.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(enlarged.frame.width, inlineWidth)
        let largePlaying = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "正在播放"), object: enlarged)
        XCTAssertEqual(XCTWaiter.wait(for: [largePlaying], timeout: 10), .completed)
        XCTAssertTrue((enlarged.value as? String ?? "").contains("胶片"))
        screenshot(app, name: "enlarged-edited-export-preview")
        app.buttons["closeExpandedPreview"].tap()
        scrollExport(app, to: app.buttons["静态照片"])
        app.buttons["静态照片"].tap()
        app.scrollViews["exportOptionsScroll"].swipeDown()
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.press(forDuration: 0.8)
        XCTAssertTrue(enlarged.waitForExistence(timeout: 5))
        XCTAssertTrue((enlarged.value as? String ?? "").contains("封面"))
        app.buttons["closeExpandedPreview"].tap()
    }

    @MainActor func testEditorSoundIsUnifiedAndPersists() throws {
        let library = UUID().uuidString
        let fixture = try XCTUnwrap(Bundle(for: StudioFlowTests.self).url(forResource: "AudioFixture", withExtension: "mov"))
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", library, "--test-editor-video", fixture.path]
        app.launch()
        let sound = app.buttons["previewSound"]
        XCTAssertTrue(sound.waitForExistence(timeout: 10))
        XCTAssertTrue(sound.isEnabled, "Use a source with a real audio track")
        XCTAssertEqual(sound.value as? String, "有声")
        sound.tap()
        XCTAssertEqual(sound.value as? String, "静音")
        XCTAssertFalse(app.buttons["发现更多片段"].exists)
        let precise = app.buttons["精确裁剪"]
        for _ in 0..<6 {
            if precise.isHittable && precise.frame.maxY < app.buttons["editorTool0"].frame.minY - 8 { break }
            scrollEditor(app)
        }
        precise.tap()
        let step = app.buttons["入点后移一帧"]
        for _ in 0..<6 {
            if step.isHittable && step.frame.maxY < app.buttons["editorTool0"].frame.minY - 8 { break }
            scrollEditor(app)
        }
        XCTAssertTrue(step.isHittable)
        step.tap()
        screenshot(app, name: "compact-precise-trim-and-sound-icon")
        app.buttons["editorTool3"].tap()
        XCTAssertFalse(app.switches["静音"].exists)
        app.buttons["返回工作台"].tap()
        app.terminate()
        app.launchArguments = ["--test-library", library]
        app.launch()
        let draft = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "声音测试")).firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        draft.tap()
        XCTAssertTrue(sound.waitForExistence(timeout: 10))
        XCTAssertEqual(sound.value as? String, "静音", "The speaker controls the saved project setting")
        app.buttons["makeLivePhotos"].tap()
        let privacy = app.buttons["拍摄信息与隐私"]
        let exportButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "制作并保存")).firstMatch
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        let scroll = app.scrollViews["exportOptionsScroll"]
        for _ in 0..<5 where privacy.frame.maxY > exportButton.frame.minY { scroll.swipeUp() }
        privacy.tap()
        XCTAssertFalse(app.descendants(matching: .any)["exportMute"].exists)
        XCTAssertFalse(app.switches["静音导出"].exists)
        screenshot(app, name: "export-uses-project-sound")
    }

    @MainActor func testPurchaseUnavailableKeepsVisibleRetryAndFreeExit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--test-purchase-unavailable"]
        app.launch()
        selectTab(app, title: "设置")
        app.buttons["unlockUnlimited"].tap()
        let retry = app.buttons["reloadPurchase"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(retry.isHittable)
        XCTAssertTrue(retry.isEnabled)
        XCTAssertEqual(retry.label, "重新获取价格")
        let error = app.staticTexts["purchaseMessage"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.isHittable, "Price failures must remain above the pinned button")
        screenshot(app, name: "17-purchase-unavailable")
        retry.tap()
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(retry.isHittable)
        app.buttons["continueFree"].tap()
        XCTAssertTrue(app.buttons["unlockUnlimited"].waitForExistence(timeout: 5))
    }

    @MainActor func testPurchaseLoadingKeepsDisabledButtonAndFreeExit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--test-purchase-loading"]
        app.launch()
        selectTab(app, title: "设置")
        app.buttons["unlockUnlimited"].tap()
        let button = app.buttons["reloadPurchase"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isHittable)
        XCTAssertFalse(button.isEnabled)
        XCTAssertTrue(button.label.contains("正在获取价格"))
        XCTAssertTrue(app.buttons["continueFree"].isHittable)
        screenshot(app, name: "18-purchase-loading")
        app.buttons["continueFree"].tap()
        XCTAssertTrue(app.buttons["unlockUnlimited"].waitForExistence(timeout: 5))
    }

    @MainActor func testPurchasePriceAndButtonVisibleWithoutScrolling() throws {
        if UIDevice.current.systemVersion.hasPrefix("26.5") {
            throw XCTSkip("iOS 26.5 StoreKitTest sync is affected by Apple FB22237318; use a supported runtime for real test-product prices.")
        }
        let config = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Unlimited", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: config)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        defer { session.clearTransactions() }
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString]
        app.launch()
        selectTab(app, title: "设置")
        app.buttons["unlockUnlimited"].tap()
        let button = app.buttons["buyUnlimited"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertTrue(button.isHittable)
        XCTAssertTrue(button.isEnabled)
        let price = app.staticTexts["unlimitedPrice"]
        XCTAssertTrue(price.exists)
        XCTAssertTrue(price.isHittable)
        XCTAssertTrue(button.label.contains(price.label))
        XCTAssertTrue(app.buttons["restoreUnlimited"].isHittable)
        screenshot(app, name: "19-purchase-ready")
        app.buttons["continueFree"].tap()
        XCTAssertTrue(app.buttons["unlockUnlimited"].exists)
    }

    @MainActor func testCreateTwoLivePhotosSaveToPhotosAndRestoreDraft() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["试试示例"].waitForExistence(timeout: 5))
        screenshot(app, name: "01-workspace")
        app.buttons["试试示例"].tap()
        XCTAssertTrue(app.buttons["makeLivePhotos"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["下一帧"].waitForExistence(timeout: 5))
        app.buttons["下一帧"].tap()
        app.buttons["添加片段"].tap()
        XCTAssertTrue(app.buttons["片段 2"].exists)
        let layoutSettled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["添加片段"].frame.minX >= app.buttons["片段 2"].frame.maxX
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [layoutSettled], timeout: 4), .completed)
        screenshot(app, name: "02-editor")
        app.buttons["makeLivePhotos"].tap()
        XCTAssertTrue(app.staticTexts["制作与导出"].waitForExistence(timeout: 5))
        screenshot(app, name: "03-export-options")
        app.buttons["制作并保存 · 2 个作品"].tap()
        XCTAssertTrue(app.staticTexts["已制作 2 个作品"].waitForExistence(timeout: 25))
        let savedLabels = app.staticTexts.matching(NSPredicate(format: "label == %@", "已保存到照片图库及本机"))
        XCTAssertEqual(savedLabels.count, 2)
        screenshot(app, name: "04-live-photo-result")
        app.buttons["完成"].firstMatch.tap()
        XCTAssertTrue(app.buttons["返回工作台"].waitForExistence(timeout: 5))
        app.buttons["返回工作台"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "2 个片段")).firstMatch.waitForExistence(timeout: 5))
        selectTab(app, title: "作品")
        XCTAssertTrue(app.staticTexts["片刻收藏"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2 个作品"].exists)
        screenshot(app, name: "05-library")
        let record = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "海边的最后一束光")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        XCTAssertTrue(app.buttons["长按画面，或点此播放实况"].waitForExistence(timeout: 10))
        app.buttons["长按画面，或点此播放实况"].tap()
        screenshot(app, name: "06-live-photo-playback")
    }

    @MainActor func testFreeExportsAndBothCoverChoices() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString]
        app.launch()
        app.buttons["试试示例"].tap()
        XCTAssertTrue(app.buttons["makeLivePhotos"].waitForExistence(timeout: 10))
        app.buttons["chooseCover"].tap()
        let coverTime = app.sliders["手动封面时间"]
        XCTAssertTrue(coverTime.waitForExistence(timeout: 5))
        coverTime.adjust(toNormalizedSliderPosition: 0.85)
        let confirm = app.buttons["confirmCover"]
        let previewReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: confirm)
        XCTAssertEqual(XCTWaiter.wait(for: [previewReady], timeout: 10), .completed)
        screenshot(app, name: "08-manual-video-cover")
        confirm.tap()
        app.buttons["chooseCover"].tap()
        app.buttons["pickCoverPhoto"].tap()
        let photo = app.images["PXGGridLayout-Info"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        let photoReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: confirm)
        XCTAssertEqual(XCTWaiter.wait(for: [photoReady], timeout: 15), .completed)
        screenshot(app, name: "09-album-cover")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["已使用相册照片作为封面"].waitForExistence(timeout: 5))
        app.buttons["makeLivePhotos"].tap()
        app.buttons["制作并保存 · 1 个作品"].tap()
        XCTAssertTrue(app.staticTexts["已制作 1 个作品"].waitForExistence(timeout: 30))
        screenshot(app, name: "10-free-live-photo")
        app.buttons["完成"].firstMatch.tap()
        app.buttons["返回工作台"].tap()
    }

    @MainActor func testLockedSettingShowsPurchaseAndCanContinueFree() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "-unlimitedDuration", "NO"]
        app.launch()
        selectTab(app, title: "设置")
        let unlimited = app.switches["unlimitedDuration"]
        XCTAssertTrue(unlimited.waitForExistence(timeout: 5))
        unlimited.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["restoreUnlimited"].waitForExistence(timeout: 5))
        screenshot(app, name: "11-unlimited-purchase")
        app.buttons["continueFree"].tap()
        XCTAssertEqual(unlimited.value as? String, "0")
        selectTab(app, title: "工作台")
        app.buttons["试试示例"].tap()
        XCTAssertTrue(app.buttons["makeLivePhotos"].waitForExistence(timeout: 10))
    }

    @MainActor func testPurchaseResultAndRelaunch() throws {
        if UIDevice.current.systemVersion.hasPrefix("26.5") {
            throw XCTSkip("iOS 26.5 StoreKitTest sync is affected by Apple FB22237318; use a supported runtime for transaction UI tests.")
        }
        let config = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Unlimited", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: config)
        session.resetToDefaultState(); session.clearTransactions(); session.disableDialogs = true
        defer { session.clearTransactions() }
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString]
        app.launch()
        selectTab(app, title: "设置")
        app.buttons["unlockUnlimited"].tap()
        let buy = app.buttons["buyUnlimited"]
        XCTAssertTrue(buy.waitForExistence(timeout: 10))
        screenshot(app, name: "13-purchase-price")
        buy.tap()
        let confirmation = app.buttons.matching(NSPredicate(format: "label == '购买' OR label == 'Buy'")).firstMatch
        if confirmation.waitForExistence(timeout: 3) { confirmation.tap() }
        let rejected = app.staticTexts["无法验证这次购买，请尝试恢复购买。"]
        if rejected.waitForExistence(timeout: 3) {
            screenshot(app, name: "14-unverified-purchase-rejected")
            app.buttons["continueFree"].tap()
            XCTAssertTrue(app.buttons["unlockUnlimited"].exists)
            app.terminate(); app.launch()
            selectTab(app, title: "设置")
            XCTAssertTrue(app.buttons["unlockUnlimited"].waitForExistence(timeout: 5))
            return
        }
        XCTAssertTrue(app.staticTexts["已解锁"].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        selectTab(app, title: "设置")
        XCTAssertTrue(app.staticTexts["已解锁"].waitForExistence(timeout: 10))
    }

    @MainActor func testLegacyLongDraftRequiresUnlockButStaticPhotoRemainsFree() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--demo-editor", "-unlimitedDuration", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["makeLivePhotos"].waitForExistence(timeout: 10))
        app.buttons["makeLivePhotos"].tap()
        XCTAssertTrue(app.otherElements["longExportNotice"].exists || app.staticTexts["longExportNotice"].exists)
        app.buttons["制作并保存 · 1 个作品"].tap()
        XCTAssertTrue(app.buttons["continueFree"].waitForExistence(timeout: 5))
        app.buttons["continueFree"].tap()
        app.buttons["静态照片"].tap()
        app.buttons["制作并保存 · 1 个作品"].tap()
        XCTAssertTrue(app.staticTexts["已制作 1 个作品"].waitForExistence(timeout: 15))
        screenshot(app, name: "12-free-photo-from-long-draft")
    }

    @MainActor func testAdjustmentsAndStaticPhotoExport() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--demo-editor"]
        app.launch()
        XCTAssertTrue(app.buttons["makeLivePhotos"].waitForExistence(timeout: 10))
        scrollEditor(app)
        app.buttons["画面"].tap()
        scrollEditor(app)
        XCTAssertTrue(app.buttons["1:1"].waitForExistence(timeout: 5))
        app.buttons["1:1"].tap()
        app.buttons["旋转 90°"].tap()
        app.buttons["水平翻转"].tap()
        app.buttons["调色"].tap()
        app.buttons["胶片"].tap()
        app.buttons["makeLivePhotos"].tap()
        XCTAssertTrue(app.buttons["静态照片"].waitForExistence(timeout: 5))
        app.buttons["静态照片"].tap()
        app.swipeUp()
        app.buttons["本机作品 / 分享文件"].tap()
        app.buttons["制作文件 · 1 个作品"].tap()
        XCTAssertTrue(app.staticTexts["已制作 1 个作品"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["已保存到本机作品"].exists)
        screenshot(app, name: "07-square-film-export")
    }
}
