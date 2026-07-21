import XCTest

/// Temporary capture harness — walks the AA296 correction flow and attaches a
/// screenshot at each step so the fix can be eyeballed, not just asserted.
final class ScreenshotCapture: XCTestCase {

    private func snap(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)

        // Simulator processes run natively, so write straight to the host for inspection.
        let dir = URL(fileURLWithPath: "/tmp/birdseye-shots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }

    func testCaptureCorrectionFlow() throws {
        let app = XCUIApplication()
        app.launch()

        let getStarted = app.buttons["getStartedButton"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 10))
        getStarted.tap()

        let field = app.textFields["flightNumberField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        snap(app, "01-choose-mode")

        field.tap()
        field.typeText("AA296")
        app.buttons["lookupButton"].tap()

        let fixButton = app.buttons["fixRouteButton"]
        guard fixButton.waitForExistence(timeout: 25) else {
            throw XCTSkip("lookup unavailable")
        }
        snap(app, "02-briefing-with-stale-route")

        fixButton.tap()
        let selector = app.buttons["airportSelect-FROM"]
        XCTAssertTrue(selector.waitForExistence(timeout: 5))
        selector.tap()
        let search = app.textFields["airportSearch-FROM"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("OGG")
        XCTAssertTrue(app.buttons["airportResult-OGG"].waitForExistence(timeout: 5))
        snap(app, "03-airport-search-OGG")
        app.buttons["airportResult-OGG"].tap()
        app.buttons["confirmRouteButton"].tap()

        XCTAssertTrue(app.staticTexts["ROUTE CORRECTED"].waitForExistence(timeout: 5))
        snap(app, "04-route-corrected")

        app.buttons["startFlightButton"].tap()
        sleep(2)
        snap(app, "05-hud-dial")
    }
}
