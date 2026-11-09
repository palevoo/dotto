import XCTest

/// Changing a line's words where they stand on the page, as a thumb does it: hold, Edit,
/// type, and either Return or a tap anywhere else stores them. One field holds the
/// keyboard at a time: taking it for a row takes it from the live line.
final class EditInPlaceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        let keep = app.buttons["Keep it on this phone for now"]
        if keep.waitForExistence(timeout: 2) { keep.tap() }
    }

    private var liveLine: XCUIElement { app.textViews["live-line"] }
    /// The one row whose words are a field. There is at most one.
    private var rowField: XCUIElement { app.textViews["line-words"] }

    /// A line stored the ordinary way, so there is something on the page to change.
    private func store(_ words: String) {
        XCTAssertTrue(liveLine.waitForExistence(timeout: 5))
        liveLine.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        if let left = liveLine.value as? String, !left.isEmpty { liveLine.typeText("\n") }
        liveLine.typeText(words + "\n")
        XCTAssertTrue(app.staticTexts[words].waitForExistence(timeout: 5), "the line is on the page")
    }

    /// Hold a line, Edit: its words become a field in the same place and the keyboard is
    /// its. A tap on another line stores the changed words and puts the keyboard away;
    /// nothing opens.
    func testEditWhereItStandsAndATapElsewhereStores() {
        let stamp = Int.random(in: 1000...9999)
        let other = "Another line \(stamp)"
        let words = "Words to change \(stamp)"
        store(other)
        store(words)

        app.staticTexts[words].press(forDuration: 1.0)
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "the hold offers Edit")
        edit.tap()

        XCTAssertTrue(rowField.waitForExistence(timeout: 5), "the words are a field where they stood")
        XCTAssertEqual(rowField.value as? String, words)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard is the row's")
        XCTAssertEqual(app.textViews.count, 2, "the live line and the row being edited")

        rowField.typeText(", changed")
        let changed = words + ", changed"
        XCTAssertEqual(rowField.value as? String, changed, "each key stays, and so does the keyboard")
        XCTAssertTrue(app.keyboards.firstMatch.exists)

        app.staticTexts[other].tap()
        let gone = expectation(for: NSPredicate(format: "count == 0"), evaluatedWith: app.keyboards)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, "the keyboard goes")
        XCTAssertTrue(app.staticTexts[changed].waitForExistence(timeout: 5), "the changed words are stored")
        XCTAssertFalse(rowField.exists, "only the live line is a field again")
        XCTAssertFalse(app.navigationBars.buttons.firstMatch.exists, "the other line did not open")
    }

    /// Return in the row stores, like it does in the live line.
    func testReturnStoresTheEdit() {
        let words = "Return stores this \(Int.random(in: 1000...9999))"
        store(words)

        app.staticTexts[words].press(forDuration: 1.0)
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()

        XCTAssertTrue(rowField.waitForExistence(timeout: 5))
        XCTAssertEqual(rowField.value as? String, words)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        rowField.typeText(" twice\n")

        XCTAssertTrue(app.staticTexts[words + " twice"].waitForExistence(timeout: 5), "Return stores the words")
        let gone = expectation(for: NSPredicate(format: "count == 0"), evaluatedWith: app.keyboards)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, "and the keyboard goes with the edit")
    }
}
