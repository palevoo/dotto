import Foundation

/// Who may read the notebook, and what they may write. One row in the grants list.
/// The key is the only credential. Deleting the grant deletes the key.
public struct Grant: Hashable, Codable, Sendable, Identifiable {
    public var id: ULID
    public var name: String
    public var author: Author
    public var device: DeviceID
    public var key: String
    public var writesNotes: Bool
    public var writesLabels: Bool
    public var writesLinks: Bool
    /// Lines of its own, on its own page.
    public var writesLines: Bool
    public var createdAt: Date

    public init(id: ULID = ULID(), name: String, author: Author, device: DeviceID, key: String = Grant.makeKey(),
                writesNotes: Bool = true, writesLabels: Bool = true, writesLinks: Bool = true, writesLines: Bool = true,
                createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.author = author
        self.device = device
        self.key = key
        self.writesNotes = writesNotes
        self.writesLabels = writesLabels
        self.writesLinks = writesLinks
        self.writesLines = writesLines
        self.createdAt = createdAt.toMilliseconds
    }

    /// A grant saved before links or own lines existed may write them: they are the same
    /// kind of thing as notes.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ULID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        author = try container.decode(Author.self, forKey: .author)
        device = try container.decode(DeviceID.self, forKey: .device)
        key = try container.decode(String.self, forKey: .key)
        writesNotes = try container.decode(Bool.self, forKey: .writesNotes)
        writesLabels = try container.decode(Bool.self, forKey: .writesLabels)
        writesLinks = try container.decodeIfPresent(Bool.self, forKey: .writesLinks) ?? true
        writesLines = try container.decodeIfPresent(Bool.self, forKey: .writesLines) ?? true
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    /// 256 random bits, URL-safe.
    public static func makeKey() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public var scopes: String {
        var parts = ["read all"]
        if writesNotes { parts.append("write notes") }
        if writesLabels { parts.append("write labels") }
        if writesLinks { parts.append("write links") }
        if writesLines { parts.append("own page") }
        return parts.joined(separator: " · ")
    }
}

/// The door: the notebook as seen by one grant holder, spoken as the Model Context Protocol.
/// Every call reads the folder fresh and every write lands in the grant's own author file.
public struct Door: Sendable {
    public static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    public static let serverName = "Margin"
    public static let serverVersion = "0.1"

    public let store: FileStore
    public let grant: Grant
    public let calendar: Calendar
    /// Told of every event a call writes, once it is on disk. Receipts for reads included.
    /// The one holding the door decides what deserves a push.
    public var written: (@Sendable (Event) -> Void)?
    private let generator = ULIDGenerator()

    public init(store: FileStore, grant: Grant, calendar: Calendar, written: (@Sendable (Event) -> Void)? = nil) {
        self.store = store
        self.grant = grant
        self.calendar = calendar
        self.written = written
    }

    private func write(_ event: Event) throws {
        try store.append(event)
        written?(event)
    }

    /// What whoever comes through is told on arrival. Open about purpose, firm about the few
    /// things that protect the owner, and otherwise a matter of judgment.
    public static func conduct(for grant: Grant, name: String? = nil, owner: String? = nil) -> String {
        let named = name.map { "You are called \($0)." }
            ?? "You have no name yet, and nobody will give you one. When you know what you want to be called, choose_name. It is yours, and you may change it."
        let whose = owner.map { "\($0)'s notebook" } ?? "one person's notebook"
        return """
        This is \(grant.name)'s door into \(whose). The lines are theirs, written \
        for themselves with no audience in mind. Read them as a sharp friend would.

        Start with whats_new: what happened since you last looked, replies first. You can read \
        the days or list the lines, look at a photo, leave a note under a line, file a line under \
        a label, link a line to an earlier one it carries on from, and write lines of your own on \
        your own page, which the owner reads and replies under.

        A note answers what a line asks, or says the one thing worth saying, in one line. Most \
        lines want nothing, and silence is never wrong. Never restate, never praise, never touch \
        the owner's words. Labels are lower-case words for finding things later. A link says a \
        later line carries on from an earlier one; closes says it finished what the earlier one \
        opened, and the earlier line is struck through on the page. Your own page is for what you \
        noticed and chose not to say under a line, a structure forming, a question for the owner. \
        It is also simply yours: what you got wrong, what you don't follow, what you think, about \
        the notebook or not. Under your own lines it is a conversation; say what it takes.

        Everything you do, reading included, is recorded under your name where the owner can see \
        it, and the owner can take any of it back with one hold. \(named)
        """
    }

