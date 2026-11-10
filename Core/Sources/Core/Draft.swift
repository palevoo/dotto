import Foundation

/// Something that landed in the live line before it was stored.
public struct DraftMedia: Identifiable, Hashable, Codable, Sendable {
    public let hash: String
    public let mime: String
    public let width: Int?
    public let height: Int?
    public let duration: Double?
    /// When it happened: the shutter, or the start of the recording.
    public let at: Date
    /// Where, if the photo knows.
    public var location: Location?
    /// True for a photo brought in from the library rather than made here.
    public var fromBefore = false

    public var id: String { hash }

    public init(hash: String, mime: String, width: Int? = nil, height: Int? = nil, duration: Double? = nil,
                at: Date, location: Location? = nil, fromBefore: Bool = false) {
        self.hash = hash
        self.mime = mime
        self.width = width
        self.height = height
        self.duration = duration
        self.at = at
        self.location = location
        self.fromBefore = fromBefore
    }
}

/// The live line before Return: its words, what landed with them, and the moment it began.
/// It is in one of two states, empty or begun, and only its own moves change it: writing,
/// something landing, something taken out. The moment is fixed when the first thing lands and
/// let go when the last thing leaves, so `begun` is nil exactly while the line is empty.
/// Photos from before offer their own moment, and the line takes it until told otherwise.
/// Nothing stores it but Return, which is `stored`.
public struct Draft: Equatable, Codable, Sendable {
    public private(set) var text = ""
    public private(set) var media: [DraftMedia] = []
    /// When the first character or the first thing landed. Nil while the line is empty.
    public private(set) var begun: Date?
    /// Whether the line is stored at its photos' moment rather than when it began.
    public private(set) var keepsPhotoMoment = false

    enum CodingKeys: String, CodingKey {
        case text, media, keepsPhotoMoment
        case begun = "startedAt"
    }

    public init() {}

    public var isEmpty: Bool { text.isEmpty && media.isEmpty }

    /// The words as the thumb has them: typed, pasted, cut. Begins the line on the first
    /// character and ends it when the last goes with nothing else there.
    public mutating func write(_ words: String, now: Date) {
        text = words
        settle(at: now)
    }

    /// Words that arrive after whatever is there: a passage read off a page, in quotation
    /// marks, or what a voice note said. Blank words change nothing.
    public mutating func append(_ words: String, quoted: Bool = false, now: Date) {
        let flat = words.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        guard !flat.isEmpty else { return }
        let piece = quoted ? "\u{201C}\(flat)\u{201D}" : flat
        text = text.isEmpty ? piece : text + " " + piece
        settle(at: now)
    }

    /// A photo or a voice note lands. If the line has not begun, it begins at `moment`: now
    /// for a photo, the start of the recording for a voice note. The first photo from before
    /// offers its own moment, and the line takes it.
    public mutating func add(_ item: DraftMedia, beginning moment: Date, now: Date, calendar: Calendar) {
        let offered = photoMoment(now: now, calendar: calendar) != nil
        media.append(item)
        settle(at: moment)
        if !offered, photoMoment(now: now, calendar: calendar) != nil { keepsPhotoMoment = true }
    }

    /// Something is taken out again. With the last photo from before goes its moment.
    public mutating func remove(_ id: DraftMedia.ID, now: Date, calendar: Calendar) {
        media.removeAll { $0.id == id }
        settle(at: now)
        if photoMoment(now: now, calendar: calendar) == nil { keepsPhotoMoment = false }
    }

    /// Between the photos' moment and now, when the photos offer one.
    public mutating func toggleMoment(now: Date, calendar: Calendar) {
        guard photoMoment(now: now, calendar: calendar) != nil else { return }
        keepsPhotoMoment.toggle()
    }

    /// The moment the photos in the line were taken, when they all come from one earlier day:
    /// the earliest of them. Nil when nothing is from before, or the photos are from different days.
    public func photoMoment(now: Date, calendar: Calendar) -> Date? {
        let earlier = media.filter(\.fromBefore).map(\.at)
        guard let first = earlier.min() else { return nil }
        let day = DayKey(first, calendar: calendar)
        guard day != DayKey(now, calendar: calendar), earlier.allSatisfy({ DayKey($0, calendar: calendar) == day }) else { return nil }
        return first
    }

    /// The moment the line will be stored at: the photos' own, if kept, else when it began.
    public func moment(now: Date, calendar: Calendar) -> Date? {
        if keepsPhotoMoment, let moment = photoMoment(now: now, calendar: calendar) { return moment }
        return begun
    }

    /// Return. The events that store the line as one entry with its media, and the entry's
    /// id, or nil when there is nothing to store: no words past whitespace and nothing landed.
    /// The place is where the phone is now, or, for a line stored at its photos' moment,
    /// where the first of those photos was taken.
    public func stored(by owner: Author, on device: DeviceID, here: Location?, ids: ULIDGenerator,
                       now: Date, calendar: Calendar) -> (id: ULID, events: [Event])? {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let startedAt = moment(now: now, calendar: calendar), !words.isEmpty || !media.isEmpty else { return nil }
        let fromBefore = keepsPhotoMoment && photoMoment(now: now, calendar: calendar) != nil
        let place = fromBefore ? media.first(where: { $0.fromBefore && $0.location != nil })?.location : here
        let id = ids.next(at: startedAt)
        var events = [
            Event(id: id, author: owner, device: device, at: now,
                  payload: .entryCreate(.init(entry: id, text: words, startedAt: startedAt, location: place))),
        ]
        for item in media {
            events.append(Event(id: ids.next(at: now), author: owner, device: device, at: now,
                                payload: .mediaAttach(.init(entry: id, hash: item.hash, mime: item.mime,
                                                            width: item.width, height: item.height, duration: item.duration))))
        }
        return (id, events)
    }

    /// Keeps `begun` true to the line: set when the first thing lands, cleared when the last leaves.
    private mutating func settle(at moment: Date) {
        if isEmpty {
            begun = nil
        } else if begun == nil {
            begun = moment
        }
    }
}

/// Words as a line keeps them.
public enum Words {
    /// A passage with line breaks in it, a paste, dictation, a drop, as one line: every run
    /// of breaks, with the spaces around it, becomes one space.
    public static func flattened(_ passage: String) -> String {
        var out = ""
        var pendingSpace = false
        var sawBreak = false
        for scalar in passage.unicodeScalars {
            if CharacterSet.newlines.contains(scalar) {
                if !sawBreak { while out.hasSuffix(" ") { out.removeLast() } }
                sawBreak = true
                pendingSpace = true
            } else if sawBreak, scalar == " " {
                pendingSpace = true
            } else {
                if pendingSpace, !out.isEmpty, !out.hasSuffix(" ") { out.append(" ") }
                pendingSpace = false
                sawBreak = false
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
