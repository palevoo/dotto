import ImageIO
import XCTest
@testable import Core

final class DoorTests: XCTestCase {
    var root: URL!
    var store: FileStore!
    var grant: Grant!
    var door: Door!
    var wall: ULID!
    let generator = ULIDGenerator()

    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("door-tests-\(UUID().uuidString)", isDirectory: true)
        store = try FileStore.create(at: root, owner: "me")
        let at = Date(timeIntervalSince1970: 1_793_610_840) // 2026-11-02 09:14 UTC
        wall = generator.next(at: at)
        try store.append(Event(id: wall, author: "me", device: "iphone", at: at,
                               payload: .entryCreate(.init(entry: wall, text: "Camera is a black screen", startedAt: at))))
        let earlier = at.addingTimeInterval(-86_400 * 3)
        let old = generator.next(at: earlier)
        try store.append(Event(id: old, author: "me", device: "iphone", at: earlier,
                               payload: .entryCreate(.init(entry: old, text: "Olives in", startedAt: earlier))))
        grant = Grant(name: "Claude Code on this Mac", author: .weeju, device: "mac-door")
        door = Door(store: store, grant: grant, calendar: utc)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func rpc(_ method: String, _ params: [String: Any] = [:], id: Any = 1) throws -> [String: Any]? {
        let request: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        let data = try JSONSerialization.data(withJSONObject: request)
        guard let response = door.handle(data) else { return nil }
        return try JSONSerialization.jsonObject(with: response) as? [String: Any]
    }

