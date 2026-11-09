import XCTest

/// A note that cites a line, as a thumb meets it. The seed puts a note under the photo line
/// that cites a second line.
final class CitationTests: XCTestCase {
    private var app: XCUIApplication!
    private let photoLine = "Two pages from a book, for the viewer"
    private let citedLine = "Meaning comes later, says the second page"
    private let note = "Both pages say the same; see the second."

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-seed-photos"]
        app.launch()
        let keep = app.buttons["Keep it on this phone for now"]
        if keep.waitForExistence(timeout: 2) { keep.tap() }
    }

    /// Under the note, the cited line stands by its day and first words. Tap it and its own
    /// page opens, where the thread says it is cited.
    func testACitationIsAJump() {
        let line = app.staticTexts[photoLine]
        XCTAssertTrue(line.waitForExistence(timeout: 15), "the seeded line is on the page")
        line.tap()
        XCTAssertTrue(app.staticTexts[note].waitForExistence(timeout: 5), "the note is under the line")

        let cite = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cite-'")).firstMatch
        XCTAssertTrue(cite.waitForExistence(timeout: 5), "the note shows the line it cites")
        XCTAssertTrue(cite.label.contains(citedLine), "the citation carries the cited line's first words")
        cite.tap()

        XCTAssertTrue(app.staticTexts[citedLine].waitForExistence(timeout: 5), "the cited line's page opens")
        XCTAssertTrue(app.staticTexts["cited"].waitForExistence(timeout: 5), "its thread says it is cited")
    }
}
