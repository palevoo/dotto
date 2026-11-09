import XCTest
@testable import Core

/// A tag is a thing whose id is its word: made by nobody, there while a line is under it,
/// the same thing for every originator on every device. A label is the link to it.
final class TagTests: XCTestCase {
    let me: Author = "me"
    let generator = ULIDGenerator()
    var clock = Date(timeIntervalSince1970: 1_793_613_600) // 2026-11-02 10:00 UTC

    func tick(_ seconds: TimeInterval = 60) -> Date {
        clock = clock.addingTimeInterval(seconds)
        return clock
    }

    func event(_ payload: Payload, author: Author = "me", at: Date? = nil) -> Event {
        let when = at ?? tick()
        return Event(id: generator.next(at: when), author: author, device: "iphone", at: when, payload: payload)
    }

    func testATagsIdIsItsWord() {
        XCTAssertEqual(ULID.tag("Reading"), ULID.tag(" reading "), "the word is normalised first")
        XCTAssertNotEqual(ULID.tag("reading"), ULID.tag("margin"))
        XCTAssertTrue(ULID.tag("reading").isTag)
        XCTAssertFalse(ULID(timestamp: clock).isTag, "an id made at a moment is never a tag's")
        XCTAssertEqual(ULID(ULID.tag("reading").string), ULID.tag("reading"), "it is a ULID like any other on the wire")
    }

