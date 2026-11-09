import XCTest
@testable import Core

/// Shapes: things lines belong to, and facts on lines and things. Proposed by originators,
/// standing until dropped, the same from any order of arrival.
final class ShapeTests: XCTestCase {
    let me: Author = "me"
    let generator = ULIDGenerator()
    var clock = Date(timeIntervalSince1970: 1_793_613_600) // 2026-11-02 10:00 UTC
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func tick(_ seconds: TimeInterval = 60) -> Date {
        clock = clock.addingTimeInterval(seconds)
        return clock
    }

    func event(_ payload: Payload, author: Author = "me", at: Date? = nil) -> Event {
        let when = at ?? tick()
        return Event(id: generator.next(at: when), author: author, device: "iphone", at: when, payload: payload)
    }

    /// An event from before everything else here, arriving late. Its id is from its own
    /// moment: the generator would keep ids monotonic and make it newer.
    func older(_ payload: Payload, author: Author, by seconds: TimeInterval = 86_400) -> Event {
        let when = Date(timeIntervalSince1970: 1_793_613_600 - seconds)
        return Event(id: ULID(timestamp: when), author: author, device: "iphone", at: when, payload: payload)
    }

    func testAThingIsMadeOnceAndSetOnlyByItsOriginator() {
        let fig = ULID(timestamp: clock)
        var notebook = Notebook(owner: me)
        notebook.apply(event(.thingSet(.init(thing: fig, name: " Fig ", kind: "Plant")), author: .weeju))
        XCTAssertEqual(notebook.thing(fig)?.name, "Fig", "trimmed")
        XCTAssertEqual(notebook.thing(fig)?.kind, "plant", "a kind is a lower-case word")
        XCTAssertEqual(notebook.thing(fig)?.author, .weeju)

        notebook.apply(event(.thingSet(.init(thing: fig, name: "Ficus")), author: "margo"))
        XCTAssertEqual(notebook.thing(fig)?.name, "Fig", "only its own originator sets it")

        let rename = event(.thingSet(.init(thing: fig, name: "The fig", kind: "plant")), author: .weeju)
        notebook.apply(rename)
        notebook.apply(older(.thingSet(.init(thing: fig, name: "Old name", kind: "plant")), author: .weeju))
        XCTAssertEqual(notebook.thing(fig)?.name, "The fig", "the newest set stands, whatever order it arrives in")
        XCTAssertEqual(notebook.allThings.map(\.id), [fig])
        XCTAssertEqual(notebook.things(kind: "plant").count, 1)
        XCTAssertEqual(notebook.things(kind: "book").count, 0)
        XCTAssertEqual(notebook.trail.map(\.what), ["made a thing: Fig, a plant", "renamed a thing to The fig"])
    }

    func testALineBelongsToAThingByALinkAndWaitsForEither() {
        let fig = ULID(timestamp: clock)
        let line = ULID(timestamp: clock.addingTimeInterval(60))
        let make = event(.thingSet(.init(thing: fig, name: "fig")), author: .weeju)
        let write = event(.entryCreate(.init(entry: line, text: "Potted the fig", startedAt: clock)))
        let belong = event(.link(.init(from: line, to: fig)), author: .weeju)

        // The link arrives first, then the line, then the thing: placed once both are here.
        var notebook = Notebook(owner: me)
        notebook.apply(belong)
        notebook.apply(write)
        XCTAssertEqual(notebook.entry(line)?.belongsTo, [])
        notebook.apply(make)
        XCTAssertEqual(notebook.entry(line)?.belongsTo.map(\.to), [fig])
        XCTAssertEqual(notebook.entry(line)?.belongsTo.first?.toKind, .thing)
        XCTAssertEqual(notebook.thing(fig)?.lines, [line])
        XCTAssertEqual(notebook.entry(line)?.activity.map(\.what), ["put this with fig"])

        let forward = Notebook(owner: me, events: [make, write, belong])
        XCTAssertEqual(forward.entry(line)?.belongsTo, notebook.entry(line)?.belongsTo)
        XCTAssertEqual(forward.thing(fig)?.incoming, notebook.thing(fig)?.incoming)

        // Nothing points from a thing, and a note belongs to nothing.
        let note = ULID(timestamp: clock)
        notebook.apply(event(.noteAdd(.init(entry: line, note: note, text: "Which pot?")), author: .weeju))
        notebook.apply(event(.link(.init(from: fig, to: line)), author: .weeju))
        notebook.apply(event(.link(.init(from: note, to: fig)), author: .weeju))
        XCTAssertEqual(notebook.entry(line)?.incoming, [])
        XCTAssertEqual(notebook.thing(fig)?.lines, [line])

        // The owner takes the belonging back with one hold; a drop of the thing clears it everywhere.
        notebook.apply(event(.unlink(.init(from: line, to: fig))))
        XCTAssertEqual(notebook.entry(line)?.belongsTo, [])
        XCTAssertEqual(notebook.thing(fig)?.lines, [])
        notebook.apply(event(.link(.init(from: line, to: fig)), author: .weeju))
        XCTAssertEqual(notebook.thing(fig)?.lines, [line])
        notebook.apply(event(.thingRemove(.init(thing: fig))))
        XCTAssertNil(notebook.thing(fig))
        XCTAssertEqual(notebook.entry(line)?.belongsTo, [])
        notebook.apply(older(.thingSet(.init(thing: fig, name: "fig")), author: .weeju, by: 1800))
        XCTAssertNil(notebook.thing(fig), "a drop is final; a set arriving late does not bring it back")
    }

