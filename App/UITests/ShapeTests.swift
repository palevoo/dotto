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
        // The second line is with the fig and, since the seed also marks it to do, due at a moment.
        let belongs = shapes.matching(NSPredicate(format: "label BEGINSWITH %@", "the fig · due")).firstMatch
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
        XCTAssertTrue(app.line("Meaning comes later, says the second page").exists, "the line belongs to it")
    }

    /// Read, and nothing said: a line the seed took in and left nothing under wears a mark
    /// under its time; a line written since, which nobody has got to, does not.
    ///
    /// Run on a page with a day before it. A page shorter than the screen and taller than
    /// the room above the keyboard stops answering when the keyboard comes up: found on 10
    /// November, there before, not solved. It goes away when the page no longer tracks its
    /// top row (`scrollTargetLayout`), which the pinned date and the calendar need.
    func testALineReadWithNothingSaidWearsAMark() {
        app.terminate()
        app = .onAFreshNotebook(seeded: true, yesterday: 40)
        let liveLine = app.textViews["live-line"]
        XCTAssertTrue(liveLine.waitForExistence(timeout: 15))
        XCTAssertTrue(app.otherElements["read-mark"].firstMatch.waitForExistence(timeout: 10), "a line that was read and not answered says so")
        let before = app.otherElements.matching(identifier: "read-mark").count

        liveLine.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let words = "Nobody has read this yet \(Int.random(in: 1000...9999))"
        liveLine.typeText(words + "\n")
        XCTAssertTrue(app.staticTexts[words].waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements.matching(identifier: "read-mark").count, before, "the new line has no mark")
    }

    /// A todo ends where it stands. The seeded line that is to do wears its mark under its
    /// time; a tap finishes it on the day page, and on the todos page it keeps its place,
    /// finished, where a second tap opens it again.
    func testATodoIsFinishedWhereItStands() {
        let mark = app.buttons["todo-mark"].firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 15), "the line to do wears its mark")
        XCTAssertEqual(mark.label, "To do")
        mark.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "todo-mark", "Done")).firstMatch.waitForExistence(timeout: 5),
                      "one tap and it is done, on its day")
        let shapes = app.staticTexts.matching(identifier: "shapes")
        XCTAssertTrue(shapes.matching(NSPredicate(format: "label BEGINSWITH %@", "the fig · kept")).firstMatch.waitForExistence(timeout: 5),
                      "and it no longer says when it was due")

        app.buttons["date"].firstMatch.tap()
        let todos = app.buttons["todos"]
        XCTAssertTrue(todos.waitForExistence(timeout: 5), "the todos page is still offered on the day something was finished")
        todos.tap()
        XCTAssertTrue(app.staticTexts["Todos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Meaning comes later, says the second page"].exists, "finished today, it keeps its place")
        let there = app.buttons["todo-mark"].firstMatch
        XCTAssertEqual(there.label, "Done")
        there.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "todo-mark", "To do")).firstMatch.waitForExistence(timeout: 5),
                      "a second tap opens it again")
    }

    /// What is coming has a page: the seeded event and the seeded todo that is due, each on
    /// its day. The event is not to do and wears no mark; the todo wears its own.
    func testWhatIsComingHasAPage() {
        XCTAssertTrue(app.buttons["date"].waitForExistence(timeout: 15))
        app.buttons["date"].tap()
        let coming = app.buttons["coming"]
        XCTAssertTrue(coming.waitForExistence(timeout: 5), "the sheet offers what is coming")
        coming.tap()
        XCTAssertTrue(app.staticTexts["Coming"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.line("A quiet afternoon").exists, "the event is coming")
        XCTAssertTrue(app.line("Meaning comes later, says the second page").exists, "and so is what is due")
        XCTAssertEqual(app.buttons.matching(identifier: "todo-mark").count, 1, "only what is to do wears the mark")
    }

    /// A streak's page says its run and shows its days. The seeded one began three days ago
    /// and broke yesterday: four days, one of them broken, and a run of one, today. Stopped,
    /// it says so; begun again, it is one day old.
    func testAStreakShowsItsRunAndItsDays() {
        XCTAssertTrue(app.buttons["date"].waitForExistence(timeout: 15))
        app.buttons["date"].tap()
        let streaks = app.buttons["kind-streak"]
        XCTAssertTrue(streaks.waitForExistence(timeout: 5), "streaks are a kind with a page")
        streaks.tap()
        let row = app.staticTexts["thing-no sugar"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["· 1 day"].exists, "its row says its run")
        row.tap()

        let run = app.staticTexts["streak-run"]
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        XCTAssertEqual(run.label, "1", "broken yesterday, today is the first day again")
        let summary = app.staticTexts["streak-summary"]
        XCTAssertTrue(summary.label.contains("1 broken"), summary.label)
        XCTAssertTrue(summary.label.contains("longest 2"), summary.label)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "streak-day").count, 4, "a dot for each day since it began")
        XCTAssertFalse(app.otherElements["fact-since"].exists, "what it is worked out from is not said again")
        // The line that broke it says so, here as on its day.
        let hint = app.staticTexts.matching(identifier: "line-hint").firstMatch
        XCTAssertTrue(hint.label.contains("broke"), hint.label)

        run.press(forDuration: 1.0)
        app.buttons["Begin again from today"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label == %@", "streak-run", "1")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "streak-day").count, 1, "begun again, it is one day old")
    }
}
