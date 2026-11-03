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
    private(set) var grants: [Grant] = []
    private(set) var port: UInt16?
    private(set) var problem: String?

    private let bookmarkKey = "margin.folder.bookmark"
    private let ownerKey = "margin.owner"
    private let shared = DoorState()
    private var server: DoorServer?
    private var watcher: FolderWatcher?
    private var cloud: CloudWatcher?
    private var summaryTask: Task<Void, Never>?

    init() {
        loadGrants()
        restoreFolder()
        Task { await openDoor() }
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
        guard let store, let notebook = try? store.load() else {
            summary = ""
            return
        }
        let days = notebook.days(calendar: .current)
        var text = "\(notebook.entries.count) lines over \(days.count) days"
        if let last = days.last?.key { text += " · last \(last)" }
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

    /// Every reader writes as weeju for now. A second ink arrives with the second kind of reader.
    /// The grant's name travels on its events as the device, so the history under a line can say
    /// "weeju, via claude-code".
    func addGrant(name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        grants.append(Grant(name: cleanName, author: .weeju, device: Self.device(for: cleanName)))
        saveGrants()
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
        return DeviceID(rawValue: joined.isEmpty ? "reader" : joined)
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

    // MARK: - The door

    private func openDoor() async {
        let shared = self.shared
        let router = DoorRouter(calendar: .current) { key in shared.resolve(key) }
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
