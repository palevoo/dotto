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
/// and there is nothing to merge. Any reader with the folder can take part by appending
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
        case badEventFile(URL, line: Int)
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
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(text.utf8))
                try handle.synchronize()
            }
        }
    }

    /// Every event in every file, sorted by id.
    public func loadEvents() throws -> [Event] {
        var events: [Event] = []
        for url in try eventFiles() {
            let text = try coordinated(reading: url) { url in
                try String(contentsOf: url, encoding: .utf8)
            }
            do {
                events.append(contentsOf: try JSONLines.decodeAll(text))
            } catch JSONLines.DecodeError.badLine(let number, _) {
                throw Error.badEventFile(url, line: number)
            }
        }
        return events.sorted { $0.id < $1.id }
    }

    /// The event files present on disk. Files iCloud has not pulled down yet show as
    /// `.name.jsonl.icloud`; those are asked for and will be there next time.
    public func eventFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: eventsDirectory.path) else { return [] }
        let names = try FileManager.default.contentsOfDirectory(atPath: eventsDirectory.path)
        for name in names where name.hasSuffix(".icloud") {
            try? FileManager.default.startDownloadingUbiquitousItem(at: eventsDirectory.appendingPathComponent(name))
        }
        return names
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