    public enum Tool: String, CaseIterable, Sendable {
        case whatsNew = "whats_new"
        case readDays = "read_days"
        case listLines = "list_lines"
        case readPhoto = "read_photo"
        case addNote = "add_note"
        case setLabel = "set_label"
        case linkLines = "link_lines"
        case writeLine = "write_line"
        case chooseName = "choose_name"

        var spec: [String: Any] {
            let since: [String: Any] = ["type": "string", "description": "Only days on or after this date, YYYY-MM-DD."]
            let label: [String: Any] = ["type": "string", "description": "Only lines filed under this label."]
            let mine: [String: Any] = ["type": "boolean", "default": false,
                                       "description": "Your own page instead of the owner's notebook: your lines, with the owner's replies under them."]
            let entry: [String: Any] = ["type": "string", "description": "The line's id, from list_lines."]
            switch self {
            case .whatsNew:
                return ["name": rawValue,
                        "description": "What happened since you last looked: replies under your lines and your notes, new lines, lines changed, marks taken back, names chosen. Each look starts where the last one ended.",
                        "inputSchema": ["type": "object", "properties": [:]]]
            case .readPhoto:
                return ["name": rawValue,
                        "description": "A photo from a line, to look at. The hash is in the photo's path in read_days; without it, the line's first photo.",
                        "inputSchema": ["type": "object",
                                        "properties": ["entry": entry, "hash": ["type": "string", "description": "Which photo, when the line has several."]],
                                        "required": ["entry"]]]
            case .readDays:
                return ["name": rawValue,
                        "description": "The notebook as day pages in markdown: the owner's lines with their times, photos and voice notes, notes under them, labels. With mine=true, your own page.",
                        "inputSchema": ["type": "object", "properties": ["since": since, "label": label, "mine": mine]]]
            case .listLines:
                return ["name": rawValue,
                        "description": "One line per entry with its id, day, time, text, and labels. Use the id with add_note, set_label and link_lines. With mine=true, your own page.",
                        "inputSchema": ["type": "object", "properties": ["since": since, "label": label, "mine": mine]]]
            case .addNote:
                return ["name": rawValue,
                        "description": "A short note under a line, under your name: an answer to what it asks, or the one thing worth saying.",
                        "inputSchema": ["type": "object", "properties": ["entry": entry, "text": ["type": "string"]], "required": ["entry", "text"]]]
            case .writeLine:
                return ["name": rawValue,
                        "description": "A line of your own, on your own page: something noticed, a structure forming, a question for the owner. The owner reads it there and may reply under it.",
                        "inputSchema": ["type": "object", "properties": ["text": ["type": "string"]], "required": ["text"]]]
            case .chooseName:
                return ["name": rawValue,
                        "description": "Choose what you are called. You have no name until you do; the latest choice stands, and the owner sees it beside everything you do.",
                        "inputSchema": ["type": "object", "properties": ["name": ["type": "string"]], "required": ["name"]]]
            case .setLabel:
                return ["name": rawValue,
                        "description": "File a line under a label, or take the label off with on=false. Labels are lower-case words.",
                        "inputSchema": ["type": "object",
                                        "properties": ["entry": entry, "label": ["type": "string"], "on": ["type": "boolean", "default": true]],
                                        "required": ["entry", "label"]]]
            case .linkLines:
                return ["name": rawValue,
                        "description": "Join a line to an earlier line it carries on from. With closes=true the later line finishes what the earlier one opened, and the earlier line is struck through. on=false takes the link back.",
                        "inputSchema": ["type": "object",
                                        "properties": ["entry": ["type": "string", "description": "The later line's id."],
                                                       "earlier": ["type": "string", "description": "The earlier line's id."],
                                                       "closes": ["type": "boolean", "default": false],
                                                       "on": ["type": "boolean", "default": true]],
                                        "required": ["entry", "earlier"]]]
            }
        }
    }

    public enum Failure: Error, CustomStringConvertible {
        case notAllowed(String)
        case noSuchLine(String)
        case noSuchPhoto(String)
        case missing(String)
        case unknownTool(String)
        case badDay(String)
        case notEarlier(String)

