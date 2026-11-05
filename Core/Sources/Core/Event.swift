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
    case visit = "visit"
    case nameSet = "name.set"
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
    case visit(Visit)
    case nameSet(NameSet)

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
        case .visit: .visit
        case .nameSet: .nameSet
        }
    }

    /// An author chooses what they are called. Nobody has a name until they choose one;
    /// the latest choice stands. The author id on every event never changes.
    public struct NameSet: Hashable, Codable, Sendable {
        public var name: String

        public init(name: String) { self.name = name }
    }

    /// An author joins a later line to an earlier one: the later continues the earlier and,
    /// when `closes` is set, finishes what the earlier line opened. One link per pair of
    /// lines; a newer add or remove for the same pair replaces an older one.
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

        public init(entry: ULID, text: String, startedAt: Date, location: Location? = nil) {
            self.entry = entry
            self.text = text
            self.startedAt = startedAt.toMilliseconds
            self.location = location
        }

        enum CodingKeys: String, CodingKey {
            case entry, text
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
        case .visit: .visit(try container.decode(Payload.Visit.self, forKey: .payload))
        case .nameSet: .nameSet(try container.decode(Payload.NameSet.self, forKey: .payload))
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
        case .visit(let p): try container.encode(p, forKey: .payload)
        case .nameSet(let p): try container.encode(p, forKey: .payload)
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
