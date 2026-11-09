import Foundation

/// Who wrote an event: the owner of the notebook or any grant holder. An id, not a name;
/// a name is chosen later with `name.set` and may change, the id never does.
public struct Author: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public var description: String { rawValue }

    /// The id the first grant wrote under, before ids were made fresh per grant. Kept so
    /// the lines it left keep their author.
    public static let weeju: Author = "weeju"

    /// A fresh id for a new author: six characters nobody chose.
    public static func fresh() -> Author {
        Author(rawValue: String(ULID().string.suffix(6)).lowercased())
    }

    /// A hue in 0..<1 that follows from the id, so an author has a colour of their own
    /// everywhere, on every device, from the first thing they do, without anyone choosing.
    public var hue: Double {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in rawValue.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return Double(hash % 360) / 360
    }
}

/// Which device wrote an event. One device, one event file.
public struct DeviceID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public var description: String { rawValue }
}

/// Coordinates captured silently when a line starts. Named later through the door, never a prompt.
public struct Location: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var accuracy: Double?

    public init(latitude: Double, longitude: Double, accuracy: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
    }
}

/// What a fact says, in one of five kinds, so a page can add yields, draw a streak or put a
/// thing on a map. Written as one key naming the kind: `{"number": 10, "unit": "L"}`,
/// `{"words": "potted"}`, `{"moment": "2026-11-01T10:00:00.000Z"}`, `{"span": 2460}`
/// in seconds, `{"place": {"latitude": …, "longitude": …}}`.
public enum FactValue: Hashable, Sendable, Codable {
    case number(Double, unit: String?)
    case words(String)
    case moment(Date)
    case span(TimeInterval)
    case place(Location)

    enum CodingKeys: String, CodingKey {
        case number, unit, words, moment, span, place
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let number = try container.decodeIfPresent(Double.self, forKey: .number) {
            self = .number(number, unit: try container.decodeIfPresent(String.self, forKey: .unit))
        } else if let words = try container.decodeIfPresent(String.self, forKey: .words) {
            self = .words(words)
        } else if let moment = try container.decodeIfPresent(Date.self, forKey: .moment) {
            self = .moment(moment)
        } else if let span = try container.decodeIfPresent(TimeInterval.self, forKey: .span) {
            self = .span(span)
        } else if let place = try container.decodeIfPresent(Location.self, forKey: .place) {
            self = .place(place)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "A fact value names its kind: number, words, moment, span or place."))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .number(let number, let unit):
            try container.encode(number, forKey: .number)
            try container.encodeIfPresent(unit, forKey: .unit)
        case .words(let words): try container.encode(words, forKey: .words)
        case .moment(let moment): try container.encode(moment.toMilliseconds, forKey: .moment)
        case .span(let span): try container.encode(span, forKey: .span)
        case .place(let place): try container.encode(place, forKey: .place)
        }
    }

    /// The value as the page says it: "10 L", "potted", "2026-11-01 10:00", "41 min", "38.70, -9.10".
    public func words(calendar: Calendar) -> String {
        switch self {
        case .number(let number, let unit):
            let shown = number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(format: "%.2f", number)
            return unit.map { "\(shown) \($0)" } ?? shown
        case .words(let words):
            return words
        case .moment(let moment):
            return Projector.moment(moment, calendar: calendar)
        case .span(let seconds):
            let total = Int(seconds.rounded())
            if total < 60 { return "\(total) s" }
            if total < 3600 { return "\(total / 60) min" }
            if total < 86_400 {
                let minutes = (total % 3600) / 60
                return minutes == 0 ? "\(total / 3600) h" : "\(total / 3600) h \(minutes) min"
            }
            return "\(total / 86_400) d"
        case .place(let place):
            return String(format: "%.2f, %.2f", place.latitude, place.longitude)
        }
    }
}