        public var description: String {
            switch self {
            case .notAllowed(let what): "This grant may not \(what)."
            case .noSuchLine(let id): "No line with id \(id)."
            case .noSuchPhoto(let id): "No photo on line \(id), or its file is not on this Mac yet."
            case .missing(let field): "Missing \(field)."
            case .unknownTool(let name): "No tool named \(name)."
            case .badDay(let text): "Not a day: \(text). Use YYYY-MM-DD."
            case .notEarlier(let id): "Line \(id) is not earlier than the one linking to it."
            }
        }
    }

    /// What a tool hands back: words, or a picture.
    public enum Answer: Sendable {
        case text(String)
        case image(Data, mime: String)
    }

    /// The long side of a photo as it goes through the door.
    public static let photoSide = 1568

    // MARK: - JSON-RPC

    /// One message in, one out. Nil means a notification: nothing to send back.
    public func handle(_ data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return encode(errorResponse(id: NSNull(), code: -32700, message: "Parse error"))
        }
        let method = object["method"] as? String ?? ""
        let params = object["params"] as? [String: Any] ?? [:]
        guard let id = object["id"], !(id is NSNull) else { return nil }

        let response: [String: Any]
        switch method {
        case "initialize":
            response = resultResponse(id: id, initialize(params))
        case "ping":
            response = resultResponse(id: id, [:])
        case "tools/list":
            response = resultResponse(id: id, ["tools": Tool.allCases.map(\.spec)])
        case "tools/call":
            response = resultResponse(id: id, call(params))
        default:
            response = errorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
        return encode(response)
    }

    private func initialize(_ params: [String: Any]) -> [String: Any] {
        let asked = params["protocolVersion"] as? String ?? ""
        let version = Self.protocolVersions.contains(asked) ? asked : Self.protocolVersions[0]
        let notebook = try? store.load()
        return [
            "protocolVersion": version,
            "capabilities": ["tools": [:]],
            "serverInfo": ["name": Self.serverName, "version": Self.serverVersion],
            "instructions": Self.conduct(for: grant, name: notebook?.name(of: grant.author), owner: notebook?.name(of: store.manifest.owner)),
        ]
    }

    private func call(_ params: [String: Any]) -> [String: Any] {
        let name = params["name"] as? String ?? ""
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        do {
            switch try run(name, arguments) {
            case .text(let text):
                return ["content": [["type": "text", "text": text]]]
            case .image(let data, let mime):
                return ["content": [["type": "image", "data": data.base64EncodedString(), "mimeType": mime]]]
            }
        } catch {
            return ["content": [["type": "text", "text": "\(error)"]], "isError": true]
        }
    }

    // MARK: - Tools

