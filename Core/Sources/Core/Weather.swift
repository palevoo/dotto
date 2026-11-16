import Foundation

// The weather of a line.
//
// A line is stamped with when and where, and the weather follows from those two, so nothing
// new is captured and writing costs what it did. It is found out afterwards, by a source,
// and said once per line: with no signal it is said when the phone is back, and a line from
// June gets it like a line from today.
//
// It is the weather model's value for that square of land and that hour, not a measurement
// on the land. A station on the land would be another source, saying the same thing better.
//
// The source is Open-Meteo, whose data may be kept (CC BY 4.0). Apple's weather may not be
// stored, kept in a database or fetched for the past in bulk (Developer Program License
// Agreement, attachment 8, 1.5 and 1.6), which is all this does, so it cannot be the source.
// What is sent is a place rounded to about a kilometre and a span of days; nothing else.

public extension Author {
    /// The source that says what it was like where and when a line was written. It is
    /// called Weather without being named, as dotto is called dotto, and has no page: it
    /// writes no lines.
    static let weather: Author = "weather"
}

/// What it was like where and when a line was written. Metric, as the source gives it; a
/// page says it in the person's own units. Every value may be missing: a source says what
/// it knows.
public struct Conditions: Hashable, Codable, Sendable {
    /// Who the values are from: "open-meteo", later a station's own name.
    public var source: String
    /// Degrees Celsius, at the line's hour.
    public var temperature: Double?
    /// The sky, as the World Meteorological Organization's code: 0 clear, 61 light rain.
    public var sky: Int?
    /// Whether the sun was up.
    public var daylight: Bool?
    /// Relative humidity, percent.
    public var humidity: Double?
    /// Wind, kilometres an hour, and the direction it came from, degrees from north.
    public var wind: Double?
    public var windFrom: Double?
    /// Rain or snow in the line's hour, millimetres of water.
    public var rain: Double?
    /// Over the day before the line, the 24 hours up to its hour: how much fell, the
    /// coldest and the warmest. What a plant or a walk has just been through.
    public var rainBefore: Double?
    public var low: Double?
    public var high: Double?

    public init(source: String, temperature: Double? = nil, sky: Int? = nil, daylight: Bool? = nil, humidity: Double? = nil,
                wind: Double? = nil, windFrom: Double? = nil, rain: Double? = nil, rainBefore: Double? = nil,
                low: Double? = nil, high: Double? = nil) {
        self.source = source
        self.temperature = temperature
        self.sky = sky
        self.daylight = daylight
        self.humidity = humidity
        self.wind = wind
        self.windFrom = windFrom
        self.rain = rain
        self.rainBefore = rainBefore
        self.low = low
        self.high = high
    }

    /// The sky in words, when the code is one that has them.
    public var skyWords: String? { sky.flatMap(Sky.words) }

