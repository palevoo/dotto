import AppKit
import Foundation
import Security

/// What the home kept while its id was social.interface.margin.mac, brought to where it keeps
/// things now.
///
/// The system files an app's settings and its keychain entries under the app's id, so under a
/// new id the home would open with nothing: no folder, no keys for its grants, no push key,
/// and it would send again every due notice it had sent. The first time it opens under the new
/// id it copies those over: the settings, under the names they have now; each key in the
/// keychain, for which the system asks the owner once per key, since to the keychain this is
/// another app; and the folder of the app's own records. Copied, never moved: what the earlier
/// app kept stays where it was until that app is deleted, and it still runs on it.
///
/// It is done once everything came over. A key the owner did not allow is asked for again at
/// the next launch. A Mac that never ran the earlier app has nothing to carry.
///
/// Only one Mac ever ran the earlier id. Once that Mac has opened under the new one, this file
/// and its one call can go.
enum CarryOver {
    static let earlierID = "social.interface.margin.mac"
    private static let earlierSupportFolder = "Margin"
    private static let doneKey = "dotto.carried"

    /// The earlier app, if it is running now. Two homes on one notebook would each answer
    /// every line, and the first holds the door's port.
    static var earlierIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: earlierID).isEmpty
    }

    /// Before anything else reads a setting, a key or the records folder.
    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        carrySettings(into: defaults)
        carryRecords()
        // Both, even when the first could not all be read.
        let grants = carryKeys("grant-keys")
        let push = carryKeys("push-key")
        if grants && push { defaults.set(true, forKey: doneKey) }
    }

    /// Each setting the earlier app kept, under the name it has now, where none is set here.
    private static func carrySettings(into defaults: UserDefaults) {
        guard let earlier = UserDefaults(suiteName: earlierID) else { return }
        let names: [(was: String, now: String)] = [
            ("margin.folder.bookmark", Identity.Kept.folder),
            ("margin.owner", Identity.Kept.owner),
            ("margin.device", Identity.Kept.device),
            ("margin.reader.model", Identity.Kept.readerModel),
            ("margin.due.sent", Identity.Kept.dueSent),
            ("margin.push.keyID", Identity.Kept.pushKeyID),
            ("margin.push.teamID", Identity.Kept.pushTeamID),
            ("dotto.capture.draft", Identity.Kept.draft),
        ]
        for name in names where defaults.object(forKey: name.now) == nil {
            if let value = earlier.object(forKey: name.was) { defaults.set(value, forKey: name.now) }
        }
    }

    /// The app's own records, the loops' log and runs: the whole folder, when there is none here yet.
    private static func carryRecords() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let from = support.appendingPathComponent(earlierSupportFolder, isDirectory: true)
        let to = support.appendingPathComponent(Identity.supportFolder, isDirectory: true)
        guard FileManager.default.fileExists(atPath: from.path), !FileManager.default.fileExists(atPath: to.path) else { return }
        try? FileManager.default.copyItem(at: from, to: to)
    }

    /// Every keychain entry of one kind the earlier app kept, copied to this app's own service.
    /// False when one that is there could not be read or written, so it is tried again.
    private static func carryKeys(_ what: String) -> Bool {
        let from = "\(earlierID).\(what)"
        let to = Identity.keychainService(what)
        let list: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: from,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var found: CFTypeRef?
        let status = SecItemCopyMatching(list as CFDictionary, &found)
        if status == errSecItemNotFound { return true }
        guard status == errSecSuccess, let entries = found as? [[String: Any]] else { return false }

        var all = true
        for entry in entries {
            guard let account = entry[kSecAttrAccount as String] as? String else { continue }
            let here: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: to,
                kSecAttrAccount as String: account,
            ]
            // Already here: nothing to ask the owner for.
            if SecItemCopyMatching(here as CFDictionary, nil) == errSecSuccess { continue }
            let one: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: from,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
            ]
            var value: CFTypeRef?
            guard SecItemCopyMatching(one as CFDictionary, &value) == errSecSuccess, let data = value as? Data else {
                all = false
                continue
            }
            var copy = here
            copy[kSecValueData as String] = data
            if SecItemAdd(copy as CFDictionary, nil) != errSecSuccess { all = false }
        }
        return all
    }
}
