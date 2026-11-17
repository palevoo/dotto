import Core
import Foundation

/// One loop, running: a sentence said once, kept in the notebook, run by the Mac app itself.
///
/// The app is already open, since it is the door, and it already watches the folder. A loop
/// woken by lines looks when something lands that its grant has not seen; a loop woken by
/// the clock looks at its hour every day. Either way it runs one headless session of the
/// claude command the person already pays for: the door as its only server, every built-in
/// tool off, no settings and no project in reach, the door's conduct and the loop's brief as
/// its whole brief, the loop's cap on turns and on spend, nothing kept afterwards. Every step
/// of a run is written down as it happens, a record per run with the raw stream beside it; a
/// receipt for the run goes into the notebook under the loop's originator, so Logs say it ran.
@MainActor
final class LoopRunner {
    let loop: Loop
    let grant: Grant
    let door: String
    let runsDirectory: URL
    let logURL: URL
    var model: String
    /// Where the claude command is, or nil when the Mac has none.
    let claude: String?
    private(set) var status: LoopStatus
    private(set) var runs: [RunRecord] = []
    /// Told whenever the status or a run changes, so the window follows.
    var onChange: () -> Void = {}
    /// Told when a run has ended, with its record, so the receipt can be written.
    var onRan: (RunRecord) -> Void = { _ in }

    /// The phase the loop is in and what each event means there. Decided in Core, under test.
    private var machine = LoopMachine()
    /// The session under way, so it can be ended: the loop stopped, the app quitting.
    private var current: RunningSession?
    private var pendingWake: DispatchWorkItem?
    private var clock: Timer?
    private let calendar = Calendar.current
    /// A line and its photo land a moment apart; one run takes both.
    private let grace: TimeInterval = 5

    init(loop: Loop, grant: Grant, door: String, model: String, runsDirectory: URL, logURL: URL) {
        self.loop = loop
        // The loop is a hand of its own: its own place in what has been seen, its own file.
        var hand = grant
        hand.device = loop.hand
        self.grant = hand
        self.door = door
        self.model = model
        self.runsDirectory = runsDirectory
        self.logURL = logURL
        claude = Self.findClaude()
        status = LoopStatus(startedAt: Date())
        if claude == nil { status.trouble = "the claude command was not found on this Mac" }
        try? FileManager.default.createDirectory(at: runsDirectory, withIntermediateDirectories: true)
        runs = RunFiles.runs(in: runsDirectory, limit: 200).filter { $0.loop == loop.id }.prefix(8).map { $0 }
        log("\(loop.name) on as \(grant.name), \(loop.wake.words), claude at \(claude ?? "nowhere")")
        if case .clock = loop.wake { scheduleClock() }
    }