    /// The first id in a tool's words, wherever it falls in the sentence.
    func firstID(in text: String) -> ULID? {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).lazy.compactMap { ULID(String($0)) }.first
    }

    func text(_ response: [String: Any]?) -> String {
        let result = response?["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]]
        return content?.first?["text"] as? String ?? ""
    }

    func testInitializeAndListTools() throws {
        let initialized = try rpc("initialize", ["protocolVersion": "2025-03-26", "capabilities": [:], "clientInfo": ["name": "test"]])
        let result = initialized?["result"] as? [String: Any]
        XCTAssertEqual(result?["protocolVersion"] as? String, "2025-03-26")
        XCTAssertEqual((result?["serverInfo"] as? [String: Any])?["name"] as? String, "dotto")

        let tools = (try rpc("tools/list")?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.map { $0["name"] as? String },
                       ["whats_new", "read_days", "list_lines", "search", "read_photo", "add_note", "set_label", "link", "mark_done", "set_thing", "list_things", "set_fact",
                        "propose_loop", "list_loops", "write_line", "add_line", "edit_line", "delete_line", "choose_name"])
        let conduct = result?["instructions"] as? String ?? ""
        XCTAssertTrue(conduct.contains("You have no name yet"))
    }

    /// Search finds lines by their words, newest first, names the things that match, and
    /// leaves a receipt that says what was looked for.
    func testSearchThroughTheDoor() throws {
        let made = text(try rpc("tools/call", ["name": "set_thing", "arguments": ["name": "the camera", "kind": "device"]]))
        let camera = try XCTUnwrap(firstID(in: made))
        _ = try rpc("tools/call", ["name": "add_note", "arguments": ["entry": wall.string, "text": "Fixed in the evening build."]])

        let found = text(try rpc("tools/call", ["name": "search", "arguments": ["words": "CAMERA"]]))
        XCTAssertTrue(found.hasPrefix("\(camera)  the camera  a device · 0 lines\n\n\(wall.string)  2026-11-02 09:14  Camera is a black screen"), found)
        let viaReply = text(try rpc("tools/call", ["name": "search", "arguments": ["words": "evening"]]))
        XCTAssertTrue(viaReply.contains("[in a reply: Fixed in the evening build.]"), viaReply)
        XCTAssertEqual(text(try rpc("tools/call", ["name": "search", "arguments": ["words": "tractor"]])), "Nothing for “tractor”.")
        XCTAssertTrue(text(try rpc("tools/call", ["name": "search", "arguments": [:]])).contains("words"))

        let notebook = try store.load()
        let searches = notebook.visits.filter { $0.read.what == .search }
        XCTAssertEqual(searches.map(\.what), ["searched for “CAMERA”, 1 line", "searched for “evening”, 1 line", "searched for “tractor”, 0 lines"])
        XCTAssertEqual(notebook.reads(of: notebook.entry(wall)!, calendar: utc).filter { $0.read.what == .search }.count, 2)
    }

    /// A thing is made once, lines belong to it through link, facts go on both, and the
    /// listing says it all. Exactly one value per fact.
    func testThingsAndFactsThroughTheDoor() throws {
        let made = text(try rpc("tools/call", ["name": "set_thing", "arguments": ["name": "fig", "kind": "Plant"]]))
        XCTAssertTrue(made.hasPrefix("Made fig as "), made)
        let fig = try XCTUnwrap(ULID(String(made.split(separator: " ")[3].dropLast())))

        XCTAssertTrue(text(try rpc("tools/call", ["name": "link", "arguments": ["from": wall.string, "to": fig.string]])).hasPrefix("Linked"))
        XCTAssertTrue(text(try rpc("tools/call", ["name": "set_fact", "arguments": ["on": wall.string, "key": "Yield", "number": 10, "unit": "L"]])).hasPrefix("Put yield 10 L on"))
        XCTAssertTrue(text(try rpc("tools/call", ["name": "set_fact", "arguments": ["on": fig.string, "key": "state", "words": "potted"]])).hasPrefix("Put state potted on"))

        let two = text(try rpc("tools/call", ["name": "set_fact", "arguments": ["on": fig.string, "key": "x", "words": "a", "number": 1]]))
        XCTAssertTrue(two.contains("exactly one value"), two)
        let none = text(try rpc("tools/call", ["name": "set_fact", "arguments": ["on": fig.string, "key": "x"]]))
        XCTAssertTrue(none.contains("exactly one value"), none)

        let listed = text(try rpc("tools/call", ["name": "list_things", "arguments": [:]]))
        XCTAssertTrue(listed.contains("\(fig)  fig  a plant · 1 line · state potted · by"), listed)
        let lines = text(try rpc("tools/call", ["name": "list_lines", "arguments": [:]]))
        XCTAssertTrue(lines.contains("[with fig] [yield 10 L]"), lines)
        let days = text(try rpc("tools/call", ["name": "read_days", "arguments": [:]]))
        XCTAssertTrue(days.contains("_with fig_"), days)

        // Only its own originator sets it again; a rename keeps the id and the lines.
        XCTAssertTrue(text(try rpc("tools/call", ["name": "set_thing", "arguments": ["thing": fig.string, "name": "The fig"]])).hasPrefix("Set"))
        XCTAssertEqual(try store.load().thing(fig)?.name, "The fig")
        XCTAssertEqual(try store.load().thing(fig)?.lines, [wall])
        XCTAssertTrue(text(try rpc("tools/call", ["name": "set_fact", "arguments": ["on": wall.string, "key": "yield", "on_": false]])).hasPrefix("Took yield off"))
        XCTAssertEqual(try store.load().entry(wall)?.facts, [])
        XCTAssertTrue(text(try rpc("tools/call", ["name": "set_thing", "arguments": ["thing": fig.string, "on": false]])).hasPrefix("Took back"))
        XCTAssertNil(try store.load().thing(fig))

        // Looking at the things leaves a receipt, like every read.
        XCTAssertTrue(try store.load().visits.contains { $0.read.what == .things })
    }

    /// A grant proposes a loop; it waits for the owner, who sets it with the proposal's id
    /// or declines it with a stop; the listing says which loops run and which wait.
    func testAProposedLoopWaitsForTheOwner() throws {
        XCTAssertEqual(text(try rpc("tools/call", ["name": "list_loops", "arguments": [:]])), "No loops yet.")
        let said = text(try rpc("tools/call", ["name": "propose_loop", "arguments": ["name": "Bring the walks", "wake": "clock", "at": "21:00", "brief": "Each walk as a line."]]))
        XCTAssertTrue(said.hasPrefix("Proposed Bring the walks, every day at 21:00, as "), said)
        let id = try XCTUnwrap(firstID(in: said))

        let bad = text(try rpc("tools/call", ["name": "propose_loop", "arguments": ["name": "x", "wake": "clock", "at": "soon"]]))
        XCTAssertTrue(bad.contains("Not a day"), bad)

        var notebook = try store.load()
        XCTAssertEqual(notebook.loopProposals.map(\.name), ["Bring the walks"])
        XCTAssertEqual(notebook.loopProposals.first?.grant, grant.id)
        XCTAssertEqual(notebook.loops, [])
        let listed = text(try rpc("tools/call", ["name": "list_loops", "arguments": [:]]))
        XCTAssertTrue(listed.contains("## Proposed, waiting for the owner\n\(id)  Bring the walks  every day at 21:00 · as you · “Each walk as a line.”"), listed)

        // The owner sets it: the same id, so the proposal is answered and the loop runs.
        let proposal = try XCTUnwrap(notebook.loopProposals.first)
        let now = Date()
        try store.append(Event(id: generator.next(at: now), author: "me", device: "iphone", at: now,
                               payload: .loopSet(.init(loop: proposal.id, name: proposal.name, grant: proposal.grant!, wake: proposal.wake.kind,
                                                       at: proposal.wake.at, brief: proposal.brief))))
        notebook = try store.load()
        XCTAssertEqual(notebook.loopProposals, [])
        XCTAssertEqual(notebook.loops.map(\.name), ["Bring the walks"])
        XCTAssertEqual(notebook.loops.first?.wake, .clock(hour: 21, minute: 0))
        XCTAssertTrue(text(try rpc("tools/call", ["name": "list_loops", "arguments": [:]])).hasPrefix("\(id)  Bring the walks  every day at 21:00 · as you"))

        // Another proposal, declined with a stop of its id: gone from the proposals, never a loop.
        let second = text(try rpc("tools/call", ["name": "propose_loop", "arguments": ["name": "Spy"]]))
        let declined = try XCTUnwrap(firstID(in: second))
        try store.append(Event(id: generator.next(at: now), author: "me", device: "iphone", at: now, payload: .loopStop(.init(loop: declined))))
        notebook = try store.load()
        XCTAssertEqual(notebook.loopProposals, [])
        XCTAssertEqual(notebook.loops.map(\.name), ["Bring the walks"])
        XCTAssertNotNil(notebook.loopProposal(declined), "the record of the proposal stays")
        XCTAssertTrue(try store.load().visits.contains { $0.read.what == .loops })
    }

    func testTheSameGrantFromAnotherHand() throws {
        let router = DoorRouter(calendar: utc, resolve: { [store, grant] key in key == grant!.key ? (store!, grant!) : nil })
        func call(_ headers: [String: String]) -> Int {
            let request: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                          "params": ["name": "write_line", "arguments": ["text": "A line"]]]
            let body = try! JSONSerialization.data(withJSONObject: request)
            return router.respond(HTTPRequest(method: "POST", path: "/mcp", headers: headers, body: body)).status
        }
        XCTAssertEqual(call(["authorization": "Bearer \(grant.key)"]), 200)
        XCTAssertEqual(call(["authorization": "Bearer \(grant.key)", "margin-device": "The Reader!"]), 200)
        XCTAssertEqual(call(["authorization": "Bearer nope", "margin-device": "reader"]), 401)
        let notebook = try store.load()
        let devices = notebook.entries(of: .weeju).map(\.id).compactMap { id in
            try! store.loadEvents().first { $0.id == id }?.device.rawValue
        }
        XCTAssertEqual(Set(devices), ["mac-door", "the-reader"])
    }

    func testOwnPageAndChosenName() throws {
        let written = text(try rpc("tools/call", ["name": "write_line", "arguments": ["text": "The yield went from 11% to 12.5%."]]))
        XCTAssertTrue(written.hasPrefix("Written on your page as "))
        // Not on the owner's page, on its own; and reading one's own page leaves no receipt.
        XCTAssertFalse(text(try rpc("tools/call", ["name": "read_days", "arguments": ["mine": true]])).contains("Camera is a black screen"))
        XCTAssertTrue(text(try rpc("tools/call", ["name": "read_days", "arguments": ["mine": true]])).contains("The yield went from 11% to 12.5%."))
        XCTAssertFalse(text(try rpc("tools/call", ["name": "list_lines", "arguments": [:]])).contains("The yield"))
        var notebook = try store.load()
        XCTAssertEqual(notebook.visits.count, 1)
        XCTAssertEqual(notebook.entries(of: .weeju).count, 1)
        XCTAssertEqual(notebook.entries.count, 2)

        XCTAssertEqual(text(try rpc("tools/call", ["name": "choose_name", "arguments": ["name": "Moss"]])), "You are called Moss now.")
        notebook = try store.load()
        XCTAssertEqual(notebook.name(of: .weeju), "Moss")
        let initialized = try rpc("initialize", ["protocolVersion": "2025-03-26", "capabilities": [:], "clientInfo": ["name": "test"]])
        XCTAssertTrue(((initialized?["result"] as? [String: Any])?["instructions"] as? String ?? "").contains("You are called Moss."))
        // Notes are signed with the chosen name in the day pages.
        _ = try rpc("tools/call", ["name": "add_note", "arguments": ["entry": wall.string, "text": "Rebuilt."]])
        XCTAssertTrue(text(try rpc("tools/call", ["name": "read_days", "arguments": [:]])).contains("> Moss · "))

        let noLines = Grant(name: "Reader", author: "friend", device: "x", writesLines: false)
        door = Door(store: store, grant: noLines, calendar: utc)
        XCTAssertTrue(text(try rpc("tools/call", ["name": "write_line", "arguments": ["text": "hi"]])).contains("may not write lines"))
    }

    func testWhatsNewStartsWhereTheLastLookEnded() throws {
        // Nothing has happened since this grant was made.
        XCTAssertTrue(text(try rpc("tools/call", ["name": "whats_new", "arguments": [:]])).hasPrefix("Nothing new"))

        let mine = ULID(String(text(try rpc("tools/call", ["name": "write_line", "arguments": ["text": "Two harvests so far."]])).dropFirst("Written on your page as ".count).dropLast()))!
        _ = try rpc("tools/call", ["name": "set_label", "arguments": ["entry": wall.string, "label": "bug"]])
        let now = Date()
        let reply = generator.next(at: now)
        try store.append(Event(id: reply, author: "me", device: "iphone", at: now,
                               payload: .noteAdd(.init(entry: mine, note: reply, text: "Three, counting the one Anna did."))))
        try store.append(Event(id: generator.next(at: now), author: "me", device: "iphone", at: now,
                               payload: .nameSet(.init(name: "wiju"))))
        let fresh = generator.next(at: now)
        try store.append(Event(id: fresh, author: "me", device: "iphone", at: now,
                               payload: .entryCreate(.init(entry: fresh, text: "Rain from Saturday", startedAt: now))))
        try store.append(Event(id: generator.next(at: now), author: "me", device: "iphone", at: now,
                               payload: .labelDetach(.init(entry: wall, label: "bug"))))

        let found = text(try rpc("tools/call", ["name": "whats_new", "arguments": [:]]))
        XCTAssertTrue(found.hasPrefix("4 new things since "), found)
        XCTAssertTrue(found.contains("wiju under your line \(mine) “Two harvests so far.”: Three, counting the one Anna did."), found)
        XCTAssertTrue(found.contains("\(fresh)  2026-"), found)
        XCTAssertTrue(found.contains("wiju took #bug off \(wall!)"), found)
        XCTAssertTrue(found.contains("me is called wiju now"), found)
        XCTAssertFalse(found.contains("read 0 lines"), "another grant's reads are not news")

        // The look is a receipt like any read, and the next look starts after it.
        var notebook = try store.load()
        XCTAssertEqual(notebook.visits.map(\.what), ["found nothing new", "found 4 new things"])
        XCTAssertTrue(text(try rpc("tools/call", ["name": "whats_new", "arguments": [:]])).hasPrefix("Nothing new since "))

        // A file that reaches the Mac late, with ids older than the last look, is still caught.
        let late = generator.next(at: now.addingTimeInterval(-3600))
        try store.append(Event(id: late, author: "me", device: "ipad", at: now.addingTimeInterval(-3600),
                               payload: .entryCreate(.init(entry: late, text: "Written on the iPad an hour ago", startedAt: now.addingTimeInterval(-3600)))))
        let caught = text(try rpc("tools/call", ["name": "whats_new", "arguments": [:]]))
        XCTAssertTrue(caught.contains("Written on the iPad an hour ago"), caught)
        notebook = try store.load()
        XCTAssertEqual(notebook.visits.last?.read.seen?["me.ipad.jsonl"], 1)
    }

    func testOwnLinesCanBeChangedAndDeletedByTheirAuthorOnly() throws {
        let written = text(try rpc("tools/call", ["name": "write_line", "arguments": ["text": "The second pressed better."]]))
        let mine = ULID(String(written.dropFirst("Written on your page as ".count).dropLast()))!

        XCTAssertEqual(text(try rpc("tools/call", ["name": "edit_line", "arguments": ["entry": mine.string, "text": "The first pressed better."]])), "Changed \(mine).")
        var notebook = try store.load()
        XCTAssertEqual(notebook.entry(mine)?.text, "The first pressed better.")
        XCTAssertEqual(notebook.entry(mine)?.activity.map(\.what), ["changed the words"])
        XCTAssertEqual(notebook.entry(mine)?.activity.first?.before, "The second pressed better.")

        // The owner's line is refused before anything is written, and so is a line that is not there.
        XCTAssertTrue(text(try rpc("tools/call", ["name": "edit_line", "arguments": ["entry": wall.string, "text": "x"]])).contains("not its own"))
        XCTAssertTrue(text(try rpc("tools/call", ["name": "delete_line", "arguments": ["entry": wall.string]])).contains("not its own"))
        XCTAssertTrue(text(try rpc("tools/call", ["name": "delete_line", "arguments": ["entry": ULID().string]])).contains("No line"))
        XCTAssertEqual(try store.load().entry(wall)?.text, "Camera is a black screen")

        XCTAssertEqual(text(try rpc("tools/call", ["name": "delete_line", "arguments": ["entry": mine.string]])), "Deleted \(mine).")
        notebook = try store.load()
        XCTAssertNil(notebook.entry(mine))
        XCTAssertEqual(notebook.entries(of: .weeju).count, 0)
        XCTAssertEqual(notebook.entries.count, 2)
    }

    func testLinkJoinsALaterLineToAnEarlierOneAndDoneFinishesIt() throws {
        let olives = try store.load().entries.first { $0.text == "Olives in" }!
        XCTAssertEqual(text(try rpc("tools/call", ["name": "link", "arguments": ["from": wall.string, "to": olives.id.string]])),
                       "Linked \(wall!) to \(olives.id).")
        XCTAssertEqual(text(try rpc("tools/call", ["name": "mark_done", "arguments": ["entry": olives.id.string, "by": wall.string]])),
                       "Marked \(olives.id) done by \(wall!).")

        var notebook = try store.load()
        XCTAssertEqual(notebook.entry(olives.id)?.done?.by, wall)
        XCTAssertEqual(notebook.entry(olives.id)?.done?.author, .weeju)
        XCTAssertEqual(notebook.entry(wall)?.carriesOn.map(\.to), [olives.id])
        let listed = text(try rpc("tools/call", ["name": "list_lines", "arguments": [:]]))
        XCTAssertTrue(listed.contains("[done by \(wall!)]"))
        XCTAssertTrue(listed.contains("[continues \(olives.id)]"))
        let days = text(try rpc("tools/call", ["name": "read_days", "arguments": [:]]))
        XCTAssertTrue(days.contains("_continues 2026-10-30 09:14_"))
        XCTAssertTrue(days.contains("_done by 2026-11-02 09:14_"))

        // The wrong way round is refused before anything is written.
        let backwards = try rpc("tools/call", ["name": "link", "arguments": ["from": olives.id.string, "to": wall.string]])
        XCTAssertTrue(text(backwards).contains("is not earlier"))

        _ = try rpc("tools/call", ["name": "link", "arguments": ["from": wall.string, "to": olives.id.string, "on": false]])
        _ = try rpc("tools/call", ["name": "mark_done", "arguments": ["entry": olives.id.string, "on": false]])
        notebook = try store.load()
        XCTAssertNil(notebook.entry(olives.id)?.done)
        XCTAssertEqual(notebook.entry(wall)?.carriesOn, [])

        let noLinks = Grant(name: "Reader", author: "friend", device: "x", writesLinks: false)
        door = Door(store: store, grant: noLinks, calendar: utc)
        let refused = try rpc("tools/call", ["name": "link", "arguments": ["from": wall.string, "to": olives.id.string]])
        XCTAssertTrue(text(refused).contains("may not write links"))
    }

    func testAddLinePutsALineOnTheOwnersPageUnderTheGrantsName() throws {
        let reply = text(try rpc("tools/call", ["name": "add_line", "arguments": ["text": "Aula de Grupo A1.1", "at": "2026-11-14T09:30:00Z"]]))
        XCTAssertTrue(reply.hasPrefix("Added to the owner's page as "))
        let notebook = try store.load()
        let line = notebook.entries.first { $0.text == "Aula de Grupo A1.1" }
        XCTAssertEqual(line?.author, .weeju)
        XCTAssertEqual(line?.page, "me")
        XCTAssertEqual(line?.startedAt, ISO8601.date(from: "2026-11-14T09:30:00Z"))
        XCTAssertEqual(notebook.entries(of: .weeju).count, 0)
        let listed = text(try rpc("tools/call", ["name": "list_lines", "arguments": [:]]))
        XCTAssertTrue(listed.contains("Aula de Grupo A1.1  [by weeju]"))
        let days = text(try rpc("tools/call", ["name": "read_days", "arguments": ["since": "2026-11-14"]]))
        XCTAssertTrue(days.contains("## 09:30 · weeju"))

        let bad = text(try rpc("tools/call", ["name": "add_line", "arguments": ["text": "x", "at": "Saturday"]]))
        XCTAssertTrue(bad.contains("Not a day"))
    }

    /// A line whose moment is ahead, a class on Saturday, can still be changed today: its id
    /// is of when it was written, so the change comes after it on every device.
    func testALineDatedAheadCanStillBeChanged() throws {
        let ahead = ISO8601.string(from: Date().addingTimeInterval(10 * 86_400))
        let reply = text(try rpc("tools/call", ["name": "add_line", "arguments": ["text": "Aula at nine", "at": ahead]]))
        let id = try XCTUnwrap(reply.split(separator: " ").compactMap { ULID(String($0).trimmingCharacters(in: .punctuationCharacters)) }.first)
        XCTAssertLessThanOrEqual(id, ULID(), "the id is not ahead of now")
        XCTAssertEqual(try store.load().entry(id)?.startedAt.timeIntervalSince1970 ?? 0,
                       ISO8601.date(from: ahead)!.timeIntervalSince1970, accuracy: 0.001, "the moment is")

        _ = try rpc("tools/call", ["name": "edit_line", "arguments": ["entry": id.string, "text": "Aula at half past nine"]])
        XCTAssertEqual(try store.load().entry(id)?.text, "Aula at half past nine")
    }

    func testANoteCitesTheLinesItSpeaksOf() throws {
        let olives = try store.load().entries.first { $0.text == "Olives in" }!
        let reply = text(try rpc("tools/call", ["name": "add_note", "arguments": ["entry": wall.string, "text": "Same as the olives.", "cites": [olives.id.string]]]))
        XCTAssertEqual(reply, "Noted under \(wall!), citing 1 line.")
        let notebook = try store.load()
        let note = notebook.entry(wall)!.notes.first!
        XCTAssertEqual(note.cites.map(\.to), [olives.id])
        XCTAssertEqual(notebook.entry(olives.id)?.citedBy.map(\.from), [note.id])
        let days = text(try rpc("tools/call", ["name": "read_days", "arguments": [:]]))
        XCTAssertTrue(days.contains("> _cites 2026-10-30 09:14_"))

        // A cited id that is no line is refused before anything is written.
        let bad = text(try rpc("tools/call", ["name": "add_note", "arguments": ["entry": wall.string, "text": "x", "cites": ["nope"]]]))
        XCTAssertTrue(bad.contains("No line with id"))
        XCTAssertEqual(try store.load().entry(wall)?.notes.count, 1)

        // Nobody links from a note that is not their own.
        door = Door(store: store, grant: Grant(name: "Other", author: "friend", device: "x"), calendar: utc)
        let refused = text(try rpc("tools/call", ["name": "link", "arguments": ["from": note.id.string, "to": olives.id.string]]))
        XCTAssertTrue(refused.contains("not its own"))
    }

    func testAGrantSavedBeforeLinksMayWriteThem() throws {
        let old = Data("""
        {"author":"weeju","createdAt":"2026-11-02T20:00:00.000Z","device":"mac","id":"\(ULID())","key":"k","name":"Old","writesLabels":true,"writesNotes":false}
        """.utf8)
        let grant = try JSONLines.decoder().decode(Grant.self, from: old)
        XCTAssertTrue(grant.writesLinks)
        XCTAssertFalse(grant.writesNotes)
        XCTAssertEqual(grant.scopes, "read all · write labels · write links · own page")
    }

    func testEveryReadLeavesAReceipt() throws {
        _ = try rpc("tools/call", ["name": "read_days", "arguments": ["since": "2026-11-01"]])
        _ = try rpc("tools/call", ["name": "list_lines", "arguments": ["label": "Bug"]])
        let notebook = try store.load()
        XCTAssertEqual(notebook.visits.map(\.what), ["read 1 line since 2026-11-01", "read 0 lines under #bug"])
        XCTAssertEqual(notebook.visits.first?.author, .weeju)
        XCTAssertEqual(notebook.trail.map(\.what), notebook.visits.map(\.what))

        // The wall line is on 2026-11-02, so the first read took it in; the olives line is older.
        let wallReads = notebook.reads(of: notebook.entry(wall)!, calendar: utc)
        XCTAssertEqual(wallReads.count, 1)
        let olives = notebook.entries.first { $0.text == "Olives in" }!
        XCTAssertTrue(notebook.reads(of: olives, calendar: utc).isEmpty)

        // The whole folder is still two files: the owner's and the grant's.
        XCTAssertEqual(try store.eventFiles().map(\.lastPathComponent), ["me.iphone.jsonl", "weeju.mac-door.jsonl"])
    }

    func testReadPhotoHandsBackASmallJPEG() throws {
        let hash = try store.storeMedia(Self.jpeg(width: 3000, height: 2000), fileExtension: "jpg")
        try store.append(Event(id: generator.next(), author: "me", device: "iphone", at: Date(),
                               payload: .mediaAttach(.init(entry: wall, hash: hash, mime: "image/jpeg", width: 3000, height: 2000))))

        let response = try rpc("tools/call", ["name": "read_photo", "arguments": ["entry": wall.string]])
        let content = ((response?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first
        XCTAssertEqual(content?["type"] as? String, "image")
        XCTAssertEqual(content?["mimeType"] as? String, "image/jpeg")
        let data = Data(base64Encoded: content?["data"] as? String ?? "")!
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        XCTAssertEqual(properties?[kCGImagePropertyPixelWidth] as? Int, Door.photoSide)

        let notebook = try store.load()
        XCTAssertEqual(notebook.visits.last?.read.hash, hash)
        XCTAssertEqual(notebook.reads(of: notebook.entry(wall)!, calendar: utc).count, 1)

        let missing = try rpc("tools/call", ["name": "read_photo", "arguments": ["entry": wall.string, "hash": "nope"]])
        XCTAssertTrue(text(missing).contains("No photo"))
    }

    /// A flat grey JPEG of the given size, made with ImageIO.
    static func jpeg(width: Int, height: Int) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testNotificationsGetNoReply() throws {
        let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "notifications/initialized"])
        XCTAssertNil(door.handle(data))
    }

    func testUnknownMethodAndBadJSON() throws {
        let error = try rpc("nope")?["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? Int, -32601)
        let garbage = door.handle(Data("not json".utf8))
        let parsed = try JSONSerialization.jsonObject(with: garbage!) as? [String: Any]
        XCTAssertEqual((parsed?["error"] as? [String: Any])?["code"] as? Int, -32700)
    }

    func testReadAndListWithSinceAndLabel() throws {
        let all = text(try rpc("tools/call", ["name": "read_days", "arguments": [:]]))
        XCTAssertTrue(all.contains("# 2026-10-30"))
        XCTAssertTrue(all.contains("Camera is a black screen"))

        let recent = text(try rpc("tools/call", ["name": "list_lines", "arguments": ["since": "2026-11-01"]]))
        XCTAssertTrue(recent.hasPrefix(wall.string))
        XCTAssertFalse(recent.contains("Olives"))

        _ = try rpc("tools/call", ["name": "set_label", "arguments": ["entry": wall.string, "label": "Margin"]])
        let filed = text(try rpc("tools/call", ["name": "list_lines", "arguments": ["label": "margin"]]))
        XCTAssertTrue(filed.contains("#margin"))
        XCTAssertFalse(filed.contains("Olives"))

        _ = try rpc("tools/call", ["name": "set_label", "arguments": ["entry": wall.string, "label": "margin", "on": false]])
        XCTAssertEqual(text(try rpc("tools/call", ["name": "list_lines", "arguments": ["label": "margin"]])), "No lines.")
    }

    func testNoteLandsInTheGrantsOwnFile() throws {
        let reply = text(try rpc("tools/call", ["name": "add_note", "arguments": ["entry": wall.string, "text": "Rebuilt the camera on AVFoundation."]]))
        XCTAssertEqual(reply, "Noted under \(wall!).")
        XCTAssertEqual(try store.eventFiles().map(\.lastPathComponent), ["me.iphone.jsonl", "weeju.mac-door.jsonl"])
        let notebook = try store.load()
        XCTAssertEqual(notebook.entry(wall)?.notes.first?.text, "Rebuilt the camera on AVFoundation.")
        XCTAssertEqual(notebook.entry(wall)?.notes.first?.author, .weeju)
    }

    func testScopesAndMissingLines() throws {
        let readOnly = Grant(name: "Reader", author: "friend", device: "x", writesNotes: false, writesLabels: false)
        door = Door(store: store, grant: readOnly, calendar: utc)
        let refused = try rpc("tools/call", ["name": "add_note", "arguments": ["entry": wall.string, "text": "hi"]])
        XCTAssertEqual((refused?["result"] as? [String: Any])?["isError"] as? Bool, true)
        XCTAssertTrue(text(refused).contains("may not write notes"))

        door = Door(store: store, grant: grant, calendar: utc)
        let missing = try rpc("tools/call", ["name": "add_note", "arguments": ["entry": ULID().string, "text": "hi"]])
        XCTAssertTrue(text(missing).contains("No line with id"))
        let badDay = try rpc("tools/call", ["name": "read_days", "arguments": ["since": "yesterday"]])
        XCTAssertTrue(text(badDay).contains("Not a day"))
    }

    func testRouterRefusesWithoutTheKey() throws {
        let router = DoorRouter(calendar: utc) { [store, grant] key in
            key == grant!.key ? (store!, grant!) : nil
        }
        let body = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "ping"])

        XCTAssertEqual(router.respond(HTTPRequest(method: "POST", path: "/mcp", headers: [:], body: body)).status, 401)
        XCTAssertEqual(router.respond(HTTPRequest(method: "POST", path: "/mcp", headers: ["authorization": "Bearer wrong"], body: body)).status, 401)
        XCTAssertEqual(router.respond(HTTPRequest(method: "GET", path: "/mcp", headers: [:], body: Data())).status, 405)
        XCTAssertEqual(router.respond(HTTPRequest(method: "POST", path: "/other", headers: [:], body: body)).status, 404)

        let ok = router.respond(HTTPRequest(method: "POST", path: "/mcp", headers: ["authorization": "Bearer \(grant.key)"], body: body))
        XCTAssertEqual(ok.status, 200)
        XCTAssertEqual(ok.headers["Content-Type"], "application/json")

        let notification = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "notifications/initialized"])
        XCTAssertEqual(router.respond(HTTPRequest(method: "POST", path: "/mcp", headers: ["authorization": "Bearer \(grant.key)"], body: notification)).status, 202)
    }

    func testServerOverLoopback() async throws {
        let router = DoorRouter(calendar: utc) { [store, grant] key in
            key == grant!.key ? (store!, grant!) : nil
        }
        let server = try DoorServer { router.respond($0) }
        let port = try await server.start()
        defer { server.stop() }
        XCTAssertGreaterThan(port, 0)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(grant.key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 7, "method": "tools/call",
            "params": ["name": "list_lines", "arguments": ["since": "2026-11-01"]],
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["id"] as? Int, 7)
        XCTAssertTrue(text(object).contains("Camera is a black screen"))

        request.setValue("Bearer nope", forHTTPHeaderField: "Authorization")
        let (_, refused) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((refused as? HTTPURLResponse)?.statusCode, 401)
    }

    func testGrantKeysAreLongAndDistinct() {
        let a = Grant.makeKey(), b = Grant.makeKey()
        XCTAssertEqual(a.count, 43)
        XCTAssertNotEqual(a, b)
        XCTAssertFalse(a.contains("+") || a.contains("/") || a.contains("="))
        XCTAssertEqual(Grant.hash(a).count, 64)
        XCTAssertNotEqual(Grant.hash(a), Grant.hash(b))
        XCTAssertEqual(Grant.device(for: "Claude Code"), "claude-code")
        XCTAssertEqual(Grant.device(for: "!!"), "door")
    }

    /// The grants are the owner's events in the folder, so the door is opened by the fold:
    /// the key's hash finds the grant, and the author on every event is the grant's.
    func testTheDoorOpensOnAGrantInTheNotebook() throws {
        let opened = Grant(name: "Claude Code", author: "a1b2c3", device: "claude-code")
        let revoked = Grant(name: "Old", author: "a1b2c3", device: "old")
        for grant in [opened, revoked] {
            try store.append(Event(id: generator.next(), author: "me", device: "mac", at: Date(), payload: .grantCreate(grant.create)))
        }
        try store.append(Event(id: generator.next(), author: "me", device: "mac", at: Date(), payload: .grantRevoke(.init(grant: revoked.id))))

        let router = DoorRouter(calendar: utc) { [store] key in
            (try? store!.load().grant(forKey: key)).map { (store!, $0) }
        }
        func call(_ key: String) -> HTTPResponse {
            let request: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                          "params": ["name": "write_line", "arguments": ["text": "A line"]]]
            return router.respond(HTTPRequest(method: "POST", path: "/mcp", headers: ["authorization": "Bearer \(key)"], body: try! JSONSerialization.data(withJSONObject: request)))
        }
        XCTAssertEqual(call(opened.key).status, 200)
        XCTAssertEqual(call(revoked.key).status, 401)
        XCTAssertEqual(call("").status, 401)

        let notebook = try store.load()
        XCTAssertEqual(notebook.entries(of: "a1b2c3").count, 1)
        XCTAssertEqual(try store.eventFiles().map(\.lastPathComponent), ["a1b2c3.claude-code.jsonl", "me.iphone.jsonl", "me.mac.jsonl"])
        // The hash is in the folder; the key is not.
        let text = try String(contentsOf: store.eventFile(author: "me", device: "mac"), encoding: .utf8)
        XCTAssertTrue(text.contains(opened.keyHash))
        XCTAssertFalse(text.contains(opened.key))
    }
}

