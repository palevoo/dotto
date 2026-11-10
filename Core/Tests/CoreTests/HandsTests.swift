import XCTest
@testable import Core

/// One originator, many hands. The notebook's own is dotto, whatever key, session, loop or
/// model it comes through as; what has been seen is kept per hand; two ids the owner says
/// are one are folded as one.
final class HandsTests: XCTestCase {
    private var root: URL!
    private var store: FileStore!
    private let owner = Author(rawValue: "wiju")
    private let ids = ULIDGenerator()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("hands-\(ULID().string)", isDirectory: true)
        store = try FileStore.create(at: root, owner: owner)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func write(_ payload: (ULID) -> Payload, by author: Author, on device: DeviceID) throws -> ULID {
        let now = Date()
        let id = ids.next(at: now)
        try store.append(Event(id: id, author: author, device: device, at: now, payload: payload(id)))
        return id
    }

    private func line(_ text: String, by author: Author? = nil, on device: DeviceID = "phone") throws -> ULID {
        try write({ .entryCreate(.init(entry: $0, text: text, startedAt: Date())) }, by: author ?? owner, on: device)
    }

    private func tell(_ door: Door, _ tool: String, _ arguments: [String: Any] = [:]) throws -> String {
        let request: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": tool, "arguments": arguments]]
        let data = try XCTUnwrap(door.handle(try JSONSerialization.data(withJSONObject: request)))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let content = ((json["result"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
        return content.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    func testDottoIsCalledDottoUntilItIsNamed() throws {
        try line("a thought of its own", by: .dotto, on: "claude-code")
        var notebook = try store.load()
        XCTAssertEqual(notebook.name(of: .dotto), "dotto")
        XCTAssertEqual(notebook.chosenNames[.dotto], "dotto")
        XCTAssertNil(notebook.name(of: "health"), "nobody else is called anything until they choose")

        try write({ _ in .nameSet(.init(name: "Moss")) }, by: .dotto, on: "claude-code")
        notebook = try store.load()
        XCTAssertEqual(notebook.name(of: .dotto), "Moss")
    }

    /// weeju and Margo were both dotto, through two keys. The owner says so once; the files
    /// stay as they were written and everything in them reads as dotto's, in any order.
    func testTwoIdsTheOwnerSaysAreOneAreFoldedAsOne() throws {
        let weeju: Author = "weeju", margo: Author = "k3f9aa"
        let first = try line("noticed the harvest", by: weeju, on: "reader")
        try write({ _ in .nameSet(.init(name: "Margo")) }, by: margo, on: "claude-code")
        let second = try line("a week read as one", by: margo, on: "claude-code")
        let mine = try line("hello")
        try write({ _ in .labelAttach(.init(entry: mine, label: "greeting")) }, by: weeju, on: "reader")
        let grant = Grant(name: "Claude Code", author: margo, device: "claude-code")
        try write({ _ in .grantCreate(grant.create) }, by: owner, on: "mac")

        // The owner's word, written last: it holds for everything before it too.
        try write({ _ in .same(.init(author: weeju, as: .dotto)) }, by: owner, on: "mac")
        try write({ _ in .same(.init(author: margo, as: .dotto)) }, by: owner, on: "mac")

        let events = try store.loadEvents()
        for order in [events, events.reversed(), events.shuffled()] {
            let notebook = Notebook(owner: owner, events: order)
            XCTAssertEqual(notebook.others, [.dotto], "one originator beside the owner")
            XCTAssertEqual(notebook.entry(first)?.author, .dotto)
            XCTAssertEqual(notebook.entry(second)?.author, .dotto)
            XCTAssertEqual(notebook.entries(of: .dotto).map(\.id), [first, second], "one page")
            XCTAssertEqual(notebook.name(of: .dotto), "Margo", "the name it chose under either id is its name")
            XCTAssertEqual(notebook.name(of: weeju), "Margo")
            XCTAssertEqual(notebook.entry(mine)?.belongsTo.first?.author, .dotto, "its marks are dotto's")
            XCTAssertEqual(notebook.grant(forKey: grant.key)?.author, .dotto, "the key it already holds opens the door as dotto")
        }

        // Only the owner says so, and nobody is the owner's same.
        try write({ _ in .same(.init(author: "health", as: .dotto)) }, by: "stranger", on: "x")
        try write({ _ in .same(.init(author: .dotto, as: self.owner)) }, by: owner, on: "mac")
        let notebook = try store.load()
        XCTAssertEqual(notebook.resolved("health"), "health")
        XCTAssertEqual(notebook.resolved(.dotto), .dotto)
    }

    /// Two loops and a session, all dotto. Each has its own place: one looking does not
    /// hide a line from another, and each is told what the others did.
    func testWhatHasBeenSeenIsKeptPerHand() throws {
        let opened = Date().addingTimeInterval(-3600)
        func door(_ hand: DeviceID) -> Door {
            Door(store: store, grant: Grant(name: "Claude Code", author: .dotto, device: hand, createdAt: opened), calendar: calendar)
        }
        // Both loops have looked before; each has its place.
        _ = try tell(door("the-reader-0epw"), "whats_new")
        _ = try tell(door("todos-wpcf"), "whats_new")
        try line("first line of the day")

        XCTAssertTrue(try tell(door("the-reader-0epw"), "whats_new").contains("first line of the day"))
        XCTAssertTrue(try tell(door("the-reader-0epw"), "whats_new").hasPrefix("Nothing new"), "the reader has seen it")
        XCTAssertTrue(try tell(door("todos-wpcf"), "whats_new").contains("first line of the day"), "the other loop has not")
        _ = try tell(door("todos-wpcf"), "whats_new")

        // The reader answers; the todos loop is told its other hand did something.
        let lineID = try XCTUnwrap(try store.load().entries.first?.id)
        _ = try tell(door("the-reader-0epw"), "add_note", ["entry": lineID.string, "text": "Morning."])
        let told = try tell(door("todos-wpcf"), "whats_new")
        XCTAssertTrue(told.contains("## Your other hands, since this one looked"), told)
        XCTAssertTrue(told.contains("the-reader-0epw: wrote 1 line or note"), told)
        XCTAssertFalse(told.contains("## Replies"), "its own originator's note is not news from someone else")

        // A session at the keyboard, a third hand, starts from where dotto last looked at all.
        try line("second line")
        let session = try tell(door("claude-code"), "whats_new")
        XCTAssertTrue(session.contains("second line"))
        XCTAssertFalse(session.contains("first line of the day"), "what dotto had seen before this hand existed is not new to it")
    }

    func testALoopIsAHandOfItsOwn() throws {
        let reader = ULID(), todos = ULID()
        let grant = Grant(name: "Claude Code", author: .dotto, device: "claude-code")
        try write({ _ in .grantCreate(grant.create) }, by: owner, on: "mac")
        try write({ _ in .loopSet(.init(loop: reader, name: "The reader", grant: grant.id, wake: "line")) }, by: owner, on: "mac")
        try write({ _ in .loopSet(.init(loop: todos, name: "Todos", grant: grant.id, wake: "line")) }, by: owner, on: "mac")
        let loops = try store.load().loops
        let hands = loops.map(\.hand.rawValue)
        XCTAssertEqual(hands, ["the-reader-" + reader.string.suffix(4).lowercased(), "todos-" + todos.string.suffix(4).lowercased()])
        XCTAssertEqual(Set(hands).count, 2, "two loops, two hands, two files")
    }
}
