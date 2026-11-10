import Foundation

/// A photo, video or audio file behind an entry.
public struct Media: Hashable, Sendable, Identifiable {
    public var hash: String
    public var mime: String
    public var width: Int?
    public var height: Int?
    public var duration: Double?
    public var at: Date

    public var id: String { hash }
}

/// A line under an entry, by anyone: a reply.
public struct Note: Hashable, Sendable, Identifiable {
    public var id: ULID
    public var entry: ULID
    public var author: Author
    public var text: String
    public var at: Date
    public var editedAt: Date?
    /// The lines this note speaks of: links from the note to each, oldest first.
    public var cites: [Link] = []
    /// The reply this one answers, when it was said under a reply and not under the line.
    public var answers: ULID? = nil
    /// The id of the event that last set `text`, so an older edit arriving late cannot win.
    var lastTextEvent: ULID
}

/// A link joins one thing to another by their ids, and that is all it is. What it means
/// comes from what its ends are: a line to an earlier line is a thread, the later carrying
/// on from the earlier; a note to a line is a citation, the note pointing at the line it
/// speaks of; a line to a thing is belonging, this quote is of that book. One link per
/// pair, from the thing that points to the thing pointed at.
public struct Link: Hashable, Sendable, Identifiable {
    public enum End: Hashable, Sendable {
        case line, note, thing
    }

    /// The event that placed it.
    public let id: ULID
    public let from: ULID
    public let to: ULID
    public let fromKind: End
    public let toKind: End
    /// Where each end is, for going there: the line itself, the line a note sits under, or
    /// the thing.
    public let fromEntry: ULID
    public let toEntry: ULID
    public let author: Author
    public let at: Date
    /// When each end was written, so either side can be named without a lookup.
    public let fromAt: Date
    public let toAt: Date
}

/// A loop as the notebook has it: a sentence said once, kept, run, with a receipt each time.
public struct Loop: Hashable, Sendable, Identifiable {
    public enum Wake: Hashable, Sendable {
        /// When a line lands that the loop's grant has not seen.
        case line
        /// Every day at this hour and minute, in the home's local time.
        case clock(hour: Int, minute: Int)

        public var words: String {
            switch self {
            case .line: "when a line lands"
            case .clock(let hour, let minute): String(format: "every day at %02d:%02d", hour, minute)
            }
        }

        /// As the event says it: "line" or "clock", with "HH:MM" for the clock.
        public var kind: String {
            switch self {
            case .line: "line"
            case .clock: "clock"
            }
        }

        public var at: String? {
            if case .clock(let hour, let minute) = self { return String(format: "%02d:%02d", hour, minute) }
            return nil
        }

        /// From the event's words. A clock without a readable hour is a line.
        public static func parse(_ kind: String, at: String?) -> Wake {
            guard kind == "clock", let at, let colon = at.firstIndex(of: ":"),
                  let hour = Int(at[..<colon]), let minute = Int(at[at.index(after: colon)...]),
                  (0..<24).contains(hour), (0..<60).contains(minute) else { return .line }
            return .clock(hour: hour, minute: minute)
        }
    }

    /// The loop's id, kept across sets; `setBy` is the event that last set it.
    public let id: ULID
    public let setBy: ULID
    public let name: String
    public let grant: ULID
    public let wake: Wake
    public let brief: String?
    public let turns: Int
    public let budget: Double
    public let createdAt: Date
    /// The last receipt, if the loop has run.
    public var lastRun: LoopRun?

    /// Whether this is the same work as another: what would be run, as whom, within what.
    /// A receipt landing does not make it other work.
    public func sameWork(as other: Loop) -> Bool {
        id == other.id && setBy == other.setBy && name == other.name && grant == other.grant && wake == other.wake
            && brief == other.brief && turns == other.turns && budget == other.budget
    }

    /// The hand the loop is: what its events say they came through, and what keeps its own
    /// place in the notebook, so two loops of one originator each see what is new to them
    /// and each write to a file of their own. Its name as a slug, with a little of its id
    /// so two loops of one name are two hands: "the-reader-0epw".
    public var hand: DeviceID {
        let slug = String(name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
            .split(separator: "-").joined(separator: "-")
        // Short enough to pass through the door's header as it is.
        return DeviceID(rawValue: (slug.isEmpty ? "loop" : String(slug.prefix(24))) + "-" + id.string.suffix(4).lowercased())
    }
}

/// A loop someone other than the owner asked for, waiting for the owner's hand: set with
/// one tap, or declined. Gone from the proposals once either has happened.
public struct LoopProposal: Hashable, Sendable, Identifiable {
    public let id: ULID
    public let author: Author
    public let at: Date
    public let name: String
    /// The grant it would run as: the proposer's own.
    public let grant: ULID?
    public let wake: Loop.Wake
    public let brief: String?
    public let turns: Int
    public let budget: Double
}

/// A receipt for one run of a loop, as folded.
public struct LoopRun: Hashable, Sendable, Identifiable {
    public let id: ULID
    public let loop: ULID
    public let author: Author
    public let ok: Bool
    public let turns: Int?
    public let cost: Double?
    public let summary: String
    public let startedAt: Date
    public let endedAt: Date
}

/// A line is finished. State on the line, not a connection: the first fact.
public struct Done: Hashable, Sendable {
    /// The event that marked it.
    public let id: ULID
    /// The line that finished it, when one did, and when that line started if it is known.
    public let by: ULID?
    public let byAt: Date?
    public let author: Author
    public let at: Date
}

/// A fact: a key and a value on a line or a thing, by an originator. The yield on the
/// harvest line, the fig's state, the detox's days. One per originator per key; newest wins.
public struct Fact: Hashable, Sendable, Identifiable {
    /// The event that set it.
    public let id: ULID
    /// The line or thing it is on.
    public let on: ULID
    public let key: String
    public let value: FactValue
    public let author: Author
    public let at: Date
}

/// A thing: a shape with an id and a name that lines belong to. A fig, a book, a person,
/// the detox. Made by an originator, standing until dropped; its facts are its state, and
/// its lines are the captures linked to it.
///
/// A tag is the simplest thing: its name is a word, its id comes from the word, and nobody
/// made it. It is there as long as a line is under it, and anyone's label is the link.
public struct Thing: Hashable, Sendable, Identifiable {
    public let id: ULID
    public var name: String
    /// A word: plant, book, person. Not a link, for now.
    public var kind: String?
    /// Who made it; nobody, for a tag.
    public let author: Author?
    /// When it was made; for a tag, the earliest label seen.
    public var createdAt: Date
    /// The event that last set its name or kind.
    public var setBy: ULID
    public var facts: [Fact] = []
    /// Links from the lines that belong to it, oldest first.
    public var incoming: [Link] = []

    /// The lines that belong to it, oldest link first.
    public var lines: [ULID] { incoming.map(\.fromEntry) }

    /// A tag: a word nobody made, that lines are filed under.
    public var isTag: Bool { id.isTag }
}

/// What the page shows: the fold of every event about one line.
public struct Entry: Hashable, Sendable, Identifiable {
    public var id: ULID
    public var author: Author
    /// Whose page it is on: its author's, or the owner's when another originator put it there.
    public var page: Author
    public var startedAt: Date
    public var text: String
    public var location: Location?
    public var media: [Media] = []
    public var notes: [Note] = []
    public var editedAt: Date?
    public var isDeleted = false

