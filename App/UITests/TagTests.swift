import XCTest

/// Tags, as a thumb meets them. The seeded line carries the tag "book".
final class TagTests: XCTestCase {
    private var app: XCUIApplication!
    private let seededWords = "Two pages from a book, for the viewer"

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-seed-photos"]
        app.launch()
        let keep = app.buttons["Keep it on this phone for now"]
        if keep.waitForExistence(timeout: 2) { keep.tap() }
    }

    /// Tapping a tag on a line's page goes back to the page, filtered by that tag: the
    /// tag stands beside the date, lines under it show, lines without it do not.
    func testTagOpensThePageFilteredByIt() {
        let line = app.staticTexts[seededWords]
        XCTAssertTrue(line.waitForExistence(timeout: 15), "the seeded line is on the page")
        line.tap()

        let tag = app.buttons["tag-book"]
        XCTAssertTrue(tag.waitForExistence(timeout: 5), "the line's page shows its tag")
        tag.tap()

        let filter = app.buttons["#book"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "the page is filtered by the tag")
        XCTAssertTrue(app.staticTexts[seededWords].waitForExistence(timeout: 5), "the tagged line is on the filtered page")
        let others = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Typed one key'"))
        XCTAssertEqual(others.count, 0, "lines without the tag are not")

        filter.tap()
        let cleared = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: filter)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed, "the x clears the filter")
    }
}
