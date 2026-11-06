import AppKit
import Core
import Foundation
import Observation

/// The Mac's state: which folder, which grants, and whether the door is open.
///
/// The app is sandboxed. It can read exactly the folder the person picked in the open panel,
/// remembered through a security-scoped bookmark, and nothing else on the disk.
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

    private let bookmarkKey = "margin.folder.bookmark"
    private let ownerKey = "margin.owner"
    private let shared = DoorState()
    private let pusher = Pusher()
    private var server: DoorServer?
    private var watcher: FolderWatcher?
    private var cloud: CloudWatcher?
    private var summaryTask: Task<Void, Never>?

    init() {
        loadGrants()
        restoreFolder()
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
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return
        }
        adopt(url, remember: stale)
    }

    private func adopt(_ url: URL, remember: Bool) {
        guard url.startAccessingSecurityScopedResource() else {
            problem = "macOS did not let Margin into \(url.lastPathComponent)."
            return
        }
        do {
            let manifest = url.appendingPathComponent(FileStore.manifestName)
            let store = FileManager.default.fileExists(atPath: manifest.path)
                ? try FileStore.open(url)
                : try FileStore.create(at: url, owner: owner)
            if remember {
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
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

    // MARK: - The door

    private func openDoor() async {
        let shared = self.shared
        let router = DoorRouter(calendar: .current, resolve: { key in shared.resolve(key) },
                                written: { [weak self] event in self?.pushIfWords(event) })
        do {
            let server = try DoorServer(port: Self.defaultPort) { router.respond($0) }
            self.server = server
            port = try await server.start()
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