    func testADeletedLineLeavesItsThing() {
        let fig = ULID(timestamp: clock)
        let line = ULID(timestamp: clock.addingTimeInterval(60))
        var notebook = Notebook(owner: me, events: [
            event(.thingSet(.init(thing: fig, name: "fig")), author: .weeju),
            event(.entryCreate(.init(entry: line, text: "Potted", startedAt: clock))),
            event(.link(.init(from: line, to: fig)), author: .weeju),
        ])
        XCTAssertEqual(notebook.thing(fig)?.lines, [line])
        notebook.apply(event(.entryDelete(.init(entry: line))))
        XCTAssertEqual(notebook.thing(fig)?.lines, [])
    }

    func testFactsOnALineAndAThingOnePerOriginatorPerKey() {
        let harvest = ULID(timestamp: clock)
        let fig = ULID(timestamp: clock)
        var notebook = Notebook(owner: me, events: [
            event(.entryCreate(.init(entry: harvest, text: "90 kg gave 10 L", startedAt: clock))),
            event(.thingSet(.init(thing: fig, name: "fig", kind: "plant")), author: .weeju),
        ])

        let yield = event(.factSet(.init(on: harvest, key: " Yield", value: .number(10, unit: "L"))), author: .weeju)
        notebook.apply(yield)
        XCTAssertEqual(notebook.entry(harvest)?.facts.map(\.key), ["yield"])
        XCTAssertEqual(notebook.entry(harvest)?.facts.first?.value, .number(10, unit: "L"))
        XCTAssertEqual(notebook.entry(harvest)?.facts.first?.id, yield.id)
        XCTAssertEqual(notebook.entry(harvest)?.activity.map(\.what), ["put yield 10 L on this"])

        // The same originator again: replaced. Another originator: beside it.
        notebook.apply(event(.factSet(.init(on: harvest, key: "yield", value: .number(12, unit: "L"))), author: .weeju))
        notebook.apply(event(.factSet(.init(on: harvest, key: "yield", value: .number(11, unit: "L"))), author: "margo"))
        XCTAssertEqual(notebook.entry(harvest)?.facts.map { "\($0.author) \($0.value.words(calendar: utc))" }, ["margo 11 L", "weeju 12 L"])

        // An older word arriving late does not win.
        notebook.apply(older(.factSet(.init(on: harvest, key: "yield", value: .number(1, unit: "L"))), author: .weeju))
        XCTAssertEqual(notebook.entry(harvest)?.facts.last?.value, .number(12, unit: "L"))

        // The owner takes another's off, naming whose; the originator takes its own off.
        notebook.apply(event(.factRemove(.init(on: harvest, key: "yield", of: "margo"))))
        XCTAssertEqual(notebook.entry(harvest)?.facts.map(\.author), [.weeju])
        notebook.apply(event(.factRemove(.init(on: harvest, key: "yield", of: .weeju)), author: "margo"))
        XCTAssertEqual(notebook.entry(harvest)?.facts.map(\.author), [.weeju], "nobody else takes it off")
        notebook.apply(event(.factRemove(.init(on: harvest, key: "yield")), author: .weeju))
        XCTAssertEqual(notebook.entry(harvest)?.facts, [])

        // Facts on a thing are its state, and they wait for a thing not seen yet.
        let state = event(.factSet(.init(on: fig, key: "state", value: .words("potted"))), author: .weeju)
        notebook.apply(state)
        XCTAssertEqual(notebook.thing(fig)?.facts.map { "\($0.key) \($0.value.words(calendar: utc))" }, ["state potted"])
        let late = Notebook(owner: me, events: [state, event(.thingSet(.init(thing: fig, name: "fig")), author: .weeju)])
        XCTAssertEqual(late.thing(fig)?.facts.map(\.key), ["state"])
    }

