import XCTest
@testable import Core

/// A dot is four arcs that meet at four points, one on each side of a box. Four numbers, a
/// proportion and a turn say which dot.
final class DotTests: XCTestCase {
    let centre = Dot.Point(x: 50, y: 50)

    func distance(_ a: Dot.Point, _ b: Dot.Point) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    /// The point halfway along a curve that starts at `from`.
    func halfway(from: Dot.Point, _ curve: Dot.Curve) -> Dot.Point {
        Dot.Point(
            x: (from.x + 3 * curve.control1.x + 3 * curve.control2.x + curve.end.x) / 8,
            y: (from.y + 3 * curve.control1.y + 3 * curve.control2.y + curve.end.y) / 8
        )
    }

    func assertPoint(_ point: Dot.Point, x: Double, y: Double, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(point.x, x, accuracy: 1e-9, message, file: file, line: line)
        XCTAssertEqual(point.y, y, accuracy: 1e-9, message, file: file, line: line)
    }

    func testAllHalvesIsACircle() {
        let outline = Dot(top: 0.5, right: 0.5, bottom: 0.5, left: 0.5).outline(size: 80, centre: centre)
        XCTAssertEqual(outline.curves.count, 4)
        var from = outline.start
        for curve in outline.curves {
            XCTAssertEqual(distance(curve.end, centre), 40, accuracy: 1e-9)
            XCTAssertEqual(distance(halfway(from: from, curve), centre), 40, accuracy: 0.02, "a curve strays from a true arc by less than a part in two thousand")
            from = curve.end
        }
    }

    func testTheEdgeComesBackToWhereItStarted() {
        let outline = Dot(top: 0.58, right: 0.55, bottom: 0.53, left: 0.46, proportion: 1.09, turn: -8).outline(size: 60, centre: centre)
        let last = outline.curves[3].end
        assertPoint(last, x: outline.start.x, y: outline.start.y)
    }

    func testTheArcsMeetWhereTheNumbersSay() {
        let outline = Dot(top: 0.58, right: 0.55, bottom: 0.53, left: 0.46).outline(size: 100, centre: centre)
        assertPoint(outline.start, x: 0, y: 46, "on the left side, 46 down")
        assertPoint(outline.curves[0].end, x: 58, y: 0, "on the top side, 58 across")
        assertPoint(outline.curves[1].end, x: 100, y: 55, "on the right side, 55 down")
        assertPoint(outline.curves[2].end, x: 53, y: 100, "on the bottom side, 53 across")
    }

    func testAWiderDotIsAsMuchShorter() {
        // A proportion of 1.21 is 1.1 wide and 1 / 1.1 tall.
        let outline = Dot(top: 0.5, right: 0.5, bottom: 0.5, left: 0.5, proportion: 1.21).outline(size: 100, centre: centre)
        assertPoint(outline.curves[1].end, x: 50 + 55, y: 50)
        assertPoint(outline.curves[2].end, x: 50, y: 50 + 50 / 1.1)
    }

    func testAQuarterTurnPutsTheTopPointOnTheRight() {
        let outline = Dot(top: 0.58, right: 0.5, bottom: 0.5, left: 0.5, turn: 90).outline(size: 100, centre: centre)
        assertPoint(outline.curves[0].end, x: 100, y: 58, "clockwise, as a page turns it")
    }

    func testAnOriginatorsDotFollowsFromItsId() {
        let one: Author = "k3x9q2"
        let other: Author = "p7m4zd"
        XCTAssertEqual(one.dot, one.dot, "the same every time it is asked")
        XCTAssertEqual(one.dot, Author(rawValue: "k3x9q2").dot, "and wherever it is asked")
        XCTAssertNotEqual(one.dot, other.dot)
        XCTAssertEqual(Author.dotto.dot, .dotto, "the notebook's own wears Dotto's dot")
        for author in [one, other, "me", "health"] as [Author] {
            let dot = author.dot
            for meets in [dot.top, dot.right, dot.bottom, dot.left] {
                XCTAssertTrue((0.36...0.64).contains(meets), "no point sits near a corner")
            }
            XCTAssertTrue((0.86...1.16).contains(dot.proportion))
            XCTAssertTrue((-24.0...24.0).contains(dot.turn))
        }
    }

    func testDottosOwnDotIsTheFirstThereIsToChooseFrom() {
        XCTAssertEqual(Dot.all.first, .dotto)
        XCTAssertEqual(Set(Dot.all).count, Dot.all.count, "no two alike")
    }

    func testTheEdgeAsAnSVGPath() {
        let outline = Dot(top: 0.5, right: 0.5, bottom: 0.5, left: 0.5).outline(size: 100, centre: centre)
        XCTAssertEqual(
            outline.svg,
            "M0 50 C0 22.39 22.39 0 50 0 C77.61 0 100 22.39 100 50 C100 77.61 77.61 100 50 100 C22.39 100 0 77.61 0 50 Z"
        )
    }
}
