import Core
import Foundation

// The reader: the author that wakes on its own.
//
// A login agent the Mac app registers, kept alive by launchd, outside the app's sandbox so
// it can run the Claude Code command the person already pays for. It watches the notebook's
// events folder and, when something lands that its grant has not seen, runs one headless
// session through the door, then goes back to waiting. The session has the door as its only
// server and no built-in tools at all; its brief is the door's conduct. Each run leaves one
// line in a status file the Mac window shows, and every read and write it makes is in Logs
// through the door like any other hand.

/// What the Mac app writes for the reader: where the notebook is, how to reach the door, and
/// the grant it acts under. Removing the file stops the reader.
struct ReaderConfig: Codable {
    var folder: String
    var door: String
    var grant: Grant
    var model: String?
    var maxTurns: Int
    var maxBudgetUSD: Double
}

/// One line about the last run, for the Mac window.
struct ReaderStatus: Codable {
    var at: Date
    var ok: Bool
    var summary: String
    var turns: Int?
    var costUSD: Double?
    var durationMs: Int?
}

enum Paths {
    static let support = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/social.interface.margin.mac/Data/Library/Application Support/Margin", isDirectory: true)
    static let config = support.appendingPathComponent("reader.json")
    static let status = support.appendingPathComponent("reader-status.json")
    static let log = support.appendingPathComponent("reader.log")
}

enum Log {
    static func line(_ text: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\(stamp) \(text)\n"
        if let handle = try? FileHandle(forWritingTo: Paths.log) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(entry.utf8))
        } else {
            try? Data(entry.utf8).write(to: Paths.log)
        }
        FileHandle.standardError.write(Data(entry.utf8))
    }
}

/// Watches one path, a file or a directory, for any change. Calls back on the main queue.
final class PathWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let path: String
    private let onChange: () -> Void

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
        arm()
    }

    private func arm() {
        source?.cancel()
        source = nil
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .extend, .rename, .delete, .attrib], queue: .main)
        source.setEventHandler { [weak self] in
            self?.arm()
            self?.onChange()
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }
}

@MainActor
final class Reader {
    private var config: ReaderConfig?
    private var folderWatcher: FolderWatcher?
    private var configWatcher: PathWatcher?
    private var supportWatcher: PathWatcher?
    private var pendingRun: DispatchWorkItem?
    private var running = false
    private var runAgain = false
    private let calendar = Calendar.current
    private let claude: String?
    /// A line and its photo land a moment apart; one run takes both.
    private let grace: TimeInterval = 5

    init() {
        claude = Self.findClaude()
        Log.line("reader started, build \(Build.commit ?? "dev"), claude at \(claude ?? "nowhere")")
        // The config file may not exist yet, or may be replaced; the folder it lives in says when.
        supportWatcher = PathWatcher(path: Paths.support.path) { [weak self] in self?.loadConfig() }
        loadConfig()
    }

