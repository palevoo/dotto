#if DEBUG
import Core
import UIKit

/// Lines for the UI tests, made on launch when asked for with `-uitest-seed-photos`: one
/// line with two photos of printed words, so the viewer has pages to turn and words for
/// Live Text to find. Debug builds only; made once per notebook.
@MainActor
enum Seed {
    static let words = "Two pages from a book, for the viewer"
    static let pages = [
        "Writing costs nothing. One gesture, no categories, no decisions, no audience.",
        "Meaning comes later. What a line is, what it connects to, what it should trigger, is decided after it is written.",
    ]

    static func runIfAsked(_ model: NotebookModel) async {
        // A test's notebook is new, and so is what Setup has switched on: the weather is off
        // until a test says otherwise, and no test ever asks the real source.
        if ProcessInfo.processInfo.arguments.contains("-uitest-notebook") {
            model.weather.turnOff()
            model.weather.ask = { try Weather.Hours(data: answer(to: $0)) }
        }
        seedYesterdayIfAsked(model)
        guard ProcessInfo.processInfo.arguments.contains("-uitest-seed-photos") else { return }
        let line: ULID
        if let existing = model.notebook.entries.first(where: { $0.text == words }) {
            line = existing.id
        } else {
            for page in pages {
                await model.addPhoto(render(page))
            }
            model.draftText = words
            guard let made = model.commitDraft() else { return }
            line = made
        }
        let seed = Author(rawValue: "seed")
        // A tag on the line, placed by another originator, as the owner never files.
        if model.notebook.entry(line)?.labels.contains("book") != true {
            try? model.store.append(Event(id: ULID(), author: seed, device: model.device, at: Date(),
                                          payload: .labelAttach(.init(entry: line, label: "book"))))
        }
        // A second line, and a note under the first that cites it.
        let second: ULID
        if let existing = model.notebook.entries.first(where: { $0.text == cited }) {
            second = existing.id
        } else {
            model.draftText = cited
            guard let made = model.commitDraft() else { return }
            second = made
        }
        if model.notebook.entry(line)?.notes.contains(where: { !$0.cites.isEmpty }) != true {
            let note = ULID()
            try? model.store.append(Event(id: note, author: seed, device: model.device, at: Date(),
                                          payload: .noteAdd(.init(entry: line, note: note, text: citing))))
            try? model.store.append(Event(id: ULID(), author: seed, device: model.device, at: Date(),
                                          payload: .link(.init(from: note, to: second))))
        }
        // A thing the second line belongs to, with its state, and a fact on the first line.
        if !model.notebook.allThings.contains(where: { $0.name == thing }) {
            let fig = ULID()
            try? model.store.append([
                Event(id: fig, author: seed, device: model.device, at: Date(), payload: .thingSet(.init(thing: fig, name: thing, kind: "plant"))),
                Event(id: ULID(), author: seed, device: model.device, at: Date(), payload: .link(.init(from: second, to: fig))),
                Event(id: ULID(), author: seed, device: model.device, at: Date(), payload: .factSet(.init(on: fig, key: "state", value: .words("potted")))),
                Event(id: ULID(), author: seed, device: model.device, at: Date(), payload: .factSet(.init(on: fig, key: "about", value: .words(about)))),
                Event(id: ULID(), author: seed, device: model.device, at: Date(), payload: .factSet(.init(on: fig, key: "source", value: .words(source)))),
                Event(id: ULID(), author: seed, device: model.device, at: Date(), payload: .factSet(.init(on: line, key: "pages", value: .number(2, unit: nil)))),
            ])
        }
        // What the second line points at, kept beside it, as the home keeps a page.
        if model.notebook.entry(second)?.media.contains(where: \.isKept) != true,
           let hash = try? model.store.storeMedia(Data("# \(keptTitle)\n\nKept from \(source)\n\n\(keptWords)\n".utf8), fileExtension: "md") {
            try? model.store.append(Event(id: ULID(), author: model.store.manifest.owner, device: model.device, at: Date(),
                                          payload: .mediaAttach(.init(entry: second, hash: hash, mime: "text/markdown", title: keptTitle, source: source))))
        }
        // Something to do, due tomorrow, so the todos page has a line.
        if model.notebook.entry(second)?.facts("todo").isEmpty != false {
            try? model.store.append([
                Event(id: ULID(), author: seed, device: model.device, at: Date(), payload: .factSet(.init(on: second, key: "todo", value: .words("open")))),
                Event(id: ULID(), author: seed, device: model.device, at: Date(),
                      payload: .factSet(.init(on: second, key: "due", value: .moment(Date().addingTimeInterval(86_400))))),
            ])
        }
        // A grant for the seed, so a loop can run as it, and a loop it proposes.
        let seedGrant = model.notebook.allGrants.first { $0.author == seed } ?? Grant(name: "Seed", author: seed, device: "seed")
        if !model.notebook.allGrants.contains(where: { $0.author == seed }) {
            try? model.store.append(Event(id: ULID(), author: model.store.manifest.owner, device: model.device, at: Date(),
                                          payload: .grantCreate(seedGrant.create)))
        }
        if model.notebook.loopProposals.isEmpty, !model.notebook.allLoops.contains(where: { $0.name == proposal }) {
            let id = ULID()
            try? model.store.append(Event(id: id, author: seed, device: model.device, at: Date(),
                                          payload: .loopPropose(.init(loop: id, name: proposal, grant: seedGrant.id, wake: "line",
                                                                      brief: "Each walk as a line, in Health's name."))))
        }
        // A walk, as Health would put it on the owner's page under its own name.
        if !model.notebook.entries.contains(where: { $0.text == walk }) {
            let health = NotebookModel.health
            var events: [Event] = []
            if model.notebook.name(of: health) == nil {
                events.append(Event(id: ULID(), author: health, device: model.device, at: Date(), payload: .nameSet(.init(name: "Health"))))
            }
            let id = ULID()
            events.append(Event(id: id, author: health, device: model.device, at: Date(),
                                payload: .entryCreate(.init(entry: id, text: walk, startedAt: Date(), page: model.store.manifest.owner))))
            try? model.store.append(events)
        }
        // A plain line of the owner's that nothing is made of, so one line is read with
        // nothing said and wears no other mark.
        if !model.notebook.entries.contains(where: { $0.text == plain }) {
            model.draftText = plain
            _ = model.commitDraft()
        }
        // And an event on it, the day after tomorrow: something that happens, not to do.
        if let quiet = model.notebook.entries.first(where: { $0.text == plain }), quiet.at == nil {
            try? model.store.append(Event(id: ULID(), author: seed, device: model.device, at: Date(),
                                          payload: .factSet(.init(on: quiet.id, key: "at", value: .moment(Date().addingTimeInterval(2 * 86_400))))))
        }
        // A streak begun three days ago, which the quiet line says broke yesterday.
        if !model.notebook.allThings.contains(where: { $0.name == streak }),
           let quiet = model.notebook.entries.first(where: { $0.text == plain }) {
            let id = ULID()
            try? model.store.append([
                Event(id: id, author: seed, device: model.device, at: Date(), payload: .thingSet(.init(thing: id, name: streak, kind: "streak"))),
                Event(id: ULID(), author: seed, device: model.device, at: Date(),
                      payload: .factSet(.init(on: id, key: "since", value: .moment(Date().addingTimeInterval(-3 * 86_400))))),
                Event(id: ULID(), author: seed, device: model.device, at: Date(), payload: .link(.init(from: quiet.id, to: id))),
                Event(id: ULID(), author: seed, device: model.device, at: Date(),
                      payload: .factSet(.init(on: quiet.id, key: "break", value: .moment(Date().addingTimeInterval(-86_400))))),
            ])
        }
        // A line with a place and nothing said about its weather yet: what Setup's switch fills.
        if !model.notebook.entries.contains(where: { $0.text == placed }) {
            let at = Date().addingTimeInterval(-600)
            let id = ULID(timestamp: at)
            try? model.store.append(Event(id: id, author: model.store.manifest.owner, device: model.device, at: at,
                                          payload: .entryCreate(.init(entry: id, text: placed, startedAt: at,
                                                                      location: Location(latitude: 39.4712, longitude: -8.1987, accuracy: 20)))))
        }
        // The weather where and when the quiet line was written, as the source would say it.
        if let quiet = model.notebook.entries.first(where: { $0.text == plain }), quiet.conditions == nil {
            try? model.store.append(Event(id: ULID(), author: .weather, device: model.device, at: Date(),
                                          payload: .conditionsSet(.init(entry: quiet.id, conditions: weather))))
        }
        // The seed has looked: everything written so far is taken in, so the lines it left
        // nothing under are read with nothing said.
        if !model.notebook.visits.contains(where: { $0.author == seed && $0.read.what == .inbox }),
           let files = try? model.store.loadEventsByFile() {
            try? model.store.append(Event(id: ULID(), author: seed, device: model.device, at: Date(),
                                          payload: .visit(.init(what: .inbox, count: 2,
                                                                seen: Dictionary(uniqueKeysWithValues: files.map { ($0.file, $0.events.count) })))))
        }
        model.reload()
    }