    /// Links from this line to other things, oldest first.
    public var outgoing: [Link] = []
    /// Links from other things to this line, oldest first.
    public var incoming: [Link] = []
    /// Finished, when it is.
    public var done: Done?
    /// Facts on this line, by key then by originator.
    public var facts: [Fact] = []

    /// The thread back: earlier lines this one carries on from.
    public var carriesOn: [Link] { outgoing.filter { $0.toKind == .line } }
    /// The thread forward: later lines that carry on from this one.
    public var carriedOnBy: [Link] { incoming.filter { $0.fromKind == .line } }
    /// Notes, under this or other lines, that speak of this line.
    public var citedBy: [Link] { incoming.filter { $0.fromKind == .note } }
    /// The things this line belongs to.
    public var belongsTo: [Link] { outgoing.filter { $0.toKind == .thing } }

    /// The facts under one key, by every originator that put one.
    public func facts(_ key: String) -> [Fact] { facts.filter { $0.key == key } }

    /// Something to do, by anyone's word, and not done.
    public var isTodo: Bool { done == nil && !facts("todo").isEmpty }

    /// The moment it is due, when any originator put one: the earliest of them.
    public var due: Date? {
        facts("due").compactMap { if case .moment(let at) = $0.value { return at }; return nil }.min()
    }

    /// The tags this line is under, by word, sorted: the things among `belongsTo` that are
    /// tags, kept here so the word is at hand without the things.
    public var labels: [String] = []

    /// Everything anyone did to this line after it was written, oldest first.
    /// The accountability trail: who, from where, when, what.
    public var activity: [Activity] = []

    /// The id of the event that last set `text`, so an older edit arriving late cannot win.
    var lastTextEvent: ULID
}

/// One thing done to a line, by someone, from somewhere, at some time.
public struct Activity: Hashable, Sendable, Identifiable {
    public let id: ULID
    public let author: Author
    public let device: DeviceID
    public let at: Date
    public let what: String
    /// What was there before, when the thing done replaced something: the words an edit
    /// took the place of. Nothing is lost by changing a line.
    public let before: String?
}

/// Someone read something through the door: the receipt as folded.
public struct Visit: Hashable, Sendable, Identifiable {
    public let id: ULID
    public let author: Author
    public let device: DeviceID
    public let at: Date
    public let read: Payload.Visit

