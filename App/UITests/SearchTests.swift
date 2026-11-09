import XCTest

/// Search, as a thumb meets it: from the calendar sheet, words typed, the line found, opened.
final class SearchTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-seed-photos"]
        app.launch()
        let keep = app.buttons["Keep it on this phone for now"]
        if keep.waitForExistence(timeout: 2) { keep.tap() }
    }

    /// The seeded line "Two pages from a book, for the viewer" is found by a word of its own
    /// in any case, and the fig by its name; a word nobody wrote finds nothing.
    func testWordsFindALineAndAThing() {
        let date = app.buttons["date"]
        XCTAssertTrue(date.waitForExistence(timeout: 15))
        date.tap()
        let search = app.buttons["search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "the calendar sheet offers Search")
        search.tap()

        let field = app.textFields["search-words"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the field takes the keyboard on its own")
        field.typeText("VIEWER")
        let found = app.staticTexts["Two pages from a book, for the viewer"]
        XCTAssertTrue(found.waitForExistence(timeout: 5), "the line is found, case aside")
        XCTAssertEqual(app.staticTexts.matching(identifier: "found").count, 1, "and only it")

        field.tap()
        field.typeText(" fig")
        XCTAssertTrue(app.staticTexts["Nothing for “VIEWER fig”."].waitForExistence(timeout: 5), "every word must appear in one line")

        field.tap()
        for _ in 0..<10 { field.typeText(XCUIKeyboardKey.delete.rawValue) }
        field.typeText("fig")
        let thing = app.buttons["found-thing-the fig"]
        XCTAssertTrue(thing.waitForExistence(timeout: 5), "a thing is found by its name")
        XCTAssertTrue(app.staticTexts["Meaning comes later, says the second page"].exists, "and the line that is with it")

        app.staticTexts["Meaning comes later, says the second page"].tap()
        XCTAssertTrue(app.buttons["line-menu"].waitForExistence(timeout: 5), "a found line opens")
    }
}
