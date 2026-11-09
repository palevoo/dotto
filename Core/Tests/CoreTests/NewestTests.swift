import XCTest
@testable import Core

/// A mark keeps the newest word, in any order of arrival.
final class NewestTests: XCTestCase {
    private let first = ULID(timestamp: Date(timeIntervalSince1970: 1000))
    private let second = ULID(timestamp: Date(timeIntervalSince1970: 2000))
    private let third = ULID(timestamp: Date(timeIntervalSince1970: 3000))

    func testANewerWordReplacesAnOlderOneNeverTheOtherWay() {
        var mark = Newest("on", by: second)
        XCTAssertFalse(mark.take("off", by: first), "an older word arriving late loses")
        XCTAssertEqual(mark.value, "on")
        XCTAssertEqual(mark.id, second)

        XCTAssertTrue(mark.take("off", by: third))
        XCTAssertEqual(mark.value, "off")
        XCTAssertEqual(mark.id, third)

        XCTAssertFalse(mark.take("again", by: third), "the same event does not set it twice")
        XCTAssertEqual(mark.value, "off")
    }

    func testTheSameStateFromAnyOrder() {
        struct Word: Hashable { let on: Bool }
        let words: [(ULID, Word)] = [(first, Word(on: true)), (second, Word(on: false)), (third, Word(on: true))]
        var ends: Set<Newest<Word>> = []
        for order in [[0, 1, 2], [2, 1, 0], [1, 2, 0], [0, 2, 1], [2, 0, 1], [1, 0, 2]] {
            var marks: [String: Newest<Word>] = [:]
            for index in order { marks.mark("x", words[index].1, by: words[index].0) }
            ends.insert(marks["x"]!)
        }
        XCTAssertEqual(ends.count, 1, "every order of arrival ends the same")
        XCTAssertEqual(ends.first?.on, true, "the mark reads as its value")
        XCTAssertEqual(ends.first?.id, third)
    }

    func testMarkingADictionarySaysWhetherTheWordStands() {
        var marks: [String: Newest<Int>] = [:]
        XCTAssertTrue(marks.mark("a", 1, by: second), "the first word stands")
        XCTAssertFalse(marks.mark("a", 0, by: first), "an older one does not")
        XCTAssertTrue(marks.mark("a", 2, by: third))
        XCTAssertEqual(marks["a"]?.value, 2)
        XCTAssertTrue(marks.mark("b", 9, by: first), "another key is its own mark")
    }
}
