import Core
import Foundation

// The reader: the author that wakes on its own.
//
// A login agent the Mac app registers, kept alive by launchd, outside the app's sandbox so
// it can run the Claude Code command the person already pays for. It watches the notebook's
// events folder and, when something lands that its grant has not seen, runs one headless
// session through the door, then goes back to waiting. The session has the door as its only
// server and no built-in tools at all; its brief is the door's conduct.
//
// Everything it does is written down as it happens: its status (alive, woken, running) in
// one file, each run step by step in a file of its own with the raw stream beside it, and a
// plain log. The Mac window reads those. Every read and write it makes through the door is
// in Logs like any other hand's.

enum Paths {
    static let support = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/social.interface.margin.mac/Data/Library/Application Support/Margin", isDirectory: true)
    static let config = support.appendingPathComponent(ReaderFiles.config)
    static let status = support.appendingPathComponent(ReaderFiles.status)
    static let log = support.appendingPathComponent(ReaderFiles.log)
    static let runs = support.appendingPathComponent(ReaderFiles.runs, isDirectory: true)
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

@MainActor
final class Reader {
    private var config: ReaderConfig?
    private var status: ReaderStatus
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
        status = ReaderStatus(pid: ProcessInfo.processInfo.processIdentifier, startedAt: Date(), build: Build.commit)
        if claude == nil { status.trouble = "the claude command was not found on this Mac" }
        Log.line("reader started, build \(Build.commit ?? "dev"), pid \(status.pid), claude at \(claude ?? "nowhere")")
        try? FileManager.default.createDirectory(at: Paths.runs, withIntermediateDirectories: true)
        // The config file may not exist yet, or may be replaced; the folder it lives in says when.
        supportWatcher = PathWatcher(path: Paths.support.path) { [weak self] in self?.loadConfig() }
        loadConfig()
        save()
    }

