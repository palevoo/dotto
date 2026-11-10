import Foundation

// A streak: something kept up day after day, worked out from what is already in the
// notebook. Nothing is stored for it and nothing is counted by hand.
//
// A thing or a tag is a streak once it has a `since` moment. From the owner's line of 5
// November 2026, there are two ways one runs:
//
//   without   every day counts unless a line says it broke: no TikTok, no wine. The owner
//             states nothing while it holds; a break is what gets said.
//   with      a day counts when a line is with it: a walk, a page read. The owner, or a
//             source such as Health, states each day.
//
// What says so, all as facts:
//
//   since    on the thing, a moment: when it began. The newest stands, so beginning again
//            is a new `since`.
//   counts   on the thing, words: "with" for the second way; anything else is the first.
//   span     on the thing: how long it is meant to run, when it has an end.
//   ended    on the thing, a moment: stopped. One from before the newest `since` is void.
//   break    on a line that is with the thing: that day broke. A moment as its value names
//            the day it happened, for a line written the morning after; otherwise the day
//            is the line's own. It counts against every streak its line is with, so a line
//            that broke one and kept another is put only with the one it broke.
//
// It shows its run and its breaks, and that is all. It does not count days at anyone and
// never asks to be kept.

public struct Streak: Hashable, Sendable {
    public enum Counts: String, Hashable, Sendable {
        case without, with
    }

    /// How one day stands.
    public enum Mark: Hashable, Sendable {
        /// The day counts: kept, or done.
        case counted
        /// A line said it broke.
        case broken
        /// A day that asked for a line and had none.
        case missed
        /// Not settled: today with nothing said yet, or a day still ahead.
        case open
    }

    public struct Day: Hashable, Sendable, Identifiable {
        public let key: DayKey
        public let mark: Mark
        /// The line that says so: the one that broke it, or the first one with it that day.
        public let line: ULID?
        public let isToday: Bool

        public var id: DayKey { key }
    }

    public enum State: Hashable, Sendable {
        case running
        /// It ran its whole span.
        case complete
        /// It was stopped.
        case ended(Date)
    }

    public let counts: Counts
    public let since: Date
    /// Every day from the one it began on, through today or its last day, then the days
    /// still ahead when it has a span.
    public let days: [Day]
    /// The days in a row that count, up to now. Today is among them unless it broke; a day
    /// that waits for its line does not end the run before the day is over.
    public let run: Int
    /// The longest such row it has had.
    public let longest: Int
    public let breaks: Int
    /// How many days it is meant to run, from its span.
    public let goal: Int?
    public let state: State
}

public extension Thing {
    /// Whether it is a streak: it has a moment it began at.
    var isStreak: Bool {
        facts.contains { if $0.key == "since", case .moment = $0.value { return true }; return false }
    }
}

public extension Notebook {
    /// The facts of a thing that its streak already says, so its page does not say them twice.
    static let streakKeys: Set<String> = ["since", "counts", "span", "ended"]

    /// The streak a thing is, as of `now`; nil when it is not one.
    func streak(_ thing: Thing, at now: Date, calendar: Calendar) -> Streak? {
        func newest(_ key: String) -> Fact? { thing.facts.filter { $0.key == key }.max { ($0.at, $0.id) < ($1.at, $1.id) } }
        guard case .moment(let since)? = newest("since")?.value else { return nil }
        var counts = Streak.Counts.without
        if case .words(let said)? = newest("counts")?.value, said.trimmingCharacters(in: .whitespaces).lowercased() == "with" { counts = .with }
        var goal: Int?
        if case .span(let seconds)? = newest("span")?.value, seconds >= 86_400 { goal = Int((seconds / 86_400).rounded()) }
        var ended: Date?
        if case .moment(let at)? = newest("ended")?.value, at >= since { ended = at }

        let first = calendar.startOfDay(for: since)
        let today = calendar.startOfDay(for: now)
        guard first <= today else { return nil }
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: first) ?? first }
        func offset(of date: Date) -> Int { calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: date)).day ?? 0 }

        // The last day that is counted: today, or the day it was stopped, or the last of its span.
        var last = offset(of: today)
        if let ended { last = min(last, offset(of: ended)) }
        if let goal { last = min(last, goal - 1) }

        // What its lines say of each day.
        var broke: [Int: ULID] = [:]
        var with: [Int: ULID] = [:]
        for line in thing.lines.compactMap({ entry($0) }) {
            let breaks = line.facts("break")
            if breaks.isEmpty {
                let at = offset(of: line.startedAt)
                if with[at] == nil { with[at] = line.id }
            }
            for fact in breaks {
                var at = offset(of: line.startedAt)
                if case .moment(let happened) = fact.value { at = offset(of: happened) }
                if broke[at] == nil { broke[at] = line.id }
            }
        }

        let todayOffset = offset(of: today)
        var days: [Streak.Day] = []
        for index in 0...max(last, 0) {
            let isToday = index == todayOffset
            let mark: Streak.Mark
            let line: ULID?
            if let line_ = broke[index] {
                (mark, line) = (.broken, line_)
            } else if counts == .without {
                (mark, line) = (.counted, nil)
            } else if let line_ = with[index] {
                (mark, line) = (.counted, line_)
            } else {
                (mark, line) = (isToday && ended == nil ? .open : .missed, nil)
            }
            days.append(Streak.Day(key: DayKey(day(index), calendar: calendar), mark: mark, line: line, isToday: isToday))
        }

        // The run: back from the last counted day. A day still open does not end it.
        var run = 0
        for day in days.reversed() {
            if day.mark == .open { continue }
            guard day.mark == .counted else { break }
            run += 1
        }
        var longest = 0, row = 0
        for day in days {
            row = day.mark == .counted ? row + 1 : (day.mark == .open ? row : 0)
            longest = max(longest, row)
        }

        let state: Streak.State
        if let ended {
            state = .ended(ended)
        } else if let goal, offset(of: today) >= goal {
            state = .complete
        } else {
            state = .running
        }
        // The days still ahead, when it has an end and has not been stopped.
        if let goal, case .running = state, last + 1 < goal {
            for index in (last + 1)..<goal {
                days.append(Streak.Day(key: DayKey(day(index), calendar: calendar), mark: .open, line: nil, isToday: false))
            }
        }
        return Streak(counts: counts, since: since, days: days, run: run, longest: longest,
                      breaks: days.filter { $0.mark == .broken }.count, goal: goal, state: state)
    }
}
