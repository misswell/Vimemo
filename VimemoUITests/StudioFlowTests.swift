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
    private func scrollEditor(_ app: XCUIApplication) {
        let scroll = app.scrollViews["editorScroll"]
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.72))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.20))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor func testDraftSavingToggleAndTemporaryExportLifecycle() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "-unlimitedDuration", "NO"]
        app.launch()
        app.buttons["设置"].tap()
        let toggle = app.switches["saveDrafts"]
        for _ in 0..<4 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        screenshot(app, name: "17-draft-storage-setting")
        app.buttons["工作台"].tap()
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
        app.buttons["作品"].tap()
        XCTAssertTrue(app.staticTexts["海边的最后一束光"].waitForExistence(timeout: 5))
        app.buttons["设置"].tap()
        for _ in 0..<4 where !toggle.isHittable { app.swipeUp() }
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["clearTemporaryCache"].tap()
        XCTAssertTrue(app.alerts["临时缓存已检查"].waitForExistence(timeout: 5))
        app.alerts.buttons["好"].tap()
        toggle.tap()
        app.buttons["工作台"].tap()
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

    @MainActor func testPurchaseUnavailableKeepsVisibleRetryAndFreeExit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString, "--test-purchase-unavailable"]
        app.launch()
        app.buttons["设置"].tap()
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
        app.buttons["设置"].tap()
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
        app.buttons["设置"].tap()
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
        app.buttons["作品"].tap()
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
        app.buttons["设置"].tap()
        let unlimited = app.switches["unlimitedDuration"]
        XCTAssertTrue(unlimited.waitForExistence(timeout: 5))
        unlimited.tap()
        XCTAssertTrue(app.buttons["restoreUnlimited"].waitForExistence(timeout: 5))
        screenshot(app, name: "11-unlimited-purchase")
        app.buttons["continueFree"].tap()
        XCTAssertEqual(unlimited.value as? String, "0")
        app.buttons["工作台"].tap()
        app.buttons["试试示例"].tap()
        XCTAssertTrue(app.buttons["makeLivePhotos"].waitForExistence(timeout: 10))
    }

    @MainActor func testPurchaseResultAndRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString]
        app.launch()
        app.buttons["设置"].tap()
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
            app.buttons["设置"].tap()
            XCTAssertTrue(app.buttons["unlockUnlimited"].waitForExistence(timeout: 5))
            return
        }
        XCTAssertTrue(app.staticTexts["已解锁"].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        app.buttons["设置"].tap()
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
