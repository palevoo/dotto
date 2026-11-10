import XCTest
@testable import Core

/// A line said under something, read. Under a line it is a reply in that line's
/// conversation, beside the replies written the older way; nothing writes it yet.
final class SaidUnderTests: XCTestCase {
    private let owner = Author(rawValue: "wiju")
    private let ids = ULIDGenerator()
    private let start = Date(timeIntervalSince1970: 1_794_300_000)
    private var tick = 0.0
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func event(_ payload: (ULID) -> Payload, by author: Author, on device: DeviceID = "phone") -> Event {
        tick += 60
        let at = start.addingTimeInterval(tick)
        let id = ids.next(at: at)
        return Event(id: id, author: author, device: device, at: at, payload: payload(id))
    }

    private func line(_ text: String, by author: Author? = nil, under: ULID? = nil) -> Event {
        let at = start.addingTimeInterval(tick + 60)
        return event({ .entryCreate(.init(entry: $0, text: text, startedAt: at, under: under)) }, by: author ?? owner)
    }

    func testALineSaidUnderALineIsAReplyInAnyOrder() {
        let asked = line("What should I read on this?")
        let answer = line("Hamming, 1950, ten pages.", by: .dotto, under: asked.id)
        let again = line("And after that?", under: answer.id)
        let older = event({ .noteAdd(.init(entry: asked.id, note: $0, text: "Written the older way.")) }, by: .dotto)
        let events = [asked, answer, again, older]

        for order in [events, events.reversed(), [again, older, answer, asked], events.shuffled()] {
            let notebook = Notebook(owner: owner, events: order)
            XCTAssertEqual(notebook.entries.map(\.text), ["What should I read on this?"], "only the line is on the page")
            let replies = notebook.entry(asked.id)?.notes ?? []
            XCTAssertEqual(replies.map(\.text), ["Hamming, 1950, ten pages.", "And after that?", "Written the older way."])
            XCTAssertEqual(replies.map(\.author), [.dotto, owner, .dotto])
            XCTAssertNil(replies[0].answers, "said under the line itself")
            XCTAssertEqual(replies[1].answers, answer.id, "an answer knows the reply it answers")
            XCTAssertEqual(notebook.note(again.id)?.entry.id, asked.id, "and is in the same conversation")
            XCTAssertTrue(notebook.entries(of: .dotto).isEmpty, "a reply is not a line on its writer's page")
        }
    }

    func testAReplyIsChangedByItsWriterAndDroppedByItsWriterOrTheOwner() {
        let asked = line("Is this a second mango?")
        let answer = line("It is.", by: .dotto, under: asked.id)
        let fixed = event({ _ in .entryEdit(.init(entry: answer.id, text: "It looks like one; the root says so.")) }, by: .dotto)
        let notHis = event({ _ in .entryEdit(.init(entry: answer.id, text: "Changed by a stranger")) }, by: "stranger")
        let base = [asked, answer, fixed, notHis]

        for order in [base, base.reversed(), base.shuffled()] {
            let notebook = Notebook(owner: owner, events: order)
            XCTAssertEqual(notebook.entry(asked.id)?.notes.map(\.text), ["It looks like one; the root says so."])
        }

        // A stranger's word that it is gone changes nothing; the writer's does, and the owner's.
        let stranger = event({ _ in .entryDelete(.init(entry: answer.id)) }, by: "stranger")
        XCTAssertEqual(Notebook(owner: owner, events: base + [stranger]).entry(asked.id)?.notes.count, 1)
        let writer = event({ _ in .entryDelete(.init(entry: answer.id)) }, by: .dotto)
        let mine = event({ _ in .entryDelete(.init(entry: answer.id)) }, by: owner)
        for drop in [writer, mine] {
            for order in [base + [stranger, drop], [drop, stranger] + base, (base + [stranger, drop]).shuffled()] {
                XCTAssertEqual(Notebook(owner: owner, events: order).entry(asked.id)?.notes.count, 0)
            }
        }
        // The older way of taking a note back keeps the same rule.
        let olderStranger = event({ _ in .noteRemove(.init(note: answer.id)) }, by: "stranger")
        XCTAssertEqual(Notebook(owner: owner, events: base + [olderStranger]).entry(asked.id)?.notes.count, 1)
    }

    func testALineSaidUnderAThingIsKeptAndShownNowhereYet() {
        let fig = ULID(timestamp: start)
        let made = Event(id: fig, author: .dotto, device: "claude-code", at: start, payload: .thingSet(.init(thing: fig, name: "the fig", kind: "plant")))
        let said = line("Show its last photo first.", under: fig)
        for order in [[made, said], [said, made]] {
            let notebook = Notebook(owner: owner, events: order)
            XCTAssertTrue(notebook.entries.isEmpty, "not on the days")
            XCTAssertEqual(notebook.thing(fig)?.lines, [], "and not a line that belongs to the fig")
            XCTAssertEqual(notebook.eventCount, 2, "but counted, and in the file")
        }
    }

    func testWhatIsNewTellsOfALineSaidUnderALineAsAReply() {
        let grant = Grant(name: "Claude Code", author: .dotto, device: "claude-code", createdAt: start)
        let asked = line("How do you say tall?")
        let reply = line("In Portuguese, I mean.", under: asked.id)
        let files = [(file: "wiju.phone.jsonl", events: [asked, reply])]
        let notebook = Notebook(owner: owner, events: [asked, reply])
        let report = Inbox.pending(files: files, notebook: notebook, grant: grant, calendar: calendar)
        XCTAssertTrue(report.text.contains("## Replies"), report.text)
        XCTAssertTrue(report.text.contains("In Portuguese, I mean."), report.text)
        XCTAssertEqual(report.text.components(separatedBy: "In Portuguese, I mean.").count, 2, "told once, as a reply, not also as a new line")
    }

    func testWhereALineWasSaidIsWrittenAndReadBack() throws {
        let asked = line("Asked")
        let reply = line("Answered", under: asked.id)
        let json = try JSONLines.encode(reply)
        XCTAssertTrue(json.contains("\"under\":\"\(asked.id.string)\""), json)
        XCTAssertEqual(try JSONLines.decode(json), reply)
        XCTAssertFalse(try JSONLines.encode(asked).contains("under"), "a line said nowhere says nothing of it")
    }
}