    /// `-uitest-seed-yesterday <n>`: n lines of the owner's on the day before today, enough to
    /// make that day taller than the screen, so the page can be tried on the first line of a
    /// new day. Made once per notebook.
    static func seedYesterdayIfAsked(_ model: NotebookModel) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-uitest-seed-yesterday"), arguments.indices.contains(flag + 1),
              let count = Int(arguments[flag + 1]), count > 0,
              !model.notebook.entries.contains(where: { $0.text == yesterdayLine(1) }),
              let morning = model.calendar.date(byAdding: .day, value: -1, to: model.calendar.startOfDay(for: Date()))?.addingTimeInterval(9 * 3600)
        else { return }
        let ids = ULIDGenerator()
        let owner = model.store.manifest.owner
        let events = (1...count).map { number -> Event in
            let at = morning.addingTimeInterval(Double(number) * 60)
            let id = ids.next(at: at)
            return Event(id: id, author: owner, device: model.device, at: at,
                         payload: .entryCreate(.init(entry: id, text: yesterdayLine(number), startedAt: at)))
        }
        try? model.store.append(events)
        model.reload()
    }

    static func yesterdayLine(_ number: Int) -> String { "A line from yesterday, number \(number)" }

    static let about = "A fig cutting taken in September, rooted in water and potted in November."
    static let source = "https://example.com/figs/cuttings"
    static let plain = "A quiet afternoon"
    static let streak = "no sugar"
    static let keptTitle = "Rooting fig cuttings"
    static let keptWords = "Take a cutting in late summer. Keep it in water until roots show, then pot it."

    static let weather = Conditions(source: Weather.source, temperature: 14.2, sky: 61, daylight: true, humidity: 82, wind: 12, windFrom: 310,
                                    rain: 0.4, rainBefore: 3.1, low: 9, high: 17.4)
    static let placed = "Olives under the nets"

    /// What the source would send for a question: every hour from the day before the first
    /// line to the hour after the last, overcast and still, with a little rain each hour.
    static func answer(to ask: Weather.Ask) -> Data {
        let first = (ask.lines.map(\.at).min() ?? Date()).addingTimeInterval(-26 * 3600)
        let last = (ask.lines.map(\.at).max() ?? Date()).addingTimeInterval(2 * 3600)
        let start = (first.timeIntervalSince1970 / 3600).rounded(.down) * 3600
        let count = Int((last.timeIntervalSince1970 - start) / 3600) + 1
        func row(_ value: String) -> String { "[" + Array(repeating: value, count: count).joined(separator: ",") + "]" }
        let times = (0..<count).map { String(Int(start) + $0 * 3600) }.joined(separator: ",")
        return Data("""
        {"hourly":{"time":[\(times)],"temperature_2m":\(row("11.0")),"relative_humidity_2m":\(row("90")),"precipitation":\(row("0.1")),\
        "weather_code":\(row("3")),"wind_speed_10m":\(row("4")),"wind_direction_10m":\(row("180")),"is_day":\(row("1"))}}
        """.utf8)
    }

    static let walk = "Walk, 3.1 km, 41 min"
    static let thing = "the fig"
    static let proposal = "Bring the walks"
    static let cited = "Meaning comes later, says the second page"
    static let citing = "Both pages say the same; see the second."

    /// A page of a book: black serif on white, large enough for Live Text.
    static func render(_ text: String) -> Data {
        let size = CGSize(width: 1200, height: 1600)
        return UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 18
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.serif(56), .foregroundColor: UIColor.black, .paragraphStyle: paragraph,
            ]
            (text as NSString).draw(in: CGRect(x: 120, y: 220, width: 960, height: 1200), withAttributes: attributes)
        }
    }
}
#endif
