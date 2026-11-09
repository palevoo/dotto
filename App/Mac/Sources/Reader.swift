import Core
import Foundation

/// The reader: the author that wakes on its own, run by the Mac app itself.
///
/// The app is already open, since it is the door, and it already watches the folder. When
/// something lands that the reader's grant has not seen, this runs one headless session of
/// the claude command the person already pays for: the door as its only server, every
/// built-in tool off, no settings and no project in reach, the door's conduct as its brief,
/// a cap on turns and on spend, nothing kept afterwards. Then it waits again. Every step of
/// a run is written down as it happens, a record per run with the raw stream beside it, and
/// every read and write it makes is in Logs through the door, stamped with its device.
@MainActor
final class ReaderRunner {
    let grant: Grant
    let door: String
    let runsDirectory: URL
    let logURL: URL
    var model: String
    /// Where the claude command is, or nil when the Mac has none.
    let claude: String?
    private(set) var status: ReaderStatus
    private(set) var runs: [ReaderRun] = []
    /// Told whenever the status or a run changes, so the window follows.
    var onChange: () -> Void = {}

    private var pendingWake: DispatchWorkItem?
    private var running = false
    private var runAgain = false
    private let calendar = Calendar.current
    /// A line and its photo land a moment apart; one run takes both.
    private let grace: TimeInterval = 5
    static let maxTurns = 40
    static let maxBudgetUSD = 2.0

    init(grant: Grant, door: String, model: String, runsDirectory: URL, logURL: URL) {
        self.grant = grant
        self.door = door
        self.model = model
        self.runsDirectory = runsDirectory
        self.logURL = logURL
        claude = Self.findClaude()
        status = ReaderStatus(pid: ProcessInfo.processInfo.processIdentifier, startedAt: Date(), build: Build.commit)
        if claude == nil { status.trouble = "the claude command was not found on this Mac" }
        try? FileManager.default.createDirectory(at: runsDirectory, withIntermediateDirectories: true)
        runs = ReaderFiles.runs(in: runsDirectory)
        log("reader on as \(grant.name), claude at \(claude ?? "nowhere")")
    }

    /// The command, wherever the person's shell keeps it.
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

    private func log(_ text: String) {
        let entry = "\(ISO8601DateFormatter().string(from: Date())) \(text)\n"
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(entry.utf8))
        } else {
            try? Data(entry.utf8).write(to: logURL)
        }
    }

    /// Something changed in the folder. A moment later, see whether the grant has anything new.
    func wake(_ store: FileStore) {
        pendingWake?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.look(store) }
        pendingWake = item
        DispatchQueue.main.asyncAfter(deadline: .now() + grace, execute: item)
    }

    private func look(_ store: FileStore) {
        if running { runAgain = true; return }
        let now = Date()
        do {
            let files = try store.loadEventsByFile()
            let notebook = Notebook(owner: store.manifest.owner, events: files.flatMap(\.events))
            let pending = Core.Inbox.pending(files: files, notebook: notebook, grant: grant, calendar: calendar)
            let willRun = pending.count > 0 && claude != nil
            status.lastWake = ReaderStatus.Wake(at: now, new: pending.count, ran: willRun)
            log(willRun ? "woke: \(pending.count) new, running" : "woke: \(pending.count) new")
            guard willRun, let claude else { onChange(); return }

            let brief = Door.conduct(for: grant, name: notebook.name(of: grant.author), owner: notebook.name(of: store.manifest.owner)) + """


            You are running on your own, woken because something landed in the notebook. Nobody \
            is at the keyboard and nobody reads your final answer: everything you have to say goes \
            through the door, or stays unsaid. Do what this moment asks, and stop.
            """
            running = true
            status.state = .running
            let run = ReaderRun(startedAt: now)
            status.lastRun = run
            runs.insert(run, at: 0)
            onChange()
            let session = Session(claude: claude, door: door, grant: grant, model: model, runsDirectory: runsDirectory, brief: brief)
            Task.detached(priority: .utility) {
                let finished = session.run(run) { snapshot in
                    Task { @MainActor in self.progress(snapshot) }
                }
                await MainActor.run { self.finish(finished) }
            }
        } catch {
            status.lastWake = ReaderStatus.Wake(at: now, new: 0, ran: false)
            status.trouble = "could not read the notebook: \(error)"
            log("woke: \(status.trouble!)")
            onChange()
        }
    }

    private func progress(_ run: ReaderRun) {
        status.lastRun = run
        if let index = runs.firstIndex(where: { $0.id == run.id }) { runs[index] = run } else { runs.insert(run, at: 0) }
        onChange()
    }

    private func finish(_ run: ReaderRun) {
        running = false
        status.state = .waiting
        progress(run)
        log("\(run.ok == true ? "done" : "failed"): \(run.summary) · \(run.turns ?? 0) turns · $\(String(format: "%.2f", run.costUSD ?? 0))")
        if runAgain {
            runAgain = false
            // Whatever came in during the run; the store is re-read in look.
            if let store = lastStore { wake(store) }
        }
    }

    private var lastStore: FileStore?

    func remember(_ store: FileStore) {
        lastStore = store
    }
}

/// One headless session. Its stream is read line by line into the run as it goes, so the
/// window can follow, and kept whole beside it.
struct Session: Sendable {
    let claude: String
    let door: String
    let grant: Grant
    let model: String
    let runsDirectory: URL
    let brief: String

    func run(_ start: ReaderRun, progress: @escaping @Sendable (ReaderRun) -> Void) -> ReaderRun {
        var run = start
        let runFile = runsDirectory.appendingPathComponent("\(run.id.string).json")
        let streamFile = runsDirectory.appendingPathComponent("\(run.id.string).jsonl")
        func write(_ run: ReaderRun) {
            let encoder = JSONLines.encoder()
            encoder.outputFormatting.insert(.prettyPrinted)
            try? encoder.encode(run).write(to: runFile, options: .atomic)
            progress(run)
        }
        write(run)

        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("dotto-reader-\(run.id.string)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // The same grant as a session at the keyboard; the header says this hand is the reader.
        let servers: [String: Any] = ["mcpServers": ["dotto": [
            "type": "http", "url": door, "headers": ["Authorization": "Bearer \(grant.key)", "Dotto-Device": "reader"],
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
            "--allowedTools", "mcp__dotto",
            "--system-prompt", brief,
            "--setting-sources", "",
            "--disable-slash-commands",
            "--no-session-persistence",
            "--max-turns", String(ReaderRunner.maxTurns),
            "--max-budget-usd", String(ReaderRunner.maxBudgetUSD),
        ]
        if !model.isEmpty { arguments += ["--model", model] }

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