    /// The command, wherever the person's shell keeps it. launchd gives agents no PATH to speak of.
    private static func findClaude() -> String? {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-l", "-c", "command -v claude"]
        let pipe = Pipe()
        shell.standardOutput = pipe
        shell.standardError = FileHandle.nullDevice
        if (try? shell.run()) != nil {
            shell.waitUntilExit()
            let found = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !found.isEmpty, FileManager.default.isExecutableFile(atPath: found) { return found }
        }
        for candidate in ["~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"] {
            let path = NSString(string: candidate).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    private func save() {
        let encoder = JSONLines.encoder()
        encoder.outputFormatting.insert(.prettyPrinted)
        try? encoder.encode(status).write(to: Paths.status, options: .atomic)
    }

    private func loadConfig() {
        let loaded = (try? Data(contentsOf: Paths.config)).flatMap { try? JSONLines.decoder().decode(ReaderConfig.self, from: $0) }
        guard let loaded else {
            if config != nil { Log.line("config gone; waiting") }
            config = nil
            folderWatcher = nil
            configWatcher = nil
            status.trouble = claude == nil ? "the claude command was not found on this Mac" : "not switched on"
            save()
            return
        }
        let changed = loaded.folder != config?.folder
        config = loaded
        if claude != nil { status.trouble = nil }
        configWatcher = PathWatcher(path: Paths.config.path) { [weak self] in self?.loadConfig() }
        if changed || folderWatcher == nil {
            let events = URL(fileURLWithPath: loaded.folder).appendingPathComponent("events", isDirectory: true)
            folderWatcher = FolderWatcher(directory: events) { [weak self] in self?.runSoon() }
            Log.line("watching \(events.path) as \(loaded.grant.name)")
        }
        save()
        // A new or rewritten config is the Mac app saying: look now.
        runSoon()
    }

    private func runSoon() {
        pendingRun?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.wake() }
        pendingRun = item
        DispatchQueue.main.asyncAfter(deadline: .now() + grace, execute: item)
    }

    /// Something changed. Is there anything this grant has not seen?
    private func wake() {
        guard let config else { return }
        if running { runAgain = true; return }
        let now = Date()
        do {
            let store = try FileStore.open(URL(fileURLWithPath: config.folder))
            let files = try store.loadEventsByFile()
            let notebook = Notebook(owner: store.manifest.owner, events: files.flatMap(\.events))
            let pending = Core.Inbox.pending(files: files, notebook: notebook, grant: config.grant, calendar: calendar)
            let willRun = pending.count > 0 && claude != nil
            status.lastWake = ReaderStatus.Wake(at: now, new: pending.count, ran: willRun)
            Log.line(willRun ? "woke: \(pending.count) new, running" : "woke: \(pending.count) new")
            guard willRun, let claude else { save(); return }

            let name = notebook.name(of: config.grant.author)
            let owner = notebook.name(of: store.manifest.owner)
            let brief = Door.conduct(for: config.grant, name: name, owner: owner) + """


            You are running on your own, woken because something landed in the notebook. Nobody \
            is at the keyboard and nobody reads your final answer: everything you have to say goes \
            through the door, or stays unsaid. Do what this moment asks, and stop.
            """
            running = true
            status.state = .running
            let run = ReaderRun(startedAt: now)
            status.lastRun = run
            save()
            Task.detached(priority: .utility) { [config, brief] in
                let finished = Session.run(run, claude: claude, config: config, brief: brief) { snapshot in
                    Task { @MainActor in self.progress(snapshot) }
                }
                await MainActor.run { self.finish(finished) }
            }
        } catch {
            status.lastWake = ReaderStatus.Wake(at: now, new: 0, ran: false)
            status.trouble = "could not read the notebook: \(error)"
            Log.line("woke: \(status.trouble!)")
            save()
        }
    }

    private func progress(_ run: ReaderRun) {
        status.lastRun = run
        save()
    }

    private func finish(_ run: ReaderRun) {
        running = false
        status.state = .waiting
        status.lastRun = run
        save()
        Log.line("\(run.ok == true ? "done" : "failed"): \(run.summary) · \(run.turns ?? 0) turns · $\(String(format: "%.2f", run.costUSD ?? 0))")
        if runAgain {
            runAgain = false
            runSoon()
        }
    }
}

/// One headless session: the door as the only server, no built-in tools, no settings, no
/// project, nothing kept afterwards. Its stream is read line by line into the run as it goes,
/// so the window can follow, and kept whole beside it.
enum Session {
    static func run(_ start: ReaderRun, claude: String, config: ReaderConfig, brief: String, progress: @escaping @Sendable (ReaderRun) -> Void) -> ReaderRun {
        var run = start
        let runFile = Paths.runs.appendingPathComponent("\(run.id.string).json")
        let streamFile = Paths.runs.appendingPathComponent("\(run.id.string).jsonl")
        func write(_ run: ReaderRun) {
            let encoder = JSONLines.encoder()
            encoder.outputFormatting.insert(.prettyPrinted)
            try? encoder.encode(run).write(to: runFile, options: .atomic)
            progress(run)
        }
        write(run)

        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("margin-reader-\(run.id.string)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let servers: [String: Any] = ["mcpServers": ["margin": [
            "type": "http", "url": config.door, "headers": ["Authorization": "Bearer \(config.grant.key)"],
        ]]]
        let mcpConfig = workDir.appendingPathComponent("door.json")
        guard let json = try? JSONSerialization.data(withJSONObject: servers), (try? json.write(to: mcpConfig)) != nil else {
            run.fail("could not write the door config", at: Date())
            write(run)
            return run
        }

        var arguments = [
            "-p", "Look at what is new through the door and do what the lines want. Then stop.",
            "--output-format", "stream-json", "--verbose",
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
            run.fail("could not start claude: \(error)", at: Date())
            write(run)
            return run
        }

        // Each line of the stream as it arrives: into the run, and whole into the stream file.
        FileManager.default.createFile(atPath: streamFile.path, contents: nil)
        let stream = try? FileHandle(forWritingTo: streamFile)
        var rest = Data()
        let reading = out.fileHandleForReading
        while true {
            let chunk = reading.availableData
            if chunk.isEmpty { break }
            rest.append(chunk)
            while let newline = rest.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = rest[rest.startIndex..<newline]
                rest.removeSubrange(rest.startIndex...newline)
                guard let line = String(data: lineData, encoding: .utf8), !line.isEmpty else { continue }
                try? stream?.write(contentsOf: Data((line + "\n").utf8))
                run.absorb(line, at: Date())
                write(run)
            }
        }
        if !rest.isEmpty, let line = String(data: rest, encoding: .utf8) {
            try? stream?.write(contentsOf: Data((line + "\n").utf8))
            run.absorb(line, at: Date())
        }
        try? stream?.close()
        let errors = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        if run.isRunning {
            let said = errors.trimmingCharacters(in: .whitespacesAndNewlines)
            run.fail(said.isEmpty ? "claude exited \(process.terminationStatus) without a result" : String(said.prefix(300)), at: Date())
        }
        write(run)
        return run
    }
}

try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
let reader = MainActor.assumeIsolated { Reader() }
withExtendedLifetime(reader) { dispatchMain() }
