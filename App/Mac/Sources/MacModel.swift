import AppKit
import Core
import Foundation
import Observation

/// The Mac's state: which folder, which grants, whether the door is open, and the reader.
///
/// The app reads the folder the person picked in the open panel, remembered through a
/// bookmark, and nothing else on the disk. That is a promise the code keeps rather than one
/// macOS enforces: the app runs without the sandbox so that it can run the claude command
/// for the reader, which a sandboxed app may not.
@MainActor
@Observable
final class MacModel {
    static let defaultPort: UInt16 = 27830

    private(set) var folderURL: URL?
    private(set) var store: FileStore?
    private(set) var summary = ""
    /// The fold as last read, for the log and the words of the lines it names.
    private(set) var notebook: Notebook?
    /// What others left that may want the owner, newest first. The Mac shows it; the look
    /// that settles unread is the owner's, made on the phone.
    private(set) var inbox: [InboxItem] = []
    private(set) var grants: [Grant] = []
    private(set) var port: UInt16?
    private(set) var problem: String?
    /// The push key on this Mac, if one has been chosen.
    private(set) var pushKey: PushKey? = PushKeyStore.load()
    /// The phones the folder says can be reached.
    private(set) var pushAddresses: [PushAddress] = []
    /// What happened to the last push, in a sentence.
    private(set) var pushReport: String?
    /// The reader, while it is on: the author that wakes on its own, run by this app.
    private(set) var reader: ReaderRunner?
    /// The model the reader runs, empty for Claude Code's default.
    var readerModel = UserDefaults.standard.string(forKey: "margin.reader.model") ?? "" {
        didSet {
            UserDefaults.standard.set(readerModel, forKey: "margin.reader.model")
            reader?.model = readerModel
        }
    }
    /// Bumped whenever the reader's status or a run changes, so the window redraws.
    private(set) var readerTick = 0

    private let bookmarkKey = "margin.folder.bookmark"
    private let ownerKey = "margin.owner"
    private let readerOnKey = "margin.reader.on"
    private let shared = DoorState()
    private let pusher = Pusher()
    private var server: DoorServer?
    private var watcher: FolderWatcher?
    private var cloud: CloudWatcher?
    private var summaryTask: Task<Void, Never>?

    init() {
        loadGrants()
        restoreFolder()
        if UserDefaults.standard.bool(forKey: readerOnKey), readerGrant != nil { startReader() }
        Task {
            await pusher.use(pushKey)
            await openDoor()
        }
    }