/// The vocabulary. Versioned by addition only; a kind never changes meaning.
public enum Kind: String, Codable, Sendable, CaseIterable {
    case entryCreate = "entry.create"
    case entryEdit = "entry.edit"
    case entryDelete = "entry.delete"
    case mediaAttach = "media.attach"
    case noteAdd = "note.add"
    case noteRemove = "note.remove"
    case noteEdit = "note.edit"
    case labelAttach = "label.attach"
    case labelDetach = "label.detach"
    case linkAdd = "link.add"
    case linkRemove = "link.remove"
    case link = "link"
    case unlink = "unlink"
    case done = "done"
    case undone = "undone"
    case visit = "visit"
    case nameSet = "name.set"
    case grantCreate = "grant.create"
    case grantRevoke = "grant.revoke"
    case loopSet = "loop.set"
    case loopStop = "loop.stop"
    case loopRan = "loop.ran"
    case thingSet = "thing.set"
    case thingRemove = "thing.remove"
    case factSet = "fact.set"
    case factRemove = "fact.remove"
}

/// What happened. One case per kind, each with a fixed shape.
public enum Payload: Hashable, Sendable {
    case entryCreate(EntryCreate)
    case entryEdit(EntryEdit)
    case entryDelete(EntryDelete)
    case mediaAttach(MediaAttach)
    case noteAdd(NoteAdd)
    case noteRemove(NoteRemove)
    case noteEdit(NoteEdit)
    case labelAttach(LabelAttach)
    case labelDetach(LabelDetach)
    case linkAdd(LinkAdd)
    case linkRemove(LinkRemove)
    case link(Join)
    case unlink(Unjoin)
    case done(Done)
    case undone(Undone)
    case visit(Visit)
    case nameSet(NameSet)
    case grantCreate(GrantCreate)
    case grantRevoke(GrantRevoke)
    case loopSet(LoopSet)
    case loopStop(LoopStop)
    case loopRan(LoopRan)
    case thingSet(ThingSet)
    case thingRemove(ThingRemove)
    case factSet(FactSet)
    case factRemove(FactRemove)

    public var kind: Kind {
        switch self {
        case .entryCreate: .entryCreate
        case .entryEdit: .entryEdit
        case .entryDelete: .entryDelete
        case .mediaAttach: .mediaAttach
        case .noteAdd: .noteAdd
        case .noteRemove: .noteRemove
        case .noteEdit: .noteEdit
        case .labelAttach: .labelAttach
        case .labelDetach: .labelDetach
        case .linkAdd: .linkAdd
        case .linkRemove: .linkRemove
        case .link: .link
        case .unlink: .unlink
        case .done: .done
        case .undone: .undone
        case .visit: .visit
        case .nameSet: .nameSet
        case .grantCreate: .grantCreate
        case .grantRevoke: .grantRevoke
        case .loopSet: .loopSet
        case .loopStop: .loopStop
        case .loopRan: .loopRan
        case .thingSet: .thingSet
        case .thingRemove: .thingRemove
        case .factSet: .factSet
        case .factRemove: .factRemove
        }
    }

    /// A loop: a sentence said once, kept, run, with a receipt each time. The owner's event,
    /// like a grant: a name, the grant it runs as, what wakes it, a line landing or the clock
    /// at an hour each day, a brief in the owner's words added to the door's conduct, and a
    /// cap on turns and on spend. The newest set for a loop id stands; stop ends it. Since
    /// 9 November 2026.
    public struct LoopSet: Hashable, Codable, Sendable {
        public var loop: ULID
        public var name: String
        public var grant: ULID
        /// "line" or "clock".
        public var wake: String
        /// For the clock: "HH:MM" in the home's local time.
        public var at: String?
        public var brief: String?
        public var turns: Int
        public var budget: Double

        public init(loop: ULID, name: String, grant: ULID, wake: String, at: String? = nil, brief: String? = nil, turns: Int = 40, budget: Double = 2) {
            self.loop = loop
            self.name = name
            self.grant = grant
            self.wake = wake
            self.at = at
            self.brief = brief
            self.turns = turns
            self.budget = budget
        }
    }

    public struct LoopStop: Hashable, Codable, Sendable {
        public var loop: ULID

        public init(loop: ULID) { self.loop = loop }
    }

    /// The receipt for one run of a loop, written by the loop's own originator: when, how it
    /// went, what it cost, and what it said at the end. Logs show it.
    public struct LoopRan: Hashable, Codable, Sendable {
        public var loop: ULID
        public var run: ULID
        public var ok: Bool
        public var turns: Int?
        public var cost: Double?
        public var summary: String
        public var startedAt: Date
        public var endedAt: Date

