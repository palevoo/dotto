import XCTest

/// Loops as a thumb meets them: a proposal waiting in Setup, set with one tap; a loop set
/// from the phone in a sentence of its own.
final class LoopTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-seed-photos"]
        app.launch()
        let keep = app.buttons["Keep it on this phone for now"]
        if keep.waitForExistence(timeout: 2) { keep.tap() }
    }

    /// Through the date to Setup, to Loops. The seed's proposal waits; Set it, and it runs.
    /// Then a loop of your own, set from the form, is on the list.
    func testAProposalIsSetWithOneTapAndALoopIsSetFromThePhone() {
        let date = app.buttons["date"]
        XCTAssertTrue(date.waitForExistence(timeout: 15), "the date header is there")
        date.tap()
        let setup = app.buttons["Setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5), "the calendar sheet offers Setup")
        setup.tap()
        let loops = app.buttons["open-loops"]
        XCTAssertTrue(loops.waitForExistence(timeout: 5), "Setup has a Loops step")
        // The notebook on the simulator keeps what earlier runs did: the proposal waits the
        // first time, and is a loop already on the runs after.
        let waits = app.staticTexts["1 proposed, waiting for you"].exists
        loops.tap()

        let proposal = app.staticTexts["proposal-Bring the walks"]
        if !waits {
            XCTAssertTrue(app.staticTexts["loop-Bring the walks"].waitForExistence(timeout: 5), "the proposal was set in an earlier run")
            XCTAssertFalse(proposal.exists)
        } else {
            XCTAssertTrue(proposal.waitForExistence(timeout: 5), "the proposal waits on the Loops page")
            app.buttons["take-Bring the walks"].tap()
            XCTAssertTrue(app.staticTexts["loop-Bring the walks"].waitForExistence(timeout: 5), "one tap, and it is a loop")
            XCTAssertFalse(proposal.exists, "and no longer a proposal")
        }

        let name = "Evening look \(Int.random(in: 1000...9999))"
        let field = app.textFields["loop-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.buttons["loop-set"].tap()
        XCTAssertTrue(app.staticTexts["loop-\(name)"].waitForExistence(timeout: 5), "the loop is set from the phone")
        XCTAssertTrue(app.staticTexts["has not run yet"].firstMatch.exists)
    }
}
