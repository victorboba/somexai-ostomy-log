import XCTest

/// The core loop, driven through the real UI: log two emptyings, log an appliance change, and
/// check that the numbers the app exists to produce actually appear.
///
/// Every assertion here is on content that can only be on screen if the app genuinely worked —
/// a running total that had to be added up, a wear clock that had to start, a summary that had to
/// divide. None of them merely check that a button exists.
final class CoreLoopTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-unlock", "-resetData", "-skipOnboarding", "-uiTesting"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 20), "the dashboard never appeared")
        return app
    }

    private func logEmptying(_ app: XCUIApplication, millilitres: Int) {
        app.buttons["logEmptying"].tap()
        let chip = app.buttons["volume-\(millilitres)"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "no \(millilitres) ml button on the emptying sheet")
        chip.tap()
    }

    func testEmptyingsAddUpOnTheDashboard() {
        let app = launch()

        // An empty log says zero, not a stale number.
        XCTAssertEqual(app.staticTexts["outputToday"].label, "0 ml")

        logEmptying(app, millilitres: 250)
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5),
                      "a tap on a volume should save and close the sheet in one go")
        XCTAssertEqual(app.staticTexts["outputToday"].label, "250 ml")

        logEmptying(app, millilitres: 150)
        let total = app.staticTexts["outputToday"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertEqual(total.label, "400 ml", "the running total has to add the two emptyings up")
        XCTAssertTrue(app.staticTexts["2 emptyings"].exists)
    }

    func testAnApplianceChangeStartsTheWearClockAndReachesTheSummary() {
        let app = launch()
        logEmptying(app, millilitres: 250)

        app.buttons["log-applianceChange"].tap()
        XCTAssertTrue(app.navigationBars["Appliance change"].waitForExistence(timeout: 5))
        // A one-piece appliance is never asked what came off, which is the point of the setting.
        XCTAssertFalse(app.staticTexts["What came off"].exists)
        XCTAssertTrue(app.staticTexts["This barrier was on"].exists)
        app.buttons["Save"].tap()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        // The ring is a single combined accessibility element; `.combine` can surface it as any
        // element type depending on its children, so search by label across all types rather than
        // assuming `.other`.
        let ring = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Barrier worn")).firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 5), "the wear clock did not start after a change")

        // The 30-day card, and the summary behind it, have to have done the arithmetic.
        app.staticTexts["Last 30 days"].tap()
        XCTAssertTrue(app.navigationBars["Last 30 days"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["250 ml (8.5 fl oz)"].exists,
                      "the summary should show the one day's output in both units")
        XCTAssertTrue(app.staticTexts["Planned"].exists)
        XCTAssertTrue(app.staticTexts["Not enough changes yet"].exists,
                      "one change has nothing to measure a wear time from, and the app should say so")
    }

    func testASupplyCountsDownOnlyOnceThereIsARate() {
        let app = launch()

        app.staticTexts["Supplies"].tap()
        XCTAssertTrue(app.navigationBars["Supplies"].waitForExistence(timeout: 5))
        app.buttons["addSupply"].tap()
        XCTAssertTrue(app.navigationBars["Add a supply"].waitForExistence(timeout: 5))

        let name = app.textFields["What is it"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Barrier")

        let stepper = app.steppers.firstMatch
        XCTAssertTrue(stepper.waitForExistence(timeout: 5))
        for _ in 0..<3 { stepper.buttons.element(boundBy: 1).tap() }

        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Supplies"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Barrier"].exists)
        XCTAssertTrue(app.staticTexts["No rate yet"].exists,
                      "with no change history the app must say it has no rate rather than invent one")
        XCTAssertTrue(app.staticTexts["3 on hand · 1 per use · each barrier change"].exists)
    }
}
