import XCTest

/// The live line, driven as a thumb would: tap it, type, paste, press Return. Runs on a
/// booted simulator with `xcodebuild test -scheme Margin`. The notebook on that simulator is
/// whatever it has; a fresh one is kept on the phone when asked.
final class LiveLineTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        let keep = app.buttons["Keep it on this phone for now"]
        if keep.waitForExistence(timeout: 2) { keep.tap() }
    }

    private var liveLine: XCUIElement { app.textViews.firstMatch }

    /// Each character typed stays, and so does the keyboard. Return stores the words as a
    /// line on the page and leaves the field empty with the keyboard still up.
    func testTypingKeepsTheKeyboardAndReturnStores() {
        XCTAssertTrue(liveLine.waitForExistence(timeout: 5))
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

    /// A passage with line breaks, pasted, lands as one line of words and waits in the
    /// field. Nothing is stored until Return.
    func testPastedPassageWaitsAsOneLine() {
        let stamp = Int.random(in: 1000...9999)
        UIPasteboard.general.string = "First part \(stamp)\nsecond part\n\n  third part\n"
        let flat = "First part \(stamp) second part third part"

        XCTAssertTrue(liveLine.waitForExistence(timeout: 5))
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
