import XCTest

/// Shapes as a thumb meets them. The seed makes a thing, the fig, puts the second line with
/// it and its state on it, and a fact on the first line.
final class ShapeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = .onAFreshNotebook(seeded: true)
    }

    /// The page says what a line is in one quiet row. The line's page names the thing; tap
    /// it and the thing's page has its state and the line.
    func testALineSaysWhatItIsAndTheThingHasAPage() {
        let shapes = app.staticTexts.matching(identifier: "shapes")
        let fact = shapes.matching(NSPredicate(format: "label == %@", "pages 2 · #book")).firstMatch
        XCTAssertTrue(fact.waitForExistence(timeout: 15), "the first line wears its fact, then its tag")
        // The second line is with the fig and, since the seed also marks it, a todo with a due moment.
        let belongs = shapes.matching(NSPredicate(format: "label BEGINSWITH %@", "the fig · todo · due")).firstMatch
        XCTAssertTrue(belongs.exists, "the second line wears the thing it belongs to and its facts")

        app.staticTexts["Meaning comes later, says the second page"].tap()
        let with = app.buttons["with-the fig"]
        XCTAssertTrue(with.waitForExistence(timeout: 5), "the line's page names the thing")
        with.tap()

        XCTAssertTrue(app.staticTexts["thing-name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["thing-name"].label, "the fig")

        // What it is, as a paragraph; where it comes from, as a link; and what its line
        // pointed at, kept, one tap away with its words.
        XCTAssertEqual(app.staticTexts["thing-about"].label, "A fig cutting taken in September, rooted in water and potted in November.")
        XCTAssertTrue(app.links["thing-source"].exists || app.buttons["thing-source"].exists, "the source is a way out")
        XCTAssertFalse(app.staticTexts["fact-about"].exists, "and not repeated in the list of facts")
        let kept = app.buttons["thing-kept"]
        XCTAssertTrue(kept.waitForExistence(timeout: 5), "the kept page is on the thing's page")
        kept.tap()
        XCTAssertTrue(app.staticTexts["kept-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["kept-title"].label, "Rooting fig cuttings")
        XCTAssertEqual(app.staticTexts["kept-words"].label, "Take a cutting in late summer. Keep it in water until roots show, then pot it.")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["thing-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["plant"].exists, "and its kind")
        XCTAssertTrue(app.otherElements["fact-state"].exists || app.staticTexts["potted"].exists, "its state is a fact on it")
        XCTAssertTrue(app.staticTexts["Meaning comes later, says the second page"].exists, "the line belongs to it")
    }
}
