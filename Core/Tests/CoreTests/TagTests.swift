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
        XCTAssertNotEqual(ULID.tag("reading"), ULID.tag("app"))
        XCTAssertTrue(ULID.tag("reading").isTag)
        XCTAssertFalse(ULID(timestamp: clock).isTag, "an id made at a moment is never a tag's")
        XCTAssertEqual(ULID(ULID.tag("reading").string), ULID.tag("reading"), "it is a ULID like any other on the wire")
    }

    func testALabelIsTheLinkToATagEveryoneShares() {
        let line = ULID(timestamp: clock)
        let other = ULID(timestamp: clock.addingTimeInterval(1))
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: line, text: "Notes on the salt chapter", startedAt: clock))))
        notebook.apply(event(.entryCreate(.init(entry: other, text: "Notes on the yeast chapter", startedAt: clock))))
        notebook.apply(event(.labelAttach(.init(entry: line, label: "Reading")), author: .moss))
        notebook.apply(event(.labelAttach(.init(entry: other, label: "reading")), author: "health"))

        let tag = ULID.tag("reading")
        let thing = notebook.thing(tag)
        XCTAssertEqual(thing?.name, "reading")
        XCTAssertNil(thing?.author, "nobody made it")
        XCTAssertNil(thing?.kind)
        XCTAssertEqual(thing?.lines, [line, other], "two originators, one tag")
        XCTAssertEqual(notebook.entry(line)?.labels, ["reading"])
        XCTAssertEqual(notebook.entry(line)?.belongsTo.map(\.to), [tag], "the label is the belonging")
        XCTAssertEqual(notebook.entry(line)?.belongsTo.first?.author, .moss, "signed by whoever filed it")
        XCTAssertEqual(notebook.tags.map(\.name), ["reading"])
        XCTAssertEqual(notebook.allThings.map(\.id), [tag], "a tag with lines stands among the things")
        XCTAssertTrue(notebook.madeThings.isEmpty)
        XCTAssertTrue(notebook.thingNames.isEmpty, "a tag reads as its word, not as a thing's name")
        XCTAssertTrue(notebook.kinds.isEmpty, "tags are not a kind")
        XCTAssertEqual(notebook.entry(line)?.activity.map(\.what), ["filed under #reading"])
    }

    func testATagStandsWhileALineIsUnderIt() {
        let line = ULID(timestamp: clock)
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: line, text: "A bug", startedAt: clock))))
        notebook.apply(event(.labelAttach(.init(entry: line, label: "bug")), author: .moss))
        notebook.apply(event(.labelDetach(.init(entry: line, label: "bug")), author: .moss))
        XCTAssertEqual(notebook.entry(line)?.labels, [])
        XCTAssertTrue(notebook.tags.isEmpty, "an empty tag is not listed")
        XCTAssertTrue(notebook.allThings.isEmpty)
        XCTAssertNotNil(notebook.thing(ULID.tag("bug")), "but its page can still be opened")
        XCTAssertEqual(notebook.entry(line)?.activity.map(\.what), ["filed under #bug", "took #bug off"])

        notebook.apply(event(.labelAttach(.init(entry: line, label: "bug")), author: "fern"))
        XCTAssertEqual(notebook.tags.map(\.name), ["bug"], "the same word is the same tag again")
    }

    func testTheOwnerTakesALabelOffWithAnUnlinkAndDropsATagWhole() {
        let a = ULID(timestamp: clock)
        let b = ULID(timestamp: clock.addingTimeInterval(1))
        let tag = ULID.tag("garden")
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: a, text: "Fig potted", startedAt: clock))))
        notebook.apply(event(.entryCreate(.init(entry: b, text: "Roses pruned", startedAt: clock))))
        notebook.apply(event(.labelAttach(.init(entry: a, label: "garden")), author: .moss))
        notebook.apply(event(.labelAttach(.init(entry: b, label: "garden")), author: .moss))

        // One line out from under the tag: the link taken back, as with any thing.
        notebook.apply(event(.unlink(.init(from: a, to: tag))))
        XCTAssertEqual(notebook.entry(a)?.labels, [])
        XCTAssertEqual(notebook.entry(b)?.labels, ["garden"])
        XCTAssertEqual(notebook.thing(tag)?.lines, [b])

        // The whole tag dropped: every label under it goes; the word is not retired.
        notebook.apply(event(.labelAttach(.init(entry: a, label: "garden")), author: .moss))
        notebook.apply(event(.thingRemove(.init(thing: tag))))
        XCTAssertEqual(notebook.entry(a)?.labels, [])
        XCTAssertEqual(notebook.entry(b)?.labels, [])
        XCTAssertTrue(notebook.tags.isEmpty)
        XCTAssertEqual(notebook.trail.last?.what, "dropped the tag #garden")

        notebook.apply(event(.labelAttach(.init(entry: b, label: "garden")), author: .moss))
        XCTAssertEqual(notebook.entry(b)?.labels, ["garden"], "a label after the drop stands")
        XCTAssertEqual(notebook.thing(tag)?.lines, [b])
    }

    func testOnlyTheOwnerDropsATagAndNobodySetsOne() {
        let a = ULID(timestamp: clock)
        let tag = ULID.tag("idea")
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: a, text: "An idea", startedAt: clock))))
        notebook.apply(event(.labelAttach(.init(entry: a, label: "idea")), author: .moss))
        notebook.apply(event(.thingRemove(.init(thing: tag)), author: .moss))
        XCTAssertEqual(notebook.entry(a)?.labels, ["idea"], "a tag is nobody's to drop but the owner's")
        notebook.apply(event(.thingSet(.init(thing: tag, name: "Ideas", kind: "list")), author: .moss))
        XCTAssertEqual(notebook.thing(tag)?.name, "idea", "a tag is not set; its word is its name")
        XCTAssertNil(notebook.thing(tag)?.kind)
    }

    func testATagTakesFactsLikeAnyThing() {
        let a = ULID(timestamp: clock)
        let tag = ULID.tag("sugar")
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: a, text: "Day one", startedAt: clock))))
        // The fact arrives before the first label on another device: it waits for the tag.
        notebook.apply(event(.factSet(.init(on: tag, key: "days", value: .number(1, unit: nil))), author: .moss))
        XCTAssertNil(notebook.thing(tag))
        notebook.apply(event(.labelAttach(.init(entry: a, label: "sugar")), author: .moss))
        XCTAssertEqual(notebook.thing(tag)?.facts.map(\.key), ["days"])
    }

    func testOrderOfArrivalDoesNotMatter() {
        let a = ULID(timestamp: clock)
        let tag = ULID.tag("app")
        let write = event(.entryCreate(.init(entry: a, text: "The inbox", startedAt: clock)))
        let file = event(.labelAttach(.init(entry: a, label: "app")), author: .moss)
        let unfile = event(.unlink(.init(from: a, to: tag)))
        for order in [[write, file, unfile], [unfile, file, write], [file, unfile, write], [unfile, write, file]] {
            var notebook = Notebook(owner: me)
            for e in order { notebook.apply(e) }
            XCTAssertEqual(notebook.entry(a)?.labels, [], "the newest mark wins: \(order.map(\.kindName))")
            XCTAssertTrue(notebook.tags.isEmpty)
        }
        var notebook = Notebook(owner: me)
        for e in [unfile, write] { notebook.apply(e) }
        notebook.apply(event(.labelAttach(.init(entry: a, label: "app")), author: .moss))
        XCTAssertEqual(notebook.entry(a)?.labels, ["app"], "a label newer than the owner's takeback stands")
    }
}
