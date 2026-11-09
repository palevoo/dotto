import Foundation

// The reader, the author that wakes on its own: its status while on, and the record of each
// run, step by step, so the owner can see exactly what it did. Kept in Core so the record is
// under test and any app can read it.

/// One thing that happened inside a run: a tool the session called, what came back, words
/// it said, the end.
public struct ReaderStep: Codable, Sendable, Hashable {
    public var at: Date
    /// "started", the door tool's name, "got", "said", "ended".
    public var what: String
    public var detail: String

    public init(at: Date, what: String, detail: String) {
        self.at = at
        self.what = what
        self.detail = detail
    }
}

/// One run of the reader, as it unfolds. Built from the session's own stream, line by line.
public struct ReaderRun: Codable, Sendable, Identifiable, Hashable {
    public var id: ULID
    public var startedAt: Date
    public var endedAt: Date?
    /// Nil while running.
    public var ok: Bool?
    public var summary: String
    public var turns: Int?
    public var costUSD: Double?
    public var model: String?
    public var steps: [ReaderStep]

    public init(id: ULID = ULID(), startedAt: Date = Date()) {
        self.id = id
        self.startedAt = startedAt
        self.summary = ""
        self.steps = []
    }

    public var isRunning: Bool { endedAt == nil }

    /// The door's tools the run called, by name, in order.
    public var calls: [String] {
        steps.map(\.what).filter { !["started", "got", "said", "ended"].contains($0) }
    }

    /// Reads one line of the session's stream and records what it says. Lines it does not
    /// understand are ignored.
    public mutating func absorb(_ line: String, at now: Date) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return }
        switch type {
        case "system":
            guard object["subtype"] as? String == "init" else { return }
            let model = object["model"] as? String
            self.model = model
            steps.append(ReaderStep(at: now, what: "started", detail: model ?? ""))
        case "assistant":
            for item in Self.content(of: object) {
                switch item["type"] as? String {
                case "tool_use":
                    let name = (item["name"] as? String ?? "?")
                        .replacingOccurrences(of: "mcp__dotto__", with: "")
                        .replacingOccurrences(of: "mcp__margin__", with: "")
                    steps.append(ReaderStep(at: now, what: name, detail: Self.compact(item["input"])))
                case "text":
                    let text = (item["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { steps.append(ReaderStep(at: now, what: "said", detail: Self.clip(text))) }
                default:
                    break
                }
            }
        case "user":
            for item in Self.content(of: object) where item["type"] as? String == "tool_result" {
                steps.append(ReaderStep(at: now, what: "got", detail: Self.clip(Self.text(of: item["content"]))))
            }
        case "result":
            endedAt = now
            turns = object["num_turns"] as? Int
            costUSD = object["total_cost_usd"] as? Double
            let failed = object["is_error"] as? Bool ?? false
            ok = !failed
            let problems = (object["errors"] as? [String])?.joined(separator: "; ") ?? ""
            let said = (object["result"] as? String ?? "").replacingOccurrences(of: "\n", with: " ")
            summary = failed ? (problems.isEmpty ? Self.clip(said) : problems) : (said.isEmpty ? "ran" : Self.clip(said))
            steps.append(ReaderStep(at: now, what: "ended", detail: summary))
        default:
            break
        }
    }

    /// The run ended without the stream saying so: the process died or said nothing usable.
    public mutating func fail(_ why: String, at now: Date) {
        endedAt = now
        ok = false
        summary = why
        steps.append(ReaderStep(at: now, what: "ended", detail: why))
    }

    private static func content(of object: [String: Any]) -> [[String: Any]] {
        guard let message = object["message"] as? [String: Any] else { return [] }
        if let items = message["content"] as? [[String: Any]] { return items }
        if let text = message["content"] as? String { return [["type": "text", "text": text]] }
        return []
    }

    private static func text(of content: Any?) -> String {
        if let text = content as? String { return text }
        if let items = content as? [[String: Any]] {
            return items.compactMap { $0["text"] as? String }.joined(separator: " ")
        }
        return ""
    }

    /// A tool's input as one short line: `entry: 01M…, text: "When roots show"`.
    private static func compact(_ input: Any?) -> String {
        guard let input = input as? [String: Any], !input.isEmpty else { return "" }
        let parts = input.keys.sorted().map { key -> String in
            let value = input[key]
            let shown: String
            if let text = value as? String { shown = "\u{201C}\(text)\u{201D}" }
            else if let value { shown = "\(value)" } else { shown = "" }
            return "\(key): \(shown)"
        }
        return clip(parts.joined(separator: ", "))
    }

    private static func clip(_ text: String, _ limit: Int = 160) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > limit ? String(flat.prefix(limit - 1)) + "…" : flat
    }
}

/// What the reader is doing: waiting, woken, running, and what stands in its way.
public struct ReaderStatus: Codable, Sendable {
    public enum State: String, Codable, Sendable {
        case waiting, running
    }

    public struct Wake: Codable, Sendable, Hashable {
        public var at: Date
        /// How many new things the grant had not seen.
        public var new: Int
        public var ran: Bool

        public init(at: Date, new: Int, ran: Bool) {
            self.at = at
            self.new = new
            self.ran = ran
        }
    }

    public var pid: Int32
    public var startedAt: Date
    public var build: String?
    public var state: State
    public var lastWake: Wake?
    public var lastRun: ReaderRun?
    /// What stands in the way, if anything: no config, no claude command, a notebook that would not open.
    public var trouble: String?

    public init(pid: Int32, startedAt: Date, build: String?, state: State = .waiting) {
        self.pid = pid
        self.startedAt = startedAt
        self.build = build
        self.state = state
    }
}

/// The reader's files, beside the Mac app's grants: a log, and a folder of runs.
public enum ReaderFiles {
    public static let log = "reader.log"
    public static let runs = "reader-runs"

    /// The runs kept in a folder, newest first, at most `limit`.
    public static func runs(in directory: URL, limit: Int = 8) -> [ReaderRun] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted(by: >).prefix(limit).compactMap { name in
            (try? Data(contentsOf: directory.appendingPathComponent(name))).flatMap { try? JSONLines.decoder().decode(ReaderRun.self, from: $0) }
        }
    }
}
