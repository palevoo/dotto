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

/// A reader's line under an entry, in that reader's ink.
public struct Note: Hashable, Sendable, Identifiable {
    public var id: ULID
    public var entry: ULID
    public var author: Author
    public var text: String
    public var at: Date
}

/// A reader's thread between two of the owner's lines: the later continues the earlier
/// and, when `closes` is set, finishes what the earlier line opened.
public struct Link: Hashable, Sendable, Identifiable {
    /// The event that placed it.
    public let id: ULID
    public let later: ULID
    public let earlier: ULID
    public let closes: Bool
    public let author: Author
    public let at: Date
    /// When each line started, so either side can be named without a lookup.
    public let laterAt: Date
    public let earlierAt: Date
}

/// What the page shows: the fold of every event about one line.
public struct Entry: Hashable, Sendable, Identifiable {
    public var id: ULID
    public var author: Author
    public var startedAt: Date
    public var text: String
    public var location: Location?
    public var media: [Media] = []
    public var notes: [Note] = []
    public var editedAt: Date?
    public var isDeleted = false

    /// Links from this line back to earlier ones, oldest link first.
    public var earlier: [Link] = []
    /// Links from later lines to this one, oldest link first.
    public var later: [Link] = []

    /// The link by which a later line finished this one, when one did.
    public var closedBy: Link? {
        later.first { $0.closes }
    }

    /// Words a reader filed this line under, sorted.
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
}

/// A reader read something: the receipt as folded.
public struct Visit: Hashable, Sendable, Identifiable {
    public let id: ULID
    public let author: Author
    public let device: DeviceID
    public let at: Date
    public let read: Payload.Visit

