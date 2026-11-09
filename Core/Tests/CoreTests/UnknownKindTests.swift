import XCTest
@testable import Core

/// A device on an older build meets an event kind it does not know. The line is read, the
/// file keeps its count, the fold leaves it alone, and it is written back as it was.
final class UnknownKindTests: XCTestCase {
    let line = #"{"at":"2026-11-10T09:00:00.000Z","author":"me","device":"iphone","id":"01KA0000000000000000000001","kind":"future.kind","payload":{"n":3,"on":"01KA0000000000000000000000","words":"later","yes":true,"list":[1,"a",null]}}"#

    func testAnUnknownKindIsCarriedNotDropped() throws {
        let event = try JSONLines.decode(line)
        XCTAssertNil(event.kind)
        XCTAssertEqual(event.kindName, "future.kind")
        guard case .unknown(let kind, let payload) = event.payload else { return XCTFail("carried as unknown") }
        XCTAssertEqual(kind, "future.kind")
        XCTAssertEqual(payload, .object(["n": .number(3), "on": .string("01KA0000000000000000000000"), "words": .string("later"),
                                         "yes": .bool(true), "list": .array([.number(1), .string("a"), .null])]))

        // Written back, the same bytes: keys sorted as the file has them.
        let back = try JSONLines.encode(event)
        let expected = #"{"at":"2026-11-10T09:00:00.000Z","author":"me","device":"iphone","id":"01KA0000000000000000000001","kind":"future.kind","payload":{"list":[1,"a",null],"n":3,"on":"01KA0000000000000000000000","words":"later","yes":true}}"#
        XCTAssertEqual(back, expected)
    }

    func testAFileWithAnUnknownKindStillReadsWhole() throws {
        let known = Event(id: ULID(timestamp: Date(timeIntervalSince1970: 1_794_000_000)), author: "me", device: "iphone",
                          at: Date(timeIntervalSince1970: 1_794_000_000),
                          payload: .entryCreate(.init(entry: ULID(timestamp: Date(timeIntervalSince1970: 1_794_000_000)), text: "Known", startedAt: Date(timeIntervalSince1970: 1_794_000_000))))
        let text = try JSONLines.encode(known) + "\n" + line + "\n"
        let events = try JSONLines.decodeAll(text)
        XCTAssertEqual(events.count, 2, "the count per file holds, so cursors into it do too")

        let notebook = Notebook(owner: "me", events: events)
        XCTAssertEqual(notebook.entries.map(\.text), ["Known"])
        XCTAssertEqual(notebook.eventCount, 2)
        XCTAssertEqual(notebook.trail, [], "nothing is said about what is not understood")
    }
}
