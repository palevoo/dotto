import XCTest
@testable import Core

final class ProjectorTests: XCTestCase {
    let me: Author = "me"
    let generator = ULIDGenerator()
    var root: URL!

    var lisbon: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("projector-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func event(_ payload: Payload, author: Author = "me", at: Date) -> Event {
        Event(id: generator.next(at: at), author: author, device: "iphone", at: at, payload: payload)
    }

    func sampleEvents() -> (events: [Event], wall: ULID) {
        let nine14 = Date(timeIntervalSince1970: 1_793_610_840) // 2026-11-02 09:14 Lisbon (UTC in winter)
        let nine20 = nine14.addingTimeInterval(6 * 60)
        let nine31 = nine14.addingTimeInterval(17 * 60)
        let wall = ULID(), tanks = ULID()
        let events = [
            event(.entryCreate(.init(entry: wall, text: "Wall dimensions are 10 m total length on both sides, 1.5 m height, 30 cm width.", startedAt: nine14)), at: nine14),
            event(.mediaAttach(.init(entry: wall, hash: "3f2a", mime: "image/jpeg", width: 1280, height: 960)), at: nine14.addingTimeInterval(30)),
            event(.noteAdd(.init(entry: wall, note: ULID(), text: "Closed the to-do from 29 Oct.\nAbout 15 m² of face to render.")), author: .weeju, at: nine20),
            event(.entryCreate(.init(entry: tanks, text: "", startedAt: nine31)), at: nine31),
            event(.mediaAttach(.init(entry: tanks, hash: "9c01", mime: "audio/mp4", duration: 42)), at: nine31),
        ]
        return (events, wall)
    }

    func testMarkdownForADay() {
        let notebook = Notebook(owner: me, events: sampleEvents().events)
        let day = notebook.days(calendar: lisbon)[0]
        XCTAssertEqual(
            Projector.markdown(for: day, calendar: lisbon),
            """
            # 2026-11-02 · Monday

            ## 09:14
            Wall dimensions are 10 m total length on both sides, 1.5 m height, 30 cm width.

            ![photo](../media/3f2a.jpg)

            > weeju · 09:20
            > Closed the to-do from 29 Oct.
            > About 15 m² of face to render.

            ## 09:31

            [voice 0:42](../media/9c01.m4a)

            """
        )
    }

    func testMarkdownShowsTheThread() {
        let (events, wall) = sampleEvents()
        let later = Date(timeIntervalSince1970: 1_793_610_840 + 86_400 * 2 + 60) // 2026-11-04 09:15
        let potted = ULID(timestamp: later)
        let notebook = Notebook(owner: me, events: events + [
            event(.entryCreate(.init(entry: potted, text: "Rendered the wall.", startedAt: later)), at: later),
            event(.linkAdd(.init(later: potted, earlier: wall, closes: true)), author: .weeju, at: later.addingTimeInterval(3600)),
        ])
        let days = notebook.days(calendar: lisbon)
        XCTAssertTrue(Projector.markdown(for: days[0], calendar: lisbon).contains("\n_done by 2026-11-04 09:15_\n"))
        XCTAssertTrue(Projector.markdown(for: days[1], calendar: lisbon).hasSuffix("Rendered the wall.\n\n_continues 2026-11-02 09:14_\n"))
    }

    func testWriteCreatesAndPrunesDayFiles() throws {
        let store = try FileStore.create(at: root, owner: me)
        let (events, wall) = sampleEvents()
        try store.append(events)

        let written = try Projector.write(try store.load(), to: store, calendar: lisbon)
        XCTAssertEqual(written.map(\.lastPathComponent), ["2026-11-02.md"])

        // A stale file from a day that no longer has entries goes away; an unrelated file stays.
        let stale = store.daysDirectory.appendingPathComponent("2020-01-01.md")
        let unrelated = store.daysDirectory.appendingPathComponent("README.txt")
        try Data("old".utf8).write(to: stale)
        try Data("keep".utf8).write(to: unrelated)

        // Delete the wall entry; the day still exists because of the voice note.
        try store.append(event(.entryDelete(.init(entry: wall)), at: Date(timeIntervalSince1970: 1_793_614_000)))
        try Projector.write(try store.load(), to: store, calendar: lisbon)

        let names = try FileManager.default.contentsOfDirectory(atPath: store.daysDirectory.path).sorted()
        XCTAssertEqual(names, ["2026-11-02.md", "README.txt"])
        let text = try String(contentsOf: store.daysDirectory.appendingPathComponent("2026-11-02.md"), encoding: .utf8)
        XCTAssertFalse(text.contains("Wall dimensions"))
        XCTAssertTrue(text.contains("[voice 0:42]"))
    }

    func testWriteIsDeterministic() throws {
        let store = try FileStore.create(at: root, owner: me)
        try store.append(sampleEvents().events)
        try Projector.write(try store.load(), to: store, calendar: lisbon)
        let url = store.daysDirectory.appendingPathComponent("2026-11-02.md")
        let before = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        Thread.sleep(forTimeInterval: 0.05)
        try Projector.write(try store.load(), to: store, calendar: lisbon)
        let after = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        XCTAssertEqual(before, after, "unchanged days are not rewritten")
    }

    func testFileExtensions() {
        XCTAssertEqual(Projector.fileExtension(forMIME: "image/jpeg"), "jpg")
        XCTAssertEqual(Projector.fileExtension(forMIME: "audio/x-m4a"), "m4a")
        XCTAssertEqual(Projector.fileExtension(forMIME: "video/quicktime"), "mov")
        XCTAssertEqual(Projector.fileExtension(forMIME: "application/pdf"), "bin")
    }
}
