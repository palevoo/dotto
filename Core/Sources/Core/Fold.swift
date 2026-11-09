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
    /// The id of the event that last set `text`, so an older edit arriving late cannot win.
    var lastTextEvent: ULID
}

/// A link joins one thing to another by their ids, and that is all it is. What it means
/// comes from what its ends are: a line to an earlier line is a thread, the later carrying
/// on from the earlier; a note to a line is a citation, the note pointing at the line it
/// speaks of. One link per pair, from the thing that points to the thing pointed at.
public struct Link: Hashable, Sendable, Identifiable {
    public enum End: Hashable, Sendable {
        case line, note
    }

    /// The event that placed it.
    public let id: ULID
    public let from: ULID
    public let to: ULID
    public let fromKind: End
    public let toKind: End
    /// The line each end is on: the line itself, or the line a note sits under. For going there.
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

    /// The thread back: earlier lines this one carries on from.
    public var carriesOn: [Link] { outgoing.filter { $0.toKind == .line } }
    /// The thread forward: later lines that carry on from this one.
    public var carriedOnBy: [Link] { incoming.filter { $0.fromKind == .line } }
    /// Notes, under this or other lines, that speak of this line.
    public var citedBy: [Link] { incoming.filter { $0.fromKind == .note } }

    /// Words this line is filed under, sorted.
    public var labels: [String] {
        labelMarks.filter { $0.value.on }.keys.sorted()
    }

    /// Everything anyone did to this line after it was written, oldest first.
    /// The accountability trail: who, from where, when, what.
    public var activity: [Activity] = []

    /// The id of the event that last set `text`, so an older edit arriving late cannot win.
    var lastTextEvent: ULID

    /// Per label, the latest attach or detach seen, so order of arrival does not matter.
    var labelMarks: [String: LabelMark] = [:]

