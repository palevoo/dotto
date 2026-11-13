import XCTest

/// A phone on its own. Until someone else holds a key to the notebook nothing reads it, and
/// Setup says so, so that silence under a line is not taken for a fault.
final class NothingReadsTests: XCTestCase {
    private func openSetup(_ app: XCUIApplication) {
        let date = app.buttons["date"]
        XCTAssertTrue(date.waitForExistence(timeout: 15), "the date header is there")
        date.tap()
        let setup = app.buttons["Setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5), "the calendar sheet offers Setup")
        setup.tap()
        XCTAssertTrue(app.buttons["open-loops"].waitForExistence(timeout: 5), "Setup has a Loops step")
    }

    private let said = "Nothing reads this notebook yet, so nothing answers. That begins in dotto on a Mac"

    func testANotebookNobodyElseHoldsAKeyToSaysSo() {
        continueAfterFailure = false
        let app = XCUIApplication.onAFreshNotebook()
        openSetup(app)
        XCTAssertTrue(app.staticTexts[said].exists, "a new notebook says nothing reads it")
    }

    func testOnceAKeyIsHandedOutItIsNotSaid() {
        continueAfterFailure = false
        // The seed hands a key to an originator of its own.
        let app = XCUIApplication.onAFreshNotebook(seeded: true)
        openSetup(app)
        XCTAssertFalse(app.staticTexts[said].exists, "someone holds a key, so it is not said")
    }
}
