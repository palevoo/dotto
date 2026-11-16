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
        notebook.apply(event(.thingSet(.init(thing: fig, name: " Fig ", kind: "Plant")), author: .moss))
        XCTAssertEqual(notebook.thing(fig)?.name, "Fig", "trimmed")
        XCTAssertEqual(notebook.thing(fig)?.kind, "plant", "a kind is a lower-case word")
        XCTAssertEqual(notebook.thing(fig)?.author, .moss)

        notebook.apply(event(.thingSet(.init(thing: fig, name: "Ficus")), author: "fern"))
        XCTAssertEqual(notebook.thing(fig)?.name, "Fig", "only its own originator sets it")

        let rename = event(.thingSet(.init(thing: fig, name: "The fig", kind: "plant")), author: .moss)
        notebook.apply(rename)
        notebook.apply(older(.thingSet(.init(thing: fig, name: "Old name", kind: "plant")), author: .moss))
        XCTAssertEqual(notebook.thing(fig)?.name, "The fig", "the newest set stands, whatever order it arrives in")
        XCTAssertEqual(notebook.allThings.map(\.id), [fig])
        XCTAssertEqual(notebook.things(kind: "plant").count, 1)
        XCTAssertEqual(notebook.things(kind: "book").count, 0)
        XCTAssertEqual(notebook.trail.map(\.what), ["made a thing: Fig, a plant", "renamed a thing to The fig"])
    }

    func testALineBelongsToAThingByALinkAndWaitsForEither() {
        let fig = ULID(timestamp: clock)
        let line = ULID(timestamp: clock.addingTimeInterval(60))
        let make = event(.thingSet(.init(thing: fig, name: "fig")), author: .moss)
        let write = event(.entryCreate(.init(entry: line, text: "Potted the fig", startedAt: clock)))
        let belong = event(.link(.init(from: line, to: fig)), author: .moss)

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
        notebook.apply(event(.noteAdd(.init(entry: line, note: note, text: "Which pot?")), author: .moss))
        notebook.apply(event(.link(.init(from: fig, to: line)), author: .moss))
        notebook.apply(event(.link(.init(from: note, to: fig)), author: .moss))
        XCTAssertEqual(notebook.entry(line)?.incoming, [])
        XCTAssertEqual(notebook.thing(fig)?.lines, [line])

        // The owner takes the belonging back with one hold; a drop of the thing clears it everywhere.
        notebook.apply(event(.unlink(.init(from: line, to: fig))))
        XCTAssertEqual(notebook.entry(line)?.belongsTo, [])
        XCTAssertEqual(notebook.thing(fig)?.lines, [])
        notebook.apply(event(.link(.init(from: line, to: fig)), author: .moss))
        XCTAssertEqual(notebook.thing(fig)?.lines, [line])
        notebook.apply(event(.thingRemove(.init(thing: fig))))
        XCTAssertNil(notebook.thing(fig))
        XCTAssertEqual(notebook.entry(line)?.belongsTo, [])
        notebook.apply(older(.thingSet(.init(thing: fig, name: "fig")), author: .moss, by: 1800))
        XCTAssertNil(notebook.thing(fig), "a drop is final; a set arriving late does not bring it back")
    }

    func testADeletedLineLeavesItsThing() {
        let fig = ULID(timestamp: clock)
        let line = ULID(timestamp: clock.addingTimeInterval(60))
        var notebook = Notebook(owner: me, events: [
            event(.thingSet(.init(thing: fig, name: "fig")), author: .moss),
            event(.entryCreate(.init(entry: line, text: "Potted", startedAt: clock))),
            event(.link(.init(from: line, to: fig)), author: .moss),
        ])
        XCTAssertEqual(notebook.thing(fig)?.lines, [line])
        notebook.apply(event(.entryDelete(.init(entry: line))))
        XCTAssertEqual(notebook.thing(fig)?.lines, [])
    }

    func testFactsOnALineAndAThingOnePerOriginatorPerKey() {
        let flour = ULID(timestamp: clock)
        let fig = ULID(timestamp: clock)
        var notebook = Notebook(owner: me, events: [
            event(.entryCreate(.init(entry: flour, text: "Bought the rye flour, 2 kg", startedAt: clock))),
            event(.thingSet(.init(thing: fig, name: "fig", kind: "plant")), author: .moss),
        ])

        let weight = event(.factSet(.init(on: flour, key: " Weight", value: .number(2, unit: "kg"))), author: .moss)
        notebook.apply(weight)
        XCTAssertEqual(notebook.entry(flour)?.facts.map(\.key), ["weight"])
        XCTAssertEqual(notebook.entry(flour)?.facts.first?.value, .number(2, unit: "kg"))
        XCTAssertEqual(notebook.entry(flour)?.facts.first?.id, weight.id)
        XCTAssertEqual(notebook.entry(flour)?.activity.map(\.what), ["put weight 2 kg on this"])

        // The same originator again: replaced. Another originator: beside it.
        notebook.apply(event(.factSet(.init(on: flour, key: "weight", value: .number(3, unit: "kg"))), author: .moss))
        notebook.apply(event(.factSet(.init(on: flour, key: "weight", value: .number(4, unit: "kg"))), author: "fern"))
        XCTAssertEqual(notebook.entry(flour)?.facts.map { "\($0.author) \($0.value.words(calendar: utc))" }, ["fern 4 kg", "moss 3 kg"])

        // An older word arriving late does not win.
        notebook.apply(older(.factSet(.init(on: flour, key: "weight", value: .number(1, unit: "kg"))), author: .moss))
        XCTAssertEqual(notebook.entry(flour)?.facts.last?.value, .number(3, unit: "kg"))

        // The owner takes another's off, naming whose; the originator takes its own off.
        notebook.apply(event(.factRemove(.init(on: flour, key: "weight", of: "fern"))))
        XCTAssertEqual(notebook.entry(flour)?.facts.map(\.author), [.moss])
        notebook.apply(event(.factRemove(.init(on: flour, key: "weight", of: .moss)), author: "fern"))
        XCTAssertEqual(notebook.entry(flour)?.facts.map(\.author), [.moss], "nobody else takes it off")
        notebook.apply(event(.factRemove(.init(on: flour, key: "weight")), author: .moss))
        XCTAssertEqual(notebook.entry(flour)?.facts, [])

        // Facts on a thing are its state, and they wait for a thing not seen yet.
        let state = event(.factSet(.init(on: fig, key: "state", value: .words("potted"))), author: .moss)
        notebook.apply(state)
        XCTAssertEqual(notebook.thing(fig)?.facts.map { "\($0.key) \($0.value.words(calendar: utc))" }, ["state potted"])
        let late = Notebook(owner: me, events: [state, event(.thingSet(.init(thing: fig, name: "fig")), author: .moss)])
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
            (.place(Location(latitude: 54.5, longitude: -3.2)), "54.50, -3.20", #"{"place":{"latitude":54.5,"longitude":-3.2}}"#),
        ]
        for (value, words, json) in values {
            XCTAssertEqual(value.words(calendar: utc), words)
            let data = try JSONLines.encoder().encode(value)
            XCTAssertEqual(String(decoding: data, as: UTF8.self), json)
            XCTAssertEqual(try JSONLines.decoder().decode(FactValue.self, from: data), value)
        }
        // A kind of value not known here is carried as it was, and written back the same.
        let newer = Data(#"{"colour":"red"}"#.utf8)
        let carried = try JSONLines.decoder().decode(FactValue.self, from: newer)
        XCTAssertEqual(carried, .unknown(.object(["colour": .string("red")])))
        XCTAssertEqual(try JSONLines.encoder().encode(carried), newer)
    }

    func testTheInboxShowsThingsAndFactsAsProposals() {
        let fig = ULID(timestamp: clock)
        let line = ULID(timestamp: clock.addingTimeInterval(60))
        var files: [String: [Event]] = [:]
        func write(_ payload: Payload, by author: Author) {
            let event = event(payload, author: author)
            files["\(author).iphone.jsonl", default: []].append(event)
        }
        write(.entryCreate(.init(entry: line, text: "Bought the rye flour, 2 kg", startedAt: clock)), by: me)
        write(.thingSet(.init(thing: fig, name: "fig", kind: "plant")), by: .moss)
        write(.factSet(.init(on: line, key: "weight", value: .number(2, unit: "kg"))), by: .moss)
        write(.factSet(.init(on: fig, key: "state", value: .words("potted"))), by: .moss)
        let byFile = files.keys.sorted().map { ($0, files[$0]!) }
        let notebook = Notebook(owner: me, events: byFile.flatMap(\.1))
        let items = Inbox.items(files: byFile, notebook: notebook, calendar: utc)
        XCTAssertEqual(items.map(\.what), ["put state potted on", "put weight 2 kg on", "made a thing"])
        XCTAssertEqual(items.map(\.kind), [.shape, .shape, .shape])
        XCTAssertEqual(items[0].thing, fig)
        XCTAssertEqual(items[0].text, "fig")
        XCTAssertEqual(items[1].entry, line)
        XCTAssertEqual(items[2].about, "a plant")
        XCTAssertTrue(items.allSatisfy(\.unread))
    }

    /// A proposed loop is an inbox item that wants the owner until it is set or declined.
    func testAProposedLoopWantsTheOwnerUntilAnswered() {
        let grant = Grant(name: "Claude Code", author: .moss, device: "claude-code")
        let proposal = ULID(timestamp: clock)
        var files: [String: [Event]] = [:]
        func write(_ payload: Payload, by author: Author) {
            let event = event(payload, author: author)
            files["\(author).iphone.jsonl", default: []].append(event)
        }
        write(.grantCreate(grant.create), by: me)
        write(.loopPropose(.init(loop: proposal, name: "The evening look", grant: grant.id, wake: "clock", at: "21:00", brief: "Read the day once.")), by: .moss)
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
        let books = ULID(timestamp: clock), rye = ULID(timestamp: clock.addingTimeInterval(60)), haircut = ULID(timestamp: clock.addingTimeInterval(120))
        let fig = ULID(timestamp: clock), book = ULID(timestamp: clock), untyped = ULID(timestamp: clock)
        let thursday = now.addingTimeInterval(2 * 86_400)
        var notebook = Notebook(owner: me, events: [
            event(.entryCreate(.init(entry: books, text: "Return the library books", startedAt: clock))),
            event(.entryCreate(.init(entry: rye, text: "Buy rye flour", startedAt: clock.addingTimeInterval(60)))),
            event(.entryCreate(.init(entry: haircut, text: "Haircut", startedAt: clock.addingTimeInterval(120)))),
            event(.factSet(.init(on: books, key: "todo", value: .words("open"))), author: .moss),
            event(.factSet(.init(on: rye, key: "todo", value: .words("open"))), author: .moss),
            event(.factSet(.init(on: rye, key: "due", value: .moment(thursday))), author: .moss),
            event(.factSet(.init(on: haircut, key: "due", value: .moment(now.addingTimeInterval(86_400)))), author: .moss),
            event(.thingSet(.init(thing: fig, name: "fig", kind: "plant")), author: .moss),
            event(.thingSet(.init(thing: book, name: "The Country Loaf", kind: "book")), author: .moss),
            event(.thingSet(.init(thing: untyped, name: "something")), author: .moss),
        ])
        XCTAssertEqual(notebook.todos.map(\.text), ["Buy rye flour", "Return the library books"], "due first, then newest")
        XCTAssertEqual(notebook.entry(rye)?.due, thursday)
        XCTAssertFalse(notebook.entry(haircut)!.isTodo, "an appointment is due, not a todo")
        XCTAssertEqual(notebook.due(after: now).map(\.text), ["Haircut", "Buy rye flour"])
        XCTAssertEqual(notebook.due(after: now.addingTimeInterval(3 * 86_400)), [])

        notebook.apply(event(.done(.init(entry: books)), author: .moss))
        XCTAssertEqual(notebook.todos.map(\.text), ["Buy rye flour"], "done leaves the list")
        notebook.apply(event(.factRemove(.init(on: rye, key: "todo", of: .moss))))
        XCTAssertEqual(notebook.todos, [], "and so does the owner taking the fact off")

        XCTAssertEqual(notebook.kinds.map { "\($0.kind ?? "-") \($0.count)" }, ["book 1", "plant 1", "- 1"])
    }

    /// An event happens at its moment and is never to do; something due wants the owner at
    /// its moment. Both are what is coming. The phone says an event the evening before and
    /// an hour before, and something due once, when it is due; never for a moment gone by.
    func testWhatIsComingAndWhatIsSaidOfIt() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // clock is Monday 2 November 2026, 10:00 UTC.
        let eyeTest = ULID(timestamp: clock), seeds = ULID(timestamp: clock.addingTimeInterval(60)), soon = ULID(timestamp: clock.addingTimeInterval(120))
        let friday = clock.addingTimeInterval(4 * 86_400 + 3600)        // Friday 11:00
        let march = clock.addingTimeInterval(100 * 86_400)
        let today = clock.addingTimeInterval(1800)                        // today 10:30
        var notebook = Notebook(owner: me, events: [
            event(.entryCreate(.init(entry: eyeTest, text: "Eye test", startedAt: clock)), at: clock),
            event(.entryCreate(.init(entry: seeds, text: "Plant the seeds", startedAt: clock)), at: clock),
            event(.entryCreate(.init(entry: soon, text: "Dentist", startedAt: clock)), at: clock),
            event(.factSet(.init(on: eyeTest, key: "at", value: .moment(friday))), author: .moss, at: clock),
            event(.factSet(.init(on: seeds, key: "todo", value: .words("open"))), author: .moss, at: clock),
            event(.factSet(.init(on: seeds, key: "due", value: .moment(march))), author: .moss, at: clock),
            event(.factSet(.init(on: soon, key: "at", value: .moment(today))), author: .moss, at: clock),
        ])
        XCTAssertNil(notebook.entry(eyeTest)?.todo, "an appointment is not to do")
        XCTAssertEqual(notebook.entry(eyeTest)?.moment, friday)
        XCTAssertEqual(notebook.coming(after: clock).map(\.text), ["Dentist", "Eye test", "Plant the seeds"])
        XCTAssertEqual(notebook.todos.map(\.text), ["Plant the seeds"], "and is not among the todos")

        let said = notebook.notices(after: clock, calendar: calendar)
        XCTAssertEqual(said.map(\.title), ["Tomorrow at 11:00", "In an hour, at 11:00", "Due now"],
                       "an event twice ahead, something due once; the dentist in half an hour is too near for either")
        XCTAssertEqual(said[0].fire, clock.addingTimeInterval(3 * 86_400 + 10 * 3600), "Thursday at eight in the evening")
        XCTAssertEqual(said[1].fire, friday.addingTimeInterval(-3600))
        XCTAssertEqual(said[2].fire, march)
        XCTAssertEqual(said.map(\.todo), [false, false, true])
        XCTAssertEqual(said[0].key, Notice.key(entry: eyeTest, moment: friday))

        // Moved, the notices are others; done, there are none; past, it is no longer coming.
        notebook.apply(event(.factSet(.init(on: eyeTest, key: "at", value: .moment(friday.addingTimeInterval(86_400)))), author: .moss, at: clock.addingTimeInterval(1)))
        XCTAssertNotEqual(notebook.notices(after: clock, calendar: calendar).first?.id, said[0].id, "a moment moved is another notice")
        notebook.apply(event(.done(.init(entry: seeds)), at: clock.addingTimeInterval(2)))
        XCTAssertEqual(notebook.notices(after: clock, calendar: calendar).map(\.body), ["Eye test", "Eye test"])
        XCTAssertEqual(notebook.coming(after: friday.addingTimeInterval(2 * 86_400)), [], "an event passes by itself")
    }

    /// A todo ends: done closes it and nothing is left saying open. On its page it keeps its
    /// place for the day it was finished; one with no moment that waited three weeks steps back.
    func testATodoEndsAndWaits() {
        let calendar = Calendar(identifier: .gregorian)
        let old = ULID(timestamp: clock.addingTimeInterval(-30 * 86_400)), books = ULID(timestamp: clock), rye = ULID(timestamp: clock.addingTimeInterval(60))
        var notebook = Notebook(owner: me, events: [
            event(.entryCreate(.init(entry: old, text: "Sharpen the knives", startedAt: clock.addingTimeInterval(-30 * 86_400)))),
            event(.entryCreate(.init(entry: books, text: "Return the library books", startedAt: clock))),
            event(.entryCreate(.init(entry: rye, text: "Buy rye flour", startedAt: clock.addingTimeInterval(60)))),
            event(.factSet(.init(on: old, key: "todo", value: .words("open"))), author: .moss),
            event(.factSet(.init(on: books, key: "todo", value: .words("open"))), author: .moss),
            event(.factSet(.init(on: rye, key: "todo", value: .words("open")))),
        ])
        let later = clock.addingTimeInterval(3600)
        XCTAssertEqual(notebook.todos(at: later, calendar: calendar).now.map(\.text), ["Buy rye flour", "Return the library books"])
        XCTAssertEqual(notebook.todos(at: later, calendar: calendar).someday.map(\.text), ["Sharpen the knives"], "three weeks with no moment: someday")
        XCTAssertEqual(notebook.entry(rye)?.todo, .open, "the owner's own word makes a todo too")

        notebook.apply(event(.done(.init(entry: books)), at: later))
        let entry = notebook.entry(books)!
        XCTAssertEqual(entry.todo, .done)
        XCTAssertEqual(entry.standingFacts, [], "done closes it; nothing is left saying open")
        XCTAssertEqual(entry.facts.map(\.key), ["todo"], "the word stays in the record")
        XCTAssertEqual(notebook.todos(at: later, calendar: calendar).now.map(\.text), ["Buy rye flour", "Return the library books"], "finished today, it keeps its place")
        XCTAssertEqual(notebook.todos(at: later.addingTimeInterval(86_400), calendar: calendar).now.map(\.text), ["Buy rye flour"], "and is gone the day after")

        notebook.apply(event(.undone(.init(entry: books)), at: later.addingTimeInterval(60)))
        XCTAssertEqual(notebook.entry(books)?.todo, .open, "opened again, it is to do again")
    }

    private var now: Date { clock }

    func testTheDayPageNamesBelongingAndFacts() {
        let fig = ULID(timestamp: clock)
        let line = ULID(timestamp: clock.addingTimeInterval(60))
        let notebook = Notebook(owner: me, events: [
            event(.entryCreate(.init(entry: line, text: "Potted the fig", startedAt: clock))),
            event(.thingSet(.init(thing: fig, name: "fig")), author: .moss),
            event(.link(.init(from: line, to: fig)), author: .moss),
            event(.factSet(.init(on: line, key: "pot", value: .words("clay"))), author: .moss),
            event(.nameSet(.init(name: "Moss")), author: .moss),
        ])
        let page = Projector.markdown(for: notebook.days(calendar: utc)[0], calendar: utc, names: notebook.chosenNames, things: notebook.thingNames)
        XCTAssertTrue(page.contains("\n_with fig_\n_pot clay · Moss_\n"), page)
    }
}