    func testFactValuesReadAsWordsAndRoundTripAsJSON() throws {
        let moment = Date(timeIntervalSince1970: 1_793_613_600)
        let values: [(FactValue, String, String)] = [
            (.number(10, unit: "L"), "10 L", #"{"number":10,"unit":"L"}"#),
            (.number(3.14159, unit: nil), "3.14", #"{"number":3.14159}"#),
            (.words("potted"), "potted", #"{"words":"potted"}"#),
            (.moment(moment), "2026-11-02 10:00", #"{"moment":"2026-11-02T10:00:00.000Z"}"#),
            (.span(2460), "41 min", #"{"span":2460}"#),
            (.span(5400), "1 h 30 min", #"{"span":5400}"#),
            (.span(3 * 86_400), "3 d", #"{"span":259200}"#),
            (.place(Location(latitude: 38.7, longitude: -9.1)), "38.70, -9.10", #"{"place":{"latitude":38.7,"longitude":-9.1}}"#),
        ]
        for (value, words, json) in values {
            XCTAssertEqual(value.words(calendar: utc), words)
            let data = try JSONLines.encoder().encode(value)
            XCTAssertEqual(String(decoding: data, as: UTF8.self), json)
            XCTAssertEqual(try JSONLines.decoder().decode(FactValue.self, from: data), value)
        }
        XCTAssertThrowsError(try JSONLines.decoder().decode(FactValue.self, from: Data(#"{"colour":"red"}"#.utf8)))
    }

    func testTheInboxShowsThingsAndFactsAsProposals() {
        let fig = ULID(timestamp: clock)
        let line = ULID(timestamp: clock.addingTimeInterval(60))
        var files: [String: [Event]] = [:]
        func write(_ payload: Payload, by author: Author) {
            let event = event(payload, author: author)
            files["\(author).iphone.jsonl", default: []].append(event)
        }
        write(.entryCreate(.init(entry: line, text: "90 kg gave 10 L", startedAt: clock)), by: me)
        write(.thingSet(.init(thing: fig, name: "fig", kind: "plant")), by: .weeju)
        write(.factSet(.init(on: line, key: "yield", value: .number(10, unit: "L"))), by: .weeju)
        write(.factSet(.init(on: fig, key: "state", value: .words("potted"))), by: .weeju)
        let byFile = files.keys.sorted().map { ($0, files[$0]!) }
        let notebook = Notebook(owner: me, events: byFile.flatMap(\.1))
        let items = Inbox.items(files: byFile, notebook: notebook, calendar: utc)
        XCTAssertEqual(items.map(\.what), ["put state potted on", "put yield 10 L on", "made a thing"])
        XCTAssertEqual(items.map(\.kind), [.shape, .shape, .shape])
        XCTAssertEqual(items[0].thing, fig)
        XCTAssertEqual(items[0].text, "fig")
        XCTAssertEqual(items[1].entry, line)
        XCTAssertEqual(items[2].about, "a plant")
        XCTAssertTrue(items.allSatisfy(\.unread))
    }

    /// A proposed loop is an inbox item that wants the owner until it is set or declined.
    func testAProposedLoopWantsTheOwnerUntilAnswered() {
        let grant = Grant(name: "Claude Code", author: .weeju, device: "claude-code")
        let proposal = ULID(timestamp: clock)
        var files: [String: [Event]] = [:]
        func write(_ payload: Payload, by author: Author) {
            let event = event(payload, author: author)
            files["\(author).iphone.jsonl", default: []].append(event)
        }
        write(.grantCreate(grant.create), by: me)
        write(.loopPropose(.init(loop: proposal, name: "The evening look", grant: grant.id, wake: "clock", at: "21:00", brief: "Read the day once.")), by: .weeju)
        func items() -> [InboxItem] {
            let byFile = files.keys.sorted().map { ($0, files[$0]!) }
            return Inbox.items(files: byFile, notebook: Notebook(owner: me, events: byFile.flatMap(\.1)), calendar: utc)
        }
        var item = items()[0]
        XCTAssertEqual(item.kind, .loop)
        XCTAssertEqual(item.text, "The evening look · every day at 21:00")
        XCTAssertEqual(item.about, "Read the day once.")
        XCTAssertTrue(item.wantsYou)

        write(.loopSet(.init(loop: proposal, name: "The evening look", grant: grant.id, wake: "clock", at: "21:00")), by: me)
        item = items()[0]
        XCTAssertTrue(item.answered)
        XCTAssertFalse(item.wantsYou)
        XCTAssertFalse(item.unread)
    }

    /// Todos are lines anyone marked todo and nobody marked done, due first; kinds count things.
    func testTodosDueAndKinds() {
        let tv = ULID(timestamp: clock), tyres = ULID(timestamp: clock.addingTimeInterval(60)), visit = ULID(timestamp: clock.addingTimeInterval(120))
        let fig = ULID(timestamp: clock), book = ULID(timestamp: clock), untyped = ULID(timestamp: clock)
        let thursday = now.addingTimeInterval(2 * 86_400)
        var notebook = Notebook(owner: me, events: [
            event(.entryCreate(.init(entry: tv, text: "Sell the TV", startedAt: clock))),
            event(.entryCreate(.init(entry: tyres, text: "Tyres", startedAt: clock.addingTimeInterval(60)))),
            event(.entryCreate(.init(entry: visit, text: "Apartment visit", startedAt: clock.addingTimeInterval(120)))),
            event(.factSet(.init(on: tv, key: "todo", value: .words("open"))), author: .weeju),
            event(.factSet(.init(on: tyres, key: "todo", value: .words("open"))), author: .weeju),
            event(.factSet(.init(on: tyres, key: "due", value: .moment(thursday))), author: .weeju),
            event(.factSet(.init(on: visit, key: "due", value: .moment(now.addingTimeInterval(86_400)))), author: .weeju),
            event(.thingSet(.init(thing: fig, name: "fig", kind: "plant")), author: .weeju),
            event(.thingSet(.init(thing: book, name: "Infinity", kind: "book")), author: .weeju),
            event(.thingSet(.init(thing: untyped, name: "something")), author: .weeju),
        ])
        XCTAssertEqual(notebook.todos.map(\.text), ["Tyres", "Sell the TV"], "due first, then newest")
        XCTAssertEqual(notebook.entry(tyres)?.due, thursday)
        XCTAssertFalse(notebook.entry(visit)!.isTodo, "an appointment is due, not a todo")
        XCTAssertEqual(notebook.due(after: now).map(\.text), ["Apartment visit", "Tyres"])
        XCTAssertEqual(notebook.due(after: now.addingTimeInterval(3 * 86_400)), [])

        notebook.apply(event(.done(.init(entry: tv)), author: .weeju))
        XCTAssertEqual(notebook.todos.map(\.text), ["Tyres"], "done leaves the list")
        notebook.apply(event(.factRemove(.init(on: tyres, key: "todo", of: .weeju))))
        XCTAssertEqual(notebook.todos, [], "and so does the owner taking the fact off")

        XCTAssertEqual(notebook.kinds.map { "\($0.kind ?? "-") \($0.count)" }, ["book 1", "plant 1", "- 1"])
    }

    private var now: Date { clock }

    func testTheDayPageNamesBelongingAndFacts() {
        let fig = ULID(timestamp: clock)
        let line = ULID(timestamp: clock.addingTimeInterval(60))
        let notebook = Notebook(owner: me, events: [
            event(.entryCreate(.init(entry: line, text: "Potted the fig", startedAt: clock))),
            event(.thingSet(.init(thing: fig, name: "fig")), author: .weeju),
            event(.link(.init(from: line, to: fig)), author: .weeju),
            event(.factSet(.init(on: line, key: "pot", value: .words("clay"))), author: .weeju),
            event(.nameSet(.init(name: "Moss")), author: .weeju),
        ])
        let page = Projector.markdown(for: notebook.days(calendar: utc)[0], calendar: utc, names: notebook.chosenNames, things: notebook.thingNames)
        XCTAssertTrue(page.contains("\n_with fig_\n_pot clay · Moss_\n"), page)
    }
}
