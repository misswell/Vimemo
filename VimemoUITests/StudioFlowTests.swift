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
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.72))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.20))
        start.press(forDuration: 0.05, thenDragTo: end)
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

        let preview = app.descendants(matching: .any)["editorPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        screenshot(app, name: "portrait-preview")
        let bounds = preview.frame
        XCTAssertGreaterThan(bounds.height, 0)
        XCTAssertEqual(bounds.width / bounds.height, 0.75, accuracy: 0.08,
                       "Portrait video preview should use the source aspect ratio instead of a landscape frame.")
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
        playback.tap()
        XCTAssertEqual(playback.label, "暂停预览")
        playback.tap()
        XCTAssertEqual(playback.label, "播放编辑后片段")
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

    @MainActor func testPersistentToolsCoverResetAndQuickDraftExport() throws {
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
        let quickExport = app.buttons["导出重新命名"]
        XCTAssertTrue(quickExport.waitForExistence(timeout: 5))
        quickExport.tap()
        screenshot(app, name: "30-quick-export-after-tap")
        XCTAssertTrue(app.staticTexts["制作与导出"].waitForExistence(timeout: 5))
        screenshot(app, name: "19-quick-export")
        app.buttons["静态照片"].tap()
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

    @MainActor func testMuteToggleAppearsInVideoExportPrivacyOptions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--demo-editor"]
        app.launch()
        XCTAssertTrue(app.buttons["makeLivePhotos"].waitForExistence(timeout: 10))
        app.buttons["makeLivePhotos"].tap()

        let privacy = app.buttons["拍摄信息与隐私"]
        let exportButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "制作并保存")).firstMatch
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.scrollViews.count, 0)
        let scroll = app.scrollViews.element(boundBy: app.scrollViews.count - 1)
        for _ in 0..<5 where privacy.frame.maxY > exportButton.frame.minY { scroll.swipeUp() }
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        XCTAssertLessThan(privacy.frame.maxY, exportButton.frame.minY)
        privacy.tap()
        XCTAssertTrue(app.staticTexts["开启后，导出的视频不包含音轨；原始视频不受影响。"].waitForExistence(timeout: 5))

        let mute = app.descendants(matching: .any).matching(identifier: "exportMute").firstMatch
        XCTAssertTrue(mute.waitForExistence(timeout: 5))
        for _ in 0..<3 where !mute.isHittable { scroll.swipeUp() }
        XCTAssertTrue(mute.isHittable)
        XCTAssertEqual(mute.value as? String, "0")
        mute.tap()
        XCTAssertEqual(mute.value as? String, "1")
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
