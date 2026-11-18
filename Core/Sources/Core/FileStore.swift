import CryptoKit
import Foundation

/// `notebook.json` at the root of the folder.
public struct NotebookManifest: Hashable, Codable, Sendable {
    public var id: ULID
    public var created: Date
    public var owner: Author
    public var version: Int

    public init(id: ULID, created: Date, owner: Author, version: Int = 1) {
        self.id = id
        self.created = created
        self.owner = owner
        self.version = version
    }
}

/// The notebook as a folder. This is the canonical copy.
///
///     <root>/
///       notebook.json
///       events/<author>.<device>.jsonl   one writer per file, append-only
///       media/<hash>.<ext>
///       days/YYYY-MM-DD.md               derived, see Projector
///
/// Each device appends only to its own file, so two writers never touch the same bytes
/// and there is nothing to merge. Anyone with the folder can take part by appending
/// to a file of its own.
public struct FileStore: Sendable {
    public let root: URL
    public let manifest: NotebookManifest

    public static let manifestName = "notebook.json"

    public var eventsDirectory: URL { root.appendingPathComponent("events", isDirectory: true) }
    public var mediaDirectory: URL { root.appendingPathComponent("media", isDirectory: true) }
    public var daysDirectory: URL { root.appendingPathComponent("days", isDirectory: true) }

    public enum Error: Swift.Error, Equatable {
        case alreadyANotebook(URL)
        case notANotebook(URL)
    }

    /// Makes a new notebook folder. Fails if one is already there.
    public static func create(at root: URL, owner: Author, id: ULID = ULID(), now: Date = Date()) throws -> FileStore {
        let manifestURL = root.appendingPathComponent(manifestName)
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            throw Error.alreadyANotebook(root)
        }
        let manifest = NotebookManifest(id: id, created: now.toMilliseconds, owner: owner)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = FileStore(root: root, manifest: manifest)
        for directory in [store.eventsDirectory, store.mediaDirectory, store.daysDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = JSONLines.encoder()
        encoder.outputFormatting.insert(.prettyPrinted)
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        return store
    }

    /// Opens an existing notebook folder.
    public static func open(_ root: URL) throws -> FileStore {
        let manifestURL = root.appendingPathComponent(manifestName)
        guard let data = FileManager.default.contents(atPath: manifestURL.path) else {
            throw Error.notANotebook(root)
        }
        let manifest = try JSONLines.decoder().decode(NotebookManifest.self, from: data)
        return FileStore(root: root, manifest: manifest)
    }

