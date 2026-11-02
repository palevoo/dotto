import XCTest
@testable import Core

final class ULIDTests: XCTestCase {
    func testShapeAndRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_793_613_600.123) // 2026-11-02 10:00:00.123 UTC
        let ulid = ULID(timestamp: date)
        XCTAssertEqual(ulid.string.count, 26)
        XCTAssertEqual(ulid.milliseconds, 1_793_613_600_123)
        XCTAssertEqual(ulid.timestamp.timeIntervalSince1970, 1_793_613_600.123, accuracy: 0.0005)

        let parsed = ULID(ulid.string)
        XCTAssertEqual(parsed, ulid)
        XCTAssertEqual(ULID(ulid.string.lowercased()), ulid)
    }

    func testRandomBytesRoundTrip() {
        let random: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB]
        let ulid = ULID(milliseconds: 42, random: random)
        XCTAssertEqual(ulid.randomBytes, random)
        XCTAssertEqual(ulid.milliseconds, 42)
    }

    func testSortsByTime() {
        let earlier = ULID(timestamp: Date(timeIntervalSince1970: 1000))
        let later = ULID(timestamp: Date(timeIntervalSince1970: 1001))
        XCTAssertLessThan(earlier, later)
        XCTAssertEqual([later, earlier].sorted(), [earlier, later])
    }

    func testRejectsBadStrings() {
        XCTAssertNil(ULID("too-short"))
        XCTAssertNil(ULID("01ARZ3NDEKTSV4RRFFQ69G5FAI")) // I is not in the alphabet
        XCTAssertNil(ULID("8ZZZZZZZZZZZZZZZZZZZZZZZZZ")) // first char over 7 overflows 48 bits
        XCTAssertNotNil(ULID("01ARZ3NDEKTSV4RRFFQ69G5FAV"))
    }

    func testGeneratorIsMonotonicWithinAMillisecond() {
        let generator = ULIDGenerator()
        let moment = Date(timeIntervalSince1970: 1_793_613_600)
        var previous = generator.next(at: moment)
        for _ in 0..<1000 {
            let next = generator.next(at: moment)
            XCTAssertGreaterThan(next, previous)
            XCTAssertEqual(next.milliseconds, previous.milliseconds)
            previous = next
        }
    }

    func testGeneratorSurvivesClockGoingBackwards() {
        let generator = ULIDGenerator()
        let first = generator.next(at: Date(timeIntervalSince1970: 2000))
        let second = generator.next(at: Date(timeIntervalSince1970: 1000))
        XCTAssertGreaterThan(second, first)
    }

    func testCodable() throws {
        let ulid = ULID()
        let data = try JSONEncoder().encode([ulid])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[\"\(ulid.string)\"]")
        XCTAssertEqual(try JSONDecoder().decode([ULID].self, from: data), [ulid])
        XCTAssertThrowsError(try JSONDecoder().decode(ULID.self, from: Data("\"nope\"".utf8)))
    }
}
