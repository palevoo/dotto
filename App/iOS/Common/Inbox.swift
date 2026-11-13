import Core
import Foundation

/// What the share sheet keeps for the app: lines and photos written from outside, waiting
/// in the app group until the app opens and takes them into the notebook. The share sheet
/// cannot reach the notebook folder itself; this is the one hand-over.
enum Inbox {
    /// The group the app and the share sheet are both in, as the build named it.
    static let group = Bundle.main.object(forInfoDictionaryKey: "DottoAppGroup") as? String ?? "group.works.dotto"
    private static let ownerKey = "inbox.owner"
    private static let deviceKey = "inbox.device"

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("inbox", isDirectory: true)
    }

    static var eventsURL: URL? { container?.appendingPathComponent("events.jsonl") }
    static var mediaDirectory: URL? { container?.appendingPathComponent("media", isDirectory: true) }

    /// Who this phone writes as. The app says so once it has opened a notebook.
    static var owner: Author? {
        UserDefaults(suiteName: group)?.string(forKey: ownerKey).map(Author.init(rawValue:))
    }

    static var device: DeviceID? {
        UserDefaults(suiteName: group)?.string(forKey: deviceKey).map(DeviceID.init(rawValue:))
    }

    static func remember(owner: Author, device: DeviceID) {
        let defaults = UserDefaults(suiteName: group)
        defaults?.set(owner.rawValue, forKey: ownerKey)
        defaults?.set(device.rawValue, forKey: deviceKey)
    }

    enum Failure: Error {
        case noContainer
    }

    /// From the share sheet: one line and its photos, appended for the app to take.
    static func keep(_ events: [Event], media: [(hash: String, data: Data)]) throws {
        guard let eventsURL, let mediaDirectory else { throw Failure.noContainer }
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        for item in media {
            try item.data.write(to: mediaDirectory.appendingPathComponent(item.hash + ".jpg"), options: .atomic)
        }
        var text = ""
        for event in events {
            text += try JSONLines.encode(event)
            text += "\n"
        }
        if !FileManager.default.fileExists(atPath: eventsURL.path) {
            FileManager.default.createFile(atPath: eventsURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: eventsURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.synchronize()
    }

    /// From the app: everything waiting goes into the notebook, media first so no line
    /// ever points at a photo that is not there. Returns what was taken.
    static func take(into store: FileStore) throws -> [Event] {
        guard let eventsURL, let mediaDirectory,
              FileManager.default.fileExists(atPath: eventsURL.path) else { return [] }
        // A line the share sheet did not finish writing is passed over; the rest is taken.
        let events = JSONLines.read(try Data(contentsOf: eventsURL)).events
        for case .mediaAttach(let attach) in events.map(\.payload) {
            let url = mediaDirectory.appendingPathComponent(attach.hash + ".jpg")
            if let data = try? Data(contentsOf: url) {
                try store.storeMedia(data, fileExtension: "jpg")
            }
        }
        if !events.isEmpty { try store.append(events) }
        try FileManager.default.removeItem(at: eventsURL)
        try? FileManager.default.removeItem(at: mediaDirectory)
        return events
    }
}
