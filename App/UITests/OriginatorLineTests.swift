import XCTest

/// A line another originator put on the owner's page, as a thumb meets it. The seed puts a
/// walk there in Health's name.
final class OriginatorLineTests: XCTestCase {
    private var app: XCUIApplication!
    private let walk = "Walk, 3.1 km, 41 min"

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-seed-photos"]
        app.launch()
        let keep = app.buttons["Keep it on this phone for now"]
        if keep.waitForExistence(timeout: 2) { keep.tap() }
    }

    /// The walk is on the page wearing Health's name. Hold it: there is Drop and no Edit.
    /// Drop, and it is gone.
    func testALineByAnotherOriginatorWearsItsNameAndDropsWithAHold() {
        let line = app.staticTexts[walk]
        XCTAssertTrue(line.waitForExistence(timeout: 15), "the walk is on the page")
        XCTAssertTrue(app.staticTexts["Health"].waitForExistence(timeout: 5), "it wears Health's name")

        line.press(forDuration: 1.0)
        let drop = app.buttons["Drop"]
        XCTAssertTrue(drop.waitForExistence(timeout: 5), "the hold offers Drop")
        XCTAssertFalse(app.buttons["Edit"].exists, "and never Edit: the words are Health's")
        drop.tap()

        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: line)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, "the line is gone from the page")
    }
}