    // MARK: - The folder

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Pick the folder that holds your notebook, or an empty one to start it here."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        adopt(url, remember: true)
    }

    private func restoreFolder() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        // A bookmark made while the app was sandboxed carries a security scope; it still resolves.
        guard let url = (try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))
            ?? (try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)) else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return
        }
        adopt(url, remember: stale)
    }

    private func adopt(_ url: URL, remember: Bool) {
        do {
            let manifest = url.appendingPathComponent(FileStore.manifestName)
            let store = FileManager.default.fileExists(atPath: manifest.path)
                ? try FileStore.open(url)
                : try FileStore.create(at: url, owner: owner)
            if remember {
                let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            }
            folderURL = url
            self.store = store
            problem = nil
            shared.update(store: store, grants: grants)
            keepFresh(store)
            refreshSummary()
        } catch {
            problem = "Could not open the notebook in \(url.lastPathComponent): \(error)"
        }
    }

    /// The folder is watched, so a line the phone writes shows here on its own. When the
    /// folder is in iCloud Drive, iCloud is asked to say when a file has a newer version,
    /// and the bytes are pulled down the moment it does.
    private func keepFresh(_ store: FileStore) {
        watcher = FolderWatcher(directory: store.eventsDirectory) { [weak self] in
            self?.refreshSummarySoon()
        }
        cloud = CloudWatcher(store: store) { [weak self] in
            self?.refreshSummarySoon()
        }
    }

    private func refreshSummarySoon() {
        summaryTask?.cancel()
        summaryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.refreshSummary()
        }
    }

    func refreshSummary() {
        guard let store, let files = try? store.loadEventsByFile() else {
            summary = ""
            self.notebook = nil
            inbox = []
            return
        }
        let notebook = Notebook(owner: store.manifest.owner, events: files.flatMap(\.events))
        self.notebook = notebook
        inbox = Core.Inbox.items(files: files, notebook: notebook, calendar: .current)
        // Something changed in the folder: the reader looks, a moment later.
        reader?.remember(store)
        reader?.wake(store)
        pushAddresses = (try? store.pushAddresses()) ?? []
        let days = notebook.days(calendar: .current)
        var text = "\(notebook.entries.count) lines over \(days.count) days"
        if let last = days.last?.key { text += " · last \(last)" }
        // Photos the door would refuse until iCloud brings them.
        if let arriving = cloud?.state?.arriving, arriving > 0 { text += " · \(arriving) media files not yet on this Mac" }
        if let trouble = cloud?.state?.trouble { text += " · iCloud: \(trouble)" }
        summary = text
    }

    /// Only used when the Mac starts a new notebook. Opening one made on the phone keeps the phone's owner.
    private var owner: Author {
        if let raw = UserDefaults.standard.string(forKey: ownerKey) { return Author(rawValue: raw) }
        let raw = "me-" + String(ULID().string.suffix(6)).lowercased()
        UserDefaults.standard.set(raw, forKey: ownerKey)
        return Author(rawValue: raw)
    }

    // MARK: - Grants

    private var grantsURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Margin", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("grants.json")
    }

    /// A new grant is a new author with a fresh id and no name; it chooses one through the
    /// door when it wants to. The grant's name travels on its events as the device, so the
    /// history under a line can say "via claude-code".
    func addGrant(name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        grants.append(Grant(name: cleanName, author: .fresh(), device: Self.device(for: cleanName)))
        saveGrants()
    }

    /// What an author is called, if they have chosen; else their id.
    func name(of author: Author) -> String {
        notebook?.name(of: author) ?? author.rawValue
    }

    func revoke(_ grant: Grant) {
        grants.removeAll { $0.id == grant.id }
        saveGrants()
    }

    /// What the person pastes into a terminal so Claude Code knows the door and the key.
    func connectCommand(for grant: Grant) -> String {
        "claude mcp add --transport http margin http://127.0.0.1:\(port ?? Self.defaultPort)/mcp --header \"Authorization: Bearer \(grant.key)\""
    }

    private func loadGrants() {
        guard let data = try? Data(contentsOf: grantsURL),
              let loaded = try? JSONLines.decoder().decode([Grant].self, from: data) else { return }
        grants = loaded.map { grant in
            // Grants made before the name travelled as the device.
            guard grant.device == "mac-door" else { return grant }
            var fixed = grant
            fixed.device = Self.device(for: grant.name)
            return fixed
        }
        if grants != loaded { saveGrants() }
    }

    static func device(for name: String) -> DeviceID {
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let joined = String(slug).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return DeviceID(rawValue: joined.isEmpty ? "door" : joined)
    }

    private func saveGrants() {
        let encoder = JSONLines.encoder()
        encoder.outputFormatting.insert(.prettyPrinted)
        do {
            try encoder.encode(grants).write(to: grantsURL, options: [.atomic, .completeFileProtection])
        } catch {
            problem = "Could not save grants: \(error)"
        }
        shared.update(store: store, grants: grants)
    }

    // MARK: - Pushes

    /// The `.p8` Apple hands out once, named AuthKey_<id>.p8. The id is read from the name,
    /// the team from this app's own signing. The key goes into the keychain.
    func choosePushKey() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Key"
        panel.message = "Pick the push key downloaded from the developer account, AuthKey_<id>.p8."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let keyID = PushKey.keyID(fromFileName: url.lastPathComponent) else {
            pushReport = "The file should be named as Apple named it, AuthKey_<id>.p8, so the key's id is known."
            return
        }
        guard let teamID = Bundle.main.object(forInfoDictionaryKey: "MarginTeamID") as? String, !teamID.isEmpty else {
            pushReport = "This build carries no team id, so the claim could not be signed."
            return
        }
        do {
            let pem = try String(contentsOf: url, encoding: .utf8)
            // Refuse early what Apple would refuse later.
            _ = try APNS.token(for: PushKey(keyID: keyID, teamID: teamID, pem: pem))
            let key = PushKey(keyID: keyID, teamID: teamID, pem: pem)
            try PushKeyStore.save(key)
            pushKey = key
            pushReport = nil
            Task { await pusher.use(key) }
        } catch {
            pushReport = "Could not take the key: \(error.localizedDescription)"
        }
    }

    func removePushKey() {
        PushKeyStore.remove()
        pushKey = nil
        pushReport = nil
        Task { await pusher.use(nil) }
    }

    /// One push to every phone, to see it arrive.
    func sendTestPush() {
        push(APNS.Message(title: "Margin", body: "Pushes reach this phone."))
    }

    /// Words written through the door go to the phone as a push: a note under a line, a line
    /// on the writer's own page, a name chosen. Marks stay silent: labels and links are for
    /// the page, not the pocket. The push is titled with the writer's name once it has one.
    nonisolated private func pushIfWords(_ event: Event) {
        Task { @MainActor in
            let title = self.notebook?.name(of: event.author) ?? "Margin"
            switch event.payload {
            case .noteAdd(let note):
                self.push(APNS.Message(title: title, body: note.text, entry: note.entry))
            case .entryCreate(let line):
                self.push(APNS.Message(title: title, body: line.text, entry: line.entry))
            case .nameSet(let chosen):
                self.push(APNS.Message(title: "Margin", body: "Chose the name \(chosen.name)."))
            default:
                break
            }
        }
    }

    private func push(_ message: APNS.Message) {
        guard pushKey != nil else {
            pushReport = "No push key on this Mac yet."
            return
        }
        let addresses = (try? store?.pushAddresses()) ?? []
        guard !addresses.isEmpty else {
            pushReport = "No phone has written its address to the folder yet. Allow notifications in the phone's Setup."
            return
        }
        Task {
            let outcomes = await pusher.send(message, to: addresses)
            pushReport = outcomes.map { outcome in
                outcome.ok ? "Sent to \(outcome.device.rawValue)." : "\(outcome.device.rawValue): \(outcome.reason ?? "refused")."
            }.joined(separator: " ")
        }
    }

    // MARK: - The reader

    static let readerGrantName = "Reader"

    private var supportDirectory: URL {
        grantsURL.deletingLastPathComponent()
    }
    private var readerRunsURL: URL { supportDirectory.appendingPathComponent(ReaderFiles.runs, isDirectory: true) }
    var readerLogURL: URL { supportDirectory.appendingPathComponent(ReaderFiles.log) }

    /// The grant the reader acts under: the same author as the hand sessions, so it is one
    /// being with two hands, told apart in Logs by the device stamp.
    var readerGrant: Grant? {
        grants.first { $0.name == Self.readerGrantName }
    }

    /// The authors the reader could act as: every grant that is not itself.
    var readerCandidates: [Grant] {
        grants.filter { $0.name != Self.readerGrantName }
    }

    var readerStatus: ReaderStatus? { _ = readerTick; return reader?.status }
    var readerRuns: [ReaderRun] { _ = readerTick; return reader?.runs ?? [] }

    /// Switches the reader on as one of the grants' authors: a grant of its own with the
    /// same author and the device "reader", and the runner inside this app, which looks
    /// at once and whenever the folder changes from then on.
    func turnReaderOn(as author: Author) {
        if readerGrant == nil {
            grants.append(Grant(name: Self.readerGrantName, author: author, device: "reader"))
            saveGrants()
        }
        UserDefaults.standard.set(true, forKey: readerOnKey)
        startReader()
    }

    func turnReaderOff() {
        UserDefaults.standard.set(false, forKey: readerOnKey)
        reader = nil
        if let grant = readerGrant { revoke(grant) }
        readerTick += 1
    }

    /// Looks now, without waiting for a line to land.
    func lookNow() {
        guard let store else { return }
        reader?.wake(store)
    }

    private func startReader() {
        guard let grant = readerGrant else { return }
        let runner = ReaderRunner(grant: grant, door: "http://127.0.0.1:\(Self.defaultPort)/mcp", model: readerModel,
                                  runsDirectory: readerRunsURL, logURL: readerLogURL)
        runner.onChange = { [weak self] in self?.readerTick += 1 }
        reader = runner
        readerTick += 1
        if let store {
            runner.remember(store)
            runner.wake(store)
        }
    }

    // MARK: - The door

    private func openDoor() async {
        let shared = self.shared
        let router = DoorRouter(calendar: .current, resolve: { key in shared.resolve(key) },
                                written: { [weak self] event in self?.pushIfWords(event) })
        do {
            let server = try DoorServer(port: Self.defaultPort) { router.respond($0) }
            self.server = server
            port = try await server.start()
            // The door is open: the reader may look now.
            if let store { reader?.wake(store) }
        } catch {
            problem = "The door could not open on port \(Self.defaultPort): \(error)"
        }
    }
}

/// What the server thread may see: the current store and grants, behind a lock.
final class DoorState: @unchecked Sendable {
    private let lock = NSLock()
    private var store: FileStore?
    private var grants: [Grant] = []

    func update(store: FileStore?, grants: [Grant]) {
        lock.lock()
        self.store = store
        self.grants = grants
        lock.unlock()
    }

    func resolve(_ key: String) -> (FileStore, Grant)? {
        lock.lock()
        defer { lock.unlock() }
        guard let store, let grant = grants.first(where: { $0.key == key }) else { return nil }
        return (store, grant)
    }
}