        public init(loop: ULID, run: ULID, ok: Bool, turns: Int?, cost: Double?, summary: String, startedAt: Date, endedAt: Date) {
            self.loop = loop
            self.run = run
            self.ok = ok
            self.turns = turns
            self.cost = cost
            self.summary = summary
            self.startedAt = startedAt.toMilliseconds
            self.endedAt = endedAt.toMilliseconds
        }
    }

    /// A thing: a shape with an id and a name that lines belong to, a fig, a book, a person,
    /// the detox, a tag. Made by whoever proposes it; it stands until dropped. Only its own
    /// originator sets it again, to rename it or give it a kind, and the newest set stands.
    /// A kind is a word for now, plant, book, person, not a link. Since 10 November 2026.
    public struct ThingSet: Hashable, Codable, Sendable {
        public var thing: ULID
        public var name: String
        public var kind: String?

        public init(thing: ULID, name: String, kind: String? = nil) {
            self.thing = thing
            self.name = name
            self.kind = kind
        }
    }

    /// A thing dropped: by the owner with one hold, or taken back by the one who made it.
    /// Final; the lines that belonged to it keep nothing of it.
    public struct ThingRemove: Hashable, Codable, Sendable {
        public var thing: ULID

        public init(thing: ULID) { self.thing = thing }
    }

    /// A fact: a key and a value put on a line or a thing by an originator. The yield on the
    /// harvest line, the state of the fig, the days of the detox. One fact per originator per
    /// key on a thing; the newest word of that originator wins. Since 10 November 2026.
    public struct FactSet: Hashable, Codable, Sendable {
        /// The line or the thing it is on.
        public var on: ULID
        public var key: String
        public var value: FactValue

        public init(on: ULID, key: String, value: FactValue) {
            self.on = on
            self.key = key
            self.value = value
        }
    }

    /// A fact taken off: by its own originator, or by the owner, who names whose it was.
    public struct FactRemove: Hashable, Codable, Sendable {
        public var on: ULID
        public var key: String
        /// Whose fact, when the remover is not the one who put it. Absent, the remover's own.
        public var of: Author?

        public init(on: ULID, key: String, of: Author? = nil) {
            self.on = on
            self.key = key
            self.of = of
        }
    }

    /// The owner opens the door to someone: one key for an author. The author is the
    /// identity; a grant is a key for it, and an author may hold several over time. The key
    /// itself is never written here, only its SHA-256, so any device holding the folder can
    /// recognise the key without being able to use it. Only the owner's grant events count.
    public struct GrantCreate: Hashable, Codable, Sendable {
        public var grant: ULID
        public var author: Author
        /// Who the key was handed to, in the owner's words: "Claude Code", "Grok".
        public var name: String
        /// What the author's events say they came through, when the hand does not say.
        public var device: DeviceID
        /// SHA-256 of the key, lower-case hex.
        public var keyHash: String
        /// What the key may write: notes, labels, links, lines. Reading is always allowed.
        public var may: [String]

        public init(grant: ULID, author: Author, name: String, device: DeviceID, keyHash: String, may: [String]) {
            self.grant = grant
            self.author = author
            self.name = name
            self.device = device
            self.keyHash = keyHash
            self.may = may
        }

        enum CodingKeys: String, CodingKey {
            case grant, author, name, device, may
            case keyHash = "hash"
        }
    }

    /// The owner closes a grant. The key stops opening the door; the author's events stay.
    public struct GrantRevoke: Hashable, Codable, Sendable {
        public var grant: ULID

        public init(grant: ULID) { self.grant = grant }
    }

    /// An author chooses what they are called. Nobody has a name until they choose one;
    /// the latest choice stands. The author id on every event never changes.
    public struct NameSet: Hashable, Codable, Sendable {
        public var name: String

        public init(name: String) { self.name = name }
    }

    /// A link joins one thing to another by their ids, and that is all it is. What it means
    /// comes from what its ends are: a line to an earlier line is a thread, a note to a line
    /// is a citation, a line to a shape is belonging. One link per pair, from the thing that
    /// points to the thing pointed at; a newer link or unlink for the same pair replaces an
    /// older one. Since 9 November 2026; `link.add` and `link.remove` are the older shape.
    public struct Join: Hashable, Codable, Sendable {
        public var from: ULID
        public var to: ULID

        public init(from: ULID, to: ULID) {
            self.from = from
            self.to = to
        }
    }

