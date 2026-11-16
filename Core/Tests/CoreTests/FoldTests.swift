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
        notebook.apply(event(.entryCreate(.init(entry: id, text: "Measure the shelf", startedAt: clock))))
        XCTAssertEqual(notebook.entry(id)?.text, "Measure the shelf")
        XCTAssertNil(notebook.entry(id)?.editedAt)

        notebook.apply(event(.entryEdit(.init(entry: id, text: "Measure the shelf for the brackets"))))
        XCTAssertEqual(notebook.entry(id)?.text, "Measure the shelf for the brackets")
        XCTAssertNotNil(notebook.entry(id)?.editedAt)
        // The words before the change stay on the line's history.
        XCTAssertEqual(notebook.entry(id)?.activity.last?.before, "Measure the shelf")

        notebook.apply(event(.entryDelete(.init(entry: id))))
        XCTAssertNil(notebook.entry(id))
        XCTAssertEqual(notebook.entries, [])
        XCTAssertEqual(notebook.eventCount, 3)
    }

    func testOnlyTheOwnerOpensTheDoor() {
        var notebook = Notebook(owner: me)
        let claude = Grant(name: "Claude Code", author: "a1b2c3", device: "claude-code")
        let grok = Grant(name: "Grok", author: "d4e5f6", device: "grok", writesLines: false)

        // A grant someone else writes is nothing, and does not make them an author.
        notebook.apply(event(.grantCreate(claude.create), author: "stranger", device: "x"))
        XCTAssertEqual(notebook.grants, [])
        XCTAssertEqual(notebook.others, [])

        // The owner's grants open the door, oldest first, with the key left out.
        notebook.apply(event(.grantCreate(claude.create), device: mac))
        notebook.apply(event(.grantCreate(grok.create), device: mac))
        XCTAssertEqual(notebook.grants.map(\.name), ["Claude Code", "Grok"])
        XCTAssertEqual(notebook.grants.map(\.key), ["", ""])
        XCTAssertEqual(notebook.grants.last?.scopes, "read all · write notes · write labels · write links")

        // A key is recognised by its hash and handed back whole; a wrong key opens nothing.
        let opened = notebook.grant(forKey: claude.key)
        XCTAssertEqual(opened?.id, claude.id)
        XCTAssertEqual(opened?.author, "a1b2c3")
        XCTAssertEqual(opened?.key, claude.key)
        XCTAssertNil(notebook.grant(forKey: "nope"))

        // Revoked, the key stops opening the door; the grant stays in the record.
        notebook.apply(event(.grantRevoke(.init(grant: claude.id)), device: mac))
        XCTAssertNil(notebook.grant(forKey: claude.key))
        XCTAssertEqual(notebook.grants.map(\.name), ["Grok"])
        XCTAssertEqual(notebook.allGrants.map(\.name), ["Claude Code", "Grok"])

        // A revoke that arrives before its grant still counts; a second opening of the same id changes nothing.
        let late = Grant(name: "Late", author: "g7h8i9", device: "late")
        notebook.apply(event(.grantRevoke(.init(grant: late.id)), device: mac))
        notebook.apply(event(.grantCreate(late.create), device: mac))
        XCTAssertEqual(notebook.grants.map(\.name), ["Grok"])
        notebook.apply(event(.grantCreate(grok.create), device: mac))
        XCTAssertEqual(notebook.grants.count, 1)
    }

    func testALineBelongsToWhoeverWroteIt() {
        let id = ULID()
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: id, text: "I wrote this", startedAt: clock))))
        notebook.apply(event(.entryEdit(.init(entry: id, text: "Moss changed it")), author: .moss))
        notebook.apply(event(.entryDelete(.init(entry: id)), author: .moss))
        notebook.apply(event(.mediaAttach(.init(entry: id, hash: "x", mime: "image/jpeg")), author: .moss))
        XCTAssertEqual(notebook.entry(id)?.text, "I wrote this")
        XCTAssertEqual(notebook.entry(id)?.media, [])

        // Another author's line is theirs: on their page, not the owner's, and only they change it.
        let theirs = ULID()
        notebook.apply(event(.entryCreate(.init(entry: theirs, text: "Noticed the loaves come out lighter", startedAt: clock)), author: .moss))
        notebook.apply(event(.entryEdit(.init(entry: theirs, text: "Owner changed it"))))
        notebook.apply(event(.entryDelete(.init(entry: theirs))))
        XCTAssertEqual(notebook.entry(theirs)?.text, "Noticed the loaves come out lighter")
        XCTAssertEqual(notebook.entries.map(\.id), [id])
        XCTAssertEqual(notebook.entries(of: .moss).map(\.id), [theirs])
        XCTAssertEqual(notebook.days(of: .moss, calendar: .current).count, 1)
        XCTAssertEqual(notebook.others, [.moss])
        // The owner may still reply under it.
        notebook.apply(event(.noteAdd(.init(entry: theirs, note: ULID(), text: "Good eye"))))
        XCTAssertEqual(notebook.entry(theirs)?.notes.map(\.text), ["Good eye"])
        notebook.apply(event(.entryEdit(.init(entry: theirs, text: "Noticed the loaves come out lighter, 900 g to 820 g")), author: .moss))
        XCTAssertEqual(notebook.entry(theirs)?.text, "Noticed the loaves come out lighter, 900 g to 820 g")
    }

    func testNamesAreChosenAndTheLatestStands() {
        var notebook = Notebook(owner: me)
        XCTAssertNil(notebook.name(of: .moss))
        let first = event(.nameSet(.init(name: "Fern")), author: .moss)
        let second = event(.nameSet(.init(name: "Moss")), author: .moss)
        notebook.apply(second)
        notebook.apply(first)
        XCTAssertEqual(notebook.name(of: .moss), "Moss")
        XCTAssertEqual(notebook.trail.map(\.what), ["chose the name Fern", "chose the name Moss"])
        notebook.apply(event(.nameSet(.init(name: "  ")), author: .moss))
        XCTAssertEqual(notebook.name(of: .moss), "Moss")
        // The owner may choose one too, quietly.
        notebook.apply(event(.nameSet(.init(name: "Sam"))))
        XCTAssertEqual(notebook.name(of: me), "Sam")
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
            event(.noteAdd(.init(entry: id, note: noteID, text: "a note")), author: .moss, device: mac),
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
        let add = event(.noteAdd(.init(entry: id, note: noteID, text: "hello")), author: .moss)
        let remove = event(.noteRemove(.init(note: noteID)), author: .moss)
        notebook.apply(remove)
        notebook.apply(add)
        XCTAssertEqual(notebook.entry(id)?.notes, [])
    }

    func testANoteIsEditedOnlyByItsAuthorAndTheLatestWins() {
        let id = ULID()
        let noteID = ULID()
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: id, text: "line", startedAt: clock))))
        let add = event(.noteAdd(.init(entry: id, note: noteID, text: "hello")), author: .moss)
        let older = event(.noteEdit(.init(note: noteID, text: "hallo")), author: .moss)
        let newer = event(.noteEdit(.init(note: noteID, text: "hullo")), author: .moss)
        let byOwner = event(.noteEdit(.init(note: noteID, text: "mine now")))
        // The edits arrive before the note, and out of order.
        notebook.apply(newer)
        notebook.apply(byOwner)
        notebook.apply(add)
        notebook.apply(older)
        XCTAssertEqual(notebook.entry(id)?.notes.first?.text, "hullo")
        XCTAssertNotNil(notebook.entry(id)?.notes.first?.editedAt)
        XCTAssertEqual(notebook.entry(id)?.activity.map(\.what), ["left a note", "changed a note"])
        XCTAssertEqual(notebook.entry(id)?.activity.last?.before, "hello")
    }

    func testLabelsAreOrderIndependentAndCaseFolded() {
        let id = ULID()
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: id, text: "camera is a black screen", startedAt: clock))))
        let attach = event(.labelAttach(.init(entry: id, label: "App")), author: .moss, device: mac)
        let attachBug = event(.labelAttach(.init(entry: id, label: "bug")), author: .moss, device: mac)
        let detach = event(.labelDetach(.init(entry: id, label: "app")), author: .moss, device: mac)

        notebook.apply(detach)   // the later event arrives first
        notebook.apply(attach)   // the older attach must not resurrect it
        notebook.apply(attachBug)
        XCTAssertEqual(notebook.entry(id)?.labels, ["bug"])
    }

    func testActivityRecordsWhoDidWhat() {
        let id = ULID()
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: id, text: "Voice recording doesn’t play", startedAt: clock))))
        notebook.apply(event(.labelAttach(.init(entry: id, label: "bug")), author: .moss, device: "claude-code"))
        notebook.apply(event(.noteAdd(.init(entry: id, note: ULID(), text: "Playback made stricter.")), author: .moss, device: "claude-code"))
        notebook.apply(event(.entryEdit(.init(entry: id, text: "Voice recording does not play"))))
        notebook.apply(event(.labelDetach(.init(entry: id, label: "bug")), author: .moss, device: "claude-code"))

        let activity = notebook.entry(id)!.activity
        XCTAssertEqual(activity.map(\.what), ["filed under #bug", "left a note", "changed the words", "took #bug off"])
        XCTAssertEqual(activity.map(\.author), [.moss, .moss, me, .moss])
        XCTAssertEqual(activity.first?.device, "claude-code")
        XCTAssertEqual(notebook.entry(id)?.labels, [])
    }

    /// Two lines about one plant, two days apart. Another originator joins them afterwards,
    /// and says the later one finished the earlier.
    func testLinksRunFromALaterLineToAnEarlierOne() {
        let pot = ULID(timestamp: clock), potted = ULID(timestamp: clock.addingTimeInterval(86_400 * 2))
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: pot, text: "The fig cutting needs a pot", startedAt: clock))))
        notebook.apply(event(.entryCreate(.init(entry: potted, text: "Potted the fig cutting", startedAt: clock.addingTimeInterval(86_400 * 2)))))
        notebook.apply(event(.link(.init(from: potted, to: pot)), author: .moss, device: mac))
        notebook.apply(event(.done(.init(entry: pot, by: potted)), author: .moss, device: mac))

        XCTAssertEqual(notebook.entry(potted)?.carriesOn.map(\.to), [pot])
        XCTAssertEqual(notebook.entry(pot)?.carriedOnBy.map(\.from), [potted])
        XCTAssertEqual(notebook.entry(pot)?.carriedOnBy.first?.fromKind, .line)
        XCTAssertEqual(notebook.entry(pot)?.done?.by, potted)
        XCTAssertEqual(notebook.entry(pot)?.done?.byAt, notebook.entry(potted)?.startedAt)
        XCTAssertEqual(notebook.entry(pot)?.done?.author, .moss)
        XCTAssertNil(notebook.entry(potted)?.done)
        XCTAssertEqual(notebook.entry(potted)?.activity.map(\.what), ["linked this to an earlier line"])
        XCTAssertEqual(notebook.entry(pot)?.activity.map(\.what), ["linked a later line to this", "marked this done by a later line"])
        XCTAssertEqual(notebook.trail.map(\.what), ["linked this to an earlier line", "marked this done by a later line"])
        XCTAssertEqual(notebook.trail.first?.entry, potted)

        // The wrong way round, and to itself: nothing.
        notebook.apply(event(.link(.init(from: pot, to: potted)), author: .moss))
        notebook.apply(event(.link(.init(from: pot, to: pot)), author: .moss))
        XCTAssertEqual(notebook.entry(pot)?.carriesOn, [])
        XCTAssertEqual(notebook.entry(potted)?.carriedOnBy, [])
    }

    /// `link.add` with closes, which notebooks written by earlier builds carry, says two things
    /// in one event: a link and the earlier line finished. It folds into both and is recorded
    /// once, in its own words.
    func testTheOlderLinkShapeStillFolds() {
        let pot = ULID(timestamp: clock), potted = ULID(timestamp: clock.addingTimeInterval(86_400 * 2))
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: pot, text: "pot", startedAt: clock))))
        notebook.apply(event(.entryCreate(.init(entry: potted, text: "potted", startedAt: clock.addingTimeInterval(86_400 * 2)))))
        notebook.apply(event(.linkAdd(.init(later: potted, earlier: pot, closes: true)), author: .moss, device: mac))
        XCTAssertEqual(notebook.entry(potted)?.carriesOn.map(\.to), [pot])
        XCTAssertEqual(notebook.entry(pot)?.done?.by, potted)
        XCTAssertEqual(notebook.entry(potted)?.activity.map(\.what), ["closed an earlier line with this"])
        XCTAssertEqual(notebook.entry(pot)?.activity.map(\.what), ["marked this done by a later line"])
        XCTAssertEqual(notebook.trail.map(\.what), ["closed an earlier line with this"])

        // `link.remove` takes the finishing back with the link.
        notebook.apply(event(.linkRemove(.init(later: potted, earlier: pot)), author: "me"))
        XCTAssertEqual(notebook.entry(potted)?.carriesOn, [])
        XCTAssertNil(notebook.entry(pot)?.done)
    }

    func testLinksAreOrderIndependentAndWaitForTheirLines() {
        let pot = ULID(timestamp: clock), potted = ULID(timestamp: clock.addingTimeInterval(3600))
        let createPot = event(.entryCreate(.init(entry: pot, text: "pot", startedAt: clock)))
        let createPotted = event(.entryCreate(.init(entry: potted, text: "potted", startedAt: clock.addingTimeInterval(3600))))
        let add = event(.link(.init(from: potted, to: pot)), author: .moss)
        let again = event(.link(.init(from: potted, to: pot)), author: .moss)
        let remove = event(.unlink(.init(from: potted, to: pot)), author: "me")

        // The link arrives before either line exists; the newest word on the pair wins whatever the order.
        var notebook = Notebook(owner: me)
        notebook.apply(again)
        notebook.apply(add)
        notebook.apply(createPotted)
        notebook.apply(createPot)
        XCTAssertEqual(notebook.entry(pot)?.carriedOnBy.map(\.id), [again.id])
        XCTAssertEqual(notebook.entry(potted)?.carriesOn.map(\.id), [again.id])

        let forward = Notebook(owner: me, events: [createPot, createPotted, add, again])
        XCTAssertEqual(forward.entries, notebook.entries)

        // The owner takes it back: the remove is newest, so an older link arriving late cannot bring it back.
        var taken = Notebook(owner: me, events: [createPot, createPotted, remove])
        taken.apply(again)
        XCTAssertEqual(taken.entry(pot)?.carriedOnBy, [])
        XCTAssertEqual(taken.entry(potted)?.carriesOn, [])
        XCTAssertEqual(taken.entry(potted)?.activity.map(\.what), ["linked this to an earlier line", "took a link back"])
    }

    /// Done is state on the line: the newest word wins, it waits for a line not seen yet, and
    /// it does not need a line that finished it.
    func testDoneIsStateOnTheLine() {
        let books = ULID(timestamp: clock)
        let create = event(.entryCreate(.init(entry: books, text: "Return the library books", startedAt: clock)))
        let done = event(.done(.init(entry: books)), author: .moss)
        let undone = event(.undone(.init(entry: books)), author: "me")

        var notebook = Notebook(owner: me, events: [create])
        notebook.apply(undone)
        notebook.apply(done)
        XCTAssertNil(notebook.entry(books)?.done)
        XCTAssertEqual(notebook.entry(books)?.activity.map(\.what), ["marked this done", "took done back"])

        var late = Notebook(owner: me)
        late.apply(done)
        late.apply(create)
        XCTAssertEqual(late.entry(books)?.done?.id, done.id)
        XCTAssertNil(late.entry(books)?.done?.by)
    }

    /// A note under one line speaks of another: a citation, a link from the note to the line.
    func testANoteCitesALine() {
        let quote = ULID(timestamp: clock), loaf = ULID(timestamp: clock.addingTimeInterval(86_400 * 4))
        var notebook = Notebook(owner: me)
        notebook.apply(event(.entryCreate(.init(entry: quote, text: "Bread is mostly waiting", startedAt: clock))))
        notebook.apply(event(.entryCreate(.init(entry: loaf, text: "Two days for one loaf, most of them waiting", startedAt: clock.addingTimeInterval(86_400 * 4)))))
        let noteID = ULID(timestamp: clock.addingTimeInterval(86_400 * 4 + 60))
        // The citation may reach a device before the note it belongs to.
        notebook.apply(event(.link(.init(from: noteID, to: quote)), author: .moss))
        notebook.apply(event(.noteAdd(.init(entry: loaf, note: noteID, text: "Your quote from the book says the same.")), author: .moss))

        XCTAssertEqual(notebook.entry(loaf)?.notes.first?.cites.map(\.to), [quote])
        XCTAssertEqual(notebook.entry(quote)?.citedBy.map(\.from), [noteID])
        XCTAssertEqual(notebook.entry(quote)?.citedBy.first?.fromEntry, loaf)
        XCTAssertEqual(notebook.entry(quote)?.citedBy.first?.fromKind, .note)
        XCTAssertEqual(notebook.entry(quote)?.carriedOnBy, [])
        XCTAssertEqual(notebook.entry(quote)?.activity.map(\.what), ["cited this in a note"])
        XCTAssertEqual(notebook.note(noteID)?.entry.id, loaf)

        // The note taken back takes its citation with it.
        notebook.apply(event(.noteRemove(.init(note: noteID)), author: "me"))
        XCTAssertEqual(notebook.entry(quote)?.citedBy, [])
    }

    func testAGoneLineHoldsNoThread() {
        let pot = ULID(timestamp: clock), potted = ULID(timestamp: clock.addingTimeInterval(3600))
        var notebook = Notebook(owner: me, events: [
            event(.entryCreate(.init(entry: pot, text: "pot", startedAt: clock))),
            event(.entryCreate(.init(entry: potted, text: "potted", startedAt: clock.addingTimeInterval(3600)))),
            event(.link(.init(from: potted, to: pot)), author: .moss),
            event(.done(.init(entry: pot, by: potted)), author: .moss),
        ])
        XCTAssertEqual(notebook.entry(pot)?.carriedOnBy.count, 1)
        notebook.apply(event(.entryDelete(.init(entry: potted))))
        XCTAssertEqual(notebook.entry(pot)?.carriedOnBy, [])
        // Done is the line's own state; losing the line that finished it does not unfinish it.
        XCTAssertNotNil(notebook.entry(pot)?.done)

        // Deleted first, linked after: the same end state.
        var deletedFirst = Notebook(owner: me, events: [
            event(.entryCreate(.init(entry: pot, text: "pot", startedAt: clock))),
            event(.entryCreate(.init(entry: potted, text: "potted", startedAt: clock.addingTimeInterval(3600)))),
            event(.entryDelete(.init(entry: potted))),
        ])
        deletedFirst.apply(event(.link(.init(from: potted, to: pot)), author: .moss))
        XCTAssertEqual(deletedFirst.entry(pot)?.carriedOnBy, [])
    }

    /// Another originator puts a line on the owner's page under its own name. It is on the
    /// owner's page and not on the originator's; the owner may drop it; nobody else may touch it.
    func testALineOnTheOwnersPageUnderAnotherName() {
        let health: Author = "health"
        let walk = ULID(timestamp: clock)
        var notebook = Notebook(owner: me)
        notebook.apply(event(.nameSet(.init(name: "Health")), author: health))
        notebook.apply(event(.entryCreate(.init(entry: walk, text: "Walk, 4.2 km, 52 min", startedAt: clock, page: me)), author: health))
        XCTAssertEqual(notebook.entries.map(\.id), [walk])
        XCTAssertEqual(notebook.entries(of: health), [])
        XCTAssertEqual(notebook.entry(walk)?.author, health)
        XCTAssertEqual(notebook.entry(walk)?.page, me)

        // A stranger cannot drop it; Health, its author, could; the owner drops it with one hold.
        notebook.apply(event(.entryDelete(.init(entry: walk)), author: "stranger"))
        XCTAssertNotNil(notebook.entry(walk))
        notebook.apply(event(.entryDelete(.init(entry: walk)), author: me))
        XCTAssertNil(notebook.entry(walk))

        // A line without a page named is on its author's own page.
        let own = ULID(timestamp: clock.addingTimeInterval(60))
        notebook.apply(event(.entryCreate(.init(entry: own, text: "A thought of mine", startedAt: clock.addingTimeInterval(60))), author: .moss))
        XCTAssertEqual(notebook.entries(of: .moss).map(\.id), [own])
        XCTAssertEqual(notebook.entries, [])
    }

    /// A source hands the same thing over again to an app put on again. A line an originator
    /// already said at that moment is known, dropped or not, and another moment is not.
    func testWhatASourceAlreadySaidIsKnownByItsMoment() {
        let health: Author = "health"
        // The moment the walk began. The clock here moves on with every event made.
        let began = clock
        let walk = ULID(timestamp: began)
        var notebook = Notebook(owner: me)
        XCTAssertFalse(notebook.hasLine(by: health, startedAt: began))
        notebook.apply(event(.entryCreate(.init(entry: walk, text: "Walk, 4.2 km, 52 min", startedAt: began, page: me)), author: health))
        XCTAssertTrue(notebook.hasLine(by: health, startedAt: began))
        XCTAssertTrue(notebook.hasLine(by: health, startedAt: began.addingTimeInterval(0.4)), "the same moment, to the second")
        XCTAssertFalse(notebook.hasLine(by: health, startedAt: began.addingTimeInterval(90)), "a later walk is another line")
        XCTAssertFalse(notebook.hasLine(by: me, startedAt: began), "the owner wrote nothing then")

        // Dropped by the owner, it is still known: it does not come back.
        notebook.apply(event(.entryDelete(.init(entry: walk)), author: me))
        XCTAssertNil(notebook.entry(walk))
        XCTAssertTrue(notebook.hasLine(by: health, startedAt: began))
    }

    /// A loop is the owner's event: set, stopped, run with a receipt. Only the owner sets or
    /// stops one; the newest set stands; a receipt shows in the log.
    func testLoopsAreTheOwnersEvents() {
        var notebook = Notebook(owner: me)
        let grant = Grant(name: "Claude Code", author: .moss, device: "claude-code")
        notebook.apply(event(.grantCreate(grant.create), device: mac))
        let loop = ULID(timestamp: clock)

        // A stranger's loop is nothing.
        notebook.apply(event(.loopSet(.init(loop: loop, name: "Spy", grant: grant.id, wake: "line")), author: "stranger"))
        XCTAssertEqual(notebook.loops, [])

        notebook.apply(event(.loopSet(.init(loop: loop, name: "Answers", grant: grant.id, wake: "line")), device: mac))
        XCTAssertEqual(notebook.loops.map(\.name), ["Answers"])
        XCTAssertEqual(notebook.loops.first?.wake, .line)
        XCTAssertEqual(notebook.loops.first?.turns, 40)

        // Set again: the same loop, a clock now, in the owner's words.
        notebook.apply(event(.loopSet(.init(loop: loop, name: "The week", grant: grant.id, wake: "clock", at: "09:00", brief: "Read the week as one period.")), device: mac))
        XCTAssertEqual(notebook.loops.map(\.name), ["The week"])
        XCTAssertEqual(notebook.loops.first?.wake, .clock(hour: 9, minute: 0))
        XCTAssertEqual(notebook.loops.first?.wake.words, "every day at 09:00")
        XCTAssertEqual(notebook.loops.first?.brief, "Read the week as one period.")

        // A receipt, under the loop's own originator, shows in the log and on the loop.
        let ran = event(.loopRan(.init(loop: loop, run: ULID(), ok: true, turns: 3, cost: 0.12, summary: "answered two lines",
                                        startedAt: clock, endedAt: clock.addingTimeInterval(40))), author: .moss, device: "loop")
        notebook.apply(ran)
        XCTAssertEqual(notebook.loops.first?.lastRun?.id, ran.id)
        XCTAssertEqual(notebook.trail.last?.what, "ran The week, 3 turns, $0.12")
        XCTAssertEqual(notebook.trail.last?.author, .moss)

        // Stopped by the owner: off, and still in the record.
        notebook.apply(event(.loopStop(.init(loop: loop)), device: mac))
        XCTAssertEqual(notebook.loops, [])
        XCTAssertEqual(notebook.allLoops.map(\.name), ["The week"])

        // Set again after the stop: on again.
        notebook.apply(event(.loopSet(.init(loop: loop, name: "The week", grant: grant.id, wake: "clock", at: "09:00")), device: mac))
        XCTAssertEqual(notebook.loops.map(\.name), ["The week"])
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
