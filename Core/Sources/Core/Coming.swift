import Foundation

// What is coming, and what the phone says about it ahead of time.
//
// Two facts carry a moment, and they mean different things. `at` is when something happens,
// whether or not the owner does anything: an appointment, a class, a booking. It passes by
// itself and is never to do. `due` is when something wants the owner: a todo to be done by
// then, or a plain reminder. Said by the owner on 10 November 2026, after an appointment was
// marked todo: "Appointment ain't a freaking todo."

public extension Entry {
    /// When it happens, if it is an event: the earliest `at` anyone put.
    var at: Date? {
        facts("at").compactMap { if case .moment(let at) = $0.value { return at }; return nil }.min()
    }

    /// The moment the line carries, whichever kind: when it happens, else when it is due.
    var moment: Date? { at ?? due }
}

/// One thing the phone says ahead of a moment, or at it. Worked out from the fold, so a
/// moment moved, taken off or finished changes what is said with nothing else to undo.
public struct Notice: Hashable, Sendable, Identifiable {
    /// Stable for the same line, kind and moment, so scheduling again changes nothing.
    public let id: String
    public let entry: ULID
    /// When it is shown.
    public let fire: Date
    /// The moment it is about.
    public let moment: Date
    /// "Tomorrow at 11:00", "In an hour, at 11:00", "Now".
    public let title: String
    /// The line's own words.
    public let body: String
    /// Something to do, which can be finished from the notice itself.
    public let todo: Bool

    /// What the Mac compares against before sending its own push for a moment.
    public var key: String { Notice.key(entry: entry, moment: moment) }

    public static func key(entry: ULID, moment: Date) -> String {
        "\(entry.string)|\(Int(moment.timeIntervalSince1970))"
    }
}

public extension Notebook {
    /// The owner's lines with a moment still ahead of `now` and not done, soonest first:
    /// events and what is due, together, since both are what is coming.
    func coming(after now: Date) -> [Entry] {
        entries.compactMap { entry -> (Entry, Date)? in
            guard entry.done == nil, let moment = entry.moment, moment > now else { return nil }
            return (entry, moment)
        }
        .sorted { ($0.1, $0.0.id) < ($1.1, $1.0.id) }
        .map(\.0)
    }

    /// How long before an event the phone says it is near.
    static let eventLead: TimeInterval = 3600
    /// The hour, the evening before an event, at which the phone says it is tomorrow.
    static let eveningHour = 20

    /// What the phone should say, and when, for what is coming: the soonest `limit`, since
    /// a phone holds only so many at once and is asked again every time the app runs.
    ///
    /// An event is said twice, ahead: the evening before, and an hour before. Something
    /// due is said once, at its moment. Nothing is said for a moment already past.
    func notices(after now: Date, calendar: Calendar, limit: Int = 60) -> [Notice] {
        var notices: [Notice] = []
        for entry in coming(after: now) {
            let body = entry.text.isEmpty ? "a photo" : entry.text
            let stamp = Int((entry.moment ?? now).timeIntervalSince1970)
            func notice(_ kind: String, at fire: Date, _ title: String, moment: Date) {
                guard fire > now else { return }
                notices.append(Notice(id: "notice|\(entry.id.string)|\(kind)|\(stamp)", entry: entry.id, fire: fire, moment: moment,
                                      title: title, body: body, todo: entry.todo == .open))
            }
            if let at = entry.at {
                let time = Self.clock(at, calendar: calendar)
                // The evening before, when there is one between now and the event's day.
                if let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: at)),
                   let evening = calendar.date(bySettingHour: Self.eveningHour, minute: 0, second: 0, of: dayBefore) {
                    notice("eve", at: evening, "Tomorrow at \(time)", moment: at)
                }
                notice("near", at: at.addingTimeInterval(-Self.eventLead), "In an hour, at \(time)", moment: at)
            } else if let due = entry.due {
                notice("due", at: due, entry.todo == .open ? "Due now" : "Now", moment: due)
            }
        }
        return Array(notices.sorted { ($0.fire, $0.id) < ($1.fire, $1.id) }.prefix(limit))
    }

    /// "11:00", by the calendar's own clock.
    static func clock(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
