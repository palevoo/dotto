import Foundation

/// Who wrote an event: the owner of the notebook or any grant holder. An id, not a name;
/// a name is chosen later with `name.set` and may change, the id never does.
public struct Author: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public var description: String { rawValue }

    /// The notebook's own originator. Every notebook has one, without anyone making it, as a
    /// tag is there once a line is under it: the one who reads, answers and shapes, whatever
    /// session, loop or model it comes through as. Those are its hands; it is one. It is
    /// called dotto until it is named.
    public static let dotto: Author = "dotto"

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
    /// A kind of value this build does not know, kept as it was written, so a fact set by a
    /// newer build reads, counts and writes back unchanged here, and never costs the file.
    case unknown(JSONValue)

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
            // The vocabulary grows by addition here too: what is not one of the five is carried.
            self = .unknown(try JSONValue(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        if case .unknown(let value) = self {
            try value.encode(to: encoder)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .unknown:
            break
        case .number(let number, let unit):
            try container.encode(number, forKey: .number)
            try container.encodeIfPresent(unit, forKey: .unit)
        case .words(let words): try container.encode(words, forKey: .words)
        case .moment(let moment): try container.encode(moment.toMilliseconds, forKey: .moment)
        case .span(let span): try container.encode(span, forKey: .span)
        case .place(let place): try container.encode(place, forKey: .place)
        }
    }

    /// The value as the page says it: "10 L", "potted", "2026-11-01 10:00", "41 min", "54.50, -3.20".
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
        case .unknown:
            return "a value a newer build wrote"
        }
    }
}

/// The vocabulary. Versioned by addition only; a kind never changes meaning. A build that
/// meets a kind it does not know carries the event as `Payload.unknown` and passes over it,
/// so a phone and a Mac on different builds read the same files.
public enum Kind: String, Codable, Sendable {
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
    case loopPropose = "loop.propose"
    case same = "same"
    case shapeSet = "shape.set"
    case shapeRemove = "shape.remove"
    case conditionsSet = "conditions.set"
    case conditionsRemove = "conditions.remove"
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
    case loopPropose(LoopPropose)
    case same(Same)
    /// What the things of a kind have: the newest word for a kind stands.
    case shapeSet(KindShape)
    case shapeRemove(ShapeRemove)
    /// What it was like where and when a line was written, said afterwards by a source.
    case conditionsSet(ConditionsSet)
    case conditionsRemove(ConditionsRemove)
    /// A kind this build does not know, from a device on a newer one. Carried as it was,
    /// counted, written back unchanged, and nothing else: the vocabulary grows by addition,
    /// so an older build passes over what it cannot read yet.
    case unknown(kind: String, payload: JSONValue)