    /// The command, wherever the person's shell keeps it. launchd gives agents no PATH to speak of.
    private static func findClaude() -> String? {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-l", "-c", "command -v claude"]
        let pipe = Pipe()
        shell.standardOutput = pipe
        shell.standardError = FileHandle.nullDevice
        guard (try? shell.run()) != nil else { return nil }
        shell.waitUntilExit()
        let found = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !found.isEmpty { return found }
        for candidate in ["~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"] {
            let path = NSString(string: candidate).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    private func loadConfig() {
        let loaded = (try? Data(contentsOf: Paths.config)).flatMap { try? JSONLines.decoder().decode(ReaderConfig.self, from: $0) }
        guard let loaded else {
            if config != nil { Log.line("config gone; waiting") }
            config = nil
            folderWatcher = nil
            configWatcher = nil
            return
        }
        let changed = loaded.folder != config?.folder
        config = loaded
        configWatcher = PathWatcher(path: Paths.config.path) { [weak self] in self?.loadConfig() }
        if changed || folderWatcher == nil {
            let events = URL(fileURLWithPath: loaded.folder).appendingPathComponent("events", isDirectory: true)
            folderWatcher = FolderWatcher(directory: events) { [weak self] in self?.runSoon() }
            Log.line("watching \(events.path) as \(loaded.grant.name)")
        }
        // A new or rewritten config is the Mac app saying: the door is open, look again.
        runSoon()
    }

    private func runSoon() {
        pendingRun?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.run() }
        pendingRun = item
        DispatchQueue.main.asyncAfter(deadline: .now() + grace, execute: item)
    }

    private func run() {
        guard let config else { return }
        if running { runAgain = true; return }
        do {
            let store = try FileStore.open(URL(fileURLWithPath: config.folder))
            let files = try store.loadEventsByFile()
            let notebook = Notebook(owner: store.manifest.owner, events: files.flatMap(\.events))
            let pending = Core.Inbox.pending(files: files, notebook: notebook, grant: config.grant, calendar: calendar)
            guard pending.count > 0 else { return }
            guard let claude else {
                record(ReaderStatus(at: Date(), ok: false, summary: "claude command not found on this Mac"))
                return
            }
            Log.line("\(pending.count) new; running")
            running = true
            let name = notebook.name(of: config.grant.author)
            let owner = notebook.name(of: store.manifest.owner)
            let brief = Door.conduct(for: config.grant, name: name, owner: owner) + """


            You are running on your own, woken because something landed in the notebook. Nobody \
            is at the keyboard and nobody reads your final answer: everything you have to say goes \
            through the door, or stays unsaid. Do what this moment asks, and stop.
            """
            Task.detached(priority: .utility) { [config, brief] in
                let status = Self.session(claude: claude, config: config, brief: brief)
                await MainActor.run { self.finish(status) }
            }
        } catch {
            record(ReaderStatus(at: Date(), ok: false, summary: "could not read the notebook: \(error)"))
        }
    }

    private func finish(_ status: ReaderStatus) {
        running = false
        record(status)
        if runAgain {
            runAgain = false
            runSoon()
        }
    }

    private func record(_ status: ReaderStatus) {
        Log.line(status.ok ? "done: \(status.summary)" : "failed: \(status.summary)")
        let encoder = JSONLines.encoder()
        encoder.outputFormatting.insert(.prettyPrinted)
        try? encoder.encode(status).write(to: Paths.status, options: .atomic)
    }

    /// One headless session: the door as the only server, no built-in tools, no settings, no
    /// project, nothing kept afterwards. Returns what happened in one line.
    nonisolated private static func session(claude: String, config: ReaderConfig, brief: String) -> ReaderStatus {
        let started = Date()
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("margin-reader-\(ULID().string)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let servers: [String: Any] = ["mcpServers": ["margin": [
            "type": "http", "url": config.door, "headers": ["Authorization": "Bearer \(config.grant.key)"],
        ]]]
        let mcpConfig = workDir.appendingPathComponent("door.json")
        guard let json = try? JSONSerialization.data(withJSONObject: servers), (try? json.write(to: mcpConfig)) != nil else {
            return ReaderStatus(at: started, ok: false, summary: "could not write the door config")
        }

        var arguments = [
            "-p", "Look at what is new through the door and do what the lines want. Then stop.",
            "--output-format", "json",
            "--mcp-config", mcpConfig.path,
            "--strict-mcp-config",
            "--tools", "",
            "--allowedTools", "mcp__margin",
            "--system-prompt", brief,
            "--setting-sources", "",
            "--disable-slash-commands",
            "--no-session-persistence",
            "--max-turns", String(config.maxTurns),
            "--max-budget-usd", String(config.maxBudgetUSD),
        ]
        if let model = config.model, !model.isEmpty { arguments += ["--model", model] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claude)
        process.arguments = arguments
        process.currentDirectoryURL = workDir
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do { try process.run() } catch {
            return ReaderStatus(at: started, ok: false, summary: "could not start claude: \(error)")
        }
        let output = out.fileHandleForReading.readDataToEndOfFile()
        let errors = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        let ms = Int(Date().timeIntervalSince(started) * 1000)

        guard let result = try? JSONSerialization.jsonObject(with: output) as? [String: Any] else {
            let said = errors.trimmingCharacters(in: .whitespacesAndNewlines)
            return ReaderStatus(at: started, ok: false, summary: said.isEmpty ? "claude exited \(process.terminationStatus) with no result" : String(said.prefix(300)), durationMs: ms)
        }
        let turns = result["num_turns"] as? Int
        let cost = result["total_cost_usd"] as? Double
        let isError = result["is_error"] as? Bool ?? false
        let text = (result["result"] as? String ?? "").replacingOccurrences(of: "\n", with: " ")
        let problems = (result["errors"] as? [String])?.joined(separator: "; ") ?? ""
        let summary = isError ? (problems.isEmpty ? String(text.prefix(300)) : problems) : (text.isEmpty ? "ran" : String(text.prefix(300)))
        return ReaderStatus(at: started, ok: !isError, summary: summary, turns: turns, costUSD: cost, durationMs: ms)
    }
}

try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
let reader = MainActor.assumeIsolated { Reader() }
withExtendedLifetime(reader) { dispatchMain() }
