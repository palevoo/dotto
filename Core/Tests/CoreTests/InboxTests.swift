import XCTest
@testable import Core

/// The owner's inbox as a projection of the fold.
final class InboxTests: XCTestCase {
    let me: Author = "me"
    let moss: Author = "moss"
    let anna: Author = "anna"
    let generator = ULIDGenerator()
    var clock = Date(timeIntervalSince1970: 1_793_613_600) // 2026-11-02 10:00 UTC

    /// Events by file, as the folder keeps them: one file per author and device.
    var files: [String: [Event]] = [:]

    func tick(_ seconds: TimeInterval = 60) -> Date {
        clock = clock.addingTimeInterval(seconds)
        return clock
    }

    @discardableResult
    func write(_ payload: Payload, by author: Author, device: DeviceID = "phone", at: Date? = nil) -> Event {
        let when = at ?? tick()
        let event = Event(id: generator.next(at: when), author: author, device: device, at: when, payload: payload)
        files["\(author).\(device).jsonl", default: []].append(event)
        return event
    }

    var byFile: [(file: String, events: [Event])] {
        files.keys.sorted().map { ($0, files[$0]!) }
    }

    var notebook: Notebook {
        Notebook(owner: me, events: byFile.flatMap(\.events))
    }

    func items() -> [InboxItem] {
        Inbox.items(files: byFile, notebook: notebook, calendar: .current)
    }

    func testARepliedQuestionWantsTheOwnerUntilAnswered() {
        let line = ULID()
        write(.entryCreate(.init(entry: line, text: "Potted the fig", startedAt: clock)), by: me)
        let note = ULID()
        write(.noteAdd(.init(entry: line, note: note, text: "Which pot, the clay one?")), by: moss)

        var inbox = items()
        XCTAssertEqual(inbox.count, 1)
        XCTAssertEqual(inbox[0].kind, .reply)
        XCTAssertEqual(inbox[0].what, "replied")
        XCTAssertEqual(inbox[0].about, "Potted the fig")
        XCTAssertTrue(inbox[0].asks)
        XCTAssertFalse(inbox[0].answered)
        XCTAssertTrue(inbox[0].wantsYou)
        XCTAssertTrue(inbox[0].unread)

        write(.noteAdd(.init(entry: line, note: ULID(), text: "The clay one")), by: me)
        inbox = items()
        XCTAssertEqual(inbox.count, 1)
        XCTAssertTrue(inbox[0].answered)
        XCTAssertFalse(inbox[0].wantsYou)
    }

    func testALineOnAnotherPageAndAConversationThere() {
        let theirs = ULID()
        write(.entryCreate(.init(entry: theirs, text: "Two harvests so far. Should I keep the yields?", startedAt: clock)), by: moss)
        var inbox = items()
        XCTAssertEqual(inbox.map(\.kind), [.line])
        XCTAssertEqual(inbox[0].what, "wrote")
        XCTAssertTrue(inbox[0].wantsYou)

        // The owner replies on their page; the author answers back: that reply is for the owner.
        write(.noteAdd(.init(entry: theirs, note: ULID(), text: "Yes")), by: me)
        write(.noteAdd(.init(entry: theirs, note: ULID(), text: "Kept, on each line.")), by: moss)
        inbox = items()
        XCTAssertEqual(inbox.map(\.kind), [.reply, .line])
        XCTAssertFalse(inbox[1].wantsYou, "answered once the owner replied")
        XCTAssertNil(inbox[0].about, "a reply on their own page is not about a line of the owner's")

        // A reply on a page the owner has never joined is their own business.
        let aside = ULID()
        write(.entryCreate(.init(entry: aside, text: "Note to self", startedAt: clock)), by: anna)
        write(.noteAdd(.init(entry: aside, note: ULID(), text: "Remember this")), by: anna)
        XCTAssertEqual(items().filter { $0.kind == .reply }.count, 1)
    }