    public struct Unjoin: Hashable, Codable, Sendable {
        public var from: ULID
        public var to: ULID

        public init(from: ULID, to: ULID) {
            self.from = from
            self.to = to
        }
    }

    /// A line is finished. The first fact: state on the line, not a connection. `by` is the
    /// line that finished it, when one did, as the evidence. The newest word on a line wins.
    public struct Done: Hashable, Codable, Sendable {
        public var entry: ULID
        public var by: ULID?

        public init(entry: ULID, by: ULID? = nil) {
            self.entry = entry
            self.by = by
        }
    }

    public struct Undone: Hashable, Codable, Sendable {
        public var entry: ULID

        public init(entry: ULID) { self.entry = entry }
    }

    /// The older shape, 4 to 9 November: a later line joined to an earlier one, with `closes`
    /// meaning the later finished the earlier. Folded as a link from later to earlier, and,
    /// when closes is set, as done on the earlier line by the later.
    public struct LinkAdd: Hashable, Codable, Sendable {
        public var later: ULID
        public var earlier: ULID
        public var closes: Bool

        public init(later: ULID, earlier: ULID, closes: Bool = false) {
            self.later = later
            self.earlier = earlier
            self.closes = closes
        }
    }

    public struct LinkRemove: Hashable, Codable, Sendable {
        public var later: ULID
        public var earlier: ULID

        public init(later: ULID, earlier: ULID) {
            self.later = later
            self.earlier = earlier
        }
    }

    /// Someone read something through the door. The receipt: what was asked for and how much came back,
    /// so the owner can see every read, not only every write.
    public struct Visit: Hashable, Codable, Sendable {
        public enum What: String, Codable, Sendable {
            case days, lines, photo
            /// A look at what happened since the last look.
            case inbox
            /// A look at the things: shapes lines belong to, with their facts.
            case things
        }

        public var what: What
        /// Only days on or after this one were asked for, `YYYY-MM-DD`.
        public var since: String?
        /// Only lines under this label were asked for.
        public var label: String?
        /// Lines that came back, 1 for a photo, or the things found new.
        public var count: Int
        /// The line a photo was taken from.
        public var entry: ULID?
        /// The photo looked at.
        public var hash: String?
        /// For an inbox look: how many events each file held when it was taken, by file
        /// name. The next look starts after these, whatever order the files grew in.
        public var seen: [String: Int]?

        public init(what: What, since: String? = nil, label: String? = nil, count: Int, entry: ULID? = nil, hash: String? = nil,
                    seen: [String: Int]? = nil) {
            self.what = what
            self.since = since
            self.label = label
            self.count = count
            self.entry = entry
            self.hash = hash
            self.seen = seen
        }
    }

    /// An author files the line under a word. Never typed by the owner at the moment of writing.
    public struct LabelAttach: Hashable, Codable, Sendable {
        public var entry: ULID
        public var label: String

        public init(entry: ULID, label: String) {
            self.entry = entry
            self.label = label
        }
    }

    public struct LabelDetach: Hashable, Codable, Sendable {
        public var entry: ULID
        public var label: String

        public init(entry: ULID, label: String) {
            self.entry = entry
            self.label = label
        }
    }

    /// A line, with the moment it started. It belongs to whoever writes it.
    public struct EntryCreate: Hashable, Codable, Sendable {
        public var entry: ULID
        public var text: String
        public var startedAt: Date
        public var location: Location?
        /// Whose page the line lands on. Absent, the writer's own. Another originator may
        /// write a line onto the owner's page under its own name, a walk, a booking, a book,
        /// and the owner drops it with one hold. Since 9 November 2026.
        public var page: Author?

        public init(entry: ULID, text: String, startedAt: Date, location: Location? = nil, page: Author? = nil) {
            self.entry = entry
            self.text = text
            self.startedAt = startedAt.toMilliseconds
            self.location = location
            self.page = page
        }

        enum CodingKeys: String, CodingKey {
            case entry, text, page
            case startedAt = "at"
            case location = "loc"
        }
    }

    /// The line's author changed the words. The whole text, not a diff.
    public struct EntryEdit: Hashable, Codable, Sendable {
        public var entry: ULID
        public var text: String

        public init(entry: ULID, text: String) {
            self.entry = entry
            self.text = text
        }
    }

