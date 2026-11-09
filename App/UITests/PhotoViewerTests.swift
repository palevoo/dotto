import XCTest

/// The photo viewer, driven as a thumb would. The app is launched with `-uitest-seed-photos`,
/// which gives the notebook one line with two photos of printed words.
final class PhotoViewerTests: XCTestCase {
    private var app: XCUIApplication!
    private let seededWords = "Two pages from a book, for the viewer"

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-seed-photos"]
        app.launch()
        let keep = app.buttons["Keep it on this phone for now"]
        if keep.waitForExistence(timeout: 2) { keep.tap() }
    }

    private var viewer: XCUIElement { app.otherElements["photo-viewer"] }
    private var photo: XCUIElement { app.images["photo"].firstMatch }
    private var pageCount: XCUIElement { app.staticTexts["page-count"] }

    /// Taps the seeded line's first thumbnail and waits for the viewer.
    private func open() {
        let thumb = app.descendants(matching: .any).matching(identifier: "thumbnail").firstMatch
        XCTAssertTrue(thumb.waitForExistence(timeout: 15), "the seeded photo is on the page")
        thumb.tap()
        XCTAssertTrue(viewer.waitForExistence(timeout: 5),
                      "the viewer opens; keyboards: \(app.keyboards.count), live line: \(String(describing: app.textViews.firstMatch.value))")
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
    }

    private func wait(for predicate: String, on element: XCUIElement, _ message: String) {
        let done = expectation(for: NSPredicate(format: predicate), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 5), .completed, message)
    }

    /// Frames are structs, which a predicate cannot reach into, so a frame is read until it fits.
    private func waitForWidth(_ fits: (CGFloat) -> Bool, _ message: @autoclosure () -> String, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if fits(photo.frame.width) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail(message())
    }

    func testPinchPagesAndWords() {
        open()
        XCTAssertEqual(pageCount.label, "1 / 2")

        // Double tap: the photo grows on screen into the spot. Double tap again: back to the fit.
        let fitted = photo.frame.width
        photo.doubleTap()
        waitForWidth({ $0 > fitted * 1.3 }, "double tap zooms the photo; fitted \(fitted), now \(photo.frame.width)")
        photo.doubleTap()
        waitForWidth({ $0 < fitted * 1.1 }, "double tap returns to the fit; now \(photo.frame.width)")

        // Pinch: the same, around the fingers.
        photo.pinch(withScale: 2.5, velocity: 2)
        waitForWidth({ $0 > fitted * 1.3 }, "pinch zooms the photo; fitted \(fitted), now \(photo.frame.width)")
        photo.doubleTap()
        waitForWidth({ $0 < fitted * 1.1 }, "double tap returns to the fit; now \(photo.frame.width)")

        // Page.
        photo.swipeLeft()
        wait(for: "label == '2 / 2'", on: pageCount, "a swipe turns the page")

        // Words: swipe up raises the panel with the line's words; swipe down puts it away.
        let words = app.textViews["words"]
        XCTAssertFalse(words.isHittable, "the words wait below until asked")
        photo.swipeUp()
        XCTAssertTrue(words.waitForExistence(timeout: 5), "swipe up raises the words")
        wait(for: "hittable == true", on: words, "the words are on screen")
        XCTAssertEqual(words.value as? String, seededWords)
        photo.swipeDown()
        wait(for: "hittable == false", on: words, "swipe down puts the words away")
        XCTAssertTrue(viewer.exists, "the viewer stays; the pull was the panel's, not the transition's")

        // The button does the same.
        app.buttons["Words"].tap()
        wait(for: "hittable == true", on: words, "the words button raises the words")

        app.buttons["Close"].tap()
        wait(for: "exists == false", on: viewer, "Close shuts the viewer")
    }

    func testPullDownCloses() {
        open()
        photo.swipeDown()
        wait(for: "exists == false", on: viewer, "a pull down shuts the viewer")
    }
}
