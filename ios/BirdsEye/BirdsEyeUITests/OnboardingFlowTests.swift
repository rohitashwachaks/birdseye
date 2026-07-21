import XCTest

/// Regression coverage for the "wrong route" report: AA296 actually flies
/// OGG → DFW, but the free callsign database returns a stale PHX → DFW pair.
/// The lookup being wrong is not fixable from our side — being *stuck* with a
/// wrong route was the real bug, so these tests pin the correction path.
final class OnboardingFlowTests: XCTestCase {

    /// Expand the collapsed airport button, focus its field, type a code, pick the hit.
    private func chooseAirport(_ app: XCUIApplication, field: String, code: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let selector = app.buttons["airportSelect-\(field)"]
        XCTAssertTrue(selector.waitForExistence(timeout: 5), "\(field) selector missing", file: file, line: line)
        selector.tap()

        let search = app.textFields["airportSearch-\(field)"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "\(field) search field missing", file: file, line: line)
        search.tap()                       // SwiftUI needs an explicit tap for keyboard focus
        search.typeText(code)

        let result = app.buttons["airportResult-\(code)"]
        XCTAssertTrue(result.waitForExistence(timeout: 5),
                      "\(code) should be searchable", file: file, line: line)
        result.tap()
    }

    private func launchToChooseMode() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        let getStarted = app.buttons["getStartedButton"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 10), "welcome screen should appear")
        getStarted.tap()
        XCTAssertTrue(app.textFields["flightNumberField"].waitForExistence(timeout: 5),
                      "choose-mode screen should appear")
        return app
    }

    /// The escape hatch has to exist without any lookup failing first.
    func testManualRouteEntryIsAlwaysAvailable() {
        let app = launchToChooseMode()

        app.buttons["manualEntryToggle"].tap()

        // Pick OGG → DFW by hand: the pair the user actually needed.
        // OGG was missing from the airport list entirely before this fix.
        chooseAirport(app, field: "FROM", code: "OGG")
        chooseAirport(app, field: "TO", code: "DFW")

        app.buttons["confirmRouteButton"].tap()

        // Briefing should now describe the hand-entered route.
        XCTAssertTrue(app.staticTexts["OGG"].waitForExistence(timeout: 5),
                      "briefing should show the manually chosen origin")
        XCTAssertTrue(app.staticTexts["DFW"].exists)
    }

    /// A lookup that succeeds with the *wrong* city pair must still be correctable.
    /// Skips (rather than fails) when the network or the third-party API is unavailable —
    /// this test is about our UI, not their uptime.
    func testWrongLookupCanBeCorrected() throws {
        let app = launchToChooseMode()

        let field = app.textFields["flightNumberField"]
        field.tap()
        field.typeText("AA296")
        app.buttons["lookupButton"].tap()

        let fixButton = app.buttons["fixRouteButton"]
        guard fixButton.waitForExistence(timeout: 25) else {
            throw XCTSkip("flight lookup unavailable (offline or API down) — correction path covered by the manual test")
        }

        // Whatever the API said, the user can override it.
        fixButton.tap()

        chooseAirport(app, field: "FROM", code: "OGG")
        app.buttons["confirmRouteButton"].tap()

        XCTAssertTrue(app.staticTexts["ROUTE CORRECTED"].waitForExistence(timeout: 5),
                      "correcting the route should be reflected in the briefing")
        XCTAssertTrue(app.staticTexts["OGG"].exists, "corrected origin should replace the API's guess")
        XCTAssertFalse(app.staticTexts["PHX"].exists, "the stale origin must be gone")
    }

    /// The corrected route — not the API's guess — is what the HUD flies.
    func testCorrectedRouteReachesTheHUD() {
        let app = launchToChooseMode()

        app.buttons["manualEntryToggle"].tap()
        chooseAirport(app, field: "FROM", code: "OGG")
        chooseAirport(app, field: "TO", code: "DFW")
        app.buttons["confirmRouteButton"].tap()

        let start = app.buttons["startFlightButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        // HUD shows the flight bar labelled with the route's own endpoints.
        XCTAssertTrue(app.staticTexts["OGG"].waitForExistence(timeout: 5),
                      "HUD should be flying the corrected route")
    }
}