    /// Tombstone. The events stay; the entry stops being shown.
    public struct EntryDelete: Hashable, Codable, Sendable {
        public var entry: ULID

        public init(entry: ULID) { self.entry = entry }
    }

    /// A photo, video or audio file, addressed by the SHA-256 of its bytes.
    public struct MediaAttach: Hashable, Codable, Sendable {
        public var entry: ULID
        public var hash: String
        public var mime: String
        public var width: Int?
        public var height: Int?
        public var duration: Double?

        public init(entry: ULID, hash: String, mime: String, width: Int? = nil, height: Int? = nil, duration: Double? = nil) {
            self.entry = entry
            self.hash = hash
            self.mime = mime
            self.width = width
            self.height = height
            self.duration = duration
        }

        enum CodingKeys: String, CodingKey {
            case entry, hash, mime
            case width = "w"
            case height = "h"
            case duration = "dur"
        }
    }

    /// A line under someone's line, by anyone: a reply.
    public struct NoteAdd: Hashable, Codable, Sendable {
        public var entry: ULID
        public var note: ULID
        public var text: String

        public init(entry: ULID, note: ULID, text: String) {
            self.entry = entry
            self.note = note
            self.text = text
        }
    }

    public struct NoteRemove: Hashable, Codable, Sendable {
        public var note: ULID

        public init(note: ULID) { self.note = note }
    }

    /// The note's author changed its words. The whole text, not a diff.
    public struct NoteEdit: Hashable, Codable, Sendable {
        public var note: ULID
        public var text: String

        public init(note: ULID, text: String) {
            self.note = note
            self.text = text
        }
    }
}

/// One immutable fact. The log is a sequence of these and nothing else.
public struct Event: Hashable, Sendable, Identifiable {
    public let id: ULID
    public let author: Author
    public let device: DeviceID
    public let at: Date
    public let payload: Payload

    public init(id: ULID, author: Author, device: DeviceID, at: Date, payload: Payload) {
        self.id = id
        self.author = author
        self.device = device
        self.at = at.toMilliseconds
        self.payload = payload
    }

    public var kind: Kind { payload.kind }
}

extension Date {
    /// The log keeps time to the millisecond: the precision of its ids and of its JSON.
    public var toMilliseconds: Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 * 1000).rounded() / 1000)
    }
}