    struct LabelMark: Hashable, Sendable {
        var id: ULID
        var on: Bool
        var author: Author
        var at: Date
    }
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
        case .days, .lines:
            var text = "read \(read.count) line\(read.count == 1 ? "" : "s")"
            if let label = read.label { text += " under #\(label)" }
            if let since = read.since { text += " since \(since)" }
            return text
        }
    }
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
    /// Per author, the latest name chosen.
    private var names: [Author: NameMark] = [:]
    /// Everyone other than the owner who has left anything, in order of first appearance.
    public private(set) var others: [Author] = []
    /// Every grant the owner has opened, by id, revoked or not.
    private var grantMarks: [ULID: GrantMark] = [:]
    /// Grants revoked before their opening was seen.
    private var revokedGrants: Set<ULID> = []
    /// Every loop the owner has set, by id, with its latest set and whether it was stopped after.
    private var loopMarks: [ULID: LoopMark] = [:]
    /// The latest receipt per loop.
    private var loopRuns: [ULID: LoopRun] = [:]

    private struct LoopMark: Hashable, Sendable {
        var loop: Loop
        /// The id of the latest stop, if any; the loop is off when it is newer than the set.
        var stoppedBy: ULID?
    }

    private struct NameMark: Hashable, Sendable {
        let id: ULID
        let name: String
    }

    private struct GrantMark: Hashable, Sendable {
        let grant: Grant
        var revoked: Bool
    }
    private var noteToEntry: [ULID: ULID] = [:]
    private var removedNotes: Set<ULID> = []
    /// Edits to notes not seen yet.
    private var pendingNoteEdits: [ULID: [Event]] = [:]
    /// Per pair of ends, the latest link or unlink seen, so order of arrival does not matter.
    private var linkMarks: [LinkPair: LinkMark] = [:]
    /// Per line, the latest done or undone seen.
    private var doneMarks: [ULID: DoneMark] = [:]
    /// Events about a thing not seen yet, by that thing's id: a line or a note.
    private var waiting: [ULID: [Event]] = [:]
    private var seen: Set<ULID> = []

    private struct LinkPair: Hashable, Sendable {
        let from: ULID
        let to: ULID
    }

    private struct LinkMark: Hashable, Sendable {
        let id: ULID
        let on: Bool
        let author: Author
        let at: Date
    }

    private struct DoneMark: Hashable, Sendable {
        let id: ULID
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
        for event in events.sorted(by: { $0.id < $1.id }) {
            apply(event)
        }
    }

    public mutating func apply(_ event: Event) {
        guard !seen.contains(event.id) else { return }
        seen.insert(event.id)
        eventCount += 1
        // Only the owner opens or closes the door, and only the owner sets or stops a loop.
        if [.grantCreate, .grantRevoke, .loopSet, .loopStop].contains(event.kind), event.author != owner { return }
        if event.author != owner, !others.contains(event.author) { others.append(event.author) }

        switch event.payload {
        case .entryCreate(let p):
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
            applyOrWait(event, entry: p.entry)

        case .entryDelete(let p):
            applyOrWait(event, entry: p.entry)

        case .mediaAttach(let p):
            applyOrWait(event, entry: p.entry)

        case .noteAdd(let p):
            applyOrWait(event, entry: p.entry)

        case .labelAttach(let p):
            applyOrWait(event, entry: p.entry)

        case .labelDetach(let p):
            applyOrWait(event, entry: p.entry)

        case .linkAdd, .linkRemove, .link, .unlink, .done, .undone:
            join(event)

        case .noteRemove(let p):
            removedNotes.insert(p.note)
            if let entryID = noteToEntry[p.note], var entry = table[entryID] {
                if let gone = entry.notes.first(where: { $0.id == p.note }) {
                    // A gone note cites nothing: the lines it spoke of forget it.
                    for link in gone.cites { table[link.to]?.incoming.removeAll { $0.id == link.id } }
                }
                entry.notes.removeAll { $0.id == p.note }
                note(&entry, event, "took a note back")
                table[entryID] = entry
            }

        case .noteEdit(let p):
            // Only the note's author changes its words; an edit that arrives before the note waits on its line.
            if let entryID = noteToEntry[p.note] {
                applyOrWait(event, entry: entryID)
            } else {
                pendingNoteEdits[p.note, default: []].append(event)
            }

        case .visit(let p):
            let visit = Visit(id: event.id, author: event.author, device: event.device, at: event.at, read: p)
            visits.append(visit)
            visits.sort { $0.id < $1.id }
            // The owner's own looks at the inbox are receipts for unread, not the log of what others did.
            if event.author != owner { trace(event, visit.what, entry: p.entry) }

        case .nameSet(let p):
            let name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            if names[event.author].map({ $0.id < event.id }) ?? true {
                names[event.author] = NameMark(id: event.id, name: name)
            }
            if event.author != owner { trace(event, "chose the name \(name)", entry: nil) }

        case .grantCreate(let p):
            guard grantMarks[p.grant] == nil else { return }
            grantMarks[p.grant] = GrantMark(grant: Grant(p, createdAt: event.at), revoked: revokedGrants.contains(p.grant))

        case .grantRevoke(let p):
            revokedGrants.insert(p.grant)
            grantMarks[p.grant]?.revoked = true

        case .loopSet(let p):
            guard loopMarks[p.loop].map({ $0.loop.setBy < event.id }) ?? true else { return }
            let wake: Loop.Wake
            if p.wake == "clock", let at = p.at, let colon = at.firstIndex(of: ":"),
               let hour = Int(at[..<colon]), let minute = Int(at[at.index(after: colon)...]), (0..<24).contains(hour), (0..<60).contains(minute) {
                wake = .clock(hour: hour, minute: minute)
            } else {
                wake = .line
            }
            let loop = Loop(id: p.loop, setBy: event.id, name: p.name, grant: p.grant, wake: wake, brief: p.brief,
                            turns: p.turns, budget: p.budget, createdAt: loopMarks[p.loop]?.loop.createdAt ?? event.at, lastRun: loopRuns[p.loop])
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
            if loopRuns[p.loop].map({ $0.id < event.id }) ?? true {
                loopRuns[p.loop] = run
                loopMarks[p.loop]?.loop.lastRun = run
            }
            let name = loopMarks[p.loop]?.loop.name ?? "a loop"
            var what = "ran \(name)"
            if let turns = p.turns { what += ", \(turns) turn\(turns == 1 ? "" : "s")" }
            if let cost = p.cost { what += String(format: ", $%.2f", cost) }
            if !p.ok { what += ", and failed" }
            trace(event, what, entry: nil)
        }
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
        loopMarks.values
            .filter { mark in
                let stopped = mark.stoppedBy ?? stoppedLoops[mark.loop.id]
                return stopped.map { $0 < mark.loop.setBy } ?? true
            }
            .map(\.loop)
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// Every loop ever set, stopped ones included, oldest first.
    public var allLoops: [Loop] {
        loopMarks.values.map(\.loop).sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// The open grant a key belongs to, with the key filled in. Nil means the door stays shut.
    public func grant(forKey key: String) -> Grant? {
        let hash = Grant.hash(key)
        guard var grant = grants.first(where: { $0.keyHash == hash }) else { return nil }
        grant.key = key
        return grant
    }

    /// What an author is called, if they have chosen. Nobody is called anything until then.
    public func name(of author: Author) -> String? {
        names[author]?.name
    }

    /// Every chosen name, by author id.
    public var chosenNames: [Author: String] {
        names.mapValues(\.name)
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

    /// What a thing is, when it is known: a line, or a note under a line.
    private func end(_ id: ULID) -> (kind: Link.End, entry: Entry, at: Date)? {
        if let entry = table[id] { return (.line, entry, entry.startedAt) }
        if let host = noteToEntry[id], let entry = table[host], let note = entry.notes.first(where: { $0.id == id }) {
            return (.note, entry, note.at)
        }
        return nil
    }

    /// A link from one thing to another. The mark for the pair takes the newest event; the
    /// two ends follow the mark once both exist, and the event waits for whichever is missing.
    /// A line carries on only from one that started before it; a note cites any line.
    private mutating func place(_ event: Event, from: ULID, to: ULID, on: Bool, saying: (String, String)? = nil) {
        guard from != to else { return }
        let pair = LinkPair(from: from, to: to)
        if linkMarks[pair].map({ $0.id < event.id }) ?? true {
            linkMarks[pair] = LinkMark(id: event.id, on: on, author: event.author, at: event.at)
        }
        guard let fromEnd = end(from) else { return waiting[from, default: []].append(event) }
        guard let toEnd = end(to) else { return waiting[to, default: []].append(event) }
        guard !fromEnd.entry.isDeleted, !toEnd.entry.isDeleted, toEnd.kind == .line, let mark = linkMarks[pair] else { return }
        if fromEnd.kind == .line, !((toEnd.at, to) < (fromEnd.at, from)) { return }

        var fromEntry = fromEnd.entry
        var toEntry = fromEnd.entry.id == toEnd.entry.id ? fromEntry : toEnd.entry
        func forget() {
            fromEntry.outgoing.removeAll { $0.from == from && $0.to == to }
            if let index = fromEntry.notes.firstIndex(where: { $0.id == from }) { fromEntry.notes[index].cites.removeAll { $0.to == to } }
            toEntry.incoming.removeAll { $0.from == from && $0.to == to }
        }
        forget()
        if mark.on {
            let link = Link(id: mark.id, from: from, to: to, fromKind: fromEnd.kind, toKind: .line,
                            fromEntry: fromEnd.entry.id, toEntry: toEnd.entry.id, author: mark.author, at: mark.at,
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
        trace(event, what, entry: fromEnd.entry.id)
    }

    /// A line finished, or not after all. The newest word on the line wins; the event waits
    /// for a line not seen yet. `quietly` leaves no record of its own, for the older shape
    /// where the link already recorded it.
    private mutating func finish(_ event: Event, entry id: ULID, by: ULID?, on: Bool, quietly: Bool = false) {
        if doneMarks[id].map({ $0.id < event.id }) ?? true {
            doneMarks[id] = DoneMark(id: event.id, on: on, by: by, author: event.author, at: event.at)
        }
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
        trail.append(Trace(id: event.id, author: event.author, device: event.device, at: event.at, what: what, entry: entry))
        trail.sort { $0.id < $1.id }
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
        case .linkAdd, .linkRemove, .link, .unlink, .done, .undone: return join(event)
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
            // A gone line holds no thread: whatever it was linked to forgets it.
            for link in entry.outgoing { table[link.toEntry]?.incoming.removeAll { $0.id == link.id } }
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
            guard !removedNotes.contains(p.note), !entry.notes.contains(where: { $0.id == p.note }) else { return }
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
                for later in queued.sorted(by: { $0.id < $1.id }) { join(later) }
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

        case .labelAttach(let p):
            if let label = mark(&entry, label: p.label, on: true, by: event) {
                note(&entry, event, "filed under #\(label)")
            }

        case .labelDetach(let p):
            if let label = mark(&entry, label: p.label, on: false, by: event) {
                note(&entry, event, "took #\(label) off")
            }

        case .entryCreate, .noteRemove, .linkAdd, .linkRemove, .link, .unlink, .done, .undone, .visit, .nameSet, .grantCreate, .grantRevoke,
             .loopSet, .loopStop, .loopRan:
            break
        }
    }

    /// Returns the normalised label when the mark was applied, nil when an older event lost.
    private func mark(_ entry: inout Entry, label raw: String, on: Bool, by event: Event) -> String? {
        let label = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !label.isEmpty else { return nil }
        if let existing = entry.labelMarks[label], existing.id > event.id { return label }
        entry.labelMarks[label] = Entry.LabelMark(id: event.id, on: on, author: event.author, at: event.at)
        return label
    }

    // MARK: - Reading

    public func entry(_ id: ULID) -> Entry? {
        guard let entry = table[id], !entry.isDeleted else { return nil }
        return entry
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
            case .inbox:
                return false
            case .days, .lines:
                if let since = visit.read.since, day < since { return false }
                if let label = visit.read.label, !entry.labels.contains(label) { return false }
                return true
            }
        }
    }

    /// Every label in use, with how many live lines carry it.
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