    private init(root: URL, manifest: NotebookManifest) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.manifest = manifest
    }

    // MARK: - Events

    public func eventFile(author: Author, device: DeviceID) -> URL {
        eventsDirectory.appendingPathComponent("\(Self.safe(author.rawValue)).\(Self.safe(device.rawValue)).jsonl")
    }

    /// Appends one event to its author's and device's file, and flushes to disk.
    public func append(_ event: Event) throws {
        try append([event])
    }

    /// Appends events, grouped by file, each group in one coordinated write.
    /// Coordination matters when the folder lives in iCloud Drive, where the sync daemon
    /// is another writer of the same files.
    public func append(_ events: [Event]) throws {
        let groups = Dictionary(grouping: events) { eventFile(author: $0.author, device: $0.device) }
        try FileManager.default.createDirectory(at: eventsDirectory, withIntermediateDirectories: true)
        for (url, group) in groups {
            var text = ""
            for event in group.sorted(by: { $0.id < $1.id }) {
                text += try JSONLines.encode(event)
                text += "\n"
            }
            try coordinated(writing: url) { url in
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                let handle = try FileHandle(forUpdating: url)
                defer { try? handle.close() }
                // A write cut short leaves a last line with no end. What is written now
                // starts on a line of its own, so it is never glued onto the damage.
                let end = try handle.seekToEnd()
                var bytes = Data()
                if end > 0 {
                    try handle.seek(toOffset: end - 1)
                    if try handle.read(upToCount: 1) != Data([UInt8(ascii: "\n")]) { bytes.append(UInt8(ascii: "\n")) }
                    try handle.seekToEnd()
                }
                bytes.append(Data(text.utf8))
                try handle.write(contentsOf: bytes)
                try handle.synchronize()
            }
        }
    }

    /// Brings the events of one event file into another of the same author and device: every
    /// event the target does not have yet, by id, appended in the order written. For a
    /// notebook moved into a folder that already holds an older copy of the same file, where
    /// skipping the file would lose what was written since. Returns how many were brought.
    @discardableResult
    public static func mergeEvents(from source: URL, into target: URL, rewriting rewrite: (Event) -> Event = { $0 }) throws -> Int {
        let have = Set(JSONLines.read(try Data(contentsOf: target)).events.map(\.id))
        let missing = JSONLines.read(try Data(contentsOf: source)).events.map(rewrite).filter { !have.contains($0.id) }
        guard !missing.isEmpty else { return 0 }
        var bytes = Data()
        let handle = try FileHandle(forUpdating: target)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            if try handle.read(upToCount: 1) != Data([UInt8(ascii: "\n")]) { bytes.append(UInt8(ascii: "\n")) }
            try handle.seekToEnd()
        }
        for event in missing {
            bytes.append(Data(try JSONLines.encode(event).utf8))
            bytes.append(UInt8(ascii: "\n"))
        }
        try handle.write(contentsOf: bytes)
        try handle.synchronize()
        return missing.count
    }

    /// Every event in every file, sorted by id.
    public func loadEvents() throws -> [Event] {
        try loadEventsByFile().flatMap(\.events).sorted { $0.id < $1.id }
    }

    /// Every event, file by file, in the order written. Files only grow, so a count per
    /// file is a cursor into the whole notebook that no late arrival can slip past.
    public func loadEventsByFile() throws -> [(file: String, events: [Event])] {
        try loadFiles().map { ($0.name, $0.events) }
    }

    /// One event file as read: its events, and the lines in it that could not be read.
    public struct EventFile: Sendable {
        public let name: String
        public let events: [Event]
        /// Line numbers, from one, that are not events: a write cut short, damage in transit.
        public let unreadable: [Int]
    }

    /// Every event file, read for what can be read. A damaged line is passed over and
    /// named here; it never costs the rest of its file, nor any other file. A file that
    /// cannot be opened at all still throws.
    public func loadFiles() throws -> [EventFile] {
        try eventFiles().map { url in
            let read = JSONLines.read(try bytes(of: url))
            return EventFile(name: url.lastPathComponent, events: read.events, unreadable: read.unreadable)
        }
    }

    /// One file's bytes as they stand, read with the sync daemon kept out of the way.
    func bytes(of url: URL) throws -> Data {
        try coordinated(reading: url) { try Data(contentsOf: $0) }
    }

    /// The event files on disk. In iCloud Drive a file not pulled down yet shows as
    /// `.name.jsonl.icloud` and is not one of them; `CloudWatcher` asks for those.
    public func eventFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: eventsDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: eventsDirectory.path)
            .filter { $0.hasSuffix(".jsonl") }
            .sorted()
            .map { eventsDirectory.appendingPathComponent($0) }
    }

    private func coordinated<T>(reading url: URL, _ body: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Swift.Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result { try body(url) }
        }
        if let coordinationError { throw coordinationError }
        return try result!.get()
    }

    private func coordinated(writing url: URL, _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var result: Result<Void, Swift.Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result { try body(url) }
        }
        if let coordinationError { throw coordinationError }
        try result!.get()
    }

    /// The fold of the whole folder.
    public func load() throws -> Notebook {
        Notebook(owner: manifest.owner, events: try loadEvents())
    }

    // MARK: - Media

    /// Writes the bytes under their SHA-256 and returns the hash. Writing the same bytes twice is a no-op.
    @discardableResult
    public func storeMedia(_ data: Data, fileExtension: String) throws -> String {
        let hash = Self.hash(of: data)
        let url = mediaURL(hash: hash, fileExtension: fileExtension)
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        return hash
    }

    public func mediaURL(hash: String, fileExtension: String) -> URL {
        mediaDirectory.appendingPathComponent("\(hash).\(fileExtension)")
    }

    public static func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Internals

    /// Keeps file names to letters, digits, dash and underscore.
    static func safe(_ raw: String) -> String {
        String(raw.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" })
    }
}