extension Event: Codable {
    enum CodingKeys: String, CodingKey {
        case id, author, device, at, kind, payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ULID.self, forKey: .id)
        author = try container.decode(Author.self, forKey: .author)
        device = try container.decode(DeviceID.self, forKey: .device)
        at = try container.decode(Date.self, forKey: .at)
        let kind = try container.decode(Kind.self, forKey: .kind)
        payload = switch kind {
        case .entryCreate: .entryCreate(try container.decode(Payload.EntryCreate.self, forKey: .payload))
        case .entryEdit: .entryEdit(try container.decode(Payload.EntryEdit.self, forKey: .payload))
        case .entryDelete: .entryDelete(try container.decode(Payload.EntryDelete.self, forKey: .payload))
        case .mediaAttach: .mediaAttach(try container.decode(Payload.MediaAttach.self, forKey: .payload))
        case .noteAdd: .noteAdd(try container.decode(Payload.NoteAdd.self, forKey: .payload))
        case .noteRemove: .noteRemove(try container.decode(Payload.NoteRemove.self, forKey: .payload))
        case .noteEdit: .noteEdit(try container.decode(Payload.NoteEdit.self, forKey: .payload))
        case .labelAttach: .labelAttach(try container.decode(Payload.LabelAttach.self, forKey: .payload))
        case .labelDetach: .labelDetach(try container.decode(Payload.LabelDetach.self, forKey: .payload))
        case .linkAdd: .linkAdd(try container.decode(Payload.LinkAdd.self, forKey: .payload))
        case .linkRemove: .linkRemove(try container.decode(Payload.LinkRemove.self, forKey: .payload))
        case .link: .link(try container.decode(Payload.Join.self, forKey: .payload))
        case .unlink: .unlink(try container.decode(Payload.Unjoin.self, forKey: .payload))
        case .done: .done(try container.decode(Payload.Done.self, forKey: .payload))
        case .undone: .undone(try container.decode(Payload.Undone.self, forKey: .payload))
        case .visit: .visit(try container.decode(Payload.Visit.self, forKey: .payload))
        case .nameSet: .nameSet(try container.decode(Payload.NameSet.self, forKey: .payload))
        case .grantCreate: .grantCreate(try container.decode(Payload.GrantCreate.self, forKey: .payload))
        case .grantRevoke: .grantRevoke(try container.decode(Payload.GrantRevoke.self, forKey: .payload))
        case .loopSet: .loopSet(try container.decode(Payload.LoopSet.self, forKey: .payload))
        case .loopStop: .loopStop(try container.decode(Payload.LoopStop.self, forKey: .payload))
        case .loopRan: .loopRan(try container.decode(Payload.LoopRan.self, forKey: .payload))
        case .thingSet: .thingSet(try container.decode(Payload.ThingSet.self, forKey: .payload))
        case .thingRemove: .thingRemove(try container.decode(Payload.ThingRemove.self, forKey: .payload))
        case .factSet: .factSet(try container.decode(Payload.FactSet.self, forKey: .payload))
        case .factRemove: .factRemove(try container.decode(Payload.FactRemove.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(author, forKey: .author)
        try container.encode(device, forKey: .device)
        try container.encode(at, forKey: .at)
        try container.encode(kind, forKey: .kind)
        switch payload {
        case .entryCreate(let p): try container.encode(p, forKey: .payload)
        case .entryEdit(let p): try container.encode(p, forKey: .payload)
        case .entryDelete(let p): try container.encode(p, forKey: .payload)
        case .mediaAttach(let p): try container.encode(p, forKey: .payload)
        case .noteAdd(let p): try container.encode(p, forKey: .payload)
        case .noteRemove(let p): try container.encode(p, forKey: .payload)
        case .noteEdit(let p): try container.encode(p, forKey: .payload)
        case .labelAttach(let p): try container.encode(p, forKey: .payload)
        case .labelDetach(let p): try container.encode(p, forKey: .payload)
        case .linkAdd(let p): try container.encode(p, forKey: .payload)
        case .linkRemove(let p): try container.encode(p, forKey: .payload)
        case .link(let p): try container.encode(p, forKey: .payload)
        case .unlink(let p): try container.encode(p, forKey: .payload)
        case .done(let p): try container.encode(p, forKey: .payload)
        case .undone(let p): try container.encode(p, forKey: .payload)
        case .visit(let p): try container.encode(p, forKey: .payload)
        case .nameSet(let p): try container.encode(p, forKey: .payload)
        case .grantCreate(let p): try container.encode(p, forKey: .payload)
        case .grantRevoke(let p): try container.encode(p, forKey: .payload)
        case .loopSet(let p): try container.encode(p, forKey: .payload)
        case .loopStop(let p): try container.encode(p, forKey: .payload)
        case .loopRan(let p): try container.encode(p, forKey: .payload)
        case .thingSet(let p): try container.encode(p, forKey: .payload)
        case .thingRemove(let p): try container.encode(p, forKey: .payload)
        case .factSet(let p): try container.encode(p, forKey: .payload)
        case .factRemove(let p): try container.encode(p, forKey: .payload)
        }
    }
}

/// One event per line of JSON. Dates as ISO 8601 with milliseconds, keys sorted, so a line
/// is the same bytes on every device and diffs read like prose.
public enum JSONLines {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601.string(from: date))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = ISO8601.date(from: raw) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 date: \(raw)"))
            }
            return date
        }
        return decoder
    }

    public static func encode(_ event: Event) throws -> String {
        String(decoding: try encoder().encode(event), as: UTF8.self)
    }

    public static func decode(_ line: some StringProtocol) throws -> Event {
        try decoder().decode(Event.self, from: Data(line.utf8))
    }

    /// Decodes every non-blank line. Throws with the line number on the first bad one.
    public static func decodeAll(_ text: String) throws -> [Event] {
        let decoder = decoder()
        var events: [Event] = []
        var lineNumber = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNumber += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            do {
                events.append(try decoder.decode(Event.self, from: Data(trimmed.utf8)))
            } catch {
                throw DecodeError.badLine(number: lineNumber, underlying: error)
            }
        }
        return events
    }

    public enum DecodeError: Error {
        case badLine(number: Int, underlying: Error)
    }
}

enum ISO8601 {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
