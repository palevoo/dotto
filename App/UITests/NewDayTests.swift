import XCTest

/// The first line of a new day, after a day taller than the screen: the page goes to it, and
/// opens on it. Until 10 November it did neither: a day was one child of the lazy stack, with
/// no height the page knew until it was drawn, so the page stopped at the end of yesterday.
final class NewDayTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = .onAFreshNotebook(yesterday: 300)
    }

    func testTheFirstLineOfADayIsOnScreenAfterReturn() {
        let liveLine = app.textViews["live-line"]
        XCTAssertTrue(liveLine.waitForExistence(timeout: 15))
        liveLine.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let words = "The first line of today \(Int.random(in: 1000...9999))"
        liveLine.typeText(words + "\n")
        XCTAssertEqual(liveLine.value as? String, "", "the line is stored")

        let line = app.staticTexts[words]
        XCTAssertTrue(line.waitForExistence(timeout: 5), "the line is on the page")
        XCTAssertTrue(line.isHittable, "and on screen, above the live line")

        // The page opens at the end of today, not of the tall day before it.
        app.terminate()
        app.launch()
        XCTAssertTrue(line.waitForExistence(timeout: 15), "after a relaunch the line is on the page")
        XCTAssertTrue(line.isHittable, "and on screen")
    }

    /// Written from far up the page, in the middle of the day before: the page comes down to
    /// the line.
    func testTheFootOfThePageIsReachedAfterGoingUp() {
        let liveLine = app.textViews["live-line"]
        XCTAssertTrue(liveLine.waitForExistence(timeout: 15))
        // Up into yesterday, far from the foot.
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        liveLine.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let words = "Written from far up the page \(Int.random(in: 1000...9999))"
        liveLine.typeText(words + "\n")
        let line = app.staticTexts[words]
        XCTAssertTrue(line.waitForExistence(timeout: 5), "the line is on the page")
        XCTAssertTrue(line.isHittable, "and the page came down to it")
    }

    /// A day picked in the calendar comes to the top of the page with its first line, and
    /// the pinned date follows; today picked comes back to today's first line.
    func testADayPickedInTheCalendarComesToTheTop() throws {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.component(.day, from: now)
        // On the first of a month yesterday is on another page of the calendar.
        try XCTSkipIf(today == 1, "yesterday is in the month before")
        let yesterday = calendar.component(.day, from: calendar.date(byAdding: .day, value: -1, to: now)!)

        let liveLine = app.textViews["live-line"]
        XCTAssertTrue(liveLine.waitForExistence(timeout: 15))
        liveLine.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let words = "Today has a line \(Int.random(in: 1000...9999))"
        liveLine.typeText(words + "\n")
        XCTAssertTrue(app.staticTexts[words].waitForExistence(timeout: 5))
        // The keyboard goes, so the date can be tapped on a clear page.
        app.staticTexts[words].tap()

        let date = app.buttons["date"]
        let todayLabel = date.label
        date.tap()
        let cell = app.buttons["\(yesterday)"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "the calendar shows yesterday")
        cell.tap()
        let first = app.staticTexts["A line from yesterday, number 1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5), "yesterday's first line is on the page")
        XCTAssertTrue(first.isHittable, "and on screen")
        let moved = expectation(for: NSPredicate(format: "label != %@", todayLabel), evaluatedWith: date)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed, "the pinned date says yesterday")

        date.tap()
        let back = app.buttons["\(today)"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.staticTexts[words].waitForExistence(timeout: 5), "today's line is on the page again")
        XCTAssertTrue(app.staticTexts[words].isHittable)
    }
}