    deinit {
        clock?.invalidate()
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
        let entry = "\(ISO8601DateFormatter().string(from: Date())) [\(loop.name)] \(text)\n"
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(entry.utf8))
        } else {
            try? Data(entry.utf8).write(to: logURL)
        }
    }

    private var lastStore: FileStore?

    /// The loop was stopped, set again, or the app is quitting: nothing more is scheduled
    /// and a session under way is ended, so no claude process outlives its loop.
    func stop() {
        pendingWake?.cancel()
        clock?.invalidate()
        current?.end()
        current = nil
    }

    func remember(_ store: FileStore) {
        lastStore = store
    }

    /// Something changed in the folder. A loop woken by lines looks a moment later; one woken
    /// by the clock only remembers the store for its hour.
    func wake(_ store: FileStore) {
        lastStore = store
        guard loop.wake == .line else { return }
        carry(machine.woke())
    }

    /// Looks now, whatever woke it, and runs even with nothing new.
    func lookNow() {
        carry(machine.forced())
    }

    /// Carries out what the machine asked for.
    private func carry(_ step: LoopMachine.Step) {
        switch step {
        case .nothing:
            break
        case .scheduleLook:
            pendingWake?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.lookAfterGrace() }
            pendingWake = item
            DispatchQueue.main.asyncAfter(deadline: .now() + grace, execute: item)
        case .startRun:
            if let store = lastStore { start(store) } else { carry(machine.finished()) }
        case .lookAgain:
            carry(machine.woke())
        }
    }

    /// The grace passed: is there anything new for this loop's grant?
    private func lookAfterGrace() {
        guard let store = lastStore else { carry(machine.looked(found: false)); return }
        let now = Date()
        let found: Bool
        do {
            let files = try store.loadEventsByFile()
            let notebook = Notebook(owner: store.manifest.owner, events: files.flatMap(\.events))
            let pending = Core.Inbox.pending(files: files, notebook: notebook, grant: grant, calendar: calendar)
            let waiting = Self.waiting(files: files, notebook: notebook, grant: grant)
            let able = pending.count > 0 && claude != nil
            // What the last run was started for and did not take is not run for again; the
            // machine decides, and the window says why nothing is running.
            let leftOver = able && waiting.isSubset(of: machine.offered)
            found = able && !leftOver
            status.lastWake = LoopStatus.Wake(at: now, new: pending.count, ran: found)
            if leftOver {
                status.trouble = Self.leftWaiting
                log("woke: \(pending.count) still waiting from the last run, which did not take them; not running again until something new lands")
            } else {
                log(found ? "woke: \(pending.count) new, running" : "woke: \(pending.count) new")
            }
            onChange()
            carry(able ? machine.looked(waiting: waiting) : machine.looked(found: false))
            return
        } catch {
            found = false
            status.lastWake = LoopStatus.Wake(at: now, new: 0, ran: false)
            status.trouble = "could not read the notebook: \(error)"
            log("woke: \(status.trouble!)")
        }
        onChange()
        carry(machine.looked(found: found))
    }

    /// Said in the window while the last run's things still wait.
    private static let leftWaiting = "the last run did not take what was waiting; it runs again when something new lands, or with Look Now"

    /// Everything this loop's grant has not seen, by id: what a run would be started for.
    private static func waiting(files: [(file: String, events: [Event])], notebook: Notebook, grant: Grant) -> Set<ULID> {
        Set(Core.Inbox.fresh(files: files, notebook: notebook, grant: grant).events.map(\.id))
    }

    /// The clock: the next time the loop's hour comes round, then every day after.
    private func scheduleClock() {
        guard case .clock(let hour, let minute) = loop.wake else { return }
        clock?.invalidate()
        var next = calendar.nextDate(after: Date(), matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(86_400)
        if next.timeIntervalSinceNow < 1 { next = next.addingTimeInterval(86_400) }
        status.nextWake = next
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.carry(self.machine.forced())
                self.scheduleClock()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
        onChange()
    }

    /// A session begins. The machine has already said so; this only sets it going.
    private func start(_ store: FileStore) {
        let now = Date()
        guard let claude else {
            status.lastWake = LoopStatus.Wake(at: now, new: 0, ran: false)
            onChange()
            carry(machine.finished())
            return
        }
        do {
            let files = try store.loadEventsByFile()
            let notebook = Notebook(owner: store.manifest.owner, events: files.flatMap(\.events))
            // The run is for what waits now, however it was started.
            machine.began(with: Self.waiting(files: files, notebook: notebook, grant: grant))
            if status.trouble == Self.leftWaiting { status.trouble = nil }
            if status.lastWake == nil || status.lastWake?.ran == false {
                let pending = Core.Inbox.pending(files: files, notebook: notebook, grant: grant, calendar: calendar)
                status.lastWake = LoopStatus.Wake(at: now, new: pending.count, ran: true)
                log("looking now: \(pending.count) new, running")
            }

            // The home starts this hand, so it tells it everything before its first word:
            // the conduct and what was learned, whole.
            var brief = Door.told(to: grant, in: notebook) + """


            You are running on your own, as the loop called \(loop.name), \(loop.wake.words). Nobody \
            is at the keyboard and nobody reads your final answer: everything you have to say goes \
            through the door, or stays unsaid. Do what this moment asks, and stop.
            """
            if let words = loop.brief?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty {
                // The owner set it; the words may be the owner's or a proposer's they agreed to.
                // The reading's are every sentence kept in mind, and say so themselves.
                brief += loop.wake == .line ? "\n\n\(words)" : "\n\nThe brief the owner set for this loop: \(words)"
            }
            status.state = .running
            let run = RunRecord(loop: loop.id, startedAt: now)
            status.lastRun = run
            runs.insert(run, at: 0)
            onChange()
            let session = Session(claude: claude, door: door, grant: grant, model: model, runsDirectory: runsDirectory, brief: brief,
                                  prompt: loop.wake == .line
                                      // Handed what it would otherwise go and find, so it starts at the thinking.
                                      ? "Look at what is new and do what the lines want. Then stop.\n\n"
                                          + Core.Inbox.upFront(files: files, notebook: notebook, grant: grant, store: store, calendar: calendar)
                                      : "It is \(Projector.time(now, calendar: calendar)). Do what this loop is for, reading through the door as needed. Then stop.",
                                  maxTurns: loop.turns, maxBudgetUSD: loop.budget)
            let running = RunningSession()
            current = running
            Task.detached(priority: .utility) {
                let finished = session.run(run, as: running) { snapshot in
                    Task { @MainActor in self.progress(snapshot) }
                }
                await MainActor.run { self.finish(finished) }
            }
        } catch {
            status.lastWake = LoopStatus.Wake(at: now, new: 0, ran: false)
            status.trouble = "could not read the notebook: \(error)"
            log("start: \(status.trouble!)")
            onChange()
            carry(machine.finished())
        }
    }

    private func progress(_ run: RunRecord) {
        status.lastRun = run
        if let index = runs.firstIndex(where: { $0.id == run.id }) { runs[index] = run } else { runs.insert(run, at: 0) }
        onChange()
    }

    private func finish(_ run: RunRecord) {
        current = nil
        RunFiles.prune(runsDirectory)
        status.state = .waiting
        progress(run)
        let ending: String
        switch run.outcome {
        case .done(let said): ending = "done: \(said)"
        case .failed(let why): ending = "failed: \(why)"
        case .running: ending = "still running"
        }
        log("\(ending) · \(run.turns ?? 0) turns · $\(String(format: "%.2f", run.costUSD ?? 0))")
        onRan(run)
        // Whatever landed during the run is looked at once more; the store is re-read then.
        carry(machine.finished())
    }
}

