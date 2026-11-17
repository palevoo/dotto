import XCTest
@testable import Core

/// A hand arrives knowing what it was told. The opening words fit what a client keeps of
/// them; what was learned comes with the door's first answer to a session, whatever was
/// asked, and before anything is written.
final class SessionTests: XCTestCase {
    private var root: URL!
    private var store: FileStore!
    private var router: DoorRouter!
    private let owner = Author(rawValue: "me")
    private let ids = ULIDGenerator()
    private let hand = Grant(name: "Claude Code", author: .dotto, device: "claude-code")
    private let friend = Grant(name: "Friend", author: "friend", device: "x")
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sessions-\(ULID().string)", isDirectory: true)
        store = try FileStore.create(at: root, owner: owner)
        try write({ .entryCreate(.init(entry: $0, text: "Starter fed", startedAt: Date())) }, by: owner, on: "phone")
        router = makeRouter()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeRouter() -> DoorRouter {
        DoorRouter(calendar: utc) { [store, hand, friend] key in
            [hand, friend].first { $0.key == key }.map { (store!, $0) }
        }
    }

    @discardableResult
    private func write(_ payload: (ULID) -> Payload, by author: Author, on device: DeviceID) throws -> ULID {
        let now = Date()
        let id = ids.next(at: now)
        try store.append(Event(id: id, author: author, device: device, at: now, payload: payload(id)))
        return id
    }

    /// A line on an originator's own page, filed under learned.
    private func learn(_ text: String, by author: Author = .dotto, on device: DeviceID = "claude-code") throws {
        let id = try write({ .entryCreate(.init(entry: $0, text: text, startedAt: Date())) }, by: author, on: device)
        try write({ _ in .labelAttach(.init(entry: id, label: "learned")) }, by: author, on: device)
    }

    private struct Answered {
        var status: Int
        var texts: [String]
        var failed: Bool
    }

