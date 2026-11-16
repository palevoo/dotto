import Foundation

// A loop's runs: its status while it is on, and the record of each run, step by step, so
// the owner can see exactly what it did. Kept in Core so the record is under test and any
// app can read it.

/// One thing that happened inside a run: a tool the session called, what came back, words
/// it said, the end.
public struct RunStep: Codable, Sendable, Hashable {
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

/// One run of a loop, as it unfolds. Built from the session's own stream, line by line.
public struct RunRecord: Codable, Sendable, Identifiable, Hashable {
    public let id: ULID
    /// The loop this run was of.
    public let loop: ULID
    public let startedAt: Date
    /// Set once, by the stream's result or by `fail`. Two fields on disk; `outcome` is how
    /// they are read.
    public private(set) var endedAt: Date?
    public private(set) var ok: Bool?
    public private(set) var summary: String
    public private(set) var turns: Int?
    public private(set) var costUSD: Double?
    public private(set) var model: String?
    public private(set) var steps: [RunStep]

    public init(id: ULID = ULID(), loop: ULID, startedAt: Date = Date()) {
        self.id = id
        self.loop = loop
        self.startedAt = startedAt
        self.summary = ""
        self.steps = []
    }

    /// How the run stands: still going, done with what it said, or failed with why.
    public enum Outcome: Equatable, Sendable {
        case running
        case done(String)
        case failed(String)
    }

    public var outcome: Outcome {
        guard endedAt != nil else { return .running }
        return ok == true ? .done(summary) : .failed(summary)
    }

    public var isRunning: Bool { outcome == .running }

    /// The door's tools the run called, by name, in order.
    public var calls: [String] {
        steps.map(\.what).filter { !["started", "got", "said", "ended"].contains($0) }
    }