/// A session's process, reachable from outside the thread that runs it, so it can be ended
/// when its loop is stopped, the app quits, or it has run past its time.
final class RunningSession: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var why: String?

    func began(_ process: Process) {
        lock.lock()
        self.process = process
        let ended = why != nil
        lock.unlock()
        // Ended before it had begun: it ends now.
        if ended { process.terminate() }
    }

    /// Ends the session. The run's record says why.
    func end(_ reason: String = "stopped") {
        lock.lock()
        if why == nil { why = reason }
        let process = self.process
        lock.unlock()
        if process?.isRunning == true { process?.terminate() }
    }

    var reason: String? {
        lock.lock()
        defer { lock.unlock() }
        return why
    }
}

/// One headless session. Its stream is read line by line into the run as it goes, so the
/// window can follow, and kept whole beside it. It has the loop's caps on turns and spend,
/// and one on time: a session that has not ended after a quarter of an hour is ended.
struct Session: Sendable {
    static let longest: TimeInterval = 15 * 60

    let claude: String
    let door: String
    let grant: Grant
    let model: String
    let runsDirectory: URL
    let brief: String
    let prompt: String
    let maxTurns: Int
    let maxBudgetUSD: Double

    func run(_ start: RunRecord, as running: RunningSession, progress: @escaping @Sendable (RunRecord) -> Void) -> RunRecord {
        var run = start
        let runFile = runsDirectory.appendingPathComponent("\(run.id.string).json")
        let streamFile = runsDirectory.appendingPathComponent("\(run.id.string).jsonl")
        func write(_ run: RunRecord) {
            let encoder = JSONLines.encoder()
            encoder.outputFormatting.insert(.prettyPrinted)
            try? encoder.encode(run).write(to: runFile, options: .atomic)
            progress(run)
        }
        write(run)

        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("dotto-loop-\(run.id.string)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // The same key as a session at the keyboard; one header says which hand this is,
        // the other that its brief already told it what was learned, so the door does not
        // say it again with its first answer.
        let servers: [String: Any] = ["mcpServers": ["dotto": [
            "type": "http", "url": door,
            "headers": ["Authorization": "Bearer \(grant.key)", "Dotto-Device": grant.device.rawValue, "Dotto-Told": "brief"],
        ]]]
        let mcpConfig = workDir.appendingPathComponent("door.json")
        guard let json = try? JSONSerialization.data(withJSONObject: servers), (try? json.write(to: mcpConfig)) != nil else {
            run.fail("could not write the door config", at: Date())
            write(run)
            return run
        }

        var arguments = [
            "-p", prompt,
            "--output-format", "stream-json", "--verbose",
            "--mcp-config", mcpConfig.path,
            "--strict-mcp-config",
            "--tools", "",
            "--allowedTools", "mcp__dotto",
            "--system-prompt", brief,
            "--setting-sources", "",
            "--disable-slash-commands",
            "--no-session-persistence",
            "--max-turns", String(maxTurns),
            "--max-budget-usd", String(maxBudgetUSD),
        ]
        if !model.isEmpty { arguments += ["--model", model] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claude)
        process.arguments = arguments
        process.currentDirectoryURL = workDir
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        // What claude says on its error stream is taken as it comes, so a session that says
        // a lot there never stalls waiting for it to be read.
        final class Said: @unchecked Sendable {
            private let lock = NSLock()
            private var data = Data()
            func add(_ more: Data) { lock.lock(); data.append(more); lock.unlock() }
            var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
        }
        let said = Said()
        err.fileHandleForReading.readabilityHandler = { handle in
            let more = handle.availableData
            if !more.isEmpty { said.add(more) }
        }
        do { try process.run() } catch {
            err.fileHandleForReading.readabilityHandler = nil
            run.fail("could not start claude: \(error)", at: Date())
            write(run)
            return run
        }
        running.began(process)
        // The cap on time, beside the caps on turns and spend.
        let tooLong = DispatchWorkItem { running.end("ended after \(Int(Self.longest / 60)) minutes without finishing") }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.longest, execute: tooLong)
        defer { tooLong.cancel() }

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
        process.waitUntilExit()
        err.fileHandleForReading.readabilityHandler = nil

        if run.isRunning {
            let errors = said.text.trimmingCharacters(in: .whitespacesAndNewlines)
            run.fail(running.reason ?? (errors.isEmpty ? "claude exited \(process.terminationStatus) without a result" : String(errors.prefix(300))), at: Date())
        }
        write(run)
        return run
    }
}