    func testALabelIsTheLinkToATagEveryoneShares() {
        let line = ULID(timestamp: clock)
        let other = ULID(timestamp: clock.addingTimeInterval(1))
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: line, text: "Hamming on courage", startedAt: clock))))
        notebook.apply(event(.entryCreate(.init(entry: other, text: "Deutsch on explanation", startedAt: clock))))
        notebook.apply(event(.labelAttach(.init(entry: line, label: "Reading")), author: .weeju))
        notebook.apply(event(.labelAttach(.init(entry: other, label: "reading")), author: "health"))

        let tag = ULID.tag("reading")
        let thing = notebook.thing(tag)
        XCTAssertEqual(thing?.name, "reading")
        XCTAssertNil(thing?.author, "nobody made it")
        XCTAssertNil(thing?.kind)
        XCTAssertEqual(thing?.lines, [line, other], "two originators, one tag")
        XCTAssertEqual(notebook.entry(line)?.labels, ["reading"])
        XCTAssertEqual(notebook.entry(line)?.belongsTo.map(\.to), [tag], "the label is the belonging")
        XCTAssertEqual(notebook.entry(line)?.belongsTo.first?.author, .weeju, "signed by whoever filed it")
        XCTAssertEqual(notebook.tags.map(\.name), ["reading"])
        XCTAssertEqual(notebook.allThings.map(\.id), [tag], "a tag with lines stands among the things")
        XCTAssertTrue(notebook.madeThings.isEmpty)
        XCTAssertTrue(notebook.thingNames.isEmpty, "a tag reads as its word, not as a thing's name")
        XCTAssertTrue(notebook.kinds.isEmpty, "tags are not a kind")
        XCTAssertEqual(notebook.labelCounts, ["reading": 2])
        XCTAssertEqual(notebook.entry(line)?.activity.map(\.what), ["filed under #reading"])
    }

    func testATagStandsWhileALineIsUnderIt() {
        let line = ULID(timestamp: clock)
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: line, text: "A bug", startedAt: clock))))
        notebook.apply(event(.labelAttach(.init(entry: line, label: "bug")), author: .weeju))
        notebook.apply(event(.labelDetach(.init(entry: line, label: "bug")), author: .weeju))
        XCTAssertEqual(notebook.entry(line)?.labels, [])
        XCTAssertTrue(notebook.tags.isEmpty, "an empty tag is not listed")
        XCTAssertTrue(notebook.allThings.isEmpty)
        XCTAssertNotNil(notebook.thing(ULID.tag("bug")), "but its page can still be opened")
        XCTAssertEqual(notebook.entry(line)?.activity.map(\.what), ["filed under #bug", "took #bug off"])

        notebook.apply(event(.labelAttach(.init(entry: line, label: "bug")), author: "margo"))
        XCTAssertEqual(notebook.tags.map(\.name), ["bug"], "the same word is the same tag again")
    }

    func testTheOwnerTakesALabelOffWithAnUnlinkAndDropsATagWhole() {
        let a = ULID(timestamp: clock)
        let b = ULID(timestamp: clock.addingTimeInterval(1))
        let tag = ULID.tag("nursery")
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: a, text: "Fig potted", startedAt: clock))))
        notebook.apply(event(.entryCreate(.init(entry: b, text: "Olive pruned", startedAt: clock))))
        notebook.apply(event(.labelAttach(.init(entry: a, label: "nursery")), author: .weeju))
        notebook.apply(event(.labelAttach(.init(entry: b, label: "nursery")), author: .weeju))

        // One line out from under the tag: the link taken back, as with any thing.
        notebook.apply(event(.unlink(.init(from: a, to: tag))))
        XCTAssertEqual(notebook.entry(a)?.labels, [])
        XCTAssertEqual(notebook.entry(b)?.labels, ["nursery"])
        XCTAssertEqual(notebook.thing(tag)?.lines, [b])

        // The whole tag dropped: every label under it goes; the word is not retired.
        notebook.apply(event(.labelAttach(.init(entry: a, label: "nursery")), author: .weeju))
        notebook.apply(event(.thingRemove(.init(thing: tag))))
        XCTAssertEqual(notebook.entry(a)?.labels, [])
        XCTAssertEqual(notebook.entry(b)?.labels, [])
        XCTAssertTrue(notebook.tags.isEmpty)
        XCTAssertEqual(notebook.trail.last?.what, "dropped the tag #nursery")

        notebook.apply(event(.labelAttach(.init(entry: b, label: "nursery")), author: .weeju))
        XCTAssertEqual(notebook.entry(b)?.labels, ["nursery"], "a label after the drop stands")
        XCTAssertEqual(notebook.thing(tag)?.lines, [b])
    }

    func testOnlyTheOwnerDropsATagAndNobodySetsOne() {
        let a = ULID(timestamp: clock)
        let tag = ULID.tag("idea")
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: a, text: "An idea", startedAt: clock))))
        notebook.apply(event(.labelAttach(.init(entry: a, label: "idea")), author: .weeju))
        notebook.apply(event(.thingRemove(.init(thing: tag)), author: .weeju))
        XCTAssertEqual(notebook.entry(a)?.labels, ["idea"], "a tag is nobody's to drop but the owner's")
        notebook.apply(event(.thingSet(.init(thing: tag, name: "Ideas", kind: "list")), author: .weeju))
        XCTAssertEqual(notebook.thing(tag)?.name, "idea", "a tag is not set; its word is its name")
        XCTAssertNil(notebook.thing(tag)?.kind)
    }

    func testATagTakesFactsLikeAnyThing() {
        let a = ULID(timestamp: clock)
        let tag = ULID.tag("detox")
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: a, text: "Day one", startedAt: clock))))
        // The fact arrives before the first label on another device: it waits for the tag.
        notebook.apply(event(.factSet(.init(on: tag, key: "days", value: .number(1, unit: nil))), author: .weeju))
        XCTAssertNil(notebook.thing(tag))
        notebook.apply(event(.labelAttach(.init(entry: a, label: "detox")), author: .weeju))
        XCTAssertEqual(notebook.thing(tag)?.facts.map(\.key), ["days"])
    }

    func testOrderOfArrivalDoesNotMatter() {
        let a = ULID(timestamp: clock)
        let tag = ULID.tag("margin")
        let write = event(.entryCreate(.init(entry: a, text: "The inbox", startedAt: clock)))
        let file = event(.labelAttach(.init(entry: a, label: "margin")), author: .weeju)
        let unfile = event(.unlink(.init(from: a, to: tag)))
        for order in [[write, file, unfile], [unfile, file, write], [file, unfile, write], [unfile, write, file]] {
            var notebook = Notebook(owner: me)
            for e in order { notebook.apply(e) }
            XCTAssertEqual(notebook.entry(a)?.labels, [], "the newest mark wins: \(order.map(\.kindName))")
            XCTAssertTrue(notebook.tags.isEmpty)
        }
        var notebook = Notebook(owner: me)
        for e in [unfile, write] { notebook.apply(e) }
        notebook.apply(event(.labelAttach(.init(entry: a, label: "margin")), author: .weeju))
        XCTAssertEqual(notebook.entry(a)?.labels, ["margin"], "a label newer than the owner's takeback stands")
    }
}