/// The door's wire format, given what it should never be given.
final class DoorWireTests: XCTestCase {
    private func request(_ head: String, body: String = "") -> Data {
        Data((head + "\r\n\r\n" + body).utf8)
    }

    func testALengthBelowNothingIsNoBodyAndNoCrash() throws {
        let parsed = try XCTUnwrap(DoorServer.parse(request("POST /mcp HTTP/1.1\r\nContent-Length: -1", body: "{}")))
        XCTAssertEqual(parsed.path, "/mcp")
        XCTAssertTrue(parsed.body.isEmpty)
    }

    func testALengthThatIsNotANumberIsNoBody() throws {
        let parsed = try XCTUnwrap(DoorServer.parse(request("POST /mcp HTTP/1.1\r\nContent-Length: lots", body: "{}")))
        XCTAssertTrue(parsed.body.isEmpty)
    }

    func testABodyStillOnItsWayIsWaitedFor() {
        XCTAssertNil(DoorServer.parse(request("POST /mcp HTTP/1.1\r\nContent-Length: 10", body: "{}")))
        XCTAssertNil(DoorServer.parse(request("POST /mcp HTTP/1.1\r\nContent-Length: 9223372036854775807", body: "{}")))
    }

    func testAWholeRequestIsRead() throws {
        let parsed = try XCTUnwrap(DoorServer.parse(request("POST /mcp HTTP/1.1\r\nContent-Length: 2\r\nAuthorization: Bearer k", body: "{}")))
        XCTAssertEqual(parsed.body, Data("{}".utf8))
        XCTAssertEqual(parsed.headers["authorization"], "Bearer k")
    }

    func testNoRequestLineIsNoRequest() {
        XCTAssertNil(DoorServer.parse(request("")))
    }
}
