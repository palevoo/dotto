import XCTest

/// The weather of a line as a thumb meets it. The seed puts what a source would say on the
/// quiet line, and leaves a line with a place and nothing said yet. No test asks the real
/// source: the seed answers in its place.
final class WeatherTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = .onAFreshNotebook(seeded: true)
    }

    /// On the line's page, under its time: one quiet line. Tap it for the day before, the
    /// wind, and whose numbers they are. The day page says nothing of it.
    func testALineSaysWhatItWasLikeAndTheRestOnATap() {
        let quiet = app.line("A quiet afternoon")
        XCTAssertTrue(quiet.waitForExistence(timeout: 15))
        let hints = app.staticTexts.matching(identifier: "shapes").allElementsBoundByIndex.map(\.label)
        XCTAssertFalse(hints.contains { $0.contains("light rain") }, "the day page stays as it was")
        quiet.tap()

        let weather = app.buttons["line-weather"]
        XCTAssertTrue(weather.waitForExistence(timeout: 5), "the line's page says the weather")
        // In the simulator's own units, whichever they are.
        XCTAssertTrue(weather.label.hasSuffix("· light rain"), weather.label)
        XCTAssertFalse(app.buttons["line-weather-credit"].exists, "the rest waits behind a tap")

        weather.tap()
        let more = app.staticTexts.matching(identifier: "line-weather-more")
        XCTAssertTrue(more.firstMatch.waitForExistence(timeout: 5))
        let rows = more.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(rows.contains { $0.hasSuffix("of rain in the day before") }, "\(rows)")
        XCTAssertTrue(rows.contains { $0.hasPrefix("wind ") && $0.hasSuffix("from the north-west") }, "\(rows)")
        XCTAssertTrue(app.buttons["line-weather-credit"].exists, "and says whose numbers they are")
    }

    /// Off until switched on in Setup. Switched on, a line that has a place gets its weather
    /// with nothing else asked of anyone.
    func testSwitchedOnInSetupALineWithAPlaceGetsItsWeather() {
        let placed = app.line("Olives under the nets")
        XCTAssertTrue(placed.waitForExistence(timeout: 15))
        placed.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["line-weather"].exists, "nothing is said until Setup says to ask")
        app.navigationBars.buttons.firstMatch.tap()

        let date = app.buttons["date"]
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        date.tap()
        let setup = app.buttons["Setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        setup.tap()
        XCTAssertTrue(app.staticTexts["Its place, rounded to a kilometre, and its day are sent to Open-Meteo. Nothing else"].waitForExistence(timeout: 5),
                      "Setup says what leaves the phone before anything does")
        app.buttons["weather-on"].tap()
        XCTAssertTrue(app.staticTexts["Each line with a place keeps the weather of its hour"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(placed.waitForExistence(timeout: 5))
        placed.tap()
        let weather = app.buttons["line-weather"]
        XCTAssertTrue(weather.waitForExistence(timeout: 10), "the line has its weather")
        XCTAssertTrue(weather.label.hasSuffix("· overcast"), weather.label)
    }
}
