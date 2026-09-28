import XCTest

final class PauseUITests: XCTestCase {
    func testDialNavigationAndManualSessionFlow() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["beginMeditation"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.scrollViews.count, 0)
        let time = app.staticTexts["dialTime"].firstMatch
        let original = time.label
        let dial = app.descendants(matching: .any).matching(identifier: "durationDial").firstMatch
        XCTAssertTrue(dial.exists)
        // A clockwise quarter turn from twelve to three adds about fifteen minutes.
        let top = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.06))
        let right = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.50))
        top.press(forDuration: 0.1, thenDragTo: right)
        XCTAssertNotEqual(time.label, original)
        XCTAssertTrue(app.buttons["beginMeditation"].exists, "Releasing the dial must not start a session")
        app.buttons["beginMeditation"].tap()
        let systemAlert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if systemAlert.waitForExistence(timeout: 3), systemAlert.buttons["Allow"].exists { systemAlert.buttons["Allow"].tap() }
        XCTAssertTrue(app.buttons["pauseMeditation"].waitForExistence(timeout: 5))
        app.buttons["pauseMeditation"].tap()
        XCTAssertTrue(app.buttons["resumeMeditation"].exists)
        app.buttons["End session"].tap()
        app.buttons["Discard session"].tap()
        app.buttons["Open journal"].tap()
        XCTAssertTrue(app.staticTexts["calendarLegend"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.scrollViews.count, 0)
        XCTAssertTrue(app.staticTexts["calendarLegend"].isHittable)
        app.buttons["addMeditation"].tap()
        XCTAssertTrue(app.buttons["saveSession"].waitForExistence(timeout: 3))
        app.buttons["saveSession"].tap()
        XCTAssertTrue(app.staticTexts["total mins"].waitForExistence(timeout: 3))
        app.buttons["Back to meditation"].tap()
        XCTAssertTrue(app.buttons["beginMeditation"].waitForExistence(timeout: 3))
    }
    func testScreenshotsAndExistingSettings() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-seed-history", "-six-week-month", "-AppleLocale", "en_GB"]; app.launch()
        XCTAssertTrue(app.buttons["beginMeditation"].waitForExistence(timeout: 10))
        attach(app, "Meditate")
        app.buttons["Sounds & bells"].tap()
        XCTAssertTrue(app.staticTexts["Ambient volume"].waitForExistence(timeout: 3))
        attach(app, "Sounds and bells")
        app.buttons["Done"].tap()
        app.buttons["Open journal"].tap()
        XCTAssertTrue(app.staticTexts["calendarMonth"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["calendarLegend"].isHittable)
        XCTAssertEqual(app.scrollViews.count, 0)
        attach(app, "Journal six weeks")
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Make it yours"].waitForExistence(timeout: 5))
        attach(app, "Settings")
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        // Capture after the native navigation/sheet transition has settled.
        Thread.sleep(forTimeInterval: 0.6)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
