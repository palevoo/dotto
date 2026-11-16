import XCTest
@testable import Core

final class EventTests: XCTestCase {
    let me: Author = "me"
    let phone: DeviceID = "iphone"
    let at = Date(timeIntervalSince1970: 1_793_613_600.5) // 2026-11-02 10:00:00.5 UTC

    func testEveryPayloadRoundTrips() throws {
        let entry = ULID()
        let note = ULID()
        let payloads: [Payload] = [
            .entryCreate(.init(entry: entry, text: "Measure the shelf", startedAt: at, location: .init(latitude: 54.5, longitude: -3.2, accuracy: 12))),
            .entryEdit(.init(entry: entry, text: "Measure the shelf for the brackets")),
            .entryDelete(.init(entry: entry)),
            .mediaAttach(.init(entry: entry, hash: "abc", mime: "image/jpeg", width: 1280, height: 960)),
            .noteAdd(.init(entry: entry, note: note, text: "Kept as a to-do.")),
            .noteRemove(.init(note: note)),
            .labelAttach(.init(entry: entry, label: "app")),
            .labelDetach(.init(entry: entry, label: "app")),
            .visit(.init(what: .days, since: "2026-11-01", label: "bug", count: 4)),
            .visit(.init(what: .photo, count: 1, entry: entry, hash: "abc")),
            .nameSet(.init(name: "Moss")),
            .grantCreate(.init(grant: ULID(), author: "a1b2c3", name: "Claude Code", device: "claude-code", keyHash: Grant.hash("k"), may: ["notes", "lines"])),
            .grantRevoke(.init(grant: ULID())),
        ]
        for payload in payloads {
            let event = Event(id: ULID(), author: me, device: phone, at: at, payload: payload)
            let line = try JSONLines.encode(event)
            XCTAssertFalse(line.contains("\n"))
            XCTAssertEqual(try JSONLines.decode(line), event, "round trip of \(payload.kind)")
        }
    }

    func testLineShape() throws {
        let id = ULID("01KA1C4Q6R0000000000000000")!
        let event = Event(
            id: id, author: me, device: phone, at: at,
            payload: .entryCreate(.init(entry: id, text: "Starter fed", startedAt: at))
        )
        let line = try JSONLines.encode(event)
        XCTAssertEqual(
            line,
            #"{"at":"2026-11-02T10:00:00.500Z","author":"me","device":"iphone","id":"01KA1C4Q6R0000000000000000","kind":"entry.create","payload":{"at":"2026-11-02T10:00:00.500Z","entry":"01KA1C4Q6R0000000000000000","text":"Starter fed"}}"#
        )
    }

    func testDatesWithoutFractionDecode() throws {
        let line = #"{"at":"2026-11-02T10:00:00Z","author":"me","device":"iphone","id":"01KA1C4Q6R0000000000000000","kind":"entry.delete","payload":{"entry":"01KA1C4Q6R0000000000000000"}}"#
        let event = try JSONLines.decode(line)
        XCTAssertEqual(event.at.timeIntervalSince1970, 1_793_613_600)
    }

    func testDecodeAllSkipsBlankLinesAndReportsBadOnes() throws {
        let good = try JSONLines.encode(Event(id: ULID(), author: me, device: phone, at: at, payload: .entryDelete(.init(entry: ULID()))))
        XCTAssertEqual(try JSONLines.decodeAll("\n\(good)\n\n\(good)\n").count, 2)
        XCTAssertThrowsError(try JSONLines.decodeAll("\(good)\nnot json\n")) { error in
            guard case JSONLines.DecodeError.badLine(let number, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(number, 2)
        }
    }

    /// An unknown kind fails neither the line nor the file: the vocabulary grows by addition,
    /// so it is carried as unknown. See UnknownKindTests.
    func testUnknownKindIsCarried() throws {
        let line = #"{"at":"2026-11-02T10:00:00Z","author":"me","device":"iphone","id":"01KA1C4Q6R0000000000000000","kind":"entry.explode","payload":{}}"#
        let event = try JSONLines.decode(line)
        XCTAssertNil(event.kind)
        XCTAssertEqual(event.kindName, "entry.explode")
    }
}