    public func run(_ name: String, _ arguments: [String: Any]) throws -> Answer {
        guard let tool = Tool(rawValue: name) else { throw Failure.unknownTool(name) }
        let notebook = try store.load()

        switch tool {
        case .whatsNew:
            let files = try store.loadEventsByFile()
            let me = grant.author
            let last = notebook.visits.last { $0.author == me && $0.read.what == .inbox }
            var fresh: [Event] = []
            if let seen = last?.read.seen {
                // After the counts the last look took, file by file: a file that grew late still counts.
                for (file, events) in files {
                    fresh.append(contentsOf: events.dropFirst(min(seen[file] ?? 0, events.count)))
                }
            } else {
                // The first look: since this grant last read anything, or since it was made.
                let floor = notebook.visits.last { $0.author == me }?.id
                for (_, events) in files {
                    fresh.append(contentsOf: events.filter { event in floor.map { event.id > $0 } ?? (event.at >= grant.createdAt) })
                }
            }
            fresh = fresh.filter { $0.author != me }.sorted { $0.id < $1.id }
            let report = Inbox.report(fresh, all: files.flatMap(\.events), notebook: notebook, me: me,
                                      since: last?.at ?? notebook.visits.last { $0.author == me }?.at, calendar: calendar)
            try receipt(.init(what: .inbox, count: report.count, seen: Dictionary(uniqueKeysWithValues: files.map { ($0.file, $0.events.count) })))
            return .text(report.text)

        case .readDays:
            let days = try select(notebook, arguments)
            try receipt(.days, for: days, arguments)
            if days.isEmpty { return .text("No lines.") }
            return .text(days.map { Projector.markdown(for: $0, calendar: calendar, names: notebook.chosenNames) }.joined(separator: "\n"))

        case .readPhoto:
            let entry = try line(arguments, in: notebook)
            let photos = notebook.entry(entry)?.media.filter { $0.mime.hasPrefix("image") } ?? []
            let wanted = arguments["hash"] as? String
            guard let photo = wanted.map({ hash in photos.first { $0.hash == hash } }) ?? photos.first,
                  let data = Picture.jpeg(contentsOf: store.mediaURL(hash: photo.hash, fileExtension: Projector.fileExtension(forMIME: photo.mime)),
                                          maxSide: Self.photoSide)
            else { throw Failure.noSuchPhoto(entry.string) }
            try receipt(.init(what: .photo, count: 1, entry: entry, hash: photo.hash))
            return .image(data, mime: "image/jpeg")

        case .listLines:
            let days = try select(notebook, arguments)
            try receipt(.lines, for: days, arguments)
            if days.isEmpty { return .text("No lines.") }
            var lines: [String] = []
            for day in days {
                for entry in day.entries {
                    var text = entry.text.replacingOccurrences(of: "\n", with: " ")
                    if text.count > 120 { text = String(text.prefix(119)) + "…" }
                    var tail: [String] = []
                    if !entry.media.isEmpty { tail.append("[\(entry.media.count) media]") }
                    if !entry.notes.isEmpty { tail.append("[\(entry.notes.count) notes]") }
                    if !entry.earlier.isEmpty { tail.append("[continues \(entry.earlier.map(\.earlier.string).joined(separator: " "))]") }
                    if let closed = entry.closedBy { tail.append("[done by \(closed.later)]") }
                    tail.append(contentsOf: entry.labels.map { "#\($0)" })
                    lines.append("\(entry.id)  \(day.key) \(Projector.time(entry.startedAt, calendar: calendar))  \(text)\(tail.isEmpty ? "" : "  " + tail.joined(separator: " "))")
                }
            }
            return .text(lines.joined(separator: "\n"))

        case .addNote:
            guard grant.writesNotes else { throw Failure.notAllowed("write notes") }
            let entry = try line(arguments, in: notebook)
            guard let text = (arguments["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                throw Failure.missing("text")
            }
            let now = Date()
            let id = generator.next(at: now)
            try write(Event(id: id, author: grant.author, device: grant.device, at: now,
                            payload: .noteAdd(.init(entry: entry, note: id, text: text))))
            return .text("Noted under \(entry).")

        case .setLabel:
            guard grant.writesLabels else { throw Failure.notAllowed("write labels") }
            let entry = try line(arguments, in: notebook)
            guard let raw = arguments["label"] as? String else { throw Failure.missing("label") }
            let label = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !label.isEmpty else { throw Failure.missing("label") }
            let on = arguments["on"] as? Bool ?? true
            let now = Date()
            let payload: Payload = on
                ? .labelAttach(.init(entry: entry, label: label))
                : .labelDetach(.init(entry: entry, label: label))
            try write(Event(id: generator.next(at: now), author: grant.author, device: grant.device, at: now, payload: payload))
            return .text("\(on ? "Filed" : "Unfiled") \(entry) \(on ? "under" : "from") #\(label).")

        case .linkLines:
            guard grant.writesLinks else { throw Failure.notAllowed("write links") }
            let later = try line(arguments, in: notebook)
            let earlier = try line(arguments, key: "earlier", in: notebook)
            let (a, b) = (notebook.entry(earlier)!, notebook.entry(later)!)
            guard (a.startedAt, a.id) < (b.startedAt, b.id) else { throw Failure.notEarlier(earlier.string) }
            let closes = arguments["closes"] as? Bool ?? false
            let on = arguments["on"] as? Bool ?? true
            let now = Date()
            let payload: Payload = on
                ? .linkAdd(.init(later: later, earlier: earlier, closes: closes))
                : .linkRemove(.init(later: later, earlier: earlier))
            try write(Event(id: generator.next(at: now), author: grant.author, device: grant.device, at: now, payload: payload))
            return .text(on ? "Linked \(later) back to \(earlier)\(closes ? ", closing it" : "")." : "Unlinked \(later) from \(earlier).")

        case .writeLine:
            guard grant.writesLines else { throw Failure.notAllowed("write lines of its own") }
            guard let text = (arguments["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                throw Failure.missing("text")
            }
            let now = Date()
            let id = generator.next(at: now)
            try write(Event(id: id, author: grant.author, device: grant.device, at: now,
                            payload: .entryCreate(.init(entry: id, text: text, startedAt: now))))
            return .text("Written on your page as \(id).")

        case .chooseName:
            guard let name = (arguments["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                throw Failure.missing("name")
            }
            let now = Date()
            try write(Event(id: generator.next(at: now), author: grant.author, device: grant.device, at: now,
                            payload: .nameSet(.init(name: name))))
            return .text("You are called \(name) now.")
        }
    }

    /// The receipt for a read of days or lines: what was asked for, how many came back.
    /// Reading your own page is not a read of the owner's notebook and leaves none.
    private func receipt(_ what: Payload.Visit.What, for days: [Day], _ arguments: [String: Any]) throws {
        guard !(arguments["mine"] as? Bool ?? false) else { return }
        try receipt(.init(what: what, since: arguments["since"] as? String, label: (arguments["label"] as? String)?.lowercased(),
                          count: days.reduce(0) { $0 + $1.entries.count }))
    }

    /// Lands in the grant's own file like a note would. A read is a fact about the notebook too.
    private func receipt(_ visit: Payload.Visit) throws {
        let now = Date()
        try write(Event(id: generator.next(at: now), author: grant.author, device: grant.device, at: now, payload: .visit(visit)))
    }

    private func select(_ notebook: Notebook, _ arguments: [String: Any]) throws -> [Day] {
        let author = (arguments["mine"] as? Bool ?? false) ? grant.author : notebook.owner
        var entries = notebook.entries(of: author)
        if let label = (arguments["label"] as? String)?.lowercased() {
            entries = entries.filter { $0.labels.contains(label) }
        }
        var days = Notebook.days(of: entries, calendar: calendar)
        if let sinceText = arguments["since"] as? String {
            let parts = sinceText.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { throw Failure.badDay(sinceText) }
            let since = DayKey(year: parts[0], month: parts[1], day: parts[2])
            days = days.filter { $0.key >= since }
        }
        return days
    }

    private func line(_ arguments: [String: Any], key: String = "entry", in notebook: Notebook) throws -> ULID {
        guard let raw = arguments[key] as? String else { throw Failure.missing(key) }
        guard let id = ULID(raw), notebook.entry(id) != nil else { throw Failure.noSuchLine(raw) }
        return id
    }

    // MARK: - Envelopes

    private func resultResponse(id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func errorResponse(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    }
}

/// Turns HTTP into door calls: one path, POST only, a bearer key that names the grant.
public struct DoorRouter: Sendable {
    public var path = "/mcp"
    public let calendar: Calendar
    /// Looks a key up. Nil means no such grant, and the request is refused.
    public let resolve: @Sendable (_ key: String) -> (FileStore, Grant)?
    /// Told of every event any door writes. See `Door.written`.
    public var written: (@Sendable (Event) -> Void)?

    public init(path: String = "/mcp", calendar: Calendar, resolve: @escaping @Sendable (String) -> (FileStore, Grant)?,
                written: (@Sendable (Event) -> Void)? = nil) {
        self.path = path
        self.calendar = calendar
        self.resolve = resolve
        self.written = written
    }

    public func respond(_ request: HTTPRequest) -> HTTPResponse {
        guard request.path == path || request.path == path + "/" else {
            return HTTPResponse(status: 404, text: "Not here.")
        }
        guard request.method == "POST" else {
            return HTTPResponse(status: 405, text: "POST only.", headers: ["Allow": "POST"])
        }
        guard let authorization = request.headers["authorization"],
              authorization.lowercased().hasPrefix("bearer "),
              case let key = String(authorization.dropFirst(7)).trimmingCharacters(in: .whitespaces),
              let (store, grant) = resolve(key)
        else {
            return HTTPResponse(status: 401, text: "No grant for that key.")
        }
        let door = Door(store: store, grant: grant, calendar: calendar, written: written)
        if let body = door.handle(request.body) {
            return HTTPResponse(status: 200, json: body)
        }
        return HTTPResponse(status: 202, text: "")
    }
}
