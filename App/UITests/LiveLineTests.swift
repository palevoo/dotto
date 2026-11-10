import XCTest

/// The live line, driven as a thumb would: tap it, type, paste, press Return. Runs on a
/// booted simulator with `xcodebuild test -scheme Margin`. The notebook on that simulator is
/// whatever it has; a fresh one is kept on the phone when asked.
final class LiveLineTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = .onAFreshNotebook()
    }

    private var liveLine: XCUIElement { app.textViews["live-line"] }

    /// The live line keeps its words between launches now, so a test that needs it empty
    /// first stores whatever an earlier run left in it.
    private func startEmpty() {
        XCTAssertTrue(liveLine.waitForExistence(timeout: 5))
        guard let left = liveLine.value as? String, !left.isEmpty else { return }
        liveLine.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        liveLine.typeText("\n")
        let empty = expectation(for: NSPredicate(format: "value == ''"), evaluatedWith: liveLine)
        XCTAssertEqual(XCTWaiter.wait(for: [empty], timeout: 5), .completed, "the leftover words are stored")
    }

    /// Each character typed stays, and so does the keyboard. Return stores the words as a
    /// line on the page and leaves the field empty with the keyboard still up.
    func testTypingKeepsTheKeyboardAndReturnStores() {
        startEmpty()
        liveLine.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard comes up on a tap")

        let words = "Typed one key at a time \(Int.random(in: 1000...9999))"
        liveLine.typeText(words)
        XCTAssertTrue(app.keyboards.firstMatch.exists, "the keyboard stays while typing")
        XCTAssertEqual(liveLine.value as? String, words)

        liveLine.typeText("\n")
        XCTAssertTrue(app.staticTexts[words].waitForExistence(timeout: 5), "Return stores the words on the page")
        XCTAssertEqual(liveLine.value as? String, "", "the field is empty again")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "the keyboard stays for the next line")
    }

    /// Words typed wait in the line when the keyboard goes: a tap elsewhere on the page puts
    /// the keyboard away and stores nothing. Return, later, stores them.
    func testWordsWaitWhenTheKeyboardGoes() {
        startEmpty()
        liveLine.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))

        // A line on the page to tap on, stored the ordinary way.
        let earlier = "Stored before \(Int.random(in: 1000...9999))"
        liveLine.typeText(earlier + "\n")
        XCTAssertTrue(app.staticTexts[earlier].waitForExistence(timeout: 5))

        let words = "Waiting words \(Int.random(in: 1000...9999))"
        liveLine.typeText(words)

        // A tap on a line of the page, away from the live line: the first tap only puts the
        // keyboard away, and the line does not open.
        app.staticTexts[earlier].tap()
        let gone = expectation(for: NSPredicate(format: "count == 0"), evaluatedWith: app.keyboards)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, "the keyboard goes")
        XCTAssertEqual(liveLine.value as? String, words, "the words wait in the line")
        XCTAssertFalse(app.staticTexts[words].exists, "nothing was stored")

        liveLine.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        liveLine.typeText("\n")
        XCTAssertTrue(app.staticTexts[words].waitForExistence(timeout: 5), "Return stores the waiting words")
        XCTAssertEqual(liveLine.value as? String, "")
    }

    /// A passage with line breaks, pasted, lands as one line of words and waits in the
    /// field. Nothing is stored until Return.
    func testPastedPassageWaitsAsOneLine() {
        let stamp = Int.random(in: 1000...9999)
        UIPasteboard.general.string = "First part \(stamp)\nsecond part\n\n  third part\n"
        let flat = "First part \(stamp) second part third part"

        startEmpty()
        liveLine.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        liveLine.press(forDuration: 1.2)
        let paste = app.menuItems["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5), "the edit menu offers Paste")
        paste.tap()

        let landed = expectation(for: NSPredicate(format: "value == %@", flat), evaluatedWith: liveLine)
        if XCTWaiter.wait(for: [landed], timeout: 5) != .completed {
            // Say what is on screen instead, so the failure explains itself.
            let stored = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "\(stamp)")).count
            XCTFail("paste did not land in the field; field holds \(String(describing: liveLine.value)); "
                    + "lines on the page with the stamp: \(stored); alerts: \(app.alerts.count); "
                    + "menu items: \(app.menuItems.allElementsBoundByIndex.map(\.label))\n\(app.debugDescription.prefix(4000))")
        }
        XCTAssertFalse(app.staticTexts[flat].exists, "nothing is stored by a paste")
        XCTAssertTrue(app.keyboards.firstMatch.exists)

        liveLine.typeText("\n")
        XCTAssertTrue(app.staticTexts[flat].waitForExistence(timeout: 5), "Return stores the pasted words")
        XCTAssertEqual(liveLine.value as? String, "")
    }
}