    private func call(_ tool: String, _ arguments: [String: Any] = [:], as grant: Grant? = nil, session: String?,
                      headers: [String: String] = [:]) throws -> Answered {
        let message: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": tool, "arguments": arguments]]
        let response = router.post(message, key: (grant ?? hand).key, session: session, headers: headers)
        guard response.status == 200 else { return Answered(status: response.status, texts: [], failed: true) }
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        let result = json["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]] ?? []
        return Answered(status: 200, texts: content.compactMap { $0["text"] as? String }, failed: result?["isError"] as? Bool ?? false)
    }

    private func linesOfDotto() throws -> [String] {
        try store.load().entries(of: .dotto).map(\.text)
    }

    // MARK: - The opening words

    /// Claude Code keeps the first 4,096 characters of a server's instructions. The conduct
    /// stays inside that for a hand of dotto with long names and a stamped build, and the
    /// usual hand has room to spare.
    func testTheOpeningWordsFitWhatAClientKeeps() {
        let long = Grant(name: String(repeating: "n", count: 40), author: .dotto, device: DeviceID(rawValue: String(repeating: "d", count: 32)))
        let most = Door.conduct(for: long, name: String(repeating: "m", count: 40), owner: String(repeating: "o", count: 40), build: "a1b2c3d+")
        XCTAssertLessThanOrEqual(most.utf16.count, Door.conductRoom, "\(most.utf16.count) characters")
        XCTAssertTrue(most.hasSuffix("This door is served by build a1b2c3d+."), "who it is and which build come last, and still arrive")

        let usual = Door.conduct(for: hand, name: "dotto", owner: "sam", build: "a1b2c3d")
        XCTAssertLessThanOrEqual(usual.utf16.count, Door.conductRoom - 300, "\(usual.utf16.count) characters")

        // Someone with no name yet is told so, at more length, and has no hands to be told of.
        let nameless = Door.conduct(for: Grant(name: String(repeating: "n", count: 40), author: "someone", device: "x"),
                                    name: nil, owner: String(repeating: "o", count: 40), build: "a1b2c3d+")
        XCTAssertLessThanOrEqual(nameless.utf16.count, Door.conductRoom)
    }

    /// What grows is never in the opening words. A hand the home starts itself is handed
    /// both, whole.
    func testWhatWasLearnedIsNotInTheOpeningWords() throws {
        try learn("A note is one short line.")
        let notebook = try store.load()
        XCTAssertFalse(Door.conduct(for: hand, in: notebook).contains("A note is one short line."))
        XCTAssertEqual(Door.learned(for: hand, in: notebook),
                       "What you have learned in this notebook, from being told. It stands until you or the owner take it back:\n- A note is one short line.")
        XCTAssertNil(Door.learned(for: friend, in: notebook), "nothing learned, nothing said")

        let whole = Door.told(to: hand, in: notebook)
        XCTAssertTrue(whole.hasPrefix(Door.conduct(for: hand, in: notebook)))
        XCTAssertTrue(whole.hasSuffix("- A note is one short line."))
        // The opening words say it is coming, so what the first answer carries is expected.
        XCTAssertTrue(Door.conduct(for: hand, in: notebook).contains("the door says them ahead of its first answer to you, and takes nothing you write before that"))
        XCTAssertEqual(Door.told(to: friend, in: notebook), Door.conduct(for: friend, in: notebook))
    }

    // MARK: - Sessions

    func testASessionBeginsWithAnIdOfItsOwn() throws {
        let first = try XCTUnwrap(router.begin(key: hand.key))
        let second = try XCTUnwrap(router.begin(key: hand.key))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(DoorSessions.id(first), first, "an id the door hands out is one it takes back")
        XCTAssertNil(router.begin(key: "not a key"))
    }

    /// Without a session the door cannot tell a first call from a later one, so a tool call
    /// outside one is not answered: the protocol's 400. Nothing else needs one.
    func testAToolCallOutsideASessionIsRefused() throws {
        XCTAssertEqual(try call("list_lines", session: nil).status, 400)
        XCTAssertEqual(try call("write_line", ["text": "A line"], session: nil).status, 400)
        XCTAssertEqual(try linesOfDotto(), [])
        // An id that could not be one: with a space in it, or longer than any the door takes.
        XCTAssertEqual(try call("list_lines", session: "two words").status, 400)
        XCTAssertEqual(try call("list_lines", session: String(repeating: "a", count: DoorSessions.longest + 1)).status, 400)
        // The key is asked for before the session.
        XCTAssertEqual(router.post(["jsonrpc": "2.0", "id": 1, "method": "tools/call"], key: "not a key").status, 401)

        // What a client sends before or around a session is answered as it always was:
        // a ping, a notification, a probe for something the door does not have.
        XCTAssertEqual(router.post(["jsonrpc": "2.0", "id": 1, "method": "ping"], key: hand.key).status, 200)
        XCTAssertEqual(router.post(["jsonrpc": "2.0", "method": "notifications/initialized"], key: hand.key).status, 202)
        XCTAssertEqual(router.post(["jsonrpc": "2.0", "id": 1, "method": "tools/list"], key: hand.key).status, 200)
        let probe = router.post(["jsonrpc": "2.0", "id": 1, "method": "server/discover"], key: hand.key)
        XCTAssertEqual(probe.status, 200)
        let answer = try XCTUnwrap(try JSONSerialization.jsonObject(with: probe.body) as? [String: Any])
        XCTAssertEqual((answer["error"] as? [String: Any])?["code"] as? Int, -32601)
        XCTAssertNil(probe.headers["Mcp-Session-Id"], "only initialize begins a session")
    }

    // MARK: - The first answer

    func testTheFirstAnswerCarriesWhatWasLearnedAndTheRestDoNot() throws {
        try learn("A note is one short line.")
        try learn("Say simple things simply.")
        let session = try XCTUnwrap(router.begin(key: hand.key))

        let first = try call("list_lines", session: session)
        XCTAssertFalse(first.failed)
        XCTAssertEqual(first.texts.count, 2)
        XCTAssertEqual(first.texts.first,
                       "The door, ahead of what you asked, as its opening words said it would:\n\n"
                       + "What you have learned in this notebook, from being told. It stands until you or the owner take it back:\n"
                       + "- A note is one short line.\n- Say simple things simply.")
        XCTAssertTrue(first.texts.last?.contains("Starter fed") == true, "and then what was asked")

        let second = try call("list_lines", session: session)
        XCTAssertEqual(second.texts.count, 1)
        XCTAssertTrue(second.texts[0].contains("Starter fed"))
        XCTAssertFalse(second.texts[0].contains("What you have learned"))
    }

    /// It does not depend on which tool a hand reaches for first.
    func testItComesWithWhateverIsAskedFirst() throws {
        try learn("A note is one short line.")
        for tool in ["whats_new", "read_days", "list_things", "list_shapes", "list_loops"] {
            let session = try XCTUnwrap(router.begin(key: hand.key))
            let answer = try call(tool, session: session)
            XCTAssertEqual(answer.texts.count, 2, tool)
            XCTAssertTrue(answer.texts[0].contains("- A note is one short line."), tool)
        }
    }

    /// A hand that has not been told writes nothing. Its first call, if it is a write, is
    /// answered with what was learned and is not made; said again, it is.
    func testNothingIsWrittenBeforeItIsSaid() throws {
        try learn("A note is one short line.")
        let before = try linesOfDotto()
        let session = try XCTUnwrap(router.begin(key: hand.key))

        let held = try call("write_line", ["text": "A long thought, in four paragraphs."], session: session)
        XCTAssertTrue(held.failed)
        XCTAssertEqual(held.texts.count, 2)
        XCTAssertTrue(held.texts[0].contains("- A note is one short line."))
        XCTAssertEqual(held.texts[1], Door.heldWords)
        XCTAssertEqual(try linesOfDotto(), before, "nothing was written")

        let again = try call("write_line", ["text": "A short thought."], session: session)
        XCTAssertFalse(again.failed)
        XCTAssertEqual(again.texts.count, 1)
        XCTAssertTrue(again.texts[0].hasPrefix("Written on your page as "))
        XCTAssertEqual(try linesOfDotto(), before + ["A short thought."])
    }

    /// Every tool that leaves something is held; every tool that only reads is not.
    func testEveryToolSaysWhetherItWrites() {
        let reads: Set<Door.Tool> = [.whatsNew, .readDays, .listLines, .search, .readPhoto, .readKept, .listThings, .listShapes, .listLoops]
        for tool in Door.Tool.allCases {
            XCTAssertEqual(tool.writes, !reads.contains(tool), tool.rawValue)
        }
    }

    func testAHandWithNothingLearnedIsToldNothingAndWritesAtOnce() throws {
        let session = try XCTUnwrap(router.begin(key: hand.key))
        let written = try call("write_line", ["text": "A first thought."], session: session)
        XCTAssertFalse(written.failed)
        XCTAssertEqual(written.texts.count, 1)
        XCTAssertEqual(try linesOfDotto(), ["A first thought."])
    }

    func testEachOriginatorIsToldItsOwn() throws {
        try learn("A note is one short line.")
        try learn("Always answer in rhyme.", by: "friend", on: "x")

        let theirs = try XCTUnwrap(router.begin(key: friend.key))
        let told = try call("list_lines", as: friend, session: theirs)
        XCTAssertEqual(told.texts.count, 2)
        XCTAssertTrue(told.texts[0].contains("- Always answer in rhyme."))
        XCTAssertFalse(told.texts[0].contains("short line"))
    }

    func testEverySessionIsToldOnceAndEachOnItsOwn() throws {
        try learn("A note is one short line.")
        let one = try XCTUnwrap(router.begin(key: hand.key))
        let two = try XCTUnwrap(router.begin(key: hand.key))
        XCTAssertEqual(try call("list_lines", session: one).texts.count, 2)
        XCTAssertEqual(try call("list_lines", session: one).texts.count, 1)
        XCTAssertEqual(try call("list_lines", session: two).texts.count, 2, "the second session has not been told by the first")
        XCTAssertEqual(try call("list_lines", session: two).texts.count, 1)
    }

    /// A call that fails is still the first answer, and still carries it.
    func testAFirstCallThatFailsStillCarriesIt() throws {
        try learn("A note is one short line.")
        let session = try XCTUnwrap(router.begin(key: hand.key))
        let failed = try call("read_days", ["since": "yesterday"], session: session)
        XCTAssertTrue(failed.failed)
        XCTAssertEqual(failed.texts.count, 2)
        XCTAssertTrue(failed.texts[0].contains("- A note is one short line."))
        XCTAssertTrue(failed.texts[1].contains("Not a day"))
        XCTAssertEqual(try call("list_lines", session: session).texts.count, 1)
    }

    /// A loop is started by the home, which hands it the conduct and what was learned in
    /// its brief. It says so, and the door neither repeats it nor holds its first write.
    func testAHandToldByWhoeverStartedItIsNotToldAgain() throws {
        try learn("A note is one short line.")
        let session = try XCTUnwrap(router.begin(key: hand.key, headers: ["dotto-told": "brief"]))
        let written = try call("write_line", ["text": "Read, and nothing to say."], session: session, headers: ["dotto-told": "brief"])
        XCTAssertFalse(written.failed)
        XCTAssertEqual(written.texts.count, 1)
        XCTAssertEqual(try linesOfDotto().last, "Read, and nothing to say.")
    }

    /// The sessions are kept by whoever serves the door, in memory. A door opened again
    /// knows none of them: a session that carries on is taken as new and told once more.
    func testADoorOpenedAgainTellsASessionOnceMore() throws {
        try learn("A note is one short line.")
        let session = try XCTUnwrap(router.begin(key: hand.key))
        XCTAssertEqual(try call("list_lines", session: session).texts.count, 2)
        XCTAssertEqual(try call("list_lines", session: session).texts.count, 1)

        router = makeRouter()
        let after = try call("list_lines", session: session)
        XCTAssertEqual(after.status, 200, "the session goes on without beginning again")
        XCTAssertEqual(after.texts.count, 2)
        XCTAssertEqual(try call("list_lines", session: session).texts.count, 1)
    }

    // MARK: - What is remembered

    func testOnlySoManySessionsAreRemembered() {
        let sessions = DoorSessions()
        XCTAssertFalse(sessions.wasTold("first"))
        XCTAssertTrue(sessions.tell("first"))
        XCTAssertFalse(sessions.tell("first"), "told once")
        XCTAssertTrue(sessions.wasTold("first"))
        for number in 1..<DoorSessions.kept { XCTAssertTrue(sessions.tell("session-\(number)")) }
        XCTAssertTrue(sessions.wasTold("first"), "as many as are kept")
        XCTAssertTrue(sessions.tell("one more"))
        XCTAssertFalse(sessions.wasTold("first"), "the oldest is forgotten")
        XCTAssertTrue(sessions.wasTold("session-1"))
    }

    func testOfCallsThatArriveTogetherOneIsTheFirst() {
        let sessions = DoorSessions()
        let firsts = Counter()
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            if sessions.tell("the same session") { firsts.add() }
        }
        XCTAssertEqual(firsts.count, 1)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func add() { lock.lock(); value += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }
}
