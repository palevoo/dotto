import XCTest

/// The first line of a new day, after a day taller than the screen. The line is stored; the
/// question is whether the page goes to it.
final class NewDayTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = .onAFreshNotebook(yesterday: 300)
    }

    func testTheFirstLineOfADayIsOnScreenAfterReturn() {
        let liveLine = app.textViews["live-line"]
        XCTAssertTrue(liveLine.waitForExistence(timeout: 15))
        liveLine.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let words = "The first line of today \(Int.random(in: 1000...9999))"
        liveLine.typeText(words + "\n")
        XCTAssertEqual(liveLine.value as? String, "", "the line is stored")

        // Known since 5 November and reproduced on 10 November: the page stays at the end of
        // yesterday, whose section is the only one the lazy stack has measured, and today's
        // is never reached. Expected to fail until the page's rows are the stack's children;
        // when it passes, this expectation fails and is to be taken out.
        XCTExpectFailure("the page does not reach the first line of a new day")
        let line = app.staticTexts[words]
        XCTAssertTrue(line.waitForExistence(timeout: 5), "the line is on the page")
        XCTAssertTrue(line.isHittable, "and on screen, above the live line")
    }
}
