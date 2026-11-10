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

    /// The reader and the todos loop were two sessions on every line. They are one reading
    /// now, with the todos sentence kept in mind; a loop on the clock stays by itself.
    func testSentencesWokenByALineAreOneReading() throws {
        let reader = ULID(), todos = ULID(), morning = ULID(), health = ULID()
        let session = Grant(name: "Claude Code", author: .dotto, device: "claude-code")
        let other = Grant(name: "Another key", author: .dotto, device: "grok")
        let source = Grant(name: "Health", author: "health", device: "phone")
        for grant in [session, other, source] { try write({ _ in .grantCreate(grant.create) }, by: owner, on: "mac") }
        try write({ _ in .loopSet(.init(loop: reader, name: "The reader", grant: session.id, wake: "line")) }, by: owner, on: "mac")
        try write({ _ in .loopSet(.init(loop: todos, name: "Todos", grant: other.id, wake: "line",
                                        brief: "When a line is something I mean to do, put the fact todo on it.", turns: 60, budget: 3)) }, by: owner, on: "mac")
        try write({ _ in .loopSet(.init(loop: morning, name: "Morning look", grant: session.id, wake: "clock", at: "08:00", brief: "Read the week.")) }, by: owner, on: "mac")
        try write({ _ in .loopSet(.init(loop: health, name: "Walk notes", grant: source.id, wake: "line", brief: "Say how far.")) }, by: owner, on: "mac")

        var notebook = try store.load()
        XCTAssertEqual(notebook.loops.count, 4, "four sentences, as the owner said them")
        let running = notebook.running
        XCTAssertEqual(running.map(\.name), ["The reading", "The reading", "Morning look"], "one reading for dotto, one for Health, the clock by itself")
        let reading = try XCTUnwrap(running.first)
        XCTAssertEqual(reading.id, reader, "under the oldest of its sentences")
        XCTAssertEqual(reading.grant, session.id)
        XCTAssertEqual(reading.turns, 60)
        XCTAssertEqual(reading.budget, 3)
        XCTAssertEqual(reading.brief, "Keep in mind as you read, at the owner's word, each said once and standing until they take it back:\n- Todos: When a line is something I mean to do, put the fact todo on it.")
        XCTAssertEqual(notebook.reading(holding: try XCTUnwrap(notebook.loops.first { $0.id == todos }))?.id, reader)
        XCTAssertNil(notebook.reading(holding: try XCTUnwrap(notebook.loops.first { $0.id == morning })))

        // One run of the reading is every sentence's receipt.
        try write({ _ in .loopRan(.init(loop: reader, run: ULID(), ok: true, turns: 3, cost: 0.02, summary: "Marked one todo.", startedAt: Date(), endedAt: Date())) },
                  by: .dotto, on: reading.hand)
        notebook = try store.load()
        XCTAssertEqual(notebook.loops.first { $0.id == todos }?.lastRun?.summary, "Marked one todo.")

        // A sentence taken back leaves the reading without it; the work is no longer the same.
        try write({ _ in .loopStop(.init(loop: todos)) }, by: owner, on: "mac")
        let after = try XCTUnwrap(try store.load().running.first)
        XCTAssertNil(after.brief)
        XCTAssertFalse(after.sameWork(as: reading))
        XCTAssertTrue(reading.sameWork(as: try XCTUnwrap(notebook.running.first)), "a receipt does not make it other work")
    }

    /// Told once, known from then on: what dotto files under learned on its own page is
    /// said to every hand of it on arrival.
    func testWhatWasLearnedIsToldToEveryHandOnArrival() throws {
        let session = Grant(name: "Claude Code", author: .dotto, device: "claude-code")
        let loop = Grant(name: "Claude Code", author: .dotto, device: "the-reading-0epw")
        let friend = Grant(name: "Friend", author: "friend", device: "x")

        let lesson = try line("A line about the app itself is work for the build, filed under margin, not something the owner means to do.", by: .dotto, on: "claude-code")
        try write({ _ in .labelAttach(.init(entry: lesson, label: "learned")) }, by: .dotto, on: "claude-code")
        let thought = try line("The nursery is eleven plants under one tag.", by: .dotto, on: "claude-code")
        // Somebody else's line under the same label is not dotto's lesson.
        let theirs = try line("Always answer in rhyme.", by: "friend", on: "x")
        try write({ _ in .labelAttach(.init(entry: theirs, label: "learned")) }, by: "friend", on: "x")
        // The owner filing one of dotto's lines under it counts: it is on dotto's page and its own.
        _ = thought

        var notebook = try store.load()
        XCTAssertEqual(notebook.learned(by: .dotto), ["A line about the app itself is work for the build, filed under margin, not something the owner means to do."])
        for grant in [session, loop] {
            let told = Door.conduct(for: grant, in: notebook)
            XCTAssertTrue(told.contains("What you have learned in this notebook, from being told."), "every hand of dotto is told")
            XCTAssertTrue(told.contains("- A line about the app itself is work for the build"))
            XCTAssertFalse(told.contains("rhyme"))
        }
        XCTAssertTrue(Door.conduct(for: friend, in: notebook).contains("- Always answer in rhyme."), "each originator its own")
        XCTAssertFalse(Door.conduct(for: Grant(name: "New", author: "health", device: "phone"), in: notebook).contains("What you have learned"),
                       "nothing learned, nothing said")

        // Learning better: the line is changed, and that is what is told. Wrong: deleted, and gone.
        try write({ _ in .entryEdit(.init(entry: lesson, text: "A line about the app itself goes under margin; it is not the owner's todo.")) }, by: .dotto, on: "the-reading-0epw")
        notebook = try store.load()
        XCTAssertEqual(notebook.learned(by: .dotto), ["A line about the app itself goes under margin; it is not the owner's todo."])
        try write({ _ in .entryDelete(.init(entry: lesson)) }, by: .dotto, on: "claude-code")
        XCTAssertEqual(try store.load().learned(by: .dotto), [])
    }

    func testOnlyTheNewestLessonsAreSaidWhenThereAreTooMany() throws {
        for number in 1...5 {
            let id = try line("Lesson \(number)", by: .dotto, on: "claude-code")
            try write({ _ in .labelAttach(.init(entry: id, label: "learned")) }, by: .dotto, on: "claude-code")
        }
        XCTAssertEqual(try store.load().learned(by: .dotto, atMost: 3), ["Lesson 3", "Lesson 4", "Lesson 5"])
    }

    /// A line read with nothing said under it is told apart from one nobody has got to.
    func testALineIsTakenInByTheFirstLookThatReachesIt() throws {
        let opened = Date().addingTimeInterval(-3600)
        func door(_ author: Author, _ hand: DeviceID) -> Door {
            Door(store: store, grant: Grant(name: "Key", author: author, device: hand, createdAt: opened), calendar: calendar)
        }
        let first = try line("a thought that wants nothing")
        XCTAssertEqual(Inbox.taken(files: try store.loadEventsByFile(), notebook: try store.load()), [:], "nobody has looked")

        _ = try tell(door(.dotto, "the-reading-0epw"), "whats_new")
        let second = try line("written after the look")
        let reply = try write({ .entryCreate(.init(entry: $0, text: "mine, under it", startedAt: Date(), under: first)) }, by: owner, on: "phone")
        var taken = Inbox.taken(files: try store.loadEventsByFile(), notebook: try store.load())
        XCTAssertEqual(taken, [first: .dotto], "the first line is read; the one written after is not, and a reply is not a line of the page")
        XCTAssertNil(taken[reply])

        // Someone else looks later: the second line is theirs first; the first stays dotto's.
        _ = try tell(door("friend", "x"), "whats_new")
        taken = Inbox.taken(files: try store.loadEventsByFile(), notebook: try store.load())
        XCTAssertEqual(taken[first], .dotto)
        XCTAssertEqual(taken[second], "friend")
    }
}