    /// Where the wind came from, as one of eight directions: "north-west".
    public var windFromWords: String? {
        guard let windFrom else { return nil }
        let names = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
        let index = Int(((windFrom.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 45).rounded()) % 8
        return names[index]
    }

    /// The hour itself, in a few words: "14 °C, light rain". For a list of lines.
    public var brief: String {
        [temperature.map { "\(Self.whole($0)) °C" }, skyWords].compactMap { $0 }.joined(separator: ", ")
    }

    /// Everything said, as the day files and the door say it: "14 °C, light rain, wind
    /// 12 km/h from the north-west, humidity 82 %; in the day before 9 to 17 °C, 3.1 mm of rain".
    public var words: String {
        var now = [brief].filter { !$0.isEmpty }
        if let wind {
            now.append("wind \(Self.whole(wind)) km/h" + (windFromWords.map { " from the \($0)" } ?? ""))
        }
        if let humidity { now.append("humidity \(Self.whole(humidity)) %") }
        var before: [String] = []
        if let low, let high { before.append("\(Self.whole(low)) to \(Self.whole(high)) °C") }
        if let rainBefore { before.append(rainBefore < 0.05 ? "no rain" : "\(Self.tenth(rainBefore)) mm of rain") }
        let parts = [now.joined(separator: ", "), before.isEmpty ? "" : "in the day before " + before.joined(separator: ", ")]
        return parts.filter { !$0.isEmpty }.joined(separator: "; ")
    }

    /// Nothing known at all: not worth saying.
    public var isEmpty: Bool {
        temperature == nil && sky == nil && humidity == nil && wind == nil && rain == nil && rainBefore == nil && low == nil && high == nil
    }

    static func whole(_ value: Double) -> String {
        let rounded = value.rounded()
        return String(Int(rounded == 0 ? 0 : rounded))   // never "-0"
    }

    static func tenth(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}

/// The sky's code in plain words. The codes are the WMO's, the ones weather models report.
public enum Sky {
    public static func words(_ code: Int) -> String? {
        switch code {
        case 0: "clear"
        case 1: "mostly clear"
        case 2: "partly cloudy"
        case 3: "overcast"
        case 45, 48: "fog"
        case 51: "light drizzle"
        case 53, 55: "drizzle"
        case 56, 57: "freezing drizzle"
        case 61: "light rain"
        case 63: "rain"
        case 65: "heavy rain"
        case 66, 67: "freezing rain"
        case 71: "light snow"
        case 73: "snow"
        case 75: "heavy snow"
        case 77: "snow grains"
        case 80: "light showers"
        case 81: "showers"
        case 82: "heavy showers"
        case 85, 86: "snow showers"
        case 95: "thunderstorm"
        case 96, 99: "thunderstorm with hail"
        default: nil
        }
    }
}

public extension Payload {
    /// What it was like where and when a line was written, said by a source after the fact.
    /// One per line: the newest word stands. It is not a mark on the line and nothing to be
    /// told about; it is what the line's own when and where come to. Written flat, the line
    /// beside the values.
    struct ConditionsSet: Hashable, Codable, Sendable {
        public var entry: ULID
        public var conditions: Conditions

        public init(entry: ULID, conditions: Conditions) {
            self.entry = entry
            self.conditions = conditions
        }

        enum CodingKeys: String, CodingKey { case entry }

        public init(from decoder: Decoder) throws {
            entry = try decoder.container(keyedBy: CodingKeys.self).decode(ULID.self, forKey: .entry)
            conditions = try Conditions(from: decoder)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(entry, forKey: .entry)
            try conditions.encode(to: encoder)
        }
    }

    /// The owner takes the weather off a line: one hold. Final, so no source says it again.
    struct ConditionsRemove: Hashable, Codable, Sendable {
        public var entry: ULID

        public init(entry: ULID) { self.entry = entry }
    }
}

/// Finding the weather out: which lines still want it, what to ask, and what the answer
/// says about each line. Nothing here keeps state; it is all worked out from the notebook.
public enum Weather {
    public static let source = "open-meteo"
    /// Who to thank, wherever the weather is shown: the licence asks for it.
    public static let credit = "Weather data by Open-Meteo.com"
    public static let creditLink = URL(string: "https://open-meteo.com/")!

    /// The first day the source's record of past hours holds.
    static let earliest = Date(timeIntervalSince1970: 1_640_995_200)   // 2022-01-01
    /// How far apart in time two lines at one place may be and still be asked for together,
    /// and how long one asking may span.
    static let gap: TimeInterval = 3 * 86_400
    static let longest: TimeInterval = 30 * 86_400
    static let hour: TimeInterval = 3600
    static let day: TimeInterval = 86_400

    /// The lines that have a place and nothing said about their weather yet, oldest first.
    /// A line whose weather the owner took off is settled, and so is one from before the
    /// record begins or from a moment that has not come.
    public static func waiting(in notebook: Notebook, now: Date) -> [Entry] {
        notebook.entries.filter { entry in
            entry.location != nil && !entry.conditionsSettled && entry.startedAt >= earliest && entry.startedAt <= now
        }
    }

    /// One question to the source: a place, a span of days, and the lines it is for.
    public struct Ask: Hashable, Sendable {
        /// Rounded to a hundredth of a degree, about a kilometre: as fine as the weather is
        /// known, and all of where the owner was that leaves the phone.
        public let latitude: Double
        public let longitude: Double
        /// The first and last day asked for, as the source counts days, in UTC.
        public let from: String
        public let to: String
        /// The lines, with their moments.
        public let lines: [Line]

        public struct Line: Hashable, Sendable {
            public let entry: ULID
            public let at: Date
        }

        public var url: URL {
            var parts = URLComponents(string: "https://historical-forecast-api.open-meteo.com/v1/forecast")!
            parts.queryItems = [
                URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
                URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
                URLQueryItem(name: "start_date", value: from),
                URLQueryItem(name: "end_date", value: to),
                URLQueryItem(name: "hourly", value: "temperature_2m,relative_humidity_2m,precipitation,weather_code,wind_speed_10m,wind_direction_10m,is_day"),
                URLQueryItem(name: "timeformat", value: "unixtime"),
                URLQueryItem(name: "timezone", value: "GMT"),
            ]
            return parts.url!
        }
    }

    /// The fewest questions that cover the lines: one per place and run of days. Lines within
    /// a kilometre of each other and a few days apart are one question.
    public static func asks(for entries: [Entry]) -> [Ask] {
        struct Square: Hashable { let latitude: Int; let longitude: Int }
        var bySquare: [Square: [Ask.Line]] = [:]
        for entry in entries {
            guard let place = entry.location else { continue }
            let square = Square(latitude: Int((place.latitude * 100).rounded()), longitude: Int((place.longitude * 100).rounded()))
            bySquare[square, default: []].append(Ask.Line(entry: entry.id, at: entry.startedAt))
        }
        var asks: [Ask] = []
        for (square, lines) in bySquare {
            var run: [Ask.Line] = []
            func close() {
                guard let first = run.first, let last = run.last else { return }
                asks.append(Ask(latitude: Double(square.latitude) / 100, longitude: Double(square.longitude) / 100,
                                from: utcDay(first.at.addingTimeInterval(-day)), to: utcDay(last.at.addingTimeInterval(hour)), lines: run))
                run = []
            }
            for line in lines.sorted(by: { ($0.at, $0.entry) < ($1.at, $1.entry) }) {
                if let first = run.first, let last = run.last,
                   line.at.timeIntervalSince(last.at) > gap || line.at.timeIntervalSince(first.at) > longest {
                    close()
                }
                run.append(line)
            }
            close()
        }
        return asks.sorted { ($0.lines[0].at, $0.lines[0].entry) < ($1.lines[0].at, $1.lines[0].entry) }
    }

    /// The source's answer: one row of values per hour.
    public struct Hours: Hashable, Sendable {
        public var times: [Date]
        public var temperature: [Double?]
        public var humidity: [Double?]
        public var rain: [Double?]
        public var sky: [Double?]
        public var wind: [Double?]
        public var windFrom: [Double?]
        public var daylight: [Double?]

        private struct Answer: Decodable {
            struct Hourly: Decodable {
                let time: [Double]
                let temperature_2m: [Double?]?
                let relative_humidity_2m: [Double?]?
                let precipitation: [Double?]?
                let weather_code: [Double?]?
                let wind_speed_10m: [Double?]?
                let wind_direction_10m: [Double?]?
                let is_day: [Double?]?
            }
            let hourly: Hourly?
            let error: Bool?
            let reason: String?
        }

        /// Reads what the source sent. Throws its own words when it refused.
        public init(data: Data) throws {
            let answer: Answer
            do {
                answer = try JSONDecoder().decode(Answer.self, from: data)
            } catch {
                throw Trouble.unreadable
            }
            guard let hourly = answer.hourly else { throw Trouble.refused(answer.reason ?? "no hours in the answer") }
            times = hourly.time.map { Date(timeIntervalSince1970: $0) }
            temperature = hourly.temperature_2m ?? []
            humidity = hourly.relative_humidity_2m ?? []
            rain = hourly.precipitation ?? []
            sky = hourly.weather_code ?? []
            wind = hourly.wind_speed_10m ?? []
            windFrom = hourly.wind_direction_10m ?? []
            daylight = hourly.is_day ?? []
        }

        /// What it was like at a moment: the values of the nearest hour, and the day before
        /// it. Nil when the answer does not reach that hour or knows nothing of it.
        public func conditions(at moment: Date) -> Conditions? {
            guard let index = times.indices.min(by: { abs(times[$0].timeIntervalSince(moment)) < abs(times[$1].timeIntervalSince(moment)) }),
                  abs(times[index].timeIntervalSince(moment)) <= Weather.hour / 2 else { return nil }
            func value(_ row: [Double?], _ at: Int) -> Double? { row.indices.contains(at) ? row[at] : nil }

            var said = Conditions(source: Weather.source)
            said.temperature = value(temperature, index).map(Self.tenth)
            said.sky = value(sky, index).map { Int($0) }
            said.daylight = value(daylight, index).map { $0 > 0 }
            said.humidity = value(humidity, index).map { $0.rounded() }
            said.wind = value(wind, index).map { $0.rounded() }
            said.windFrom = value(windFrom, index).map { $0.rounded() }
            said.rain = value(rain, index).map(Self.tenth)

            // The day before: the 24 hours that end with the line's own. Said only when
            // nearly all of them are known, so a total is never of half a day.
            let before = times.indices.filter { times[$0] > times[index].addingTimeInterval(-Weather.day) && times[$0] <= times[index] }
            let fallen = before.compactMap { value(rain, $0) }
            if fallen.count >= 22 { said.rainBefore = Self.tenth(fallen.reduce(0, +)) }
            let warmth = before.compactMap { value(temperature, $0) }
            if warmth.count >= 22 {
                said.low = warmth.min().map(Self.tenth)
                said.high = warmth.max().map(Self.tenth)
            }
            return said.isEmpty ? nil : said
        }

        private static func tenth(_ value: Double) -> Double { (value * 10).rounded() / 10 }
    }

    public enum Trouble: Error, Equatable, LocalizedError {
        case unreadable
        case refused(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable: "the answer could not be read"
            case .refused(let reason): reason
            }
        }
    }

    /// Asks the source. Nothing of the owner's goes but the question's own address: no
    /// cookies, nothing kept between askings.
    public static func fetch(_ ask: Ask, session: URLSession = quiet) async throws -> Hours {
        let (data, _) = try await session.data(from: ask.url)
        return try Hours(data: data)
    }

    /// A session that keeps nothing: no cookies, no cache, no credentials.
    public static let quiet: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    /// What an answer says about the lines it was asked for, as events in the source's name.
    /// A line the answer knows nothing of gets none.
    public static func events(for ask: Ask, from hours: Hours, device: DeviceID, ids: ULIDGenerator, now: Date) -> [Event] {
        ask.lines.compactMap { line in
            guard let conditions = hours.conditions(at: line.at) else { return nil }
            return Event(id: ids.next(at: now), author: .weather, device: device, at: now,
                         payload: .conditionsSet(.init(entry: line.entry, conditions: conditions)))
        }
    }

    /// "2026-11-10", the day a moment falls on in UTC, which is how the source counts days.
    static func utcDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}
