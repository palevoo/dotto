import XCTest

/// Tags, as a thumb meets them. The seeded line is under the tag "book".
final class TagTests: XCTestCase {
    private var app: XCUIApplication!
    private let seededWords = "Two pages from a book, for the viewer"

    override func setUp() {
        continueAfterFailure = false
        app = .onAFreshNotebook(seeded: true)
    }

    /// A tag is a thing with a page: tapping it on a line's page opens the tag's page, headed
    /// by its word, with the lines under it and no others. The calendar sheet offers the same
    /// page as a chip.
    func testATagOpensItsOwnPage() {
        let line = app.staticTexts[seededWords]
        XCTAssertTrue(line.waitForExistence(timeout: 15), "the seeded line is on the page")
        line.tap()

        let tag = app.buttons["tag-book"]
        XCTAssertTrue(tag.waitForExistence(timeout: 5), "the line's page shows its tag")
        tag.tap()

        let name = app.staticTexts["thing-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "the tag's page opened")
        XCTAssertEqual(name.label, "#book")
        XCTAssertTrue(app.staticTexts["a tag"].exists, "made by nobody")
        XCTAssertTrue(app.staticTexts[seededWords].waitForExistence(timeout: 5), "the tagged line is under it")
        let others = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Typed one key'"))
        XCTAssertEqual(others.count, 0, "lines without the tag are not")

        // Back to the page, and the same tag from the calendar sheet.
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        let date = app.buttons["date"]
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        date.tap()
        let chip = app.buttons["tag-book"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "the sheet offers the tag")
        chip.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.label, "#book")
    }
}
