import XCTest

/// The inbox as one flow, answered in place; the pages over shapes from the calendar sheet.
final class InboxTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = .onAFreshNotebook(seeded: true)
    }

    private func openCalendar() {
        let date = app.buttons["date"]
        XCTAssertTrue(date.waitForExistence(timeout: 15))
        date.tap()
    }

    /// A reply under your line is a row; Reply opens a field under it; Return writes the
    /// reply under the line, which the line's page then shows.
    func testAReplyIsAnsweredFromTheInbox() {
        openCalendar()
        let inbox = app.buttons["inbox"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 5))
        inbox.tap()

        let reply = app.buttons["inbox-reply"].firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 5), "a reply under your line can be answered here")
        reply.tap()
        let field = app.textViews["inbox-reply-words"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let words = "Answered from the inbox \(Int.random(in: 1000...9999))"
        field.typeText(words + "\n")
        XCTAssertFalse(field.exists, "the field goes with the reply")

        // Back on the page, the line's own page holds the conversation with the new reply.
        app.navigationBars.buttons.firstMatch.tap()
        let line = app.staticTexts["Two pages from a book, for the viewer"].firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        line.tap()
        XCTAssertTrue(app.buttons["line-menu"].waitForExistence(timeout: 5), "the line's page opened")
        XCTAssertTrue(app.staticTexts[words].waitForExistence(timeout: 5), "the reply is under the line")
    }

    /// Todos and the things of a kind are pages reached from the calendar sheet.
    func testTodosAndKindPages() {
        openCalendar()
        let todos = app.buttons["todos"]
        XCTAssertTrue(todos.waitForExistence(timeout: 5), "the sheet offers the todos")
        todos.tap()
        XCTAssertTrue(app.staticTexts["Todos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Meaning comes later, says the second page"].exists, "the seeded todo is listed")

        app.navigationBars.buttons.firstMatch.tap()
        openCalendar()
        let plants = app.buttons["kind-plant"]
        XCTAssertTrue(plants.waitForExistence(timeout: 5), "and the kinds of things")
        plants.tap()
        XCTAssertTrue(app.staticTexts["Plants"].waitForExistence(timeout: 5))
        // The page says what a plant has, as its shape does.
        XCTAssertEqual(app.staticTexts["kind-shape"].label, "a plant has species · state · planted · about")
        XCTAssertTrue(app.staticTexts["thing-the fig"].exists, "with the fig on the plants page")
    }
}