    /// "read 4 lines", "read 3 lines under #bug", "looked at a photo", "found 2 new things".
    public var what: String {
        switch read.what {
        case .photo:
            return "looked at a photo"
        case .inbox:
            return read.count == 0 ? "found nothing new" : "found \(read.count) new thing\(read.count == 1 ? "" : "s")"
        case .things:
            return "looked at \(read.count) thing\(read.count == 1 ? "" : "s")"
        case .loops:
            return "looked at the loops"
        case .search:
            return "searched for “\(read.words ?? "")”, \(read.count) line\(read.count == 1 ? "" : "s")"
        case .other(let word):
            return "looked at \(word)"
        case .days, .lines:
            var text = "read \(read.count) line\(read.count == 1 ? "" : "s")"
            if let label = read.label { text += " under #\(label)" }
            if let since = read.since { text += " since \(since)" }
            return text
        }
    }
}

/// A line found by search: the line, and, when its own words did not hold every term,
/// the reply under it that did.
public struct SearchHit: Hashable, Sendable, Identifiable {
    public let entry: Entry
    public let via: Note?
    public var id: ULID { entry.id }
}

/// One thing anyone other than the owner's pen did, anywhere in the notebook: a visit, a
/// note, a label. In order, the log of who read and wrote what.
public struct Trace: Hashable, Sendable, Identifiable {
    public let id: ULID
    public let author: Author
    public let device: DeviceID
    public let at: Date
    public let what: String
    /// The line it was about, when it was about one.
    public let entry: ULID?
}

/// A calendar day in the notebook's time zone.
public struct DayKey: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year!
        month = parts.month!
        day = parts.day!
    }

    public func date(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// `2026-11-02`
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

public struct Day: Hashable, Sendable, Identifiable {
    public let key: DayKey
    public let entries: [Entry]

    public init(key: DayKey, entries: [Entry]) {
        self.key = key
        self.entries = entries
    }

    public var id: DayKey { key }
}

/// The fold. Feed it events in any order and it reaches the same state:
/// edits are ordered by event id, tombstones are final, a note removed before it
/// arrived stays removed, and anything about an entry not yet created waits for it.
///
/// The one rule it enforces: a line belongs to whoever wrote it. Only its author edits it,
/// deletes it or puts media behind it. Anyone may write lines of their own, which make up
/// their own page; the owner's page is the notebook. Notes, labels and links go anywhere.
public struct Notebook: Sendable {
    public let owner: Author

    private var table: [ULID: Entry] = [:]
    /// Per author, the newest name chosen.
    private var names: [Author: Newest<String>] = [:]
    /// Everyone other than the owner who has left anything, in order of first appearance.
    public private(set) var others: [Author] = []
    /// Every grant the owner has opened, by id, revoked or not.
    private var grantMarks: [ULID: GrantMark] = [:]
    /// Grants revoked before their opening was seen.
    private var revokedGrants: Set<ULID> = []
    /// Every loop the owner has set, by id, with its latest set and whether it was stopped after.
    private var loopMarks: [ULID: LoopMark] = [:]
    /// The newest receipt per loop.
    private var loopRuns: [ULID: Newest<LoopRun>] = [:]
    /// Every loop proposed by someone other than the owner, by its id, taken or not.
    private var proposals: [ULID: LoopProposal] = [:]

    private struct LoopMark: Hashable, Sendable {
        var loop: Loop
        /// The id of the latest stop, if any; the loop is off when it is newer than the set.
        var stoppedBy: ULID?
    }

    private struct GrantMark: Hashable, Sendable {
        let grant: Grant
        var revoked: Bool
    }
    private var noteToEntry: [ULID: ULID] = [:]
    /// Per reply, who has taken it back. It is gone when one of them was its writer or the owner.
    private var removedNotes: [ULID: Set<Author>] = [:]
    /// Edits to notes not seen yet.
    private var pendingNoteEdits: [ULID: [Event]] = [:]
    /// Per pair of ends, the newest link or unlink seen, so order of arrival does not matter.
    private var linkMarks: [LinkPair: Newest<LinkMark>] = [:]
    /// Per line, the newest done or undone seen.
    private var doneMarks: [ULID: Newest<DoneMark>] = [:]
    /// Every thing standing, by id.
    private var things: [ULID: Thing] = [:]
    /// Things dropped; a drop is final, and a set arriving late does not bring one back.
    private var removedThings: Set<ULID> = []
    /// Per line or thing, per key, per originator: the newest fact or its removal.
    private var factMarks: [FactKey: Newest<FactMark>] = [:]
    /// The fact keys on each line or thing, so its facts can be read back without a scan.
    private var factsOn: [ULID: Set<FactKey>] = [:]

    private struct FactKey: Hashable, Sendable {
        let on: ULID
        let key: String
        let author: Author
    }

    private struct FactMark: Hashable, Sendable {
        /// Nil when the fact was taken off.
        let value: FactValue?
        let at: Date
    }
    /// Events about a thing not seen yet, by that thing's id: a line or a note.
    private var waiting: [ULID: [Event]] = [:]
    private var seen: Set<ULID> = []

    private struct LinkPair: Hashable, Sendable {
        let from: ULID
        let to: ULID
    }

    private struct LinkMark: Hashable, Sendable {
        let on: Bool
        let author: Author
        let at: Date
    }

    private struct DoneMark: Hashable, Sendable {
        let on: Bool
        let by: ULID?
        let author: Author
        let at: Date
    }

    public private(set) var eventCount = 0

    /// Every read through the door, oldest first.
    public private(set) var visits: [Visit] = []
    /// Every visit, note and label by anyone, oldest first. The log.
    public private(set) var trail: [Trace] = []

    public init(owner: Author, events: some Sequence<Event> = []) {
        self.owner = owner
        apply(events)
    }

    public mutating func apply(_ events: some Sequence<Event>) {
        let events = Array(events)
        // Who is the same as whom is known before anything is folded, so it holds for an
        // event however early it was written and whatever order the files came in.
        for event in events { remember(event) }
        for event in events.sorted(by: { $0.id < $1.id }) {
            apply(event)
        }
    }

    // MARK: - Originators that are one

    /// Per originator, the one the owner says it is the same as; the newest word stands.
    private var sameAs: [Author: Newest<Author>] = [:]

    /// Takes the owner's word that two originators are one. Nobody is the owner's same.
    private mutating func remember(_ event: Event) {
        guard case .same(let p) = event.payload, event.author == owner, p.author != owner, p.same != owner, p.author != p.same else { return }
        sameAs.mark(p.author, p.same, by: event.id)
    }

    /// The originator an id stands for today: itself, or the one the owner said it is the
    /// same as. Followed a few steps, so one said to be another that is in turn dotto is dotto.
    public func resolved(_ author: Author) -> Author {
        var author = author
        for _ in 0..<4 {
            guard let next = sameAs[author]?.value else { break }
            author = next
        }
        return author
    }

    /// An event as its originator stands today. The id, the hand and the words are as written.
    public func resolved(_ event: Event) -> Event {
        let author = resolved(event.author)
        var payload = event.payload
        switch payload {
        case .entryCreate(var p):
            if let page = p.page { p.page = resolved(page); payload = .entryCreate(p) }
        case .factRemove(var p):
            if let of = p.of { p.of = resolved(of); payload = .factRemove(p) }
        case .grantCreate(var p):
            p.author = resolved(p.author); payload = .grantCreate(p)
        default:
            break
        }
        guard author != event.author || payload != event.payload else { return event }
        return Event(id: event.id, author: author, device: event.device, at: event.at, payload: payload)
    }

    /// Every file's events as their originators stand today, for what reads the files
    /// beside the fold: the inbox, what a hand has not seen.
    public func resolved(_ files: [(file: String, events: [Event])]) -> [(file: String, events: [Event])] {
        files.map { ($0.file, $0.events.map { asRead(resolved($0)) }) }
    }

    public mutating func apply(_ written: Event) {
        guard !seen.contains(written.id) else { return }
        seen.insert(written.id)
        eventCount += 1
        remember(written)
        let event = resolved(written)
        // Only the owner opens or closes the door, and only the owner sets or stops a loop.
        if let kind = event.kind, [.grantCreate, .grantRevoke, .loopSet, .loopStop].contains(kind), event.author != owner { return }
        if event.author != owner, !others.contains(event.author) { others.append(event.author) }

        switch event.payload {
        case .entryCreate(let p):
            if let under = p.under { return said(event, p, under: under) }
            if table[p.entry] != nil { return }
            table[p.entry] = Entry(
                id: p.entry,
                author: event.author,
                page: p.page ?? event.author,
                startedAt: p.startedAt,
                text: p.text,
                location: p.location,
                lastTextEvent: event.id
            )
            if let queued = waiting.removeValue(forKey: p.entry) {
                for later in queued.sorted(by: { $0.id < $1.id }) {
                    apply(later, toExisting: p.entry)
                }
            }

        case .entryEdit(let p):
            // A reply is a line too: a change to one is a change to its words under its line.
            if noteToEntry[p.entry] != nil { return changeReply(event, p) }
            applyOrWait(event, entry: p.entry)

        case .entryDelete(let p):
            if noteToEntry[p.entry] != nil { return removeNote(event, p.entry) }
            applyOrWait(event, entry: p.entry)

        case .mediaAttach(let p):
            applyOrWait(event, entry: p.entry)

        case .noteAdd(let p):
            applyOrWait(event, entry: p.entry)

        case .labelAttach, .labelDetach:
            tag(event)

        case .linkAdd, .linkRemove, .link, .unlink, .done, .undone:
            join(event)

        case .thingSet, .thingRemove:
            shape(event)

        case .factSet, .factRemove:
            fact(event)

        case .noteRemove(let p):
            removeNote(event, p.note)

        case .noteEdit(let p):
            // Only the note's author changes its words; an edit that arrives before the note waits on its line.
            if let entryID = noteToEntry[p.note] {
                applyOrWait(event, entry: entryID)
            } else {
                pendingNoteEdits[p.note, default: []].append(event)
            }

        case .visit(let p):
            let visit = Visit(id: event.id, author: event.author, device: event.device, at: event.at, read: p)
            visits.insert(visit, at: Self.place(of: visit.id, in: visits, by: \.id))
            // The owner's own looks at the inbox are receipts for unread, not the log of what others did.
            if event.author != owner { trace(event, visit.what, entry: p.entry) }

        case .nameSet(let p):
            let name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            names.mark(event.author, name, by: event.id)
            if event.author != owner { trace(event, "chose the name \(name)", entry: nil) }

        case .grantCreate(let p):
            guard grantMarks[p.grant] == nil else { return }
            grantMarks[p.grant] = GrantMark(grant: Grant(p, createdAt: event.at), revoked: revokedGrants.contains(p.grant))

        case .grantRevoke(let p):
            revokedGrants.insert(p.grant)
            grantMarks[p.grant]?.revoked = true

        case .loopPropose(let p):
            // Said once; a second proposal with the same id changes nothing.
            guard proposals[p.loop] == nil else { return }
            let name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let wake = Loop.Wake.parse(p.wake, at: p.at)
            proposals[p.loop] = LoopProposal(id: p.loop, author: event.author, at: event.at, name: name, grant: p.grant, wake: wake,
                                             brief: p.brief?.trimmingCharacters(in: .whitespacesAndNewlines), turns: p.turns, budget: p.budget)
            trace(event, "proposed a loop: \(name), \(wake.words)", entry: nil)

        case .loopSet(let p):
            guard loopMarks[p.loop].map({ $0.loop.setBy < event.id }) ?? true else { return }
            let wake = Loop.Wake.parse(p.wake, at: p.at)
            let loop = Loop(id: p.loop, setBy: event.id, name: p.name, grant: p.grant, wake: wake, brief: p.brief,
                            turns: p.turns, budget: p.budget, createdAt: loopMarks[p.loop]?.loop.createdAt ?? event.at, lastRun: loopRuns[p.loop]?.value)
            loopMarks[p.loop] = LoopMark(loop: loop, stoppedBy: loopMarks[p.loop]?.stoppedBy)

        case .loopStop(let p):
            if var mark = loopMarks[p.loop] {
                if mark.stoppedBy.map({ $0 < event.id }) ?? true { mark.stoppedBy = event.id }
                loopMarks[p.loop] = mark
            } else {
                // Stopped before its set was seen: remembered until it is.
                loopMarks[p.loop] = nil
                stoppedLoops[p.loop] = max(stoppedLoops[p.loop] ?? event.id, event.id)
            }

        case .loopRan(let p):
            let run = LoopRun(id: event.id, loop: p.loop, author: event.author, ok: p.ok, turns: p.turns, cost: p.cost,
                              summary: p.summary, startedAt: p.startedAt, endedAt: p.endedAt)
            if loopRuns.mark(p.loop, run, by: event.id) {
                loopMarks[p.loop]?.loop.lastRun = run
            }
            let name = loopMarks[p.loop]?.loop.name ?? "a loop"
            var what = "ran \(name)"
            if let turns = p.turns { what += ", \(turns) turn\(turns == 1 ? "" : "s")" }
            if let cost = p.cost { what += String(format: ", $%.2f", cost) }
            if !p.ok { what += ", and failed" }
            trace(event, what, entry: nil)

        case .same:
            // Taken before anything was folded, in `remember`.
            break

        case .unknown:
            // From a newer build. Counted, kept, and left for a build that knows it.
            break
        }
    }

    // MARK: - Lines said under something

    /// A line said under something. Under a line it is a reply; under a reply, an answer to
    /// it in the same conversation; either way it joins the line's conversation, where the
    /// replies written the older way already are. Under a thing it is something said on that
    /// thing's page, which has no screen yet: it is kept in the file and shown nowhere.
    /// Under something not here yet, it waits for it.
    private mutating func said(_ event: Event, _ p: Payload.EntryCreate, under: ULID) {
        guard noteToEntry[p.entry] == nil, table[p.entry] == nil else { return }
        if things[under] != nil || removedThings.contains(under) { return }
        let line: ULID
        var answers: ULID?
        if table[under] != nil {
            line = under
        } else if let root = noteToEntry[under] {
            line = root
            answers = under
        } else {
            return waiting[under, default: []].append(event)
        }
        let reply = Event(id: event.id, author: event.author, device: event.device, at: event.at,
                          payload: .noteAdd(.init(entry: line, note: p.entry, text: p.text)))
        apply(reply, toExisting: line)
        if let index = table[line]?.notes.firstIndex(where: { $0.id == p.entry }) {
            table[line]?.notes[index].answers = answers
            table[line]?.notes[index].at = p.startedAt
        }
    }

    /// The words of a reply changed, by a line's own kind of change.
    private mutating func changeReply(_ event: Event, _ p: Payload.EntryEdit) {
        guard let line = noteToEntry[p.entry] else { return }
        let change = Event(id: event.id, author: event.author, device: event.device, at: event.at,
                           payload: .noteEdit(.init(note: p.entry, text: p.text)))
        applyOrWait(change, entry: line)
    }

    /// A reply taken back. Whoever wrote it may, and the owner may; anyone else's word is
    /// kept and changes nothing. It may come before the reply does, and holds then.
    private mutating func removeNote(_ event: Event, _ id: ULID) {
        removedNotes[id, default: []].insert(event.author)
        guard let entryID = noteToEntry[id], var entry = table[entryID],
              let gone = entry.notes.first(where: { $0.id == id }),
              event.author == gone.author || event.author == owner else { return }
        // A gone note cites nothing: the lines it spoke of forget it.
        for link in gone.cites { table[link.to]?.incoming.removeAll { $0.id == link.id } }
        entry.notes.removeAll { $0.id == id }
        note(&entry, event, "took a note back")
        table[entryID] = entry
    }

    /// Something that waited for a reply, now that the reply is here: an answer to it, a
    /// change to it, its being taken back, a link that cites it.
    private mutating func afterReply(_ event: Event) {
        switch event.payload {
        case .entryCreate(let p):
            if let under = p.under { said(event, p, under: under) }
        case .entryEdit(let p):
            changeReply(event, p)
        case .entryDelete(let p):
            removeNote(event, p.entry)
        default:
            join(event)
        }
    }

    /// An event as the notebook reads it: a line said under a line is a reply, and a change
    /// to it or its being dropped is a change to a reply or its being taken back. For what
    /// reads the files beside the fold and tells of replies.
    private func asRead(_ event: Event) -> Event {
        let payload: Payload
        switch event.payload {
        case .entryCreate(let p):
            guard p.under != nil, let line = noteToEntry[p.entry] else { return event }
            payload = .noteAdd(.init(entry: line, note: p.entry, text: p.text))
        case .entryEdit(let p):
            guard noteToEntry[p.entry] != nil else { return event }
            payload = .noteEdit(.init(note: p.entry, text: p.text))
        case .entryDelete(let p):
            guard noteToEntry[p.entry] != nil else { return event }
            payload = .noteRemove(.init(note: p.entry))
        default:
            return event
        }
        return Event(id: event.id, author: event.author, device: event.device, at: event.at, payload: payload)
    }

    private var stoppedLoops: [ULID: ULID] = [:]

    /// The grants that open the door today, oldest first. Keys are not in the notebook;
    /// whoever holds one fills it in.
    public var grants: [Grant] {
        grantMarks.values.filter { !$0.revoked }.map(\.grant).sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// Every grant the owner ever opened, revoked ones included, oldest first.
    public var allGrants: [Grant] {
        grantMarks.values.map(\.grant).sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// The loops that run today, oldest first: set, and not stopped since.
    public var loops: [Loop] {
        let set = loopMarks.values
            .filter { mark in
                let stopped = mark.stoppedBy ?? stoppedLoops[mark.loop.id]
                return stopped.map { $0 < mark.loop.setBy } ?? true
            }
            .map(\.loop)
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        // A receipt of the reading is every sentence's: it ran with all of them in mind.
        return set.map { loop in
            guard loop.wake == .line else { return loop }
            var loop = loop
            loop.lastRun = sentences(with: loop, among: set).compactMap(\.lastRun).max { $0.id < $1.id }
            return loop
        }
    }

    // MARK: - What an originator has learned

    /// What an originator has learned here from being told: the lines on its own page it
    /// filed under `learned`, oldest first. Every hand of it is told them on arrival, so a
    /// correction made once holds for every reading after. Its own to change and delete;
    /// the owner's to drop. The newest are kept when there are too many to say at once.
    public func learned(by author: Author, atMost count: Int = 40, characters: Int = 6000) -> [String] {
        var kept: [String] = []
        var used = 0
        for entry in entries(of: resolved(author)).reversed() where entry.author == resolved(author) && entry.labels.contains("learned") {
            let text = entry.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            guard kept.count < count, used + text.count <= characters else { break }
            kept.append(text)
            used += text.count
        }
        return kept.reversed()
    }

    // MARK: - The reading

    /// What the home runs. A loop is a sentence, said once and kept. One woken by the clock
    /// is run at its hour, by itself. Those woken by a line are not run each by itself: an
    /// originator reads what lands once, with every such sentence kept in mind and the whole
    /// notebook in view, where a session for each read the same line with half the picture,
    /// twice. That one reading stands here as a loop of its own, under the oldest of them, so
    /// its receipts have a place; the clock loops follow as they are.
    public var running: [Loop] {
        let all = loops
        var readings: [Loop] = []
        var placed: Set<ULID> = []
        for loop in all where loop.wake == .line && !placed.contains(loop.id) {
            let together = sentences(with: loop, among: all)
            together.forEach { placed.insert($0.id) }
            readings.append(Self.reading(of: together))
        }
        return readings + all.filter { $0.wake != .line }
    }

    /// The reading a line-woken loop is part of; nil for a loop woken by the clock, or stopped.
    public func reading(holding loop: Loop) -> Loop? {
        guard loop.wake == .line else { return nil }
        let together = sentences(with: loop, among: loops)
        return together.contains { $0.id == loop.id } ? Self.reading(of: together) : nil
    }

    /// The line-woken loops of the same originator as one, oldest first.
    private func sentences(with loop: Loop, among all: [Loop]) -> [Loop] {
        func who(_ loop: Loop) -> String { grantMarks[loop.grant].map { "by:" + $0.grant.author.rawValue } ?? "grant:" + loop.grant.string }
        let mine = who(loop)
        return all.filter { $0.wake == .line && who($0) == mine }
    }

    /// One reading out of the sentences kept in mind. It comes through the key of the oldest,
    /// and is allowed the most any one of them was.
    private static func reading(of sentences: [Loop]) -> Loop {
        let first = sentences[0]
        let kept = sentences.compactMap { loop -> String? in
            guard let words = loop.brief?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty else { return nil }
            return "- \(loop.name): \(words)"
        }
        let brief = kept.isEmpty ? nil
            : "Keep in mind as you read, at the owner's word, each said once and standing until they take it back:\n" + kept.joined(separator: "\n")
        return Loop(id: first.id, setBy: sentences.map(\.setBy).max() ?? first.setBy, name: "The reading", grant: first.grant, wake: .line,
                    brief: brief, turns: sentences.map(\.turns).max() ?? first.turns, budget: sentences.map(\.budget).max() ?? first.budget,
                    createdAt: first.createdAt, lastRun: sentences.compactMap(\.lastRun).max { $0.id < $1.id })
    }

    /// Every loop ever set, stopped ones included, oldest first.
    public var allLoops: [Loop] {
        loopMarks.values.map(\.loop).sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// The loops proposed and still waiting for the owner: not set, not declined, oldest first.
    public var loopProposals: [LoopProposal] {
        proposals.values
            .filter { loopMarks[$0.id] == nil && stoppedLoops[$0.id] == nil }
            .sorted { ($0.at, $0.id) < ($1.at, $1.id) }
    }

    /// A proposal by its id, waiting or not.
    public func loopProposal(_ id: ULID) -> LoopProposal? {
        proposals[id]
    }

    /// The open grant a key belongs to, with the key filled in. Nil means the door stays shut.
    public func grant(forKey key: String) -> Grant? {
        let hash = Grant.hash(key)
        guard var grant = grants.first(where: { $0.keyHash == hash }) else { return nil }
        grant.key = key
        return grant
    }

    /// What an author is called, if they have chosen. Nobody is called anything until then,
    /// but the notebook's own, which is dotto until it is named.
    public func name(of author: Author) -> String? {
        let author = resolved(author)
        return names[author]?.value ?? (author == .dotto ? "dotto" : nil)
    }

    /// Every name, by author id: the chosen ones, and dotto's own once it has done anything.
    public var chosenNames: [Author: String] {
        var all = names.mapValues(\.value)
        if all[.dotto] == nil, others.contains(.dotto) { all[.dotto] = "dotto" }
        return all
    }

    /// Something done to one line: on the line's own trail and on the notebook's.
    private mutating func note(_ entry: inout Entry, _ event: Event, _ what: String, before: String? = nil) {
        record(&entry, event, what, before: before)
        trace(event, what, entry: entry.id)
    }

    private func record(_ entry: inout Entry, _ event: Event, _ what: String, before: String? = nil) {
        entry.activity.append(Activity(id: event.id, author: event.author, device: event.device, at: event.at, what: what, before: before))
        entry.activity.sort { $0.id < $1.id }
    }

    /// Links and done, in both their shapes. The older shape, link.add with closes, is one
    /// event saying two things, a link and a finishing, so it is recorded once in the older
    /// words and folded into both.
    private mutating func join(_ event: Event) {
        switch event.payload {
        case .link(let p):
            place(event, from: p.from, to: p.to, on: true)
        case .unlink(let p):
            place(event, from: p.from, to: p.to, on: false)
        case .done(let p):
            finish(event, entry: p.entry, by: p.by, on: true)
        case .undone(let p):
            finish(event, entry: p.entry, by: nil, on: false)
        case .linkAdd(let p):
            if p.closes {
                place(event, from: p.later, to: p.earlier, on: true,
                      saying: ("closed an earlier line with this", "marked this done by a later line"))
                finish(event, entry: p.earlier, by: p.later, on: true, quietly: true)
            } else {
                place(event, from: p.later, to: p.earlier, on: true)
            }
        case .linkRemove(let p):
            place(event, from: p.later, to: p.earlier, on: false)
            finish(event, entry: p.earlier, by: p.later, on: false, quietly: true)
        default:
            break
        }
    }

    /// One end of a link, once it is known: a line, a note under a line, or a thing. `entry`
    /// is where it is: the line, the note's line, or the thing itself.
    private struct End {
        let kind: Link.End
        let entry: ULID
        let at: Date
        let gone: Bool
    }

    private func end(_ id: ULID) -> End? {
        if let entry = table[id] { return End(kind: .line, entry: entry.id, at: entry.startedAt, gone: entry.isDeleted) }
        if let host = noteToEntry[id], let entry = table[host], let note = entry.notes.first(where: { $0.id == id }) {
            return End(kind: .note, entry: entry.id, at: note.at, gone: entry.isDeleted)
        }
        if let thing = things[id] { return End(kind: .thing, entry: thing.id, at: thing.createdAt, gone: false) }
        return nil
    }

    /// A link from one thing to another. The mark for the pair takes the newest event; the
    /// two ends follow the mark once both exist, and the event waits for whichever is missing.
    /// A line carries on only from one that started before it; a note cites any line; a line
    /// belongs to a thing. Nothing points from a thing, and nothing points at a note.
    private mutating func place(_ event: Event, from: ULID, to: ULID, on: Bool, saying: (String, String)? = nil) {
        guard from != to else { return }
        let pair = LinkPair(from: from, to: to)
        linkMarks.mark(pair, LinkMark(on: on, author: event.author, at: event.at), by: event.id)
        guard let fromEnd = end(from) else { return waiting[from, default: []].append(event) }
        guard let toEnd = end(to) else { return waiting[to, default: []].append(event) }
        guard !fromEnd.gone, !toEnd.gone, fromEnd.kind != .thing, toEnd.kind != .note, let mark = linkMarks[pair] else { return }
        if toEnd.kind == .thing {
            guard fromEnd.kind == .line else { return }
            return belong(event, line: fromEnd, thing: to, mark: mark)
        }
        if fromEnd.kind == .line, !((toEnd.at, to) < (fromEnd.at, from)) { return }

        guard var fromEntry = table[fromEnd.entry] else { return }
        var toEntry = fromEnd.entry == toEnd.entry ? fromEntry : table[toEnd.entry]!
        func forget() {
            fromEntry.outgoing.removeAll { $0.from == from && $0.to == to }
            if let index = fromEntry.notes.firstIndex(where: { $0.id == from }) { fromEntry.notes[index].cites.removeAll { $0.to == to } }
            toEntry.incoming.removeAll { $0.from == from && $0.to == to }
        }
        forget()
        if mark.on {
            let link = Link(id: mark.id, from: from, to: to, fromKind: fromEnd.kind, toKind: .line,
                            fromEntry: fromEnd.entry, toEntry: toEnd.entry, author: mark.author, at: mark.at,
                            fromAt: fromEnd.at, toAt: toEnd.at)
            switch fromEnd.kind {
            case .line:
                fromEntry.outgoing.append(link)
                fromEntry.outgoing.sort { $0.id < $1.id }
            case .note:
                if let index = fromEntry.notes.firstIndex(where: { $0.id == from }) {
                    fromEntry.notes[index].cites.append(link)
                    fromEntry.notes[index].cites.sort { $0.id < $1.id }
                }
            case .thing:
                // Nothing points from a thing; refused above.
                return
            }
            if fromEntry.id == toEntry.id { toEntry = fromEntry }
            toEntry.incoming.append(link)
            toEntry.incoming.sort { $0.id < $1.id }
            if fromEntry.id == toEntry.id { fromEntry = toEntry }
        }

        let citation = fromEnd.kind == .note
        let what = saying?.0 ?? (on ? (citation ? "cited a line in a note" : "linked this to an earlier line") : "took a link back")
        let other = saying?.1 ?? (on ? (citation ? "cited this in a note" : "linked a later line to this") : "took a link back")
        if fromEntry.id == toEntry.id {
            record(&fromEntry, event, other)
            table[fromEntry.id] = fromEntry
        } else {
            record(&fromEntry, event, what)
            record(&toEntry, event, other)
            table[fromEntry.id] = fromEntry
            table[toEntry.id] = toEntry
        }
        trace(event, what, entry: fromEnd.entry)
    }

    /// A line belongs to a thing, or stops belonging. The link sits on the line as outgoing
    /// and on the thing as incoming; the line's trail says so, under the thing's name, or
    /// under the word when the thing is a tag.
    private mutating func belong(_ event: Event, line: End, thing id: ULID, mark: Newest<LinkMark>) {
        guard var entry = table[line.entry], var thing = things[id] else { return }
        entry.outgoing.removeAll { $0.from == entry.id && $0.to == id }
        thing.incoming.removeAll { $0.from == entry.id && $0.to == id }
        if mark.on {
            let link = Link(id: mark.id, from: entry.id, to: id, fromKind: .line, toKind: .thing,
                            fromEntry: entry.id, toEntry: id, author: mark.author, at: mark.at,
                            fromAt: line.at, toAt: thing.createdAt)
            entry.outgoing.append(link)
            entry.outgoing.sort { $0.id < $1.id }
            thing.incoming.append(link)
            thing.incoming.sort { $0.id < $1.id }
        }
        let what = thing.isTag
            ? (mark.on ? "filed under #\(thing.name)" : "took #\(thing.name) off")
            : (mark.on ? "put this with \(thing.name)" : "took this out of \(thing.name)")
        record(&entry, event, what)
        trace(event, what, entry: entry.id)
        things[id] = thing
        refreshLabels(&entry)
        table[entry.id] = entry
    }

    /// The words of the tags a line is under, from its links, so they are at hand without the things.
    private func refreshLabels(_ entry: inout Entry) {
        entry.labels = entry.outgoing.compactMap { link in things[link.to].flatMap { $0.isTag ? $0.name : nil } }.sorted()
    }

    /// A label is the link from a line to its tag, and the tag is a thing whose id is its
    /// word: here the moment anyone files a line under it, by nobody, standing while a line
    /// is under it. The link itself is placed like any other, newest mark per pair.
    private mutating func tag(_ event: Event) {
        let entry: ULID
        let word: String
        let on: Bool
        switch event.payload {
        case .labelAttach(let p): (entry, word, on) = (p.entry, ULID.tagWord(p.label), true)
        case .labelDetach(let p): (entry, word, on) = (p.entry, ULID.tagWord(p.label), false)
        default: return
        }
        guard !word.isEmpty else { return }
        let id = ULID.tag(word)
        if var thing = things[id] {
            // The earliest label is when the tag began, whatever order the labels arrive in.
            if event.at < thing.createdAt { thing.createdAt = event.at; things[id] = thing }
        } else {
            materialise(Thing(id: id, name: word, kind: nil, author: nil, createdAt: event.at, setBy: event.id))
        }
        place(event, from: entry, to: id, on: on)
    }

    /// A thing is here: its facts and links that arrived before it are placed.
    private mutating func materialise(_ thing: Thing) {
        things[thing.id] = thing
        refreshFacts(on: thing.id)
        if let queued = waiting.removeValue(forKey: thing.id) {
            for later in queued.sorted(by: { $0.id < $1.id }) {
                switch later.payload {
                case .factSet, .factRemove: fact(later)
                default: join(later)
                }
            }
        }
    }

    /// A thing made, set again or dropped. Only its own originator sets it; the newest set
    /// stands; a drop is final and clears every line's belonging to it. Links and facts
    /// that arrived before the thing are placed once it is here. A tag is not made or set,
    /// and dropping one takes every line out from under it without retiring the word.
    private mutating func shape(_ event: Event) {
        switch event.payload {
        case .thingSet(let p):
            guard !p.thing.isTag, !removedThings.contains(p.thing) else { return }
            let name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let kind = p.kind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if var thing = things[p.thing] {
                guard thing.author == event.author, thing.setBy < event.id else { return }
                let renamed = thing.name != name
                thing.name = name
                thing.kind = kind?.isEmpty == false ? kind : nil
                thing.setBy = event.id
                things[p.thing] = thing
                if renamed { trace(event, "renamed a thing to \(name)", entry: nil) }
            } else {
                materialise(Thing(id: p.thing, name: name, kind: kind?.isEmpty == false ? kind : nil,
                                  author: event.author, createdAt: event.at, setBy: event.id))
                trace(event, "made a thing: \(name)\(kind.map { $0.isEmpty ? "" : ", a \($0)" } ?? "")", entry: nil)
            }

        case .thingRemove(let p):
            guard var thing = things[p.thing] else {
                if !p.thing.isTag { removedThings.insert(p.thing) }
                return
            }
            // Its own originator takes it back; the owner drops anyone's. A tag is nobody's.
            guard event.author == thing.author || event.author == owner else { return }
            if thing.isTag {
                // Every label under it is taken back by this one event; a label newer than it stands.
                var touched: [ULID] = []
                for link in thing.incoming {
                    let pair = LinkPair(from: link.from, to: link.to)
                    linkMarks.mark(pair, LinkMark(on: false, author: event.author, at: event.at), by: event.id)
                    guard linkMarks[pair]?.on == false, var entry = table[link.fromEntry] else { continue }
                    entry.outgoing.removeAll { $0.id == link.id }
                    thing.incoming.removeAll { $0.id == link.id }
                    record(&entry, event, "took #\(thing.name) off")
                    table[entry.id] = entry
                    touched.append(entry.id)
                }
                things[p.thing] = thing
                for id in touched { refreshLabels(&table[id]!) }
                trace(event, "dropped the tag #\(thing.name)", entry: nil)
                return
            }
            removedThings.insert(p.thing)
            things[p.thing] = nil
            for link in thing.incoming {
                table[link.fromEntry]?.outgoing.removeAll { $0.id == link.id }
            }
            trace(event, "dropped a thing: \(thing.name)", entry: nil)

        default:
            break
        }
    }

    /// A fact put on a line or a thing, or taken off. One per originator per key; the newest
    /// word wins. The owner may take anyone's off, naming whose. A fact on something not
    /// seen yet waits for it.
    private mutating func fact(_ event: Event) {
        let on: ULID
        let key: FactKey
        let mark: FactMark
        switch event.payload {
        case .factSet(let p):
            let word = p.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !word.isEmpty else { return }
            on = p.on
            key = FactKey(on: p.on, key: word, author: event.author)
            mark = FactMark(value: p.value, at: event.at)
        case .factRemove(let p):
            let word = p.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !word.isEmpty else { return }
            let whose = p.of ?? event.author
            guard whose == event.author || event.author == owner else { return }
            on = p.on
            key = FactKey(on: p.on, key: word, author: whose)
            mark = FactMark(value: nil, at: event.at)
        default:
            return
        }
        guard let target = end(on), target.kind != .note else {
            if end(on) == nil { waiting[on, default: []].append(event) }
            return
        }
        guard !target.gone else { return }
        factMarks.mark(key, mark, by: event.id)
        factsOn[on, default: []].insert(key)
        refreshFacts(on: on)
        if case .factSet(let p) = event.payload {
            let what = "put \(key.key) \(p.value.words(calendar: .current)) on this"
            if target.kind == .line, var entry = table[on] {
                record(&entry, event, what)
                table[on] = entry
            }
            trace(event, target.kind == .line ? what : "put \(key.key) on \(things[on]?.name ?? "a thing")", entry: target.kind == .line ? on : nil)
        } else if target.kind == .line, var entry = table[on] {
            record(&entry, event, "took \(key.key) off")
            table[on] = entry
            trace(event, "took \(key.key) off", entry: on)
        }
    }

    /// The facts standing on a line or a thing, from the marks, by key then by originator.
    private mutating func refreshFacts(on id: ULID) {
        let facts = (factsOn[id] ?? []).compactMap { key -> Fact? in
            guard let mark = factMarks[key], let value = mark.value.value else { return nil }
            return Fact(id: mark.id, on: id, key: key.key, value: value, author: key.author, at: mark.at)
        }
        .sorted { ($0.key, $0.author.rawValue, $0.id) < ($1.key, $1.author.rawValue, $1.id) }
        if table[id] != nil { table[id]!.facts = facts }
        if things[id] != nil { things[id]!.facts = facts }
    }

    /// A line finished, or not after all. The newest word on the line wins; the event waits
    /// for a line not seen yet. `quietly` leaves no record of its own, for the older shape
    /// where the link already recorded it.
    private mutating func finish(_ event: Event, entry id: ULID, by: ULID?, on: Bool, quietly: Bool = false) {
        doneMarks.mark(id, DoneMark(on: on, by: by, author: event.author, at: event.at), by: event.id)
        guard var entry = table[id] else { return waiting[id, default: []].append(event) }
        guard !entry.isDeleted, let mark = doneMarks[id] else { return }
        if mark.on {
            let evidence = mark.by.flatMap { table[$0] }.flatMap { $0.isDeleted ? nil : $0 }
            entry.done = Done(id: mark.id, by: mark.by, byAt: evidence?.startedAt, author: mark.author, at: mark.at)
        } else {
            entry.done = nil
        }
        if !quietly {
            let what = on ? (by != nil ? "marked this done by a later line" : "marked this done") : "took done back"
            record(&entry, event, what)
            trace(event, what, entry: id)
        }
        table[id] = entry
    }

    private mutating func trace(_ event: Event, _ what: String, entry: ULID?) {
        let trace = Trace(id: event.id, author: event.author, device: event.device, at: event.at, what: what, entry: entry)
        trail.insert(trace, at: Self.place(of: trace.id, in: trail, by: \.id))
    }

    /// Where an id belongs in a list kept in id order. Events are folded oldest first, so
    /// almost always the end, found at once; a late one is found by halving. Sorting the
    /// whole list for every receipt made the fold slower with the square of what was read.
    private static func place<T>(of id: ULID, in list: [T], by key: KeyPath<T, ULID>) -> Int {
        guard let last = list.last, id < last[keyPath: key] else { return list.count }
        var low = 0, high = list.count
        while low < high {
            let middle = (low + high) / 2
            if list[middle][keyPath: key] < id { low = middle + 1 } else { high = middle }
        }
        return low
    }

    private mutating func applyOrWait(_ event: Event, entry: ULID) {
        if table[entry] != nil {
            apply(event, toExisting: entry)
        } else {
            waiting[entry, default: []].append(event)
        }
    }

    private mutating func apply(_ event: Event, toExisting entryID: ULID) {
        // A link touches two things, so it is placed on its own rather than through the one below.
        switch event.payload {
        case .entryCreate(let p) where p.under != nil:
            // A reply that arrived before the line it was said under.
            return said(event, p, under: p.under!)
        case .linkAdd, .linkRemove, .link, .unlink, .done, .undone: return join(event)
        case .labelAttach, .labelDetach: return tag(event)
        case .factSet, .factRemove: return fact(event)
        default: break
        }

        guard var entry = table[entryID] else { return }
        defer { table[entryID] = entry }

        switch event.payload {
        case .entryEdit, .mediaAttach:
            // The line is its author's. Anyone else's edit or media is ignored.
            guard event.author == entry.author else { return }
        case .entryDelete:
            // Its author may delete it, and the owner may drop a line another put on the owner's page.
            guard event.author == entry.author || (event.author == owner && entry.page == owner) else { return }
        default:
            break
        }

        switch event.payload {
        case .entryEdit(let p):
            guard event.id > entry.lastTextEvent else { return }
            let before = entry.text
            entry.text = p.text
            entry.editedAt = event.at
            entry.lastTextEvent = event.id
            note(&entry, event, "changed the words", before: before.isEmpty ? nil : before)

        case .entryDelete:
            entry.isDeleted = true
            // A gone line holds no thread and belongs to nothing: whatever it was linked to forgets it.
            for link in entry.outgoing {
                table[link.toEntry]?.incoming.removeAll { $0.id == link.id }
                things[link.to]?.incoming.removeAll { $0.id == link.id }
            }
            for link in entry.incoming where link.fromEntry != entryID {
                guard var other = table[link.fromEntry] else { continue }
                other.outgoing.removeAll { $0.id == link.id }
                for index in other.notes.indices { other.notes[index].cites.removeAll { $0.id == link.id } }
                table[link.fromEntry] = other
            }
            entry.outgoing = []
            entry.incoming = []

        case .mediaAttach(let p):
            guard !entry.media.contains(where: { $0.hash == p.hash }) else { return }
            entry.media.append(Media(hash: p.hash, mime: p.mime, width: p.width, height: p.height, duration: p.duration, at: event.at))
            entry.media.sort { ($0.at, $0.hash) < ($1.at, $1.hash) }
            if event.id > entry.id {
                note(&entry, event, p.mime.hasPrefix("audio") ? "added a voice note" : "added a photo")
            }

        case .noteAdd(let p):
            noteToEntry[p.note] = entryID
            let takenBack = removedNotes[p.note].map { $0.contains(event.author) || $0.contains(owner) } ?? false
            guard !takenBack, !entry.notes.contains(where: { $0.id == p.note }) else { return }
            entry.notes.append(Note(id: p.note, entry: entryID, author: event.author, text: p.text, at: event.at, lastTextEvent: event.id))
            entry.notes.sort { $0.id < $1.id }
            note(&entry, event, "left a note")
            if let edits = pendingNoteEdits.removeValue(forKey: p.note) {
                table[entryID] = entry
                for edit in edits.sorted(by: { $0.id < $1.id }) { apply(edit, toExisting: entryID) }
                entry = table[entryID]!
            }
            // Links that cite this note arrived before it: placed now that the note is here.
            if let queued = waiting.removeValue(forKey: p.note) {
                table[entryID] = entry
                for later in queued.sorted(by: { $0.id < $1.id }) { afterReply(later) }
                entry = table[entryID]!
            }

        case .noteEdit(let p):
            guard let index = entry.notes.firstIndex(where: { $0.id == p.note }),
                  entry.notes[index].author == event.author,
                  event.id > entry.notes[index].lastTextEvent else { return }
            let before = entry.notes[index].text
            entry.notes[index].text = p.text
            entry.notes[index].editedAt = event.at
            entry.notes[index].lastTextEvent = event.id
            note(&entry, event, "changed a note", before: before)

        case .entryCreate, .noteRemove, .linkAdd, .linkRemove, .link, .unlink, .done, .undone, .visit, .nameSet, .grantCreate, .grantRevoke,
             .loopSet, .loopStop, .loopRan, .thingSet, .thingRemove, .factSet, .factRemove, .loopPropose, .labelAttach, .labelDetach, .same, .unknown:
            break
        }
    }

    // MARK: - Reading

    public func entry(_ id: ULID) -> Entry? {
        guard let entry = table[id], !entry.isDeleted else { return nil }
        return entry
    }

    /// A thing by its id, if it stands.
    public func thing(_ id: ULID) -> Thing? {
        things[id]
    }

    /// Every thing standing, oldest first; a tag stands while a line is under it.
    public var allThings: [Thing] {
        things.values.filter { !$0.isTag || !$0.incoming.isEmpty }.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// The things made by someone, oldest first: everything but the tags.
    public var madeThings: [Thing] {
        allThings.filter { !$0.isTag }
    }

    /// The tags with a line under them, by word.
    public var tags: [Thing] {
        things.values.filter { $0.isTag && !$0.incoming.isEmpty }.sorted { $0.name < $1.name }
    }

    /// Every made thing's name, by id. Tags are not here: a tag reads as its word.
    public var thingNames: [ULID: String] {
        things.filter { !$0.value.isTag }.mapValues(\.name)
    }

    /// The kinds made things have, with how many of each, most first then by name. Things
    /// with no kind are counted under nil; tags are not counted.
    public var kinds: [(kind: String?, count: Int)] {
        let counts = things.values.filter { !$0.isTag }.reduce(into: [String?: Int]()) { counts, thing in counts[thing.kind, default: 0] += 1 }
        return counts.map { (kind: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : ($0.kind ?? "~") < ($1.kind ?? "~") }
    }

    /// The owner's lines still to do: a todo fact and not done. Those with a due moment
    /// first, soonest first; then the rest, newest first.
    public var todos: [Entry] {
        let open = entries.filter(\.isTodo)
        let dated = open.filter { $0.due != nil }.sorted { ($0.due!, $0.id) < ($1.due!, $1.id) }
        let undated = open.filter { $0.due == nil }.sorted { ($0.startedAt, $0.id) > ($1.startedAt, $1.id) }
        return dated + undated
    }

    /// The owner's lines with a due moment still ahead of `now`, soonest first, done or not
    /// done: an appointment keeps its moment whether or not it is a todo.
    public func due(after now: Date) -> [Entry] {
        entries.compactMap { entry -> (Entry, Date)? in
            guard entry.done == nil, let due = entry.due, due > now else { return nil }
            return (entry, due)
        }
        .sorted { ($0.1, $0.0.id) < ($1.1, $1.0.id) }
        .map(\.0)
    }

    /// The things of one kind, oldest first.
    public func things(kind: String) -> [Thing] {
        let wanted = kind.lowercased()
        return madeThings.filter { $0.kind == wanted }
    }

    /// A note by its id, with the line it sits under.
    public func note(_ id: ULID) -> (note: Note, entry: Entry)? {
        guard let host = noteToEntry[id], let entry = entry(host), let note = entry.notes.first(where: { $0.id == id }) else { return nil }
        return (note, entry)
    }

    /// The owner's live entries, oldest first.
    public var entries: [Entry] {
        entries(of: owner)
    }

    /// One author's page, oldest first: the lines on it, their own and, on the owner's page,
    /// the ones other originators put there under their own names.
    public func entries(of author: Author) -> [Entry] {
        table.values
            .filter { !$0.isDeleted && $0.page == author }
            .sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
    }

    /// The owner's live entries grouped by the day they started, in the calendar's time zone, oldest day first.
    public func days(calendar: Calendar) -> [Day] {
        Self.days(of: entries, calendar: calendar)
    }

    /// One author's page, by day.
    public func days(of author: Author, calendar: Calendar) -> [Day] {
        Self.days(of: entries(of: author), calendar: calendar)
    }

    /// Live entries filed under `label`, grouped by day.
    public func days(labelled label: String, calendar: Calendar) -> [Day] {
        let wanted = label.lowercased()
        return Self.days(of: entries.filter { $0.labels.contains(wanted) }, calendar: calendar)
    }

    /// The visits that took this line in: made after it was written, and asking for a range
    /// or label it falls under, or for one of its photos.
    public func reads(of entry: Entry, calendar: Calendar) -> [Visit] {
        let day = DayKey(entry.startedAt, calendar: calendar).description
        return visits.filter { visit in
            guard visit.id > entry.id else { return false }
            switch visit.read.what {
            case .photo:
                return visit.read.entry == entry.id
            case .search:
                return visit.read.words.map { search($0).contains { $0.id == entry.id } } ?? false
            case .inbox, .things, .loops, .other:
                return false
            case .days, .lines:
                if let since = visit.read.since, day < since { return false }
                if let label = visit.read.label, !entry.labels.contains(label) { return false }
                return true
            }
        }
    }

    // MARK: - Search

    /// Words as search compares them: case, accents and width set aside.
    public static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
    }

    /// The terms of a query: its words, folded, in order, none empty.
    public static func terms(_ query: String) -> [String] {
        folded(query).split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init).filter { !$0.isEmpty }
    }

    /// The owner's lines in which every word of the query appears, newest first. A word is
    /// found inside a longer word, so an ending does not hide it. A line is found through
    /// its own words, a reply under it, a thing it is with, or a tag it is under; when the
    /// line's own words did not hold every term, the hit names the reply that did.
    public func search(_ query: String) -> [SearchHit] {
        let terms = Self.terms(query)
        guard !terms.isEmpty else { return [] }
        return entries.reversed().compactMap { entry -> SearchHit? in
            let own = Self.folded(entry.text)
            let around = entry.labels.map { Self.folded($0) }
                + entry.belongsTo.compactMap { things[$0.to].map { Self.folded($0.name) } }
            let notes = entry.notes.map { ($0, Self.folded($0.text)) }
            for term in terms {
                guard own.contains(term) || around.contains(where: { $0.contains(term) }) || notes.contains(where: { $0.1.contains(term) })
                else { return nil }
            }
            let missing = terms.filter { !own.contains($0) }
            let via = missing.isEmpty ? nil : notes.first { note in missing.contains { note.1.contains($0) } }?.0
            return SearchHit(entry: entry, via: via)
        }
    }

    /// The things, tags among them, whose names hold every word of the query.
    public func things(matching query: String) -> [Thing] {
        let terms = Self.terms(query)
        guard !terms.isEmpty else { return [] }
        return allThings.filter { thing in
            let name = Self.folded(thing.name)
            return terms.allSatisfy { name.contains($0) }
        }
    }

    /// Every tag in use, with how many live lines are under it.
    public var labelCounts: [String: Int] {
        entries.reduce(into: [:]) { counts, entry in
            for label in entry.labels { counts[label, default: 0] += 1 }
        }
    }

    /// Any entries grouped by the day they started, oldest day first.
    public static func days(of entries: [Entry], calendar: Calendar) -> [Day] {
        let grouped = Dictionary(grouping: entries) { DayKey($0.startedAt, calendar: calendar) }
        return grouped.keys.sorted().map { Day(key: $0, entries: grouped[$0]!) }
    }
}
