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
    public var createdAt: Date

    public init(id: ULID = ULID(), name: String, author: Author, device: DeviceID, key: String = Grant.makeKey(),
                writesNotes: Bool = true, writesLabels: Bool = true, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.author = author
        self.device = device
        self.key = key
        self.writesNotes = writesNotes
        self.writesLabels = writesLabels
        self.createdAt = createdAt.toMilliseconds
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
    private let generator = ULIDGenerator()

    public init(store: FileStore, grant: Grant, calendar: Calendar) {
        self.store = store
        self.grant = grant
        self.calendar = calendar
    }

    public enum Tool: String, CaseIterable, Sendable {
        case readDays = "read_days"
        case listLines = "list_lines"
        case addNote = "add_note"
        case setLabel = "set_label"

        var spec: [String: Any] {
            let since: [String: Any] = ["type": "string", "description": "Only days on or after this date, YYYY-MM-DD."]
            let label: [String: Any] = ["type": "string", "description": "Only lines filed under this label."]
            let entry: [String: Any] = ["type": "string", "description": "The line's id, from list_lines."]
            switch self {
            case .readDays:
                return ["name": rawValue,
                        "description": "The notebook as day pages in markdown: the owner's lines with their times, photos and voice notes, readers' notes under them, labels.",
                        "inputSchema": ["type": "object", "properties": ["since": since, "label": label]]]
            case .listLines:
                return ["name": rawValue,
                        "description": "One line per entry with its id, day, time, text, and labels. Use the id with add_note and set_label.",
                        "inputSchema": ["type": "object", "properties": ["since": since, "label": label]]]
            case .addNote:
                return ["name": rawValue,
                        "description": "Add a short note under a line, in this grant's ink. Only when something was done about the line.",
                        "inputSchema": ["type": "object", "properties": ["entry": entry, "text": ["type": "string"]], "required": ["entry", "text"]]]
            case .setLabel:
                return ["name": rawValue,
                        "description": "File a line under a label, or take the label off with on=false. Labels are lower-case words.",
                        "inputSchema": ["type": "object",
                                        "properties": ["entry": entry, "label": ["type": "string"], "on": ["type": "boolean", "default": true]],
                                        "required": ["entry", "label"]]]
            }
        }
    }

    public enum Failure: Error, CustomStringConvertible {
        case notAllowed(String)
        case noSuchLine(String)
        case missing(String)
        case unknownTool(String)
        case badDay(String)

        public var description: String {
            switch self {
            case .notAllowed(let what): "This grant may not \(what)."
            case .noSuchLine(let id): "No line with id \(id)."
            case .missing(let field): "Missing \(field)."
            case .unknownTool(let name): "No tool named \(name)."
            case .badDay(let text): "Not a day: \(text). Use YYYY-MM-DD."
            }
        }
    }

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
        return [
            "protocolVersion": version,
            "capabilities": ["tools": [:]],
            "serverInfo": ["name": Self.serverName, "version": Self.serverVersion],
            "instructions": "This is \(grant.name)'s door into one person's notebook. Read with read_days or list_lines. Write only notes and labels, only about lines you acted on, in the ink of \(grant.author).",
        ]
    }

    private func call(_ params: [String: Any]) -> [String: Any] {
        let name = params["name"] as? String ?? ""
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        do {
            let text = try run(name, arguments)
            return ["content": [["type": "text", "text": text]]]
        } catch {
            return ["content": [["type": "text", "text": "\(error)"]], "isError": true]
        }
    }

    // MARK: - Tools

    public func run(_ name: String, _ arguments: [String: Any]) throws -> String {
        guard let tool = Tool(rawValue: name) else { throw Failure.unknownTool(name) }
        let notebook = try store.load()

        switch tool {
        case .readDays:
            let days = try select(notebook, arguments)
            if days.isEmpty { return "No lines." }
            return days.map { Projector.markdown(for: $0, calendar: calendar) }.joined(separator: "\n")

        case .listLines:
            let days = try select(notebook, arguments)
            if days.isEmpty { return "No lines." }
            var lines: [String] = []
            for day in days {
                for entry in day.entries {
                    var text = entry.text.replacingOccurrences(of: "\n", with: " ")
                    if text.count > 120 { text = String(text.prefix(119)) + "…" }
                    var tail: [String] = []
                    if !entry.media.isEmpty { tail.append("[\(entry.media.count) media]") }
                    if !entry.notes.isEmpty { tail.append("[\(entry.notes.count) notes]") }
                    tail.append(contentsOf: entry.labels.map { "#\($0)" })
                    lines.append("\(entry.id)  \(day.key) \(Projector.time(entry.startedAt, calendar: calendar))  \(text)\(tail.isEmpty ? "" : "  " + tail.joined(separator: " "))")
                }
            }
            return lines.joined(separator: "\n")

        case .addNote:
            guard grant.writesNotes else { throw Failure.notAllowed("write notes") }
            let entry = try line(arguments, in: notebook)
            guard let text = (arguments["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                throw Failure.missing("text")
            }
            let now = Date()
            let id = generator.next(at: now)
            try store.append(Event(id: id, author: grant.author, device: grant.device, at: now,
                                   payload: .noteAdd(.init(entry: entry, note: id, text: text))))
            return "Noted under \(entry) as \(grant.author)."

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
            try store.append(Event(id: generator.next(at: now), author: grant.author, device: grant.device, at: now, payload: payload))
            return "\(on ? "Filed" : "Unfiled") \(entry) \(on ? "under" : "from") #\(label)."
        }
    }

    private func select(_ notebook: Notebook, _ arguments: [String: Any]) throws -> [Day] {
        var days = (arguments["label"] as? String).map { notebook.days(labelled: $0, calendar: calendar) }
            ?? notebook.days(calendar: calendar)
        if let sinceText = arguments["since"] as? String {
            let parts = sinceText.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { throw Failure.badDay(sinceText) }
            let since = DayKey(year: parts[0], month: parts[1], day: parts[2])
            days = days.filter { $0.key >= since }
        }
        return days
    }

    private func line(_ arguments: [String: Any], in notebook: Notebook) throws -> ULID {
        guard let raw = arguments["entry"] as? String else { throw Failure.missing("entry") }
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

    public init(path: String = "/mcp", calendar: Calendar, resolve: @escaping @Sendable (String) -> (FileStore, Grant)?) {
        self.path = path
        self.calendar = calendar
        self.resolve = resolve
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
        let door = Door(store: store, grant: grant, calendar: calendar)
        if let body = door.handle(request.body) {
            return HTTPResponse(status: 200, json: body)
        }
        return HTTPResponse(status: 202, text: "")
    }
}
