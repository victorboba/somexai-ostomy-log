import XCTest

/// Captures App Store screenshots from the sample history. Run with scripts/screenshots.sh OstomyLog.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAppScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["-unlock", "-resetData", "-sampleData", "-skipOnboarding", "-uiTesting"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 20))
        // The sample history has five weeks in it, so the dashboard cannot be showing an empty state.
        XCTAssertTrue(app.staticTexts["Last 30 days"].exists)
        snap("01-dashboard", app)

        app.buttons["logEmptying"].tap()
        XCTAssertTrue(app.navigationBars["Log emptying"].waitForExistence(timeout: 5))
        snap("02-log-emptying", app)
        app.buttons["Cancel"].tap()

        XCTAssertTrue(app.staticTexts["Last 30 days"].waitForExistence(timeout: 5))
        app.staticTexts["Last 30 days"].tap()
        XCTAssertTrue(app.navigationBars["Last 30 days"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Average wear time"].exists)
        snap("03-summary", app)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.staticTexts["Full history"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        snap("04-history", app)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.buttons["How do I use this app?"].tap()
        XCTAssertTrue(app.staticTexts["Log an emptying"].waitForExistence(timeout: 5))
        snap("05-how-to", app)
    }

    func testPaywall() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding", "-uiTesting", "-mockPrices"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Lifetime"].waitForExistence(timeout: 20))
        snap("paywall", app)
    }

    private func snap(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
