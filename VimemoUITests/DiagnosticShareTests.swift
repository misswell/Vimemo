import XCTest

final class DiagnosticShareTests: XCTestCase {
    @MainActor func testDiagnosticsCanBeSharedFromSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-library", UUID().uuidString]
        app.launch()
        let settings = app.buttons.matching(NSPredicate(format: "label == %@", "设置")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let export = app.buttons["exportDiagnostics"]
        for _ in 0..<5 {
            if export.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(export.isHittable)
        export.tap()
        let title = app.descendants(matching: .any)["LP.CaptionBar.TopCaption"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "The share sheet must contain a real diagnostic file")
        XCTAssertTrue(title.label.contains("Vimemo-diagnostics"), "The activity header must identify the diagnostic file")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "diagnostic-log-share"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
