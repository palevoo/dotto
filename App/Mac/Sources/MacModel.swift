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
///
/// Grants are the owner's events in the notebook, written from here into the owner's own
/// file for this Mac. The notebook keeps each key's hash; the keys themselves stay in this
/// Mac's keychain, so the Copy button works and nothing else needs them.
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
    /// The grants that open the door, from the fold, with the keys this Mac holds filled in.
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
    private let deviceKey = "margin.device"
    private let readerOnKey = "margin.reader.on"
    private let readerGrantKey = "margin.reader.grant"
    private let shared = DoorState()
    private let pusher = Pusher()
    private let generator = ULIDGenerator()
    private var server: DoorServer?
    private var watcher: FolderWatcher?
    private var cloud: CloudWatcher?
    private var summaryTask: Task<Void, Never>?

    init() {
        carryOverFromSandbox()
        restoreFolder()
        if UserDefaults.standard.bool(forKey: readerOnKey), readerGrant != nil { startReader() }
        Task {
            await pusher.use(pushKey)
            await openDoor()
        }
    }

    // MARK: - What the sandboxed app kept

    /// The app used to run sandboxed, and kept its folder choice and the reader's records
    /// inside its container. Without the sandbox it keeps them in the ordinary places, so on
    /// launch anything still only in the container is brought over: the folder choice and
    /// names when none is set here; the reader's log and runs when absent. Nothing in the
    /// container is removed. The grants file it kept is carried into the notebook once the
    /// folder is open, see `carryOverGrantsFiles`.
    private func carryOverFromSandbox() {
        let oldPrefs = Self.container.appendingPathComponent("Library/Preferences/social.interface.margin.mac.plist")
        for name in [ReaderFiles.log, ReaderFiles.runs] {
            let from = Self.oldSupport.appendingPathComponent(name)
            let to = supportDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: from.path), !FileManager.default.fileExists(atPath: to.path) {
                try? FileManager.default.copyItem(at: from, to: to)
            }
        }
        if let prefs = NSDictionary(contentsOf: oldPrefs) as? [String: Any] {
            let defaults = UserDefaults.standard
            for key in [bookmarkKey, ownerKey, "margin.reader.model"] where defaults.object(forKey: key) == nil {
                if let value = prefs[key] { defaults.set(value, forKey: key) }
            }
        }
    }

    private static var container: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/social.interface.margin.mac/Data", isDirectory: true)
    }

    private static var oldSupport: URL {
        container.appendingPathComponent("Library/Application Support/Margin", isDirectory: true)
    }

    /// Grants used to be rows in a file of this app's own, with the keys in the clear. They
    /// are the owner's events in the notebook now. Each row the fold does not know becomes a
    /// `grant.create` with the key's hash, the key goes to the keychain, and the file is set
    /// aside under another name so this runs once. Both places the file ever lived are read.
    private func carryOverGrantsFiles(_ store: FileStore, _ notebook: Notebook) {
        let known = Set(notebook.allGrants.map(\.id))
        for url in [supportDirectory.appendingPathComponent("grants.json"), Self.oldSupport.appendingPathComponent("grants.json")] {
            guard let data = try? Data(contentsOf: url), let rows = try? JSONLines.decoder().decode([Grant].self, from: data) else { continue }
            for row in rows where row.device != "reader" {
                var grant = row
                if grant.device == "mac-door" { grant.device = Grant.device(for: grant.name) }
                if !grant.key.isEmpty { try? GrantKeys.save(grant.key, for: grant.id) }
                guard !known.contains(grant.id) else { continue }
                try? store.append(Event(id: generator.next(at: grant.createdAt), author: store.manifest.owner, device: device, at: grant.createdAt,
                                        payload: .grantCreate(grant.create)))
            }
            try? FileManager.default.moveItem(at: url, to: url.deletingPathExtension().appendingPathExtension("carried.json"))
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
            shared.update(store: store)
            if let notebook = try? store.load() { carryOverGrantsFiles(store, notebook) }
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
            grants = []
            return
        }
        let notebook = Notebook(owner: store.manifest.owner, events: files.flatMap(\.events))
        self.notebook = notebook
        inbox = Core.Inbox.items(files: files, notebook: notebook, calendar: .current)
        grants = notebook.grants.map { grant in
            var held = grant
            held.key = GrantKeys.key(for: grant.id) ?? ""
            return held
        }
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

    /// This Mac, as the owner's events written here name it. Made once.
    private var device: DeviceID {
        if let raw = UserDefaults.standard.string(forKey: deviceKey) { return DeviceID(rawValue: raw) }
        let raw = "mac-" + String(ULID().string.suffix(4)).lowercased()
        UserDefaults.standard.set(raw, forKey: deviceKey)
        return DeviceID(rawValue: raw)
    }

    /// An event of the owner's, from this Mac, into the owner's file for it.
    private func write(_ payload: Payload) {
        guard let store else { return }
        let now = Date()
        do {
            try store.append(Event(id: generator.next(at: now), author: store.manifest.owner, device: device, at: now, payload: payload))
            refreshSummary()
        } catch {
            problem = "Could not write to the notebook: \(error)"
        }
    }

    // MARK: - Grants

    private var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Margin", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Everyone who has written anything other than the owner, named where they have chosen
    /// a name: the authors a new key could be handed to.
    var authors: [Author] {
        notebook?.others ?? []
    }

    /// A new grant: a key for an author. A new author gets a fresh id and no name, and
    /// chooses one through the door when it wants to. An existing author gets one more key,
    /// the same being from another hand or another machine. The key goes to the keychain, the
    /// grant into the notebook as the owner's event; the fold then shows it.
    func addGrant(name: String, as author: Author? = nil) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        open(Grant(name: cleanName, author: author ?? .fresh(), device: Grant.device(for: cleanName)))
    }

    private func open(_ grant: Grant) {
        do {
            try GrantKeys.save(grant.key, for: grant.id)
        } catch {
            problem = "Could not keep the key in the keychain: \(error.localizedDescription)"
            return
        }
        write(.grantCreate(grant.create))
    }

    /// What an author is called, if they have chosen; else their id.
    func name(of author: Author) -> String {
        notebook?.name(of: author) ?? author.rawValue
    }

    /// The key stops opening the door. The author's events stay, under their id.
    func revoke(_ grant: Grant) {
        if readerGrant?.id == grant.id { turnReaderOff() }
        write(.grantRevoke(.init(grant: grant.id)))
        GrantKeys.remove(for: grant.id)
    }

    /// The same key, another author: whoever holds it is that author from now on. The old
    /// grant is closed and a new one opened with the same hash, so nothing has to be pasted
    /// again. For a key handed out before an author had the page it should have had.
    func reassign(_ grant: Grant, to author: Author) {
        guard author != grant.author else { return }
        var moved = Grant(name: grant.name, author: author, device: grant.device, key: grant.key,
                          writesNotes: grant.writesNotes, writesLabels: grant.writesLabels, writesLinks: grant.writesLinks, writesLines: grant.writesLines)
        moved.keyHash = grant.keyHash
        let wasReader = readerGrant?.id == grant.id
        if wasReader { turnReaderOff() }
        write(.grantRevoke(.init(grant: grant.id)))
        if !grant.key.isEmpty { try? GrantKeys.save(grant.key, for: moved.id) }
        GrantKeys.remove(for: grant.id)
        write(.grantCreate(moved.create))
        if wasReader { turnReaderOn(as: moved) }
    }

    /// A fresh key for the same author, for when this Mac no longer holds the old one.
    func reissue(_ grant: Grant) {
        let fresh = Grant(name: grant.name, author: grant.author, device: grant.device,
                          writesNotes: grant.writesNotes, writesLabels: grant.writesLabels, writesLinks: grant.writesLinks, writesLines: grant.writesLines)
        let wasReader = readerGrant?.id == grant.id
        if wasReader { turnReaderOff() }
        write(.grantRevoke(.init(grant: grant.id)))
        GrantKeys.remove(for: grant.id)
        open(fresh)
        if wasReader { turnReaderOn(as: fresh) }
    }

    /// What the person pastes into a terminal so Claude Code knows the door and the key.
    /// Nil when this Mac does not hold the key.
    func connectCommand(for grant: Grant) -> String? {
        guard !grant.key.isEmpty else { return nil }
        return "claude mcp add --transport http dotto http://127.0.0.1:\(port ?? Self.defaultPort)/mcp --header \"Authorization: Bearer \(grant.key)\""
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
        push(APNS.Message(title: "dotto", body: "Pushes reach this phone."))
    }

    /// Words written through the door go to the phone as a push: a note under a line, a line
    /// on the writer's own page, a name chosen. Marks stay silent: labels and links are for
    /// the page, not the pocket. The push is titled with the writer's name once it has one.
    nonisolated private func pushIfWords(_ event: Event) {
        Task { @MainActor in
            let title = self.notebook?.name(of: event.author) ?? "dotto"
            switch event.payload {
            case .noteAdd(let note):
                self.push(APNS.Message(title: title, body: note.text, entry: note.entry))
            case .entryCreate(let line):
                self.push(APNS.Message(title: title, body: line.text, entry: line.entry))
            case .nameSet(let chosen):
                self.push(APNS.Message(title: "dotto", body: "Chose the name \(chosen.name)."))
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

    private var readerRunsURL: URL { supportDirectory.appendingPathComponent(ReaderFiles.runs, isDirectory: true) }
    var readerLogURL: URL { supportDirectory.appendingPathComponent(ReaderFiles.log) }

    /// The grant the reader acts under: one of the rows above, the same key and author as a
    /// session at the keyboard. It is one being with two hands; Logs tell them apart by the
    /// device stamp the reader sends.
    var readerGrant: Grant? {
        guard let raw = UserDefaults.standard.string(forKey: readerGrantKey) else { return nil }
        return grants.first { $0.id.string == raw }
    }

    var readerStatus: ReaderStatus? { _ = readerTick; return reader?.status }
    var readerRuns: [ReaderRun] { _ = readerTick; return reader?.runs ?? [] }

    /// Switches the reader on under one of the grants: the runner inside this app, which
    /// looks at once and whenever the folder changes from then on.
    func turnReaderOn(as grant: Grant) {
        UserDefaults.standard.set(grant.id.string, forKey: readerGrantKey)
        UserDefaults.standard.set(true, forKey: readerOnKey)
        startReader(grant)
    }

    func turnReaderOff() {
        UserDefaults.standard.set(false, forKey: readerOnKey)
        reader = nil
        readerTick += 1
    }

    /// Looks now, without waiting for a line to land.
    func lookNow() {
        guard let store else { return }
        reader?.wake(store)
    }

    private func startReader(_ chosen: Grant? = nil) {
        guard let grant = chosen ?? readerGrant else { return }
        guard !grant.key.isEmpty else {
            problem = "The reader's key is not on this Mac. Issue a new key for \(grant.name) and turn the reader on again."
            return
        }
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

/// What the server thread may see: the current store, behind a lock. A key is looked up in
/// the fold of that store, so the grants are whatever the notebook says at that moment.
final class DoorState: @unchecked Sendable {
    private let lock = NSLock()
    private var store: FileStore?

    func update(store: FileStore?) {
        lock.lock()
        self.store = store
        lock.unlock()
    }

    func resolve(_ key: String) -> (FileStore, Grant)? {
        lock.lock()
        let store = self.store
        lock.unlock()
        guard let store, let grant = try? store.load().grant(forKey: key) else { return nil }
        return (store, grant)
    }
}

/// The keys this Mac holds, one per grant, in the keychain. The notebook has only hashes.
enum GrantKeys {
    private static let service = "social.interface.margin.mac.grant-keys"

    static func key(for grant: ULID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: grant.string,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String, for grant: ULID) throws {
        remove(for: grant)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: grant.string,
            kSecValueData as String: Data(key.utf8),
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "keychain \(status)"])
        }
    }

    static func remove(for grant: ULID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: grant.string,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