    /// Reads one line of the session's stream and records what it says. Lines it does not
    /// understand are ignored, and so is anything after the end.
    public mutating func absorb(_ line: String, at now: Date) {
        guard isRunning,
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return }
        switch type {
        case "system":
            guard object["subtype"] as? String == "init" else { return }
            let model = object["model"] as? String
            self.model = model
            steps.append(RunStep(at: now, what: "started", detail: model ?? ""))
        case "assistant":
            for item in Self.content(of: object) {
                switch item["type"] as? String {
                case "tool_use":
                    let name = (item["name"] as? String ?? "?")
                        .replacingOccurrences(of: "mcp__dotto__", with: "")
                    steps.append(RunStep(at: now, what: name, detail: Self.compact(item["input"])))
                case "text":
                    let text = (item["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { steps.append(RunStep(at: now, what: "said", detail: Self.clip(text))) }
                default:
                    break
                }
            }
        case "user":
            for item in Self.content(of: object) where item["type"] as? String == "tool_result" {
                steps.append(RunStep(at: now, what: "got", detail: Self.clip(Self.text(of: item["content"]))))
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
            steps.append(RunStep(at: now, what: "ended", detail: summary))
        default:
            break
        }
    }

    /// The run ended without the stream saying so: the process died or said nothing usable.
    /// A run already ended keeps its ending.
    public mutating func fail(_ why: String, at now: Date) {
        guard isRunning else { return }
        endedAt = now
        ok = false
        summary = why
        steps.append(RunStep(at: now, what: "ended", detail: why))
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

/// The one machine behind a running loop, as a value: what phase it is in and what each
/// thing that can happen to it means in that phase. The runner on the Mac only carries out
/// the steps this hands back; it decides nothing itself, so the decisions are under test.
///
///     idle ── woke ──▶ waking ── looked(found) ──▶ running(again: false)
///      ▲                 │  looked(nothing)            │ woke / forced: again = true
///      └─────────────────┘◀──── finished ──────────────┘  (again: look once more)
///
/// A run is started for what was waiting, and remembers it. A look that finds only what
/// the last run was already started for starts nothing: that run did not take it, offline,
/// logged out, refused, and running again for the same thing would only fail again, each
/// time with a receipt that wakes the loop once more. The loop runs again when something
/// new lands, and takes the old with it then.
public struct LoopMachine: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Nothing pending.
        case idle
        /// Something landed; a look is scheduled after the grace.
        case waking
        /// A session is under way. `again` is owed when something landed, or a look was
        /// forced, while it ran.
        case running(again: Bool)
    }

    /// What the runner should do now.
    public enum Step: Equatable, Sendable {
        case nothing
        /// Schedule a look after the grace, cancelling any look already scheduled.
        case scheduleLook
        /// Start a session.
        case startRun
        /// The run is over and something was owed: look once more.
        case lookAgain
    }

    public private(set) var phase: Phase = .idle
    /// What was waiting when the last run began, by event id.
    public private(set) var offered: Set<ULID> = []

    public init() {}

    /// A run begins, whatever started it, for these waiting things.
    public mutating func began(with waiting: Set<ULID>) {
        offered = waiting
    }

    /// The grace passed and the look was taken: these are waiting. A run starts when any of
    /// them is one the last run was not started for.
    public mutating func looked(waiting: Set<ULID>) -> Step {
        looked(found: !waiting.isSubset(of: offered))
    }

    /// Something landed in the folder.
    public mutating func woke() -> Step {
        switch phase {
        case .idle, .waking:
            phase = .waking
            return .scheduleLook
        case .running:
            phase = .running(again: true)
            return .nothing
        }
    }

    /// The grace passed and the look was taken: `found` says whether there was anything to do.
    public mutating func looked(found: Bool) -> Step {
        guard case .waking = phase else { return .nothing }
        if found {
            phase = .running(again: false)
            return .startRun
        }
        phase = .idle
        return .nothing
    }

    /// A look was asked for now, by the clock or by hand: it runs whatever is new.
    public mutating func forced() -> Step {
        switch phase {
        case .running:
            phase = .running(again: true)
            return .nothing
        case .idle, .waking:
            phase = .running(again: false)
            return .startRun
        }
    }

    /// The session ended.
    public mutating func finished() -> Step {
        guard case .running(let again) = phase else { return .nothing }
        phase = .idle
        return again ? .lookAgain : .nothing
    }

    public var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }
}

/// What a loop is doing: waiting or running, and what stands in its way.
public struct LoopStatus: Sendable {
    public enum State: Sendable {
        case waiting, running
    }

    public struct Wake: Sendable, Hashable {
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

    public var startedAt: Date
    public var state: State
    public var lastWake: Wake?
    /// For a loop woken by the clock: when it next fires.
    public var nextWake: Date?
    public var lastRun: RunRecord?
    /// What stands in the way, if anything: no config, no claude command, a notebook that would not open.
    public var trouble: String?

    public init(startedAt: Date, state: State = .waiting) {
        self.startedAt = startedAt
        self.state = state
    }
}

/// Where runs are kept, beside the Mac app's grants: a log, and a folder of records.
public enum RunFiles {
    public static let log = "loops.log"
    public static let runs = "loop-runs"

    /// How many runs' records are kept. Each is every step of a session, photos read
    /// included, outside the notebook folder; the receipts in the notebook are kept for good.
    public static let kept = 200

    /// Removes the records of all but the newest runs. Names begin with the run's id, which
    /// sorts by time.
    public static func prune(_ directory: URL, keeping limit: Int = kept) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let runs = Set(names.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }).sorted(by: >)
        for run in runs.dropFirst(limit) {
            for file in ["\(run).json", "\(run).jsonl"] {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
            }
        }
    }

    /// The runs kept in a folder, newest first, at most `limit`.
    public static func runs(in directory: URL, limit: Int = 8) -> [RunRecord] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted(by: >).prefix(limit).compactMap { name in
            (try? Data(contentsOf: directory.appendingPathComponent(name))).flatMap { try? JSONLines.decoder().decode(RunRecord.self, from: $0) }
        }
    }
}
