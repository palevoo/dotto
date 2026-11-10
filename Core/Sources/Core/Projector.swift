import Foundation

/// Folds days into plain markdown files. Deterministic: the same events make the same bytes.
/// What someone opens without the app.
public enum Projector {
    /// One day as markdown.
    ///
    ///     # 2026-11-02 · Sunday
    ///
    ///     ## 09:14
    ///     Wall dimensions are 10 m total length on both sides, 1.5 m height, 30 cm width.
    ///
    ///     ![photo](../media/3f2a….jpg)
    ///
    ///     > Moss · 09:20
    ///     > Kept as a to-do.
    ///
    /// A note is signed with its author's chosen name when `names` has one, else their id.
    /// `things` names the things lines belong to, by id.
    public static func markdown(for day: Day, calendar: Calendar, names: [Author: String] = [:], things: [ULID: String] = [:]) -> String {
        var lines: [String] = []
        lines.append("# \(day.key) · \(weekday(day.key, calendar: calendar))")
        lines.append("")

        for entry in day.entries {
            // A line another originator put on this page wears its name beside the time.
            let by = entry.author == entry.page ? "" : " · \(names[entry.author] ?? entry.author.rawValue)"
            lines.append("## \(time(entry.startedAt, calendar: calendar))\(by)")
            if !entry.text.isEmpty {
                lines.append(entry.text)
            }
            for media in entry.media {
                lines.append("")
                lines.append(markdown(for: media))
            }
            for note in entry.notes {
                lines.append("")
                lines.append("> \(names[note.author] ?? note.author.rawValue) · \(time(note.at, calendar: calendar))")
                for noteLine in note.text.split(separator: "\n", omittingEmptySubsequences: false) {
                    lines.append("> \(noteLine)")
                }
                // The lines the note speaks of, each named by its day and time.
                if !note.cites.isEmpty {
                    lines.append("> _cites \(note.cites.map { moment($0.toAt, calendar: calendar) }.joined(separator: ", "))_")
                }
            }
            // The thread, as someone placed it, and done. The other line is named by its day and time.
            // Then what the line belongs to, and the facts on it, each signed.
            var threads = entry.carriesOn.map { "continues \(moment($0.toAt, calendar: calendar))" }
                + entry.carriedOnBy.map { "continued by \(moment($0.fromAt, calendar: calendar))" }
            if let done = entry.done {
                threads.append(done.byAt.map { "done by \(moment($0, calendar: calendar))" } ?? "done")
            }
            threads += entry.belongsTo.compactMap { link in things[link.to].map { "with \($0)" } }
            threads += entry.standingFacts.map { "\($0.key) \($0.value.words(calendar: calendar)) · \(names[$0.author] ?? $0.author.rawValue)" }
            if !threads.isEmpty {
                lines.append("")
                lines.append(contentsOf: threads.map { "_\($0)_" })
            }
            if !entry.labels.isEmpty {
                lines.append("")
                lines.append(entry.labels.map { "#\($0)" }.joined(separator: " "))
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Writes `days/YYYY-MM-DD.md` for every day with entries and removes files for days without.
    /// Returns the URLs written.
    @discardableResult
    public static func write(_ notebook: Notebook, to store: FileStore, calendar: Calendar) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: store.daysDirectory, withIntermediateDirectories: true)

        let days = notebook.days(calendar: calendar)
        var written: [URL] = []
        var keep: Set<String> = []

        for day in days {
            let name = "\(day.key).md"
            keep.insert(name)
            let url = store.daysDirectory.appendingPathComponent(name)
            let text = markdown(for: day, calendar: calendar, names: notebook.chosenNames, things: notebook.thingNames)
            let data = Data(text.utf8)
            if fm.contents(atPath: url.path) != data {
                try data.write(to: url, options: .atomic)
            }
            written.append(url)
        }

        for url in try fm.contentsOfDirectory(at: store.daysDirectory, includingPropertiesForKeys: nil)
        where url.pathExtension == "md" && !keep.contains(url.lastPathComponent) {
            try fm.removeItem(at: url)
        }

        return written
    }

    public static func markdown(for media: Media) -> String {
        let path = "../media/\(media.hash).\(fileExtension(forMIME: media.mime))"
        switch media.mime.split(separator: "/").first {
        case "image": return "![photo](\(path))"
        case "audio": return "[voice\(durationSuffix(media.duration))](\(path))"
        case "video": return "[video\(durationSuffix(media.duration))](\(path))"
        case "text": return "[kept: \(media.title ?? media.source ?? "a page")](\(path))" + (media.source.map { " from \($0)" } ?? "")
        default: return "[file](\(path))"
        }
    }

    public static func fileExtension(forMIME mime: String) -> String {
        switch mime.lowercased() {
        case "image/jpeg": "jpg"
        case "image/png": "png"
        case "image/heic": "heic"
        case "text/markdown": "md"
        case "text/plain": "txt"
        case "audio/mp4", "audio/m4a", "audio/x-m4a", "audio/aac": "m4a"
        case "video/quicktime": "mov"
        case "video/mp4": "mp4"
        default: "bin"
        }
    }

    // MARK: - Internals

    public static func time(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour!, parts.minute!)
    }

    /// `2026-11-02 17:16`.
    public static func moment(_ date: Date, calendar: Calendar) -> String {
        "\(DayKey(date, calendar: calendar)) \(time(date, calendar: calendar))"
    }

    static func weekday(_ key: DayKey, calendar: Calendar) -> String {
        guard let date = key.date(in: calendar) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    static func durationSuffix(_ seconds: Double?) -> String {
        guard let seconds else { return "" }
        let whole = Int(seconds.rounded())
        return String(format: " %d:%02d", whole / 60, whole % 60)
    }
}
