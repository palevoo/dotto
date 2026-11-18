import CryptoKit
import Foundation

/// A notebook folder as last read: the fold, and every event file by file.
public struct Standing: Sendable {
    public let notebook: Notebook
    /// Every event, file by file, in the order written. Files only grow, so a count per
    /// file is a cursor into the whole notebook that no late arrival can slip past.
    public let files: [(file: String, events: [Event])]
    /// Per file, the line numbers, from one, that are not events: a write cut short,
    /// damage in transit. They were passed over.
    public let unreadable: [(file: String, lines: [Int])]
}

/// Keeps one reading of a notebook folder and brings it up to date when asked, by what
/// has been added since. Whoever holds the folder open for long, the home, the phone, asks
/// here instead of reading the folder again.
///
/// An event file only grows. So of each file it remembers how far it has read, and reads
/// on from there; and when everything new is newer than everything already folded, the
/// new events are folded onto the notebook it holds. Anything else, a file that changed
/// before the place read to, a file gone, an event with an older id arriving late, a
/// word that two originators are one, and the fold is made again from the events it
/// holds, as it would be from the folder. Either way what it hands back is what reading
/// the whole folder at that moment gives.
///
/// It may be asked from any thread, one at a time. Asking waits on the disk, so the main
/// thread asks through `currentAside`.
public final class NotebookKeeper: @unchecked Sendable {
    public let store: FileStore

    private let lock = NSLock()
    private var read: [String: FileRead] = [:]
    private var notebook: Notebook
    /// The newest id folded into `notebook`.
    private var newest: ULID?
    private var standing: Standing?
    /// How many times the whole was folded, the first reading included. For the tests,
    /// which hold the keeper to folding again only when it has to.
    private(set) var foldedAgain = 0

    public init(store: FileStore) {
        self.store = store
        notebook = Notebook(owner: store.manifest.owner)
    }

    /// One event file, as far as it has been read.
    private struct FileRead {
        /// The file's length and the moment it was last written, when it was last looked
        /// at. Both as they were is a file nothing has been added to.
        var length: Int
        var modified: Date?
        /// How many bytes are taken for good: through the end of the last whole line.
        var taken = 0
        /// The hash of those bytes, so a file that is longer is known to be the same
        /// file with more at its end, and not another in its place.
        var hash = SHA256().finalize()
        /// How many lines those bytes are.
        var lines = 0
        var events: [Event] = []
        var unreadable: [Int] = []
        /// What stands after the last line end: a line still being written, or one cut
        /// short. Read each time as it is then, and never taken for good.
        var tail = Tail()

        struct Tail {
            var event: Event?
            var unreadable: Int?
        }

        var allEvents: [Event] { tail.event.map { events + [$0] } ?? events }
        var allUnreadable: [Int] { tail.unreadable.map { unreadable + [$0] } ?? unreadable }
    }

    /// The notebook as the folder has it now.
    public func current() throws -> Standing {
        lock.lock()
        defer { lock.unlock() }

        let urls = try store.eventFiles()
        var next: [String: FileRead] = [:]
        /// What is new, file by file in the order of their names, as a reading of the
        /// whole folder would meet it.
        var fresh: [[Event]] = []
        // A file that was read and is gone took its events with it. A new file is only more.
        let names = Set(urls.map(\.lastPathComponent))
        var again = standing == nil || read.keys.contains { !names.contains($0) }
        var changed = again

        for url in urls {
            let name = url.lastPathComponent
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let length = (attributes[.size] as? NSNumber)?.intValue ?? 0
            let modified = attributes[.modificationDate] as? Date
            if let before = read[name], before.length == length, before.modified == modified {
                next[name] = before
                continue
            }
            changed = true
            let bytes = try store.bytes(of: url)
            var file = read[name] ?? FileRead(length: length, modified: modified)
            let wasTail = file.tail.event
            if bytes.count < file.taken || SHA256.hash(data: bytes.prefix(file.taken)) != file.hash {
                // Not the file that was read with more at its end: read from its start.
                file = FileRead(length: length, modified: modified)
                again = true
            }
            file.length = length
            file.modified = modified

            var added: [Event] = []
            let rest = bytes.dropFirst(file.taken)
            if let end = rest.lastIndex(of: UInt8(ascii: "\n")) {
                // Whole lines. The last of them ends at `end`, and is read without it.
                let whole = rest[rest.startIndex..<end]
                let lines = JSONLines.read(Data(whole))
                added = lines.events
                file.events += lines.events
                file.unreadable += lines.unreadable.map { $0 + file.lines }
                file.lines += whole.reduce(1) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
                file.taken = end + 1 - bytes.startIndex
                file.hash = SHA256.hash(data: bytes.prefix(file.taken))
            }
            let tail = JSONLines.read(Data(bytes.dropFirst(file.taken)))
            file.tail = FileRead.Tail(event: tail.events.first, unreadable: tail.unreadable.first.map { $0 + file.lines })
            if let event = file.tail.event { added.append(event) }

            // The line that stood unfinished last time was folded then. It is the first
            // of what is read now, finished or still as it was; if it is not, the fold
            // holds an event the file no longer has.
            if let wasTail {
                if added.first == wasTail { added.removeFirst() } else { again = true }
            }
            fresh.append(added)
            next[name] = file
        }

        guard changed else { return standing! }

        let files = urls.map(\.lastPathComponent).map { (file: $0, events: next[$0]!.allEvents) }
        let added = fresh.flatMap { $0 }
        // Folded onto what is held only when that is what folding everything would do:
        // nothing new is older than what is folded, and nobody has been said to be another,
        // which changes how earlier events read.
        if !again {
            again = added.contains { event in
                if case .same = event.payload { return true }
                return newest.map { !($0 < event.id) } ?? false
            }
        }
        if again {
            let all = files.flatMap(\.events)
            notebook = Notebook(owner: store.manifest.owner, events: all)
            foldedAgain += 1
            newest = all.map(\.id).max()
        } else {
            // By id, and where two are the same id, in the order met: the order of a
            // reading of the whole folder.
            let ordered = added.enumerated().sorted { ($0.element.id, $0.offset) < ($1.element.id, $1.offset) }.map(\.element)
            for event in ordered { notebook.apply(event) }
            newest = max(newest, ordered.last?.id)
        }
        read = next
        let now = Standing(notebook: notebook, files: files,
                           unreadable: urls.map(\.lastPathComponent).map { (file: $0, lines: next[$0]!.allUnreadable) })
        standing = now
        return now
    }

    /// The same, asked for away from the caller's thread, for the main thread, which does
    /// not wait on the disk.
    public func currentAside() async throws -> Standing {
        try await Task.detached(priority: .userInitiated) { try self.current() }.value
    }
}

private func max(_ a: ULID?, _ b: ULID?) -> ULID? {
    guard let a else { return b }
    guard let b else { return a }
    return Swift.max(a, b)
}
