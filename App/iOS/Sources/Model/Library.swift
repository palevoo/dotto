import Core
import Foundation
import UIKit

/// Where the notebook folder lives and who this phone is. Nothing else is remembered.
@MainActor
enum Library {
    private static let bookmarkKey = "notebook.folder.bookmark"
    private static let ownerKey = "notebook.owner"
    private static let deviceKey = "notebook.device"

    /// The folder picked last time, if it can still be reached.
    static func openRememberedNotebook() -> NotebookModel? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return openNotebook(at: url)
    }

    /// Opens the notebook in `root`, creating one there if the folder is empty, and remembers the folder.
    static func openNotebook(at root: URL) -> NotebookModel? {
        _ = root.startAccessingSecurityScopedResource()
        do {
            let store: FileStore
            if FileManager.default.fileExists(atPath: root.appendingPathComponent(FileStore.manifestName).path) {
                store = try FileStore.open(root)
            } else {
                store = try FileStore.create(at: root, owner: owner)
            }
            UserDefaults.standard.set(try root.bookmarkData(), forKey: bookmarkKey)
            Inbox.remember(owner: store.manifest.owner, device: device)
            return NotebookModel(store: store, device: device)
        } catch {
            NSLog("could not open notebook at \(root.path): \(error)")
            return nil
        }
    }

    /// Moves the notebook into `root`: every file is copied over, then the folder is opened there
    /// and the old one removed. If `root` already holds a notebook, ours is folded into it and the
    /// lines we wrote are re-authored as its owner, since both are the same person.
    static func move(_ store: FileStore, to root: URL) -> NotebookModel? {
        _ = root.startAccessingSecurityScopedResource()
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let existing = try? FileStore.open(root)
            let newOwner = existing?.manifest.owner

            for relative in ["events", "media", "days"] {
                let sourceDir = store.root.appendingPathComponent(relative, isDirectory: true)
                let targetDir = root.appendingPathComponent(relative, isDirectory: true)
                try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
                for name in (try? fm.contentsOfDirectory(atPath: sourceDir.path)) ?? [] {
                    let source = sourceDir.appendingPathComponent(name)
                    let target = targetDir.appendingPathComponent(name)
                    if fm.fileExists(atPath: target.path) { continue }
                    if relative == "events", let newOwner, newOwner != store.manifest.owner {
                        let events = try JSONLines.decodeAll(try String(contentsOf: source, encoding: .utf8))
                        let text = try events
                            .map { try JSONLines.encode(reauthored($0, from: store.manifest.owner, to: newOwner)) }
                            .joined(separator: "\n")
                        try Data((text + "\n").utf8).write(to: target, options: .atomic)
                    } else {
                        try fm.copyItem(at: source, to: target)
                    }
                }
            }
            if existing == nil {
                try fm.copyItem(
                    at: store.root.appendingPathComponent(FileStore.manifestName),
                    to: root.appendingPathComponent(FileStore.manifestName)
                )
            }
            guard let model = openNotebook(at: root) else { return nil }
            if store.root.path.hasPrefix(localFolder.deletingLastPathComponent().resolvingSymlinksInPath().path) {
                try? fm.removeItem(at: store.root)
            }
            return model
        } catch {
            NSLog("could not move notebook to \(root.path): \(error)")
            return nil
        }
    }

    private static func reauthored(_ event: Event, from old: Author, to new: Author) -> Event {
        guard event.author == old else { return event }
        return Event(id: event.id, author: new, device: event.device, at: event.at, payload: event.payload)
    }

    /// A folder inside the app's own Documents, visible in the Files app.
    static var localFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notebook", isDirectory: true)
    }

    /// Where a notebook lives, in words.
    static func describe(_ store: FileStore) -> String {
        let path = store.root.path
        if path.hasPrefix(localFolder.deletingLastPathComponent().resolvingSymlinksInPath().path) {
            return "Notebook on this phone"
        }
        if path.contains("Mobile Documents") {
            return "Notebook in iCloud Drive · \(store.root.lastPathComponent)"
        }
        return "Notebook in \(store.root.lastPathComponent)"
    }

    /// Made once per phone. Only the manifest of a notebook created here carries it.
    static var owner: Author {
        if let raw = UserDefaults.standard.string(forKey: ownerKey) { return Author(rawValue: raw) }
        let raw = "me-" + String(ULID().string.suffix(6)).lowercased()
        UserDefaults.standard.set(raw, forKey: ownerKey)
        return Author(rawValue: raw)
    }

    static var device: DeviceID {
        if let raw = UserDefaults.standard.string(forKey: deviceKey) { return DeviceID(rawValue: raw) }
        let model = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        let raw = model + "-" + String(ULID().string.suffix(4)).lowercased()
        UserDefaults.standard.set(raw, forKey: deviceKey)
        return DeviceID(rawValue: raw)
    }
}