    /// The kind, when this build knows it.
    public var kind: Kind? {
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
        case .loopPropose: .loopPropose
        case .same: .same
        case .shapeSet: .shapeSet
        case .shapeRemove: .shapeRemove
        case .conditionsSet: .conditionsSet
        case .conditionsRemove: .conditionsRemove
        case .unknown: nil
        }
    }

    /// The owner drops what was said a kind has. Things of the kind keep their word and
    /// their facts; they are drawn by what each fact looks like.
    public struct ShapeRemove: Hashable, Codable, Sendable {
        public var kind: String

        public init(kind: String) { self.kind = kind.lowercased() }
    }

    /// The owner says two originators are one: everything `author` ever did, and does from
    /// now on, is `same`'s. Nothing is rewritten; the files keep the name they were written
    /// under and the fold reads through it. For an originator that came through two keys
    /// under two ids, both of them dotto. Only the owner's count, and nobody is made the same
    /// as the owner.
    public struct Same: Hashable, Codable, Sendable {
        public var author: Author
        public var same: Author

        public init(author: Author, as same: Author) {
            self.author = author
            self.same = same
        }
    }

    /// A loop: a sentence said once, kept, run, with a receipt each time. The owner's event,
    /// like a grant: a name, the grant it runs as, what wakes it, a line landing or the clock
    /// at an hour each day, a brief in the owner's words added to the door's conduct, and a
    /// cap on turns and on spend. The newest set for a loop id stands; stop ends it.
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

    /// A loop someone other than the owner asks for: a sentence the owner wrote, heard and
    /// shaped as a loop, with the same fields a set has. Only the owner sets a loop, so a
    /// proposal waits for their hand: set with the proposal's id as the loop's, or declined
    /// with a stop of that id. The proposer's own grant is the one it would run as.
    public struct LoopPropose: Hashable, Codable, Sendable {
        public var loop: ULID
        public var name: String
        public var grant: ULID?
        public var wake: String
        public var at: String?
        public var brief: String?
        public var turns: Int
        public var budget: Double

        public init(loop: ULID, name: String, grant: ULID?, wake: String, at: String? = nil, brief: String? = nil, turns: Int = 40, budget: Double = 2) {
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
    /// a streak, a tag. Made by whoever proposes it; it stands until dropped. Only its own
    /// originator sets it again, to rename it or give it a kind, and the newest set stands.
    /// A kind is a word for now, plant, book, person, not a link.
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

    /// A fact: a key and a value put on a line or a thing by an originator. The weight on a
    /// line about flour, the state of the fig, the days of a streak. One fact per originator
    /// per key on a thing; the newest word of that originator wins.
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
    /// older one.
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

    /// A later line joined to an earlier one, with `closes` meaning the later finished the
    /// earlier. Folded as a link from later to earlier, and, when closes is set, as done on
    /// the earlier line by the later. Still read: notebooks written by earlier builds carry it.
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

    /// A `link.add` taken back, and the finishing with it. Still read: notebooks written by
    /// earlier builds carry it.
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
        /// What was read. A kind this build does not know, from a newer one, is carried as
        /// its word and written back as it came: the vocabulary grows by addition here too.
        public enum What: Hashable, Codable, Sendable {
            case days, lines, photo
            /// A look at what happened since the last look.
            case inbox
            /// A look at the things: shapes lines belong to, with their facts.
            case things
            /// A look at the loops that run, and the ones proposed.
            case loops
            /// A search for plain words across the notebook.
            case search
            /// A kind of read from a newer build, by its word.
            case other(String)

            private static let words: [(What, String)] = [
                (.days, "days"), (.lines, "lines"), (.photo, "photo"), (.inbox, "inbox"),
                (.things, "things"), (.loops, "loops"), (.search, "search"),
            ]

            public var rawValue: String {
                if case .other(let word) = self { return word }
                return Self.words.first { $0.0 == self }!.1
            }

            public init(rawValue: String) {
                self = Self.words.first { $0.1 == rawValue }?.0 ?? .other(rawValue)
            }

            public init(from decoder: Decoder) throws {
                self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(rawValue)
            }
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
        /// For a search: the words looked for.
        public var words: String?

        public init(what: What, since: String? = nil, label: String? = nil, count: Int, entry: ULID? = nil, hash: String? = nil,
                    seen: [String: Int]? = nil, words: String? = nil) {
            self.what = what
            self.since = since
            self.label = label
            self.count = count
            self.entry = entry
            self.hash = hash
            self.seen = seen
            self.words = words
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
        /// and the owner drops it with one hold.
        public var page: Author?
        /// What the line was said under: a line, which makes it a reply; a reply, which makes
        /// it an answer to that reply in the same conversation; or a thing, which makes it
        /// something said on that thing's page. Absent, it stands on its writer's days. Where
        /// a line was said is part of it and never changes.
        public var under: ULID?

        public init(entry: ULID, text: String, startedAt: Date, location: Location? = nil, page: Author? = nil, under: ULID? = nil) {
            self.entry = entry
            self.text = text
            self.startedAt = startedAt.toMilliseconds
            self.location = location
            self.page = page
            self.under = under
        }

        enum CodingKeys: String, CodingKey {
            case entry, text, page, under
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
        /// For a page kept beside the line: what it is called, and the address it came from.
        public var title: String?
        public var source: String?

        public init(entry: ULID, hash: String, mime: String, width: Int? = nil, height: Int? = nil, duration: Double? = nil,
                    title: String? = nil, source: String? = nil) {
            self.entry = entry
            self.hash = hash
            self.mime = mime
            self.width = width
            self.height = height
            self.duration = duration
            self.title = title
            self.source = source
        }

        enum CodingKeys: String, CodingKey {
            case entry, hash, mime, title, source
            case width = "w"
            case height = "h"
            case duration = "dur"
        }
    }

    /// A line under someone's line, by anyone: a reply. Still read: notebooks written by
    /// earlier builds carry it. A reply is written as a line that says what it is under.
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

    /// A note taken back. Still read: notebooks written by earlier builds carry it.
    public struct NoteRemove: Hashable, Codable, Sendable {
        public var note: ULID

        public init(note: ULID) { self.note = note }
    }

    /// The note's author changed its words. The whole text, not a diff. Still read:
    /// notebooks written by earlier builds carry it.
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

    /// The kind, when this build knows it.
    public var kind: Kind? { payload.kind }

    /// The kind's name as the file has it, known or not.
    public var kindName: String {
        if case .unknown(let kind, _) = payload { return kind }
        return payload.kind?.rawValue ?? ""
    }
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
        let name = try container.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: name) else {
            payload = .unknown(kind: name, payload: try container.decodeIfPresent(JSONValue.self, forKey: .payload) ?? .object([:]))
            return
        }
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
        case .loopPropose: .loopPropose(try container.decode(Payload.LoopPropose.self, forKey: .payload))
        case .same: .same(try container.decode(Payload.Same.self, forKey: .payload))
        case .shapeSet: .shapeSet(try container.decode(KindShape.self, forKey: .payload))
        case .shapeRemove: .shapeRemove(try container.decode(Payload.ShapeRemove.self, forKey: .payload))
        case .conditionsSet: .conditionsSet(try container.decode(Payload.ConditionsSet.self, forKey: .payload))
        case .conditionsRemove: .conditionsRemove(try container.decode(Payload.ConditionsRemove.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(author, forKey: .author)
        try container.encode(device, forKey: .device)
        try container.encode(at, forKey: .at)
        try container.encode(kindName, forKey: .kind)
        switch payload {
        case .unknown(_, let raw): try container.encode(raw, forKey: .payload)
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
        case .loopPropose(let p): try container.encode(p, forKey: .payload)
        case .same(let p): try container.encode(p, forKey: .payload)
        case .shapeSet(let p): try container.encode(p, forKey: .payload)
        case .shapeRemove(let p): try container.encode(p, forKey: .payload)
        case .conditionsSet(let p): try container.encode(p, forKey: .payload)
        case .conditionsRemove(let p): try container.encode(p, forKey: .payload)
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

    /// An event file as it is on disk, read for what can be read. A line that is not an
    /// event, a write cut short, bytes that are not text, is passed over and its number
    /// kept, so one damaged line costs that line and never the file or the notebook.
    /// Blank lines are nothing. Line numbers start at one.
    public static func read(_ data: Data) -> (events: [Event], unreadable: [Int]) {
        let decoder = decoder()
        var events: [Event] = []
        var unreadable: [Int] = []
        var number = 0
        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false) {
            number += 1
            // Spaces, tabs and a carriage return around a line are not part of it.
            guard let first = line.firstIndex(where: { !isBlank($0) }),
                  let last = line.lastIndex(where: { !isBlank($0) }) else { continue }
            if let event = try? decoder.decode(Event.self, from: Data(line[first...last])) {
                events.append(event)
            } else {
                unreadable.append(number)
            }
        }
        return (events, unreadable)
    }

    private static func isBlank(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0D
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
