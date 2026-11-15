import CryptoKit
import XCTest
@testable import Core

/// The folder as a format. `spec/format.md` says what a notebook is on disk, and `spec/sample`
/// is a small one, with the day pages a reading of it comes to. Another program, in any
/// language, reads the format rightly when its reading of the sample's events gives those
/// pages. These tests hold Core to the same: it reads the sample as the pages say, and writes
/// every line of it back as the same bytes.
///
/// The sample is made by this file. `DOTTO_WRITE_SAMPLE=1 swift test --filter FormatTests`
/// makes it again, which gives every event a new id.
final class FormatTests: XCTestCase {
    /// `spec/sample`, from where this file is: Core/Tests/CoreTests.
    private var sample: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("spec/sample", isDirectory: true)
    }

    /// The pages are said in UTC, in English, so they are the same wherever they are made.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    override func setUpWithError() throws {
        if ProcessInfo.processInfo.environment["DOTTO_WRITE_SAMPLE"] != nil { try writeSample() }
    }

    func testTheSampleReadsAsItsPagesSay() throws {
        let fm = FileManager.default
        // A copy, so that reading it writes nothing into the repository.
        let copy = fm.temporaryDirectory.appendingPathComponent("format-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: copy) }
        try fm.createDirectory(at: copy, withIntermediateDirectories: true)
        for name in [FileStore.manifestName, "events", "media"] {
            try fm.copyItem(at: sample.appendingPathComponent(name), to: copy.appendingPathComponent(name))
        }
        let store = try FileStore.open(copy)
        _ = try Projector.write(try store.load(), to: store, calendar: utc)

        let expected = try fm.contentsOfDirectory(atPath: sample.appendingPathComponent("days").path).sorted()
        let made = try fm.contentsOfDirectory(atPath: store.daysDirectory.path).sorted()
        XCTAssertEqual(made, expected, "the same days")
        for name in expected {
            let page = try String(contentsOf: sample.appendingPathComponent("days").appendingPathComponent(name), encoding: .utf8)
            let read = try String(contentsOf: store.daysDirectory.appendingPathComponent(name), encoding: .utf8)
            XCTAssertEqual(read, page, name)
        }
    }

    func testEveryLineOfTheSampleIsWrittenBackAsItWas() throws {
        let events = sample.appendingPathComponent("events")
        var kinds: Set<String> = []
        for name in try FileManager.default.contentsOfDirectory(atPath: events.path).sorted() {
            let text = try String(contentsOf: events.appendingPathComponent(name), encoding: .utf8)
            for line in text.split(separator: "\n") {
                let event = try JSONLines.decode(line)
                XCTAssertEqual(try JSONLines.encode(event), String(line), name)
                XCTAssertNotNil(event.kind, "\(name) holds a kind this build does not know: \(event.kindName)")
                kinds.insert(event.kindName)
                // One writer per file: the file is named for who wrote it and from where.
                XCTAssertEqual(name, "\(event.author.rawValue).\(event.device.rawValue).jsonl")
            }
        }
        // What the format page shows an example of, the sample has.
        let shown: Set<String> = ["entry.create", "entry.edit", "entry.delete", "media.attach", "note.add", "label.attach", "link", "done",
                                  "thing.set", "fact.set", "name.set", "grant.create", "loop.set", "loop.ran", "visit", "conditions.set"]
        XCTAssertEqual(shown.subtracting(kinds), [], "kinds the sample lacks")
    }

    // MARK: - Making the sample

    private func at(_ moment: String) -> Date {
        ISO8601DateFormatter().date(from: moment + ":00Z")!
    }

    /// A week of bread, in two days: the owner's lines from a phone, what the notebook's own
    /// originator made of them from a home, a walk from Health, the weather.
    private func writeSample() throws {
        let fm = FileManager.default
        try? fm.removeItem(at: sample)
        let me: Author = "me", health: Author = "health"
        let phone: DeviceID = "phone", home: DeviceID = "home"
        let created = at("2026-03-02T08:00")
        let store = try FileStore.create(at: sample, owner: me, id: ULID(timestamp: created), now: created)
        // Every writer makes its own ids, on its own device, as they go: one maker per file.
        var makers: [String: ULIDGenerator] = [:]
        func maker(_ author: Author, _ device: DeviceID) -> ULIDGenerator {
            let file = "\(author.rawValue).\(device.rawValue)"
            if let known = makers[file] { return known }
            let new = ULIDGenerator()
            makers[file] = new
            return new
        }
        var events: [Event] = []
        func say(_ payload: Payload, by author: Author, from device: DeviceID, _ moment: String) {
            let when = at(moment)
            events.append(Event(id: maker(author, device).next(at: when), author: author, device: device, at: when, payload: payload))
        }
        /// An id for a line, a thing or a grant, made by whoever is about to say it.
        func id(_ moment: String, by author: Author = "me", from device: DeviceID = "phone") -> ULID {
            maker(author, device).next(at: at(moment))
        }

        // The owner hands the notebook's own originator a key. Only its hash is written.
        let grant = id("2026-03-02T08:01")
        let keyHash = SHA256.hash(data: Data("a key that was shown once".utf8)).map { String(format: "%02x", $0) }.joined()
        say(.nameSet(.init(name: "Sam")), by: me, from: phone, "2026-03-02T08:01")
        say(.grantCreate(.init(grant: grant, author: .dotto, name: "The home", device: home, keyHash: keyHash,
                               may: ["notes", "labels", "links", "lines"])), by: me, from: phone, "2026-03-02T08:01")
        let loop = id("2026-03-02T08:02")
        say(.loopSet(.init(loop: loop, name: "Reading", grant: grant, wake: "line")), by: me, from: phone, "2026-03-02T08:02")

        // Monday. A line with a place, a line with a link, something to buy, a slip dropped.
        let fed = id("2026-03-02T08:05")
        say(.entryCreate(.init(entry: fed, text: "Starter fed. Smells of green apples.", startedAt: at("2026-03-02T08:05"),
                               location: Location(latitude: 52.3702, longitude: 4.8952, accuracy: 12))), by: me, from: phone, "2026-03-02T08:05")
        let recipe = id("2026-03-02T08:20")
        say(.entryCreate(.init(entry: recipe, text: "https://example.org/country-loaf", startedAt: at("2026-03-02T08:20"))),
            by: me, from: phone, "2026-03-02T08:20")
        let flour = id("2026-03-02T12:30")
        say(.entryCreate(.init(entry: flour, text: "Buy rye flour", startedAt: at("2026-03-02T12:30"))), by: me, from: phone, "2026-03-02T12:30")
        let slip = id("2026-03-02T12:31")
        say(.entryCreate(.init(entry: slip, text: "tset", startedAt: at("2026-03-02T12:31"))), by: me, from: phone, "2026-03-02T12:31")
        say(.entryDelete(.init(entry: slip)), by: me, from: phone, "2026-03-02T12:31")
        say(.entryEdit(.init(entry: flour, text: "Buy rye flour, the dark one")), by: me, from: phone, "2026-03-02T12:40")

        // The home reads, once per line that lands, and says what it made of it.
        say(.visit(.init(what: .days, count: 1)), by: .dotto, from: home, "2026-03-02T08:06")
        let starter = id("2026-03-02T08:06", by: .dotto, from: home)
        say(.thingSet(.init(thing: starter, name: "The starter", kind: "project")), by: .dotto, from: home, "2026-03-02T08:06")
        say(.link(.init(from: fed, to: starter)), by: .dotto, from: home, "2026-03-02T08:06")
        say(.labelAttach(.init(entry: fed, label: "bread")), by: .dotto, from: home, "2026-03-02T08:06")
        say(.conditionsSet(.init(entry: fed, conditions: Conditions(source: "open-meteo", temperature: 6.4, sky: 3, daylight: true, humidity: 81,
                                                                    wind: 14, windFrom: 230, rain: 0, rainBefore: 2.5, low: 3.1, high: 8.9))),
            by: .weather, from: phone, "2026-03-02T08:07")
        // The page the link leads to, kept beside the line: its words in a file named by their hash.
        let page = "# Country loaf\n\nFlour, water, salt and a starter. Two days, most of them waiting.\n"
        let pageHash = SHA256.hash(data: Data(page.utf8)).map { String(format: "%02x", $0) }.joined()
        try Data(page.utf8).write(to: store.mediaDirectory.appendingPathComponent("\(pageHash).md"))
        say(.mediaAttach(.init(entry: recipe, hash: pageHash, mime: "text/markdown", title: "Country loaf", source: "https://example.org/country-loaf")),
            by: me, from: home, "2026-03-02T08:21")
        say(.factSet(.init(on: flour, key: "todo", value: .words("buy rye flour"))), by: .dotto, from: home, "2026-03-02T12:31")
        say(.loopRan(.init(loop: loop, run: id("2026-03-02T12:31", by: .dotto, from: home), ok: true, turns: 4, cost: 0.03, summary: "Marked the flour as something to do.",
                           startedAt: at("2026-03-02T12:30"), endedAt: at("2026-03-02T12:31"))), by: .dotto, from: home, "2026-03-02T12:31")

        // Tuesday. A walk from Health on the owner's page, the flour bought, the loaf, a reply.
        let walk = id("2026-03-03T07:20", by: health)
        say(.nameSet(.init(name: "Health")), by: health, from: phone, "2026-03-03T08:02")
        say(.entryCreate(.init(entry: walk, text: "Walk, 3.1 km, 41 min", startedAt: at("2026-03-03T07:20"), page: me)), by: health, from: phone, "2026-03-03T08:02")
        let bought = id("2026-03-03T09:10")
        say(.entryCreate(.init(entry: bought, text: "Bought the rye flour, 2 kg", startedAt: at("2026-03-03T09:10"))), by: me, from: phone, "2026-03-03T09:10")
        say(.link(.init(from: bought, to: flour)), by: .dotto, from: home, "2026-03-03T09:11")
        say(.done(.init(entry: flour, by: bought)), by: .dotto, from: home, "2026-03-03T09:11")
        say(.factSet(.init(on: bought, key: "bought", value: .number(2, unit: "kg"))), by: .dotto, from: home, "2026-03-03T09:11")
        let loaf = id("2026-03-03T18:40")
        say(.entryCreate(.init(entry: loaf, text: "First loaf out. Dense, good crust. Why dense?", startedAt: at("2026-03-03T18:40"))),
            by: me, from: phone, "2026-03-03T18:40")
        say(.link(.init(from: loaf, to: starter)), by: .dotto, from: home, "2026-03-03T18:41")
        say(.labelAttach(.init(entry: loaf, label: "bread")), by: .dotto, from: home, "2026-03-03T18:41")
        say(.noteAdd(.init(entry: loaf, note: id("2026-03-03T18:41", by: .dotto, from: home), text: "A young starter, most likely: it is two days old. Give it a week of feeding.")),
            by: .dotto, from: home, "2026-03-03T18:41")

        try store.append(events)
        _ = try Projector.write(try store.load(), to: store, calendar: utc)
    }
}
