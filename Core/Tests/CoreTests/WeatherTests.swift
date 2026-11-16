import XCTest
@testable import Core

/// The weather of a line: what its own when and where come to, found out afterwards by a
/// source and said once per line.
final class WeatherTests: XCTestCase {
    private let me: Author = "me"
    private var utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()
    private var ids = ULIDGenerator()
    /// Tuesday 10 November 2026, 16:13 UTC.
    private let afternoon = Date(timeIntervalSince1970: 1_794_327_180)
    private let hill = Location(latitude: 54.4712, longitude: -3.1987, accuracy: 20)
    private let town = Location(latitude: 53.4084, longitude: -2.9916, accuracy: 10)

    private func line(_ text: String, at when: Date, place: Location? = nil, by author: Author = "me") -> (ULID, Event) {
        let id = ids.next(at: when)
        return (id, Event(id: id, author: author, device: "phone", at: when,
                          payload: .entryCreate(.init(entry: id, text: text, startedAt: when, location: place))))
    }

    private func said(_ entry: ULID, _ conditions: Conditions, by author: Author = .weather, at when: Date) -> Event {
        Event(id: ids.next(at: when), author: author, device: "phone", at: when, payload: .conditionsSet(.init(entry: entry, conditions: conditions)))
    }

    private let rainy = Conditions(source: "open-meteo", temperature: 14.2, sky: 61, daylight: true, humidity: 82, wind: 12, windFrom: 310,
                                   rain: 0.4, rainBefore: 3.1, low: 9, high: 17.4)

    // MARK: - The event