    /// "read 4 lines", "read 3 lines under #bug", "looked at a photo".
    public var what: String {
        switch read.what {
        case .photo:
            return "looked at a photo"
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
/// The one rule it enforces: only the owner writes entries and attaches media.
/// Every other author only ever adds notes, labels and links.
public struct Notebook: Sendable {
    public let owner: Author

    private var table: [ULID: Entry] = [:]
    private var noteToEntry: [ULID: ULID] = [:]
    private var removedNotes: Set<ULID> = []
    /// Per pair of lines, the latest add or remove seen, so order of arrival does not matter.
    private var linkMarks: [LinkPair: LinkMark] = [:]
    private var waiting: [ULID: [Event]] = [:]
    private var seen: Set<ULID> = []

    private struct LinkPair: Hashable, Sendable {
        let later: ULID
        let earlier: ULID
    }

    private struct LinkMark: Hashable, Sendable {
        let id: ULID
        let on: Bool
        let closes: Bool
        let author: Author
        let at: Date
    }

    public private(set) var eventCount = 0

    /// Every read a reader made, oldest first.
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

        switch event.payload {
        case .entryCreate(let p):
            guard event.author == owner else { return }
            if table[p.entry] != nil { return }
            table[p.entry] = Entry(
                id: p.entry,
                author: event.author,
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
            guard event.author == owner else { return }
            applyOrWait(event, entry: p.entry)

        case .entryDelete(let p):
            guard event.author == owner else { return }
            applyOrWait(event, entry: p.entry)

        case .mediaAttach(let p):
            guard event.author == owner else { return }
            applyOrWait(event, entry: p.entry)

        case .noteAdd(let p):
            applyOrWait(event, entry: p.entry)

        case .labelAttach(let p):
            applyOrWait(event, entry: p.entry)

        case .labelDetach(let p):
            applyOrWait(event, entry: p.entry)

        case .linkAdd(let p):
            place(event, LinkPair(later: p.later, earlier: p.earlier), on: true, closes: p.closes)

        case .linkRemove(let p):
            place(event, LinkPair(later: p.later, earlier: p.earlier), on: false, closes: false)

        case .noteRemove(let p):
            removedNotes.insert(p.note)
            if let entryID = noteToEntry[p.note], var entry = table[entryID] {
                entry.notes.removeAll { $0.id == p.note }
                note(&entry, event, "took a note back")
                table[entryID] = entry
            }

        case .visit(let p):
            let visit = Visit(id: event.id, author: event.author, device: event.device, at: event.at, read: p)
            visits.append(visit)
            visits.sort { $0.id < $1.id }
            trace(event, visit.what, entry: p.entry)
        }
    }

    /// Something done to one line: on the line's own trail and on the notebook's.
    private mutating func note(_ entry: inout Entry, _ event: Event, _ what: String) {
        record(&entry, event, what)
        trace(event, what, entry: entry.id)
    }

    private func record(_ entry: inout Entry, _ event: Event, _ what: String) {
        entry.activity.append(Activity(id: event.id, author: event.author, device: event.device, at: event.at, what: what))
        entry.activity.sort { $0.id < $1.id }
    }

    /// A link between two lines. The mark for the pair takes the newest event; the two lines'
    /// link lists follow the mark once both lines exist, and the event waits for whichever is
    /// missing. A line can only continue one that started before it.
    private mutating func place(_ event: Event, _ pair: LinkPair, on: Bool, closes: Bool) {
        guard pair.later != pair.earlier else { return }
        if linkMarks[pair].map({ $0.id < event.id }) ?? true {
            linkMarks[pair] = LinkMark(id: event.id, on: on, closes: closes, author: event.author, at: event.at)
        }
        guard var later = table[pair.later] else { return waiting[pair.later, default: []].append(event) }
        guard var earlier = table[pair.earlier] else { return waiting[pair.earlier, default: []].append(event) }
        guard !later.isDeleted, !earlier.isDeleted,
              (earlier.startedAt, earlier.id) < (later.startedAt, later.id), let mark = linkMarks[pair] else { return }

        later.earlier.removeAll { $0.earlier == pair.earlier }
        earlier.later.removeAll { $0.later == pair.later }
        if mark.on {
            let link = Link(id: mark.id, later: pair.later, earlier: pair.earlier, closes: mark.closes, author: mark.author, at: mark.at,
                            laterAt: later.startedAt, earlierAt: earlier.startedAt)
            later.earlier.append(link)
            later.earlier.sort { $0.id < $1.id }
            earlier.later.append(link)
            earlier.later.sort { $0.id < $1.id }
        }

        let what = on ? (closes ? "closed an earlier line with this" : "linked this to an earlier line") : "took a link back"
        record(&later, event, what)
        record(&earlier, event, on ? (closes ? "marked this done by a later line" : "linked a later line to this") : "took a link back")
        trace(event, what, entry: pair.later)
        table[pair.later] = later
        table[pair.earlier] = earlier
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
        // A link touches two lines, so it is placed on its own rather than through the one below.
        switch event.payload {
        case .linkAdd(let p): return place(event, LinkPair(later: p.later, earlier: p.earlier), on: true, closes: p.closes)
        case .linkRemove(let p): return place(event, LinkPair(later: p.later, earlier: p.earlier), on: false, closes: false)
        default: break
        }

        guard var entry = table[entryID] else { return }
        defer { table[entryID] = entry }

        switch event.payload {
        case .entryEdit(let p):
            guard event.id > entry.lastTextEvent else { return }
            entry.text = p.text
            entry.editedAt = event.at
            entry.lastTextEvent = event.id
            note(&entry, event, "changed the words")

        case .entryDelete:
            entry.isDeleted = true
            // A gone line holds no thread: the lines it was linked to forget it.
            for link in entry.earlier { table[link.earlier]?.later.removeAll { $0.later == entryID } }
            for link in entry.later { table[link.later]?.earlier.removeAll { $0.earlier == entryID } }
            entry.earlier = []
            entry.later = []

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
            entry.notes.append(Note(id: p.note, entry: entryID, author: event.author, text: p.text, at: event.at))
            entry.notes.sort { $0.id < $1.id }
            note(&entry, event, "left a note")

        case .labelAttach(let p):
            if let label = mark(&entry, label: p.label, on: true, by: event) {
                note(&entry, event, "filed under #\(label)")
            }

        case .labelDetach(let p):
            if let label = mark(&entry, label: p.label, on: false, by: event) {
                note(&entry, event, "took #\(label) off")
            }

        case .entryCreate, .noteRemove, .linkAdd, .linkRemove, .visit:
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

    /// Live entries, oldest first.
    public var entries: [Entry] {
        table.values
            .filter { !$0.isDeleted }
            .sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
    }

    /// Live entries grouped by the day they started, in the calendar's time zone, oldest day first.
    public func days(calendar: Calendar) -> [Day] {
        Self.days(of: entries, calendar: calendar)
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

    private static func days(of entries: [Entry], calendar: Calendar) -> [Day] {
        let grouped = Dictionary(grouping: entries) { DayKey($0.startedAt, calendar: calendar) }
        return grouped.keys.sorted().map { Day(key: $0, entries: grouped[$0]!) }
    }
}
