import XCTest

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
