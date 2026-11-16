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

    /// Three lines: the flour, a Russian line about a walk with a reply, and a quote under a book.
    func notebook() -> (Notebook, flour: ULID, walk: ULID, quote: ULID, book: ULID) {
        let flour = ULID(timestamp: clock)
        let walk = ULID(timestamp: clock.addingTimeInterval(1))
        let quote = ULID(timestamp: clock.addingTimeInterval(2))
        let book = ULID(timestamp: clock.addingTimeInterval(3))
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: flour, text: "Bought rye flour, 900 grams", startedAt: tick()))))
        notebook.apply(event(.entryCreate(.init(entry: walk, text: "Сегодня прогулка, 4 км, так записал Health", startedAt: tick()))))
        notebook.apply(event(.entryCreate(.init(entry: quote, text: "Café at dawn, a line from the book", startedAt: tick()))))
        notebook.apply(event(.noteAdd(.init(entry: walk, note: ULID(timestamp: clock.addingTimeInterval(4)), text: "The first of the week, then.")), author: .moss))
        notebook.apply(event(.thingSet(.init(thing: book, name: "The Country Loaf, Ada Hale", kind: "book")), author: .moss))
        notebook.apply(event(.link(.init(from: quote, to: book)), author: .moss))
        notebook.apply(event(.labelAttach(.init(entry: flour, label: "bread")), author: .moss))
        return (notebook, flour, walk, quote, book)
    }

    func testEveryWordMustAppearCaseAndAccentsAside() {
        let (notebook, flour, _, quote, _) = notebook()
        XCTAssertEqual(notebook.search("FLOUR").map(\.id), [flour])
        XCTAssertEqual(notebook.search("cafe dawn").map(\.id), [quote], "accents set aside, both words needed")
        XCTAssertEqual(notebook.search("cafe flour"), [], "one line must hold every word")
        XCTAssertEqual(notebook.search("   "), [], "nothing asked, nothing found")
        XCTAssertEqual(notebook.search("gram").map(\.id), [flour], "a word is found inside a longer one")
    }

    func testAWordInsideALongerOneFindsRussianEndings() {
        let (notebook, _, walk, _, _) = notebook()
        XCTAssertEqual(notebook.search("health").map(\.id), [walk])
        XCTAssertEqual(notebook.search("неделя").map(\.id), [], "a word not there is not found")
        XCTAssertEqual(notebook.search("прогулк").map(\.id), [walk], "an ending does not hide the word")
    }

    func testFoundThroughAReplyAThingOrATag() {
        let (notebook, flour, walk, quote, _) = notebook()
        let viaReply = notebook.search("week")
        XCTAssertEqual(viaReply.map(\.id), [walk])
        XCTAssertEqual(viaReply.first?.via?.text, "The first of the week, then.", "the reply that held the word is named")
        XCTAssertNil(notebook.search("health").first?.via, "no reply named when the line's own words held it")
        XCTAssertEqual(notebook.search("hale").map(\.id), [quote], "through the thing it is with")
        XCTAssertEqual(notebook.search("bread").map(\.id), [flour], "through the tag it is under")
        XCTAssertEqual(notebook.search("hale book").map(\.id), [quote], "one word in the thing's name, one in the line")
    }

    func testNewestFirstAndThingsByName() {
        let (notebook, flour, walk, quote, book) = notebook()
        XCTAssertEqual(notebook.search("e").map(\.id), [quote, walk, flour], "newest first")
        XCTAssertEqual(notebook.things(matching: "country hale").map(\.id), [book])
        XCTAssertEqual(notebook.things(matching: "bread").map(\.id), [ULID.tag("bread")], "tags are things with names too")
        XCTAssertEqual(notebook.things(matching: "fig"), [])
    }

    func testASearchIsAReadOfTheLinesItFound() {
        var (notebook, flour, walk, _, _) = notebook()
        notebook.apply(event(.visit(.init(what: .search, count: 1, words: "flour")), author: .moss))
        XCTAssertEqual(notebook.visits.last?.what, "searched for “flour”, 1 line")
        XCTAssertEqual(notebook.reads(of: notebook.entry(flour)!, calendar: utc).count, 1, "the flour line was read by that search")
        XCTAssertEqual(notebook.reads(of: notebook.entry(walk)!, calendar: utc).count, 0)
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
        notebook.apply(event(.visit(visit), author: .moss))
        XCTAssertEqual(notebook.visits.last?.what, "looked at dreams")
    }
}
