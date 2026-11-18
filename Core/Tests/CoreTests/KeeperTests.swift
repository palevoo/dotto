import XCTest
@testable import Core

/// The keeper holds one reading of a folder and brings it up to date by what was added.
/// Whatever it does to get there, what it hands back is what reading the whole folder at
/// that moment gives: the same events file by file, the same lines passed over, the same fold.
final class KeeperTests: XCTestCase {
    var root: URL!
    var store: FileStore!
    var keeper: NotebookKeeper!
    let me: Author = "me"
    let start = Date(timeIntervalSince1970: 1_793_613_600)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("core-tests-\(UUID().uuidString)", isDirectory: true)
        store = try FileStore.create(at: root, owner: me)
        keeper = NotebookKeeper(store: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// An event at so many seconds after the start, its id made at that moment.
    private func event(_ payload: Payload, by author: Author = "me", from device: DeviceID = "phone", at seconds: Double, random: UInt8 = 0) -> Event {
        let moment = start.addingTimeInterval(seconds)
        let id = ULID(milliseconds: UInt64(moment.timeIntervalSince1970 * 1000), random: [UInt8](repeating: random, count: 10))
        return Event(id: id, author: author, device: device, at: moment, payload: payload)
    }

    private func line(_ text: String, by author: Author = "me", from device: DeviceID = "phone", at seconds: Double) -> Event {
        let made = event(.nameSet(.init(name: "")), by: author, from: device, at: seconds)
        return Event(id: made.id, author: author, device: device, at: made.at,
                     payload: .entryCreate(.init(entry: made.id, text: text, startedAt: made.at)))
    }

    /// The keeper against a reading of the whole folder, now.
    private func assertAsReadWhole(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws {
        let kept = try keeper.current()
        let whole = try store.loadFiles()
        XCTAssertEqual(kept.files.map(\.file), whole.map(\.name), message, file: file, line: line)
        XCTAssertEqual(kept.files.map(\.events), whole.map(\.events), message, file: file, line: line)
        XCTAssertEqual(kept.unreadable.map(\.lines), whole.map(\.unreadable), message, file: file, line: line)
        let folded = Notebook(owner: store.manifest.owner, events: whole.flatMap(\.events))
        XCTAssertTrue(kept.notebook == folded, "the fold differs from a fold of the whole folder. \(message)", file: file, line: line)
    }

    /// A link from a line to a thing sits on the line and on the thing, both or neither.
    /// The fold counts on it: it looks through a thing's lines only when the line has the link.
    private func assertLinksSitOnBothEnds(_ notebook: Notebook, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let entries = ([notebook.owner] + notebook.others).flatMap { notebook.entries(of: $0) }
        var onLines: Set<ULID> = [], onThings: Set<ULID> = []
        for entry in entries {
            for link in entry.belongsTo {
                onLines.insert(link.id)
                XCTAssertEqual(notebook.thing(link.to)?.incoming.filter { $0.id == link.id }.count, 1,
                               "a line's link to a thing is not on the thing. \(message)", file: file, line: line)
            }
        }
        for thing in notebook.allThings {
            XCTAssertEqual(thing.incoming.map(\.id), thing.incoming.map(\.id).sorted(), "a thing's lines are out of order. \(message)", file: file, line: line)
            for link in thing.incoming {
                onThings.insert(link.id)
                XCTAssertEqual(notebook.entry(link.fromEntry)?.outgoing.filter { $0.id == link.id }.count, 1,
                               "a thing's link from a line is not on the line. \(message)", file: file, line: line)
            }
        }
        XCTAssertEqual(onLines, onThings, message, file: file, line: line)
    }

    private func write(_ text: String, to name: String) throws {
        try FileManager.default.createDirectory(at: store.eventsDirectory, withIntermediateDirectories: true)
        let url = store.eventsDirectory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    func testAnEmptyFolderIsAnEmptyNotebook() throws {
        let standing = try keeper.current()
        XCTAssertTrue(standing.files.isEmpty)
        XCTAssertTrue(standing.notebook.entries.isEmpty)
        try assertAsReadWhole()
    }

    func testWhatIsAddedIsReadOnFromWhereItStopped() throws {
        let bread = line("bread is rising", at: 1)
        try store.append(bread)
        try assertAsReadWhole()
        XCTAssertEqual(try keeper.current().notebook.entries.map(\.text), ["bread is rising"])

        try store.append(event(.noteAdd(.init(entry: bread.id, note: ULID(timestamp: start.addingTimeInterval(2)), text: "how long?")),
                               by: .dotto, from: "home", at: 2))
        try assertAsReadWhole()
        try store.append([line("out of the oven", at: 3), line("from the desk", from: "mac", at: 4)])
        try assertAsReadWhole()
        let standing = try keeper.current()
        XCTAssertEqual(standing.notebook.entries.map(\.text), ["bread is rising", "out of the oven", "from the desk"])
        XCTAssertEqual(standing.notebook.entry(bread.id)?.notes.map(\.text), ["how long?"])
        XCTAssertEqual(standing.files.map(\.file), ["dotto.home.jsonl", "me.mac.jsonl", "me.phone.jsonl"])
    }

    /// The point of keeping: what is newer than everything held is folded onto it, and the
    /// whole is folded again only when it has to be.
    func testOnlyWhatHasToBeIsFoldedAgain() throws {
        try store.append(line("one", at: 1))
        _ = try keeper.current()
        XCTAssertEqual(keeper.foldedAgain, 1, "the first reading")
        for second in 2...9 {
            try store.append(line("line \(second)", from: second % 2 == 0 ? "phone" : "mac", at: Double(second)))
            try store.append(event(.visit(.init(what: .inbox, count: 1)), by: .dotto, from: "home", at: Double(second) + 0.5))
            _ = try keeper.current()
        }
        _ = try keeper.current()
        XCTAssertEqual(keeper.foldedAgain, 1, "newer events, new files and nothing new")
        try store.append(line("late", from: "other-phone", at: 4.2))
        _ = try keeper.current()
        XCTAssertEqual(keeper.foldedAgain, 2, "an older event arriving late")
        try store.append(line("after", at: 20))
        _ = try keeper.current()
        XCTAssertEqual(keeper.foldedAgain, 2)
        try assertAsReadWhole()
    }

    func testNothingNewIsTheSameReading() throws {
        try store.append(line("one", at: 1))
        let first = try keeper.current()
        let second = try keeper.current()
        XCTAssertTrue(first.notebook == second.notebook)
        XCTAssertEqual(first.files.map(\.events), second.files.map(\.events))
    }

    /// The phone's line reaches the home after the home has written something newer.
    func testAnOlderEventArrivingLateIsFoldedInItsPlace() throws {
        let late = line("written first, arrives last", at: 1)
        try store.append(line("from the desk", from: "mac", at: 5))
        try store.append(event(.visit(.init(what: .inbox, count: 1)), by: .dotto, from: "home", at: 6))
        try assertAsReadWhole()
        try store.append(late)
        try assertAsReadWhole()
        XCTAssertEqual(try keeper.current().notebook.entries.map(\.text), ["written first, arrives last", "from the desk"])
    }

    /// The owner's word that two originators are one changes how what came before reads.
    func testTwoSaidToBeOneAfterBothHaveWritten() throws {
        let bread = line("bread", at: 1)
        try store.append(bread)
        try store.append(event(.noteAdd(.init(entry: bread.id, note: ULID(timestamp: start.addingTimeInterval(2)), text: "from another hand")),
                               by: .moss, from: "laptop", at: 2))
        try assertAsReadWhole()
        XCTAssertEqual(try keeper.current().notebook.entry(bread.id)?.notes.map(\.author), [.moss])
        try store.append(event(.same(.init(author: .moss, as: .dotto)), at: 3))
        try assertAsReadWhole()
        XCTAssertEqual(try keeper.current().notebook.entry(bread.id)?.notes.map(\.author), [.dotto])
    }

    /// Two readers of one walk write the same id into two files at once.
    func testOneIdInTwoFiles() throws {
        let walk = ULID.said(by: "health", at: start.addingTimeInterval(60))
        func said(from device: DeviceID) -> Event {
            Event(id: walk, author: "health", device: device, at: start.addingTimeInterval(90),
                  payload: .entryCreate(.init(entry: walk, text: "Walk, 2 km", startedAt: start.addingTimeInterval(60), page: me)))
        }
        try store.append(line("before", at: 1))
        try assertAsReadWhole()
        try store.append([said(from: "phone"), said(from: "other-phone")])
        try assertAsReadWhole()
        try store.append(said(from: "third-phone"))
        try assertAsReadWhole()
        XCTAssertEqual(try keeper.current().notebook.entries.map(\.text), ["before", "Walk, 2 km"])
    }

    func testALineStillBeingWrittenIsReadWhenItIsWhole() throws {
        let one = line("one", at: 1), two = line("two", at: 2), three = line("three", at: 3)
        try store.append(one)
        try assertAsReadWhole()
        // Half of a line, as a write under way or cut short leaves it.
        let whole = try JSONLines.encode(two)
        try write(String(whole.prefix(40)), to: "me.phone.jsonl")
        try assertAsReadWhole("half a line")
        XCTAssertEqual(try keeper.current().unreadable.map(\.lines), [[2]])
        XCTAssertEqual(try keeper.current().notebook.entries.map(\.text), ["one"])
        // The rest of it arrives.
        try write(String(whole.dropFirst(40)) + "\n", to: "me.phone.jsonl")
        try assertAsReadWhole("the rest of the line")
        XCTAssertEqual(try keeper.current().unreadable.map(\.lines), [[]])
        XCTAssertEqual(try keeper.current().notebook.entries.map(\.text), ["one", "two"])
        // A whole line with no end yet is an event already, and stays one when its end comes.
        try write(try JSONLines.encode(three), to: "me.phone.jsonl")
        try assertAsReadWhole("a line with no end")
        XCTAssertEqual(try keeper.current().notebook.entries.map(\.text), ["one", "two", "three"])
        try write("\n", to: "me.phone.jsonl")
        try assertAsReadWhole("its end")
        XCTAssertEqual(try keeper.current().files.first?.events.count, 3)
    }

    func testALineCutShortIsPassedOverAndWhatFollowsIsRead() throws {
        try store.append(line("one", at: 1))
        try write("{\"at\":\"2026-11-01T10:00:00.000Z\",\"auth", to: "me.phone.jsonl")
        try assertAsReadWhole()
        // The next write starts on a line of its own.
        try store.append(line("after the damage", at: 3))
        try assertAsReadWhole()
        let standing = try keeper.current()
        XCTAssertEqual(standing.unreadable.map(\.lines), [[2]])
        XCTAssertEqual(standing.notebook.entries.map(\.text), ["one", "after the damage"])
    }

    /// A line with no end that is then written over by something else: the event folded
    /// from it is not in the file any more, and not in the fold.
    func testAnUnfinishedLineReplacedByAnother() throws {
        try store.append(line("one", at: 1))
        try write(try JSONLines.encode(line("never finished", at: 2)), to: "me.phone.jsonl")
        try assertAsReadWhole()
        XCTAssertEqual(try keeper.current().notebook.entries.map(\.text), ["one", "never finished"])
        let url = store.eventsDirectory.appendingPathComponent("me.phone.jsonl")
        let kept = try JSONLines.encode(line("one", at: 1)) + "\n" + (try JSONLines.encode(line("something else", at: 4))) + "\n"
        try Data(kept.utf8).write(to: url)
        try assertAsReadWhole()
        XCTAssertEqual(try keeper.current().notebook.entries.map(\.text), ["one", "something else"])
    }

    func testAFileThatIsNotTheOneReadIsReadFromItsStart() throws {
        try store.append([line("one", at: 1), line("two", at: 2), line("three", at: 3)])
        try store.append(line("from the desk", from: "mac", at: 4))
        try assertAsReadWhole()
        // Another version of the file in its place: shorter, and different from its start.
        let url = store.eventsDirectory.appendingPathComponent("me.phone.jsonl")
        try Data((try JSONLines.encode(line("another one", at: 1.5)) + "\n").utf8).write(to: url)
        try assertAsReadWhole("a shorter file")
        XCTAssertEqual(try keeper.current().notebook.entries.map(\.text), ["another one", "from the desk"])
        // And one that is longer than what was read, but not the same before that place.
        let longer = try [line("x", at: 1.1), line("y", at: 1.2), line("z", at: 1.3)].map { try JSONLines.encode($0) }.joined(separator: "\n") + "\n"
        try Data(longer.utf8).write(to: url)
        try assertAsReadWhole("a longer file")
        XCTAssertEqual(try keeper.current().notebook.entries.map(\.text), ["x", "y", "z", "from the desk"])
    }

    func testAFileGoneTakesItsEventsWithIt() throws {
        try store.append(line("on the phone", at: 1))
        try store.append(line("at the desk", from: "mac", at: 2))
        try assertAsReadWhole()
        try FileManager.default.removeItem(at: store.eventsDirectory.appendingPathComponent("me.phone.jsonl"))
        try assertAsReadWhole()
        XCTAssertEqual(try keeper.current().notebook.entries.map(\.text), ["at the desk"])
        // And back again, as iCloud brings a file down.
        try store.append(line("on the phone", at: 1))
        try assertAsReadWhole()
        XCTAssertEqual(try keeper.current().notebook.entries.map(\.text), ["on the phone", "at the desk"])
    }

    func testItMayBeAskedFromManyThreadsAtOnce() throws {
        try store.append(line("one", at: 1))
        let keeper = keeper!, store = store!
        let failures = Counter()
        DispatchQueue.concurrentPerform(iterations: 24) { index in
            do {
                if index % 3 == 0 {
                    let now = Date()
                    try store.append(Event(id: ULID(timestamp: now), author: "me", device: DeviceID(rawValue: "device-\(index)"), at: now,
                                           payload: .nameSet(.init(name: "name \(index)"))))
                }
                _ = try keeper.current()
            } catch {
                failures.add()
            }
        }
        XCTAssertEqual(failures.count, 0)
        try assertAsReadWhole()
    }

    /// Many folders' worth of things happening in an order nobody chose: lines, replies,
    /// marks, things, facts, reads, by several originators from several devices, with ids
    /// newer and older than what is there; lines cut short and finished; a file replaced, a
    /// file gone. After every one of them the keeper is what a whole reading is.
    func testAnyOrderOfAnythingIsAsReadWhole() throws {
        for seed in 1...5 as ClosedRange<UInt64> {
            try? FileManager.default.removeItem(at: root)
            store = try FileStore.create(at: root, owner: me)
            keeper = NotebookKeeper(store: store)
            var random = Seeded(seed: seed)
            var clock = 10.0
            var lines: [ULID] = [], notes: [ULID] = [], things: [ULID] = []
            let hands: [(Author, DeviceID)] = [("me", "phone"), ("me", "mac"), (.dotto, "home"), (.dotto, "claude-code"), ("health", "phone"), (.moss, "laptop")]

            for step in 0..<300 {
                // Mostly onward; sometimes a moment from before, as a file arriving late.
                clock += Double(random.below(5))
                let seconds = random.below(8) == 0 ? Double(random.below(Int(clock))) : clock
                let (author, device) = hands[random.below(hands.count)]
                func made(_ payload: Payload) -> Event {
                    event(payload, by: author, from: device, at: seconds, random: UInt8(random.below(250)))
                }
                func some(_ ids: [ULID]) -> ULID { ids.isEmpty ? ULID(timestamp: start) : ids[random.below(ids.count)] }
                var events: [Event] = []
                switch random.below(24) {
                case 0...5:
                    let made = made(.nameSet(.init(name: "")))
                    events = [Event(id: made.id, author: author, device: device, at: made.at,
                                    payload: .entryCreate(.init(entry: made.id, text: "line \(step)", startedAt: made.at, page: random.below(4) == 0 ? me : nil)))]
                    lines.append(made.id)
                case 6, 7:
                    let made = made(.nameSet(.init(name: "")))
                    events = [Event(id: made.id, author: author, device: device, at: made.at,
                                    payload: .entryCreate(.init(entry: made.id, text: "reply \(step)", startedAt: made.at,
                                                                under: random.below(3) == 0 ? some(notes) : some(lines))))]
                    notes.append(made.id)
                case 8:
                    let note = ULID(timestamp: start.addingTimeInterval(seconds))
                    events = [made(.noteAdd(.init(entry: some(lines), note: note, text: "note \(step)")))]
                    notes.append(note)
                case 9: events = [made(.entryEdit(.init(entry: random.below(2) == 0 ? some(lines) : some(notes), text: "changed \(step)")))]
                case 10: events = [made(.entryDelete(.init(entry: random.below(2) == 0 ? some(lines) : some(notes))))]
                case 11: events = [made(.noteRemove(.init(note: some(notes))))]
                case 12: events = [made(.labelAttach(.init(entry: some(lines), label: ["garden", "bread", "idea"][random.below(3)])))]
                case 13: events = [made(.link(.init(from: some(lines), to: random.below(2) == 0 ? some(lines) : some(things))))]
                case 14: events = [made(.unlink(.init(from: some(lines), to: random.below(2) == 0 ? some(lines) : some(things))))]
                case 15: events = [made(random.below(2) == 0 ? .done(.init(entry: some(lines))) : .undone(.init(entry: some(lines))))]
                case 16:
                    let thing = random.below(3) == 0 ? some(things) : ULID(timestamp: start.addingTimeInterval(seconds))
                    events = [made(.thingSet(.init(thing: thing, name: "thing \(step)", kind: ["plant", "book", nil][random.below(3)])))]
                    things.append(thing)
                case 17: events = [made(.thingRemove(.init(thing: some(things))))]
                case 18: events = [made(.factSet(.init(on: random.below(2) == 0 ? some(lines) : some(things), key: ["todo", "state", "yield"][random.below(3)],
                                                       value: random.below(2) == 0 ? .words("open") : .number(Double(random.below(9)), unit: "kg"))))]
                case 19, 20: events = [made(.visit(.init(what: [.inbox, .days, .lines][random.below(3)], count: random.below(9))))]
                case 21: events = [made(.nameSet(.init(name: "name \(step)")))]
                case 22:
                    // The owner's word that one originator is another, rarely.
                    if random.below(3) == 0 {
                        events = [event(.same(.init(author: .moss, as: .dotto)), at: seconds, random: UInt8(random.below(250)))]
                    }
                default:
                    // Two events in one write, in two files.
                    events = [made(.nameSet(.init(name: "pair \(step)"))),
                              event(.visit(.init(what: .search, count: 0, words: "pair")), by: .dotto, from: "home", at: seconds, random: UInt8(random.below(250)))]
                }

                let names = try store.eventFiles().map(\.lastPathComponent)
                switch random.below(120) {
                case 0...3 where !events.isEmpty:
                    // Written in two halves, looked at in between.
                    let text = try JSONLines.encode(events[0])
                    let name = store.eventFile(author: events[0].author, device: events[0].device).lastPathComponent
                    let cut = 1 + random.below(text.utf8.count - 1)
                    try write(String(decoding: text.utf8.prefix(cut), as: UTF8.self), to: name)
                    try assertAsReadWhole("seed \(seed) step \(step): half a line")
                    try write(String(decoding: text.utf8.dropFirst(cut), as: UTF8.self), to: name)
                    try assertAsReadWhole("seed \(seed) step \(step): its other half, no end")
                    try write("\n", to: name)
                case 4...6 where !names.isEmpty:
                    // A line cut short for good; what is written next goes after it.
                    try write("{\"at\":\"2026-11-0", to: names[random.below(names.count)])
                    try store.append(events)
                case 7, 8 where !names.isEmpty:
                    // Another version of a file in its place: the same without its first line.
                    let url = store.eventsDirectory.appendingPathComponent(names[random.below(names.count)])
                    let kept = try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).dropFirst()
                    try Data(kept.joined(separator: "\n").utf8).write(to: url)
                    try store.append(events)
                case 9 where names.count > 2:
                    try FileManager.default.removeItem(at: store.eventsDirectory.appendingPathComponent(names[random.below(names.count)]))
                    try store.append(events)
                default:
                    try store.append(events)
                }
                try assertAsReadWhole("seed \(seed) step \(step)")
                if step % 40 == 0 { try assertAsReadWhole("seed \(seed) step \(step), asked again") }
                assertLinksSitOnBothEnds(try keeper.current().notebook, "seed \(seed) step \(step)")
            }
            let end = try keeper.current()
            XCTAssertGreaterThan(end.files.reduce(0) { $0 + $1.events.count }, 150, "seed \(seed) made a notebook worth the test")
            XCTAssertGreaterThan(end.notebook.entries.count, 15, "seed \(seed) made a notebook worth the test")
            // Both ways of getting there were taken: folded onto, and folded again.
            XCTAssertGreaterThan(keeper.foldedAgain, 10, "seed \(seed)")
            XCTAssertLessThan(keeper.foldedAgain, 200, "seed \(seed)")
        }
    }
}

/// The same numbers every run, so a failure can be met again.
private struct Seeded {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
        // Seeds next to each other are streams far apart.
        state = next() ^ (seed << 32)
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A number from zero up to, not including, `limit`.
    mutating func below(_ limit: Int) -> Int {
        limit <= 1 ? 0 : Int(next() % UInt64(limit))
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func add() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
