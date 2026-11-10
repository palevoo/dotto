import XCTest

/// Keeping photos in Photos too, as a thumb meets it in Setup: one step, switched on with one
/// tap and off with one more. Photos asks once, for adding only; the sheet is answered here
/// when it comes, and does not come when the simulator has already said yes.
final class PhotoKeepingTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-seed-photos"]
        app.launch()
        let keep = app.buttons["Keep it on this phone for now"]
        if keep.waitForExistence(timeout: 2) { keep.tap() }
    }

    func testTheStepIsSwitchedOnAndOff() {
        let date = app.buttons["date"]
        XCTAssertTrue(date.waitForExistence(timeout: 15), "the date header is there")
        date.tap()
        let setup = app.buttons["Setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5), "the calendar sheet offers Setup")
        setup.tap()
        XCTAssertTrue(app.staticTexts["Keep photos in Photos"].waitForExistence(timeout: 5), "Setup has the step")

        let on = app.buttons["Keep photos in Photos too"]
        let off = app.buttons["Stop"]
        // An earlier run on this simulator may have left it on.
        if !on.exists, off.exists { off.tap() }
        XCTAssertTrue(on.waitForExistence(timeout: 5), "off, the step offers to keep them")
        XCTAssertTrue(app.staticTexts["A photo taken here could also be saved to Photos"].exists)

        on.tap()
        // Photos' own sheet, the first time only.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        XCTAssertTrue(app.staticTexts["Each photo taken here is also saved to Photos, at full size"].waitForExistence(timeout: 5),
                      "on, the step says what happens to each photo")
        XCTAssertTrue(off.exists)

        off.tap()
        XCTAssertTrue(on.waitForExistence(timeout: 5), "one tap takes it back")
    }
}