    func testItIsWrittenFlatAndReadsBack() throws {
        let entry = ULID(timestamp: afternoon)
        let event = Event(id: ULID(timestamp: afternoon.addingTimeInterval(2)), author: .weather, device: "phone", at: afternoon.addingTimeInterval(2),
                          payload: .conditionsSet(.init(entry: entry, conditions: Conditions(source: "open-meteo", temperature: 14.2, sky: 61, rainBefore: 3.1))))
        let written = try JSONLines.encode(event)
        XCTAssertTrue(written.contains(#""kind":"conditions.set""#))
        XCTAssertTrue(written.contains(#""payload":{"entry":"\#(entry)","rainBefore":3.1,"sky":61,"source":"open-meteo","temperature":14.2}"#),
                      "the line beside the values, and nothing for what is not known: \(written)")
        XCTAssertEqual(try JSONLines.decode(written), event)
    }

    // MARK: - The fold

    func testALineHoldsWhatASourceSaidAndTheNewestWordStands() throws {
        let (fig, figEvent) = line("Roots on one fig stick already", at: afternoon, place: hill)
        var notebook = Notebook(owner: me, events: [figEvent])
        XCTAssertNil(notebook.entry(fig)?.conditions)
        XCTAssertEqual(notebook.entry(fig)?.conditionsSettled, false)

        let first = said(fig, Conditions(source: "open-meteo", temperature: 13), at: afternoon.addingTimeInterval(5))
        let second = said(fig, rainy, at: afternoon.addingTimeInterval(60))
        // In either order of arrival, the newer word is the one that stands.
        notebook.apply(second)
        notebook.apply(first)
        let entry = try XCTUnwrap(notebook.entry(fig))
        XCTAssertEqual(entry.conditions, rainy)
        XCTAssertEqual(entry.conditionsFrom, .weather)
        XCTAssertTrue(entry.conditionsSettled)
        XCTAssertEqual(notebook.name(of: .weather), "Weather", "called Weather without being named")
    }

    func testItWaitsForALineThatHasNotArrived() throws {
        let (fig, figEvent) = line("The fig", at: afternoon, place: hill)
        var notebook = Notebook(owner: me, events: [said(fig, rainy, at: afternoon.addingTimeInterval(5))])
        XCTAssertNil(notebook.entry(fig))
        notebook.apply(figEvent)
        XCTAssertEqual(notebook.entry(fig)?.conditions, rainy)
    }

    func testTheOwnerTakesItOffWithOneHoldAndThatIsFinal() throws {
        let (fig, figEvent) = line("The fig", at: afternoon, place: hill)
        var notebook = Notebook(owner: me, events: [figEvent, said(fig, rainy, at: afternoon.addingTimeInterval(5))])

        // Nobody else takes it off.
        notebook.apply(Event(id: ids.next(at: afternoon.addingTimeInterval(10)), author: "friend", device: "x", at: afternoon.addingTimeInterval(10),
                             payload: .conditionsRemove(.init(entry: fig))))
        XCTAssertEqual(notebook.entry(fig)?.conditions, rainy)

        notebook.apply(Event(id: ids.next(at: afternoon.addingTimeInterval(20)), author: me, device: "phone", at: afternoon.addingTimeInterval(20),
                             payload: .conditionsRemove(.init(entry: fig))))
        XCTAssertNil(notebook.entry(fig)?.conditions)
        XCTAssertEqual(notebook.entry(fig)?.conditionsSettled, true, "settled, so it is not asked for again")

        // A source saying it again, from a phone that had not heard, changes nothing.
        notebook.apply(said(fig, rainy, at: afternoon.addingTimeInterval(3600)))
        XCTAssertNil(notebook.entry(fig)?.conditions)
        XCTAssertTrue(Weather.waiting(in: notebook, now: afternoon.addingTimeInterval(7200)).isEmpty)
    }

    /// Every line gets one, so it must be nothing to be told about: no row in the inbox, no
    /// news that would wake a reading, no page for the source, nothing in the notebook's log.
    func testItIsQuietEverywhereButOnTheLine() throws {
        let (fig, figEvent) = line("The fig", at: afternoon, place: hill)
        let events = [figEvent, said(fig, rainy, at: afternoon.addingTimeInterval(5))]
        let notebook = Notebook(owner: me, events: events)
        let files = [(file: "all", events: events)]

        XCTAssertEqual(notebook.others, [], "a source that writes no lines has no page")
        XCTAssertEqual(notebook.trail, [], "and the log says nothing of it")
        XCTAssertTrue(Inbox.items(files: files, notebook: notebook, calendar: utc).isEmpty)

        let grant = Grant(name: "Claude Code", author: .dotto, device: "the-reading", createdAt: afternoon.addingTimeInterval(1))
        let report = Inbox.pending(files: files, notebook: notebook, grant: grant, calendar: utc)
        XCTAssertEqual(report.count, 0, "weather alone wakes nobody")

        // The line's own history does say it, once.
        XCTAssertEqual(notebook.entry(fig)?.activity.map(\.what), ["said what it was like here: 14 °C, light rain"])
    }

    // MARK: - Which lines want it, and what to ask

    func testALineWithAPlaceAndNothingSaidIsWaiting() {
        let (fig, figEvent) = line("The fig", at: afternoon, place: hill)
        let (_, noPlace) = line("Written on the Mac", at: afternoon.addingTimeInterval(60))
        let (_, old) = line("Before the record begins", at: Date(timeIntervalSince1970: 1_600_000_000), place: hill)
        let (known, knownEvent) = line("Already said", at: afternoon.addingTimeInterval(120), place: hill)
        let notebook = Notebook(owner: me, events: [figEvent, noPlace, old, knownEvent, said(known, rainy, at: afternoon.addingTimeInterval(130))])

        XCTAssertEqual(Weather.waiting(in: notebook, now: afternoon.addingTimeInterval(3600)).map(\.id), [fig])
        XCTAssertTrue(Weather.waiting(in: notebook, now: afternoon.addingTimeInterval(-3600)).isEmpty, "a moment that has not come has no weather yet")
    }

    func testLinesNearEachOtherInPlaceAndTimeAreOneQuestion() throws {
        // Two on the hill the same afternoon, fifty metres apart; one on the hill a week
        // later; one in the town that evening.
        let nearby = Location(latitude: 54.4716, longitude: -3.1991)
        let (a, aEvent) = line("Fig", at: afternoon, place: hill)
        let (b, bEvent) = line("Seeds", at: afternoon.addingTimeInterval(600), place: nearby)
        let (c, cEvent) = line("A week on", at: afternoon.addingTimeInterval(7 * 86_400), place: hill)
        let (d, dEvent) = line("Home", at: afternoon.addingTimeInterval(4 * 3600), place: town)
        let notebook = Notebook(owner: me, events: [aEvent, bEvent, cEvent, dEvent])

        let asks = Weather.asks(for: Weather.waiting(in: notebook, now: afternoon.addingTimeInterval(30 * 86_400)))
        XCTAssertEqual(asks.map { $0.lines.map(\.entry) }, [[a, b], [d], [c]])

        let first = asks[0]
        XCTAssertEqual(first.latitude, 54.47)
        XCTAssertEqual(first.longitude, -3.2)
        XCTAssertEqual(first.from, "2026-11-09", "the day before, for what fell before the line")
        XCTAssertEqual(first.to, "2026-11-10")
        let url = first.url.absoluteString
        XCTAssertTrue(url.hasPrefix("https://historical-forecast-api.open-meteo.com/v1/forecast?latitude=54.47&longitude=-3.20&start_date=2026-11-09&end_date=2026-11-10&hourly="))
        XCTAssertFalse(url.contains("54.4712"), "the place leaves rounded to about a kilometre, never as it was found")
        XCTAssertTrue(url.hasSuffix("&timeformat=unixtime&timezone=GMT"))
    }

    // MARK: - What the answer says

    /// Forty-eight hours from 9 November 00:00 UTC, as the source sends them: an hour of
    /// rain each night, the afternoon mild, one value missing.
    private func answer() -> Data {
        let start = 1_794_182_400.0   // 2026-11-09 00:00 UTC
        let times = (0..<48).map { start + Double($0) * 3600 }
        let temperature = (0..<48).map { hour -> String in
            let ofDay = hour % 24
            return String(format: "%.1f", 9.0 + 8.4 * sin(Double(max(0, ofDay - 6)) / 18.0 * .pi))
        }
        var rain = Array(repeating: "0.00", count: 48)
        rain[3] = "1.20"      // 9 Nov 03:00, more than a day before the line
        rain[27] = "2.70"     // 10 Nov 03:00
        rain[40] = "0.40"     // 10 Nov 16:00, the line's own hour
        var code = Array(repeating: "1", count: 48)
        code[40] = "61"
        var humidity = Array(repeating: "70", count: 48)
        humidity[40] = "82"
        humidity[10] = "null"
        func row(_ values: [String]) -> String { "[" + values.joined(separator: ",") + "]" }
        let json = """
        {"latitude":54.47,"longitude":-3.2,"hourly_units":{"time":"unixtime"},"hourly":{"time":\(row(times.map { String(Int($0)) })),\
        "temperature_2m":\(row(temperature)),"relative_humidity_2m":\(row(humidity)),"precipitation":\(row(rain)),\
        "weather_code":\(row(code)),"wind_speed_10m":\(row(Array(repeating: "12.3", count: 48))),\
        "wind_direction_10m":\(row(Array(repeating: "310", count: 48))),"is_day":\(row((0..<48).map { (7...17).contains($0 % 24) ? "1" : "0" }))}}
        """
        return Data(json.utf8)
    }

    func testTheNearestHourAndTheDayBeforeIt() throws {
        let hours = try Weather.Hours(data: answer())
        XCTAssertEqual(hours.times.count, 48)

        // 16:13 is nearest 16:00.
        let conditions = try XCTUnwrap(hours.conditions(at: afternoon))
        XCTAssertEqual(conditions.source, "open-meteo")
        XCTAssertEqual(conditions.sky, 61)
        XCTAssertEqual(conditions.skyWords, "light rain")
        XCTAssertEqual(conditions.daylight, true)
        XCTAssertEqual(conditions.humidity, 82)
        XCTAssertEqual(conditions.wind, 12)
        XCTAssertEqual(conditions.windFromWords, "north-west")
        XCTAssertEqual(conditions.rain, 0.4)
        XCTAssertEqual(conditions.rainBefore, 3.1, "the night's rain and the hour's own; the night before that is more than a day back")
        XCTAssertEqual(conditions.low, 9)
        XCTAssertEqual(conditions.high, 17.4)
        XCTAssertEqual(conditions.brief, "\(Conditions.whole(conditions.temperature!)) °C, light rain")
        XCTAssertTrue(conditions.words.hasSuffix("wind 12 km/h from the north-west, humidity 82 %; in the day before 9 to 17 °C, 3.1 mm of rain"), conditions.words)
    }

    func testAnHourTheAnswerDoesNotReachSaysNothing() throws {
        let hours = try Weather.Hours(data: answer())
        XCTAssertNil(hours.conditions(at: afternoon.addingTimeInterval(3 * 86_400)))
        // Early on the first day the hour is known but not the day before it: a total is
        // never of half a day.
        let early = try XCTUnwrap(hours.conditions(at: Date(timeIntervalSince1970: 1_794_182_400 + 5 * 3600)))
        XCTAssertNotNil(early.temperature)
        XCTAssertNil(early.rainBefore)
        XCTAssertNil(early.low)
    }

    func testARefusalIsSaidInTheSourcesOwnWords() {
        XCTAssertThrowsError(try Weather.Hours(data: Data(#"{"error":true,"reason":"Daily API request limit exceeded."}"#.utf8))) { error in
            XCTAssertEqual(error as? Weather.Trouble, .refused("Daily API request limit exceeded."))
        }
        XCTAssertThrowsError(try Weather.Hours(data: Data("<html>".utf8))) { error in
            XCTAssertEqual(error as? Weather.Trouble, .unreadable)
        }
    }

    func testAnAnswerBecomesOneEventPerLineItKnows() throws {
        let (fig, figEvent) = line("Fig", at: afternoon, place: hill)
        let (late, lateEvent) = line("Two days on", at: afternoon.addingTimeInterval(2 * 86_400), place: hill)
        var notebook = Notebook(owner: me, events: [figEvent, lateEvent])
        let ask = try XCTUnwrap(Weather.asks(for: Weather.waiting(in: notebook, now: afternoon.addingTimeInterval(5 * 86_400))).first)
        XCTAssertEqual(ask.lines.map(\.entry), [fig, late])

        // The answer only reaches the first of them.
        let now = afternoon.addingTimeInterval(5 * 86_400)
        let events = Weather.events(for: ask, from: try Weather.Hours(data: answer()), device: "phone", ids: ids, now: now)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].author, .weather)
        notebook.apply(events)
        XCTAssertEqual(notebook.entry(fig)?.conditions?.sky, 61)
        XCTAssertEqual(Weather.waiting(in: notebook, now: now).map(\.id), [late])
    }

    // MARK: - As it is read

    func testTheDayFileAndTheDoorSayWhereAndWhatItWasLike() throws {
        let (fig, figEvent) = line("Roots on one fig stick already", at: afternoon, place: hill)
        let notebook = Notebook(owner: me, events: [figEvent, said(fig, rainy, at: afternoon.addingTimeInterval(5))])
        let day = try XCTUnwrap(notebook.days(calendar: utc).first)
        XCTAssertEqual(
            Projector.markdown(for: day, calendar: utc, names: notebook.chosenNames),
            """
            # 2026-11-10 · Tuesday

            ## 16:13
            Roots on one fig stick already

            _where 54.47, -3.20_
            _weather 14 °C, light rain, wind 12 km/h from the north-west, humidity 82 %; in the day before 9 to 17 °C, 3.1 mm of rain · Weather_

            """)
    }

    func testWordsForADryStillDay() {
        let dry = Conditions(source: "open-meteo", temperature: -0.2, sky: 0, rainBefore: 0, low: -3.6, high: 4)
        XCTAssertEqual(dry.words, "0 °C, clear; in the day before -4 to 4 °C, no rain")
        XCTAssertEqual(Conditions(source: "station").words, "")
        XCTAssertTrue(Conditions(source: "station").isEmpty)
    }
}