    func testLabelsOnOneDayFoldIntoOneItem() {
        let a = ULID(), b = ULID(), c = ULID()
        for (id, text) in [(a, "Cut two sticks"), (b, "Roots on one"), (c, "Potted")] {
            write(.entryCreate(.init(entry: id, text: text, startedAt: clock)), by: me)
        }
        write(.labelAttach(.init(entry: a, label: "nursery")), by: moss)
        write(.labelAttach(.init(entry: b, label: "Nursery")), by: moss)
        write(.labelAttach(.init(entry: c, label: "nursery")), by: moss)
        write(.labelAttach(.init(entry: c, label: "done")), by: moss)

        let inbox = items()
        XCTAssertEqual(inbox.count, 2)
        let nursery = inbox.first { $0.what.hasSuffix("#nursery") }!
        XCTAssertEqual(nursery.what, "filed 3 lines under #nursery")
        XCTAssertNil(nursery.entry)
        let done = inbox.first { $0.what.hasSuffix("#done") }!
        XCTAssertEqual(done.what, "filed under #done")
        XCTAssertEqual(done.entry, c)
        XCTAssertEqual(done.text, "Potted")

        // A label taken off is no longer news.
        write(.labelDetach(.init(entry: c, label: "done")), by: moss)
        XCTAssertEqual(items().count, 1)
    }

    func testALinkAndAName() {
        let earlier = ULID(), later = ULID()
        write(.entryCreate(.init(entry: earlier, text: "Need to pot this", startedAt: clock)), by: me)
        write(.entryCreate(.init(entry: later, text: "Potted it", startedAt: tick())), by: me)
        write(.linkAdd(.init(later: later, earlier: earlier, closes: true)), by: moss)
        write(.nameSet(.init(name: "Moss")), by: moss)

        let inbox = items()
        XCTAssertEqual(inbox.map(\.kind), [.name, .link])
        XCTAssertEqual(inbox[0].what, "is called Moss now")
        XCTAssertEqual(inbox[1].what, "marked done")
        XCTAssertEqual(inbox[1].entry, later)
        XCTAssertEqual(inbox[1].about, "done by this: Need to pot this")
    }

    func testTheOwnersLookSettlesUnreadByFileCount() {
        let line = ULID()
        write(.entryCreate(.init(entry: line, text: "Potted the fig", startedAt: clock)), by: me)
        write(.noteAdd(.init(entry: line, note: ULID(), text: "Nice")), by: moss)
        XCTAssertEqual(items().filter(\.unread).count, 1)

        // The owner looks, from the phone. The receipt records every file's length.
        let look = Inbox.look(files: byFile, unread: 1)
        write(.visit(look), by: me, device: "phone")
        XCTAssertEqual(items().filter(\.unread).count, 0)
        XCTAssertFalse(notebook.trail.contains { $0.author == me }, "the owner's look is not in the log of what others did")

        // A reply written on the Mac side before the look but arriving after it, with an older id, is still new.
        let late = Event(id: generator.next(at: clock.addingTimeInterval(-3600)), author: moss, device: "mac-door",
                         at: clock.addingTimeInterval(-3600), payload: .noteAdd(.init(entry: line, note: ULID(), text: "Late")))
        files["moss.mac-door.jsonl", default: []].append(late)
        let fresh = items().filter(\.unread)
        XCTAssertEqual(fresh.map(\.text), ["Late"])

        // Looking again from the Mac counts the new file too.
        write(.visit(Inbox.look(files: byFile, unread: 1)), by: me, device: "mac")
        XCTAssertEqual(items().filter(\.unread).count, 0)
    }

    func testNewestFirstAndTheOwnersOwnDoingsAreNotItems() {
        let line = ULID()
        write(.entryCreate(.init(entry: line, text: "Mine", startedAt: clock)), by: me)
        write(.labelAttach(.init(entry: line, label: "mine")), by: me)
        write(.noteAdd(.init(entry: line, note: ULID(), text: "First")), by: moss)
        write(.noteAdd(.init(entry: line, note: ULID(), text: "Second")), by: anna)
        let inbox = items()
        XCTAssertEqual(inbox.map(\.text), ["Second", "First"])
        XCTAssertEqual(inbox.map(\.author), [anna, moss])
    }
}
