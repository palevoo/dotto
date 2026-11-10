import XCTest
@testable import Core

final class FileStoreTests: XCTestCase {
    var root: URL!
    let me: Author = "me"
    let generator = ULIDGenerator()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("core-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func event(_ payload: Payload, author: Author = "me", device: DeviceID) -> Event {
        let now = Date()
        return Event(id: generator.next(at: now), author: author, device: device, at: now, payload: payload)
    }

    func testCreateOpenAndRefuseDouble() throws {
        let store = try FileStore.create(at: root, owner: me, now: Date(timeIntervalSince1970: 1_793_613_600.25))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("notebook.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.eventsDirectory.path))

        let reopened = try FileStore.open(root)
        XCTAssertEqual(reopened.manifest, store.manifest)
        XCTAssertEqual(reopened.manifest.owner, me)

        XCTAssertThrowsError(try FileStore.create(at: root, owner: me)) { error in
            XCTAssertEqual(error as? FileStore.Error, .alreadyANotebook(root))
        }
        XCTAssertThrowsError(try FileStore.open(root.appendingPathComponent("nowhere"))) { error in
            guard case FileStore.Error.notANotebook = error else { return XCTFail("\(error)") }
        }
    }

    func testOneFilePerAuthorAndDevice() throws {
        let store = try FileStore.create(at: root, owner: me)
        let id = ULID()
        try store.append(event(.entryCreate(.init(entry: id, text: "from the phone", startedAt: Date())), device: "iphone"))
        try store.append(event(.entryEdit(.init(entry: id, text: "edited on the mac")), device: "mac"))
        try store.append(event(.noteAdd(.init(entry: id, note: ULID(), text: "noted")), author: .weeju, device: "mac"))

        let names = try store.eventFiles().map(\.lastPathComponent)
        XCTAssertEqual(names, ["me.iphone.jsonl", "me.mac.jsonl", "weeju.mac.jsonl"])

        let events = try store.loadEvents()
        XCTAssertEqual(events.map(\.kind), [.entryCreate, .entryEdit, .noteAdd])
        XCTAssertEqual(events, events.sorted { $0.id < $1.id })

        let notebook = try store.load()
        XCTAssertEqual(notebook.entry(id)?.text, "edited on the mac")
        XCTAssertEqual(notebook.entry(id)?.notes.first?.author, .weeju)
    }

    func testAppendIsAppendOnly() throws {
        let store = try FileStore.create(at: root, owner: me)
        let first = event(.entryDelete(.init(entry: ULID())), device: "iphone")
        let second = event(.entryDelete(.init(entry: ULID())), device: "iphone")
        try store.append(first)
        try store.append(second)
        let text = try String(contentsOf: store.eventFile(author: me, device: "iphone"), encoding: .utf8)
        XCTAssertEqual(text, try JSONLines.encode(first) + "\n" + JSONLines.encode(second) + "\n")
    }

    func testBadLineIsReportedWithItsFile() throws {
        let store = try FileStore.create(at: root, owner: me)
        try store.append(event(.entryDelete(.init(entry: ULID())), device: "iphone"))
        let url = store.eventFile(author: me, device: "iphone")
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("garbage\n".utf8))
        try handle.close()

        // The line is passed over and named with its file; the rest still reads.
        XCTAssertEqual(try store.loadEvents().count, 1)
        let file = try XCTUnwrap(try store.loadFiles().first)
        XCTAssertEqual(file.name, url.lastPathComponent)
        XCTAssertEqual(file.unreadable, [2])
    }

    func testMediaByHash() throws {
        let store = try FileStore.create(at: root, owner: me)
        let bytes = Data("not really a jpeg".utf8)
        let hash = try store.storeMedia(bytes, fileExtension: "jpg")
        XCTAssertEqual(hash.count, 64)
        XCTAssertEqual(try store.storeMedia(bytes, fileExtension: "jpg"), hash)
        XCTAssertEqual(try Data(contentsOf: store.mediaURL(hash: hash, fileExtension: "jpg")), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.mediaDirectory.path).count, 1)
    }

    func testFileNamesAreKeptSafe() throws {
        let store = try FileStore.create(at: root, owner: me)
        let url = store.eventFile(author: "a/b c", device: "../x")
        XCTAssertEqual(url.lastPathComponent, "a_b_c.___x.jsonl")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, store.eventsDirectory.standardizedFileURL)
    }
}

/// Damage in an event file costs the damaged line and nothing else.
final class DamagedFileTests: XCTestCase {
    private var root: URL!
    private let owner = Author(rawValue: "wiju")
    private let ids = ULIDGenerator()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("damaged-\(ULID().string)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func line(_ text: String, on device: DeviceID = "phone") -> Event {
        let now = Date()
        let id = ids.next(at: now)
        return Event(id: id, author: owner, device: device, at: now, payload: .entryCreate(.init(entry: id, text: text, startedAt: now)))
    }

    func testAWriteCutShortCostsOnlyItsOwnLine() throws {
        let store = try FileStore.create(at: root, owner: owner)
        try store.append(line("first"))
        try store.append(line("on the Mac", on: "mac"))
        // A write cut short: the start of an event and no end of line.
        let file = store.eventFile(author: owner, device: "phone")
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"at":"2026-11-10T09:0"#.utf8))
        try handle.close()

        XCTAssertEqual(try store.load().entries.map(\.text).sorted(), ["first", "on the Mac"], "the notebook still reads")
        let phone = try XCTUnwrap(try store.loadFiles().first { $0.name == file.lastPathComponent })
        XCTAssertEqual(phone.unreadable, [2], "and says which line it passed over")

        // The next line is written on a line of its own, not onto the damage.
        try store.append(line("after the damage"))
        XCTAssertEqual(try store.load().entries.map(\.text).sorted(), ["after the damage", "first", "on the Mac"])
        XCTAssertEqual(try store.loadFiles().first { $0.name == file.lastPathComponent }?.unreadable, [2])
    }

    func testBytesThatAreNotTextCostOnlyTheirLine() throws {
        let store = try FileStore.create(at: root, owner: owner)
        try store.append(line("before"))
        let file = store.eventFile(author: owner, device: "phone")
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0xFF, 0xFE, 0x00, 0x0A]))
        try handle.close()
        try store.append(line("after"))
        XCTAssertEqual(try store.load().entries.map(\.text), ["before", "after"])
    }

    func testAWholeFileReadsAsBeforeAndBlankLinesAreNothing() throws {
        let first = line("one"), second = line("two")
        let text = try JSONLines.encode(first) + "\r\n\n  \n" + JSONLines.encode(second) + "\n"
        let read = JSONLines.read(Data(text.utf8))
        XCTAssertEqual(read.events, [first, second])
        XCTAssertEqual(read.unreadable, [])
        XCTAssertEqual(JSONLines.read(Data()).events, [])
    }
}
