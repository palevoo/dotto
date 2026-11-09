import XCTest
@testable import Core

/// Search: plain words over the notebook, every word found, case and accents aside, a word
/// found inside a longer one; through a line's own words, a reply, a thing or a tag.
final class SearchTests: XCTestCase {
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

    /// Three lines: the harvest, a Russian detox line with a reply, and a quote under a book.
    func notebook() -> (Notebook, harvest: ULID, detox: ULID, quote: ULID, book: ULID) {
        let harvest = ULID(timestamp: clock)
        let detox = ULID(timestamp: clock.addingTimeInterval(1))
        let quote = ULID(timestamp: clock.addingTimeInterval(2))
        let book = ULID(timestamp: clock.addingTimeInterval(3))
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: harvest, text: "90kg from our first harvest, 10 litres", startedAt: tick()))))
        notebook.apply(event(.entryCreate(.init(entry: detox, text: "Сегодня день без YouTube", startedAt: tick()))))
        notebook.apply(event(.entryCreate(.init(entry: quote, text: "Café at dawn, a line from the book", startedAt: tick()))))
        notebook.apply(event(.noteAdd(.init(entry: detox, note: ULID(timestamp: clock.addingTimeInterval(4)), text: "Day one of the detox, then.")), author: .weeju))
        notebook.apply(event(.thingSet(.init(thing: book, name: "The Beginning of Infinity, David Deutsch", kind: "book")), author: .weeju))
        notebook.apply(event(.link(.init(from: quote, to: book)), author: .weeju))
        notebook.apply(event(.labelAttach(.init(entry: harvest, label: "terreno")), author: .weeju))
        return (notebook, harvest, detox, quote, book)
    }

    func testEveryWordMustAppearCaseAndAccentsAside() {
        let (notebook, harvest, _, quote, _) = notebook()
        XCTAssertEqual(notebook.search("HARVEST").map(\.id), [harvest])
        XCTAssertEqual(notebook.search("cafe dawn").map(\.id), [quote], "accents set aside, both words needed")
        XCTAssertEqual(notebook.search("cafe harvest"), [], "one line must hold every word")
        XCTAssertEqual(notebook.search("   "), [], "nothing asked, nothing found")
        XCTAssertEqual(notebook.search("litre").map(\.id), [harvest], "a word is found inside a longer one")
    }

    func testAWordInsideALongerOneFindsRussianEndings() {
        let (notebook, _, detox, _, _) = notebook()
        XCTAssertEqual(notebook.search("youtube").map(\.id), [detox])
        XCTAssertEqual(notebook.search("неделя").map(\.id), [], "a word not there is not found")
        XCTAssertEqual(notebook.search("ден").map(\.id), [detox], "an ending does not hide the word")
    }

    func testFoundThroughAReplyAThingOrATag() {
        let (notebook, harvest, detox, quote, _) = notebook()
        let viaReply = notebook.search("detox")
        XCTAssertEqual(viaReply.map(\.id), [detox])
        XCTAssertEqual(viaReply.first?.via?.text, "Day one of the detox, then.", "the reply that held the word is named")
        XCTAssertNil(notebook.search("youtube").first?.via, "no reply named when the line's own words held it")
        XCTAssertEqual(notebook.search("deutsch").map(\.id), [quote], "through the thing it is with")
        XCTAssertEqual(notebook.search("terreno").map(\.id), [harvest], "through the tag it is under")
        XCTAssertEqual(notebook.search("deutsch book").map(\.id), [quote], "one word in the thing's name, one in the line")
    }

    func testNewestFirstAndThingsByName() {
        let (notebook, harvest, detox, quote, book) = notebook()
        XCTAssertEqual(notebook.search("e").map(\.id), [quote, detox, harvest], "newest first")
        XCTAssertEqual(notebook.things(matching: "infinity deutsch").map(\.id), [book])
        XCTAssertEqual(notebook.things(matching: "terreno").map(\.id), [ULID.tag("terreno")], "tags are things with names too")
        XCTAssertEqual(notebook.things(matching: "fig"), [])
    }

    func testASearchIsAReadOfTheLinesItFound() {
        var (notebook, harvest, detox, _, _) = notebook()
        notebook.apply(event(.visit(.init(what: .search, count: 1, words: "harvest")), author: .weeju))
        XCTAssertEqual(notebook.visits.last?.what, "searched for “harvest”, 1 line")
        XCTAssertEqual(notebook.reads(of: notebook.entry(harvest)!, calendar: utc).count, 1, "the harvest line was read by that search")
        XCTAssertEqual(notebook.reads(of: notebook.entry(detox)!, calendar: utc).count, 0)
    }

    /// A newer build's kind of read is carried by its word and written back as it came,
    /// so an older device never drops a file over it.
    func testAnUnknownKindOfReadIsCarried() throws {
        let raw = #"{"what":"dreams","count":3}"#
        let visit = try JSONDecoder().decode(Payload.Visit.self, from: Data(raw.utf8))
        XCTAssertEqual(visit.what, .other("dreams"))
        XCTAssertEqual(visit.what.rawValue, "dreams")
        let back = String(decoding: try JSONEncoder().encode(visit), as: UTF8.self)
        XCTAssertTrue(back.contains(#""what":"dreams""#), back)
        XCTAssertEqual(Payload.Visit.What(rawValue: "search"), .search)
        XCTAssertEqual(Payload.Visit.What.search.rawValue, "search")
        var notebook = Notebook(owner: me)
        notebook.apply(event(.visit(visit), author: .weeju))
        XCTAssertEqual(notebook.visits.last?.what, "looked at dreams")
    }
}
