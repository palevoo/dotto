import XCTest
@testable import Core

final class FoldTests: XCTestCase {
    let me: Author = "me"
    let phone: DeviceID = "iphone"
    let mac: DeviceID = "mac"
    let generator = ULIDGenerator()

    var clock = Date(timeIntervalSince1970: 1_793_613_600) // 2026-11-02 10:00 UTC

    func tick(_ seconds: TimeInterval = 60) -> Date {
        clock = clock.addingTimeInterval(seconds)
        return clock
    }

    func event(_ payload: Payload, author: Author = "me", device: DeviceID = "iphone", at: Date? = nil) -> Event {
        let when = at ?? tick()
        return Event(id: generator.next(at: when), author: author, device: device, at: when, payload: payload)
    }

    func testCreateEditDelete() {
        let id = ULID()
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: id, text: "Measure the wall", startedAt: clock))))
        XCTAssertEqual(notebook.entry(id)?.text, "Measure the wall")
        XCTAssertNil(notebook.entry(id)?.editedAt)

        notebook.apply(event(.entryEdit(.init(entry: id, text: "Measure the wall for the repairs"))))
        XCTAssertEqual(notebook.entry(id)?.text, "Measure the wall for the repairs")
        XCTAssertNotNil(notebook.entry(id)?.editedAt)
        // The words before the change stay on the line's history.
        XCTAssertEqual(notebook.entry(id)?.activity.last?.before, "Measure the wall")

        notebook.apply(event(.entryDelete(.init(entry: id))))
        XCTAssertNil(notebook.entry(id))
        XCTAssertEqual(notebook.entries, [])
        XCTAssertEqual(notebook.eventCount, 3)
    }

    func testALineBelongsToWhoeverWroteIt() {
        let id = ULID()
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: id, text: "I wrote this", startedAt: clock))))
        notebook.apply(event(.entryEdit(.init(entry: id, text: "Weeju changed it")), author: .weeju))
        notebook.apply(event(.entryDelete(.init(entry: id)), author: .weeju))
        notebook.apply(event(.mediaAttach(.init(entry: id, hash: "x", mime: "image/jpeg")), author: .weeju))
        XCTAssertEqual(notebook.entry(id)?.text, "I wrote this")
        XCTAssertEqual(notebook.entry(id)?.media, [])

        // Another author's line is theirs: on their page, not the owner's, and only they change it.
        let theirs = ULID()
        notebook.apply(event(.entryCreate(.init(entry: theirs, text: "Noticed the yield went up", startedAt: clock)), author: .weeju))
        notebook.apply(event(.entryEdit(.init(entry: theirs, text: "Owner changed it"))))
        notebook.apply(event(.entryDelete(.init(entry: theirs))))
        XCTAssertEqual(notebook.entry(theirs)?.text, "Noticed the yield went up")
        XCTAssertEqual(notebook.entries.map(\.id), [id])
        XCTAssertEqual(notebook.entries(of: .weeju).map(\.id), [theirs])
        XCTAssertEqual(notebook.days(of: .weeju, calendar: .current).count, 1)
        XCTAssertEqual(notebook.others, [.weeju])
        // The owner may still reply under it.
        notebook.apply(event(.noteAdd(.init(entry: theirs, note: ULID(), text: "Good eye"))))
        XCTAssertEqual(notebook.entry(theirs)?.notes.map(\.text), ["Good eye"])
        notebook.apply(event(.entryEdit(.init(entry: theirs, text: "Noticed the yield went up, 11% to 12.5%")), author: .weeju))
        XCTAssertEqual(notebook.entry(theirs)?.text, "Noticed the yield went up, 11% to 12.5%")
    }

    func testNamesAreChosenAndTheLatestStands() {
        var notebook = Notebook(owner: me)
        XCTAssertNil(notebook.name(of: .weeju))
        let first = event(.nameSet(.init(name: "Fern")), author: .weeju)
        let second = event(.nameSet(.init(name: "Moss")), author: .weeju)
        notebook.apply(second)
        notebook.apply(first)
        XCTAssertEqual(notebook.name(of: .weeju), "Moss")
        XCTAssertEqual(notebook.trail.map(\.what), ["chose the name Fern", "chose the name Moss"])
        notebook.apply(event(.nameSet(.init(name: "  ")), author: .weeju))
        XCTAssertEqual(notebook.name(of: .weeju), "Moss")
        // The owner may choose one too, quietly.
        notebook.apply(event(.nameSet(.init(name: "Nikita"))))
        XCTAssertEqual(notebook.name(of: me), "Nikita")
        XCTAssertEqual(notebook.trail.count, 2)
    }

    func testLateOlderEditDoesNotWin() {
        let id = ULID()
        let create = event(.entryCreate(.init(entry: id, text: "one", startedAt: clock)))
        let olderEdit = event(.entryEdit(.init(entry: id, text: "two")), device: mac)
        let newerEdit = event(.entryEdit(.init(entry: id, text: "three")))

        var notebook = Notebook(owner: me)
        notebook.apply(create)
        notebook.apply(newerEdit)
        notebook.apply(olderEdit) // arrives late from the other device
        XCTAssertEqual(notebook.entry(id)?.text, "three")
    }

    func testSameStateInAnyOrder() {
        let id = ULID()
        let noteID = ULID()
        let events = [
            event(.entryCreate(.init(entry: id, text: "one", startedAt: clock))),
            event(.entryEdit(.init(entry: id, text: "two"))),
            event(.mediaAttach(.init(entry: id, hash: "h1", mime: "image/jpeg"))),
            event(.noteAdd(.init(entry: id, note: noteID, text: "a note")), author: .weeju, device: mac),
            event(.mediaAttach(.init(entry: id, hash: "h2", mime: "audio/mp4", duration: 12))),
        ]
        let forward = Notebook(owner: me, events: events)
        var scrambled = Notebook(owner: me)
        for e in [events[3], events[4], events[1], events[0], events[2]] {
            scrambled.apply(e) // one at a time, out of order
        }
        XCTAssertEqual(forward.entries, scrambled.entries)
        XCTAssertEqual(forward.entry(id)?.media.map(\.hash), ["h1", "h2"])
        XCTAssertEqual(forward.entry(id)?.notes.map(\.text), ["a note"])
    }

    func testNoteRemovedBeforeItArrivesStaysRemoved() {
        let id = ULID()
        let noteID = ULID()
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: id, text: "line", startedAt: clock))))
        let add = event(.noteAdd(.init(entry: id, note: noteID, text: "hello")), author: .weeju)
        let remove = event(.noteRemove(.init(note: noteID)), author: .weeju)
        notebook.apply(remove)
        notebook.apply(add)
        XCTAssertEqual(notebook.entry(id)?.notes, [])
    }

    func testLabelsAreOrderIndependentAndCaseFolded() {
        let id = ULID()
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: id, text: "camera is a black screen", startedAt: clock))))
        let attach = event(.labelAttach(.init(entry: id, label: "Margin")), author: .weeju, device: mac)
        let attachBug = event(.labelAttach(.init(entry: id, label: "bug")), author: .weeju, device: mac)
        let detach = event(.labelDetach(.init(entry: id, label: "margin")), author: .weeju, device: mac)

        notebook.apply(detach)   // the later event arrives first
        notebook.apply(attach)   // the older attach must not resurrect it
        notebook.apply(attachBug)
        XCTAssertEqual(notebook.entry(id)?.labels, ["bug"])
        XCTAssertEqual(notebook.labelCounts, ["bug": 1])

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(notebook.days(labelled: "BUG", calendar: utc).first?.entries.map(\.id), [id])
        XCTAssertEqual(notebook.days(labelled: "margin", calendar: utc), [])
    }

    func testActivityRecordsWhoDidWhat() {
        let id = ULID()
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: id, text: "Voice recording doesn’t play", startedAt: clock))))
        notebook.apply(event(.labelAttach(.init(entry: id, label: "bug")), author: .weeju, device: "claude-code"))
        notebook.apply(event(.noteAdd(.init(entry: id, note: ULID(), text: "Playback made stricter.")), author: .weeju, device: "claude-code"))
        notebook.apply(event(.entryEdit(.init(entry: id, text: "Voice recording does not play"))))
        notebook.apply(event(.labelDetach(.init(entry: id, label: "bug")), author: .weeju, device: "claude-code"))

        let activity = notebook.entry(id)!.activity
        XCTAssertEqual(activity.map(\.what), ["filed under #bug", "left a note", "changed the words", "took #bug off"])
        XCTAssertEqual(activity.map(\.author), [.weeju, .weeju, me, .weeju])
        XCTAssertEqual(activity.first?.device, "claude-code")
        XCTAssertEqual(notebook.entry(id)?.labels, [])
    }

    /// Two lines about one plant, three days apart. The reader joins them afterwards.
    func testLinksRunFromALaterLineToAnEarlierOne() {
        let pot = ULID(timestamp: clock), potted = ULID(timestamp: clock.addingTimeInterval(86_400 * 2))
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: pot, text: "Need to plant this baby into a pot", startedAt: clock))))
        notebook.apply(event(.entryCreate(.init(entry: potted, text: "Potted the baby", startedAt: clock.addingTimeInterval(86_400 * 2)))))
        notebook.apply(event(.linkAdd(.init(later: potted, earlier: pot, closes: true)), author: .weeju, device: mac))

        XCTAssertEqual(notebook.entry(potted)?.earlier.map(\.earlier), [pot])
        XCTAssertEqual(notebook.entry(pot)?.later.map(\.later), [potted])
        XCTAssertEqual(notebook.entry(pot)?.closedBy?.later, potted)
        XCTAssertNil(notebook.entry(potted)?.closedBy)
        XCTAssertEqual(notebook.entry(potted)?.activity.map(\.what), ["closed an earlier line with this"])
        XCTAssertEqual(notebook.entry(pot)?.activity.map(\.what), ["marked this done by a later line"])
        XCTAssertEqual(notebook.trail.map(\.what), ["closed an earlier line with this"])
        XCTAssertEqual(notebook.trail.first?.entry, potted)

        // The wrong way round, and to itself: nothing.
        notebook.apply(event(.linkAdd(.init(later: pot, earlier: potted)), author: .weeju))
        notebook.apply(event(.linkAdd(.init(later: pot, earlier: pot)), author: .weeju))
        XCTAssertEqual(notebook.entry(pot)?.earlier, [])
        XCTAssertEqual(notebook.entry(potted)?.later, [])
    }

    func testLinksAreOrderIndependentAndWaitForTheirLines() {
        let pot = ULID(timestamp: clock), potted = ULID(timestamp: clock.addingTimeInterval(3600))
        let createPot = event(.entryCreate(.init(entry: pot, text: "pot", startedAt: clock)))
        let createPotted = event(.entryCreate(.init(entry: potted, text: "potted", startedAt: clock.addingTimeInterval(3600))))
        let add = event(.linkAdd(.init(later: potted, earlier: pot)), author: .weeju)
        let close = event(.linkAdd(.init(later: potted, earlier: pot, closes: true)), author: .weeju)
        let remove = event(.linkRemove(.init(later: potted, earlier: pot)), author: "me")

        // The link arrives before either line exists; the newest word on the pair wins whatever the order.
        var notebook = Notebook(owner: me)
        notebook.apply(close)
        notebook.apply(add)
        notebook.apply(createPotted)
        notebook.apply(createPot)
        XCTAssertEqual(notebook.entry(pot)?.later.map(\.closes), [true])
        XCTAssertEqual(notebook.entry(potted)?.earlier.map(\.id), [close.id])

        let forward = Notebook(owner: me, events: [createPot, createPotted, add, close])
        XCTAssertEqual(forward.entries, notebook.entries)

        // The owner takes it back: the remove is newest, so an older add arriving late cannot bring it back.
        var taken = Notebook(owner: me, events: [createPot, createPotted, remove])
        taken.apply(close)
        XCTAssertEqual(taken.entry(pot)?.later, [])
        XCTAssertEqual(taken.entry(potted)?.earlier, [])
        XCTAssertEqual(taken.entry(potted)?.activity.map(\.what), ["closed an earlier line with this", "took a link back"])
    }

    func testAGoneLineHoldsNoThread() {
        let pot = ULID(timestamp: clock), potted = ULID(timestamp: clock.addingTimeInterval(3600))
        var notebook = Notebook(owner: me, events: [
            event(.entryCreate(.init(entry: pot, text: "pot", startedAt: clock))),
            event(.entryCreate(.init(entry: potted, text: "potted", startedAt: clock.addingTimeInterval(3600)))),
            event(.linkAdd(.init(later: potted, earlier: pot, closes: true)), author: .weeju),
        ])
        XCTAssertNotNil(notebook.entry(pot)?.closedBy)
        notebook.apply(event(.entryDelete(.init(entry: potted))))
        XCTAssertNil(notebook.entry(pot)?.closedBy)
        XCTAssertEqual(notebook.entry(pot)?.later, [])

        // Deleted first, linked after: the same end state.
        var deletedFirst = Notebook(owner: me, events: [
            event(.entryCreate(.init(entry: pot, text: "pot", startedAt: clock))),
            event(.entryCreate(.init(entry: potted, text: "potted", startedAt: clock.addingTimeInterval(3600)))),
            event(.entryDelete(.init(entry: potted))),
        ])
        deletedFirst.apply(event(.linkAdd(.init(later: potted, earlier: pot, closes: true)), author: .weeju))
        XCTAssertEqual(deletedFirst.entry(pot)?.later, [])
    }

    func testDuplicateEventsAreIgnored() {
        let id = ULID()
        let create = event(.entryCreate(.init(entry: id, text: "line", startedAt: clock)))
        let attach = event(.mediaAttach(.init(entry: id, hash: "h", mime: "image/jpeg")))
        let notebook = Notebook(owner: me, events: [create, attach, attach, create])
        XCTAssertEqual(notebook.eventCount, 2)
        XCTAssertEqual(notebook.entry(id)?.media.count, 1)
    }

    func testDaysFollowTheCalendarTimeZone() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        let lateEvening = Date(timeIntervalSince1970: 1_793_660_400) // 2026-11-02 23:00 UTC = 03 Nov 08:00 Tokyo
        let a = ULID(), b = ULID()
        let notebook = Notebook(owner: me, events: [
            event(.entryCreate(.init(entry: a, text: "morning", startedAt: clock)), at: clock),
            event(.entryCreate(.init(entry: b, text: "late", startedAt: lateEvening)), at: lateEvening),
        ])

        XCTAssertEqual(notebook.days(calendar: utc).map(\.key.description), ["2026-11-02"])
        XCTAssertEqual(notebook.days(calendar: tokyo).map(\.key.description), ["2026-11-02", "2026-11-03"])
        XCTAssertEqual(notebook.days(calendar: tokyo).last?.entries.map(\.text), ["late"])
    }
}
