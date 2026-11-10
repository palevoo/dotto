import XCTest
@testable import Core

/// A streak is worked out from the notebook: when it began, what its lines say, and the day
/// it is asked on. Nothing is stored for it.
final class StreakTests: XCTestCase {
    private let me: Author = "me"
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private var ids = ULIDGenerator()
    /// Thursday 5 November 2026, 07:53 UTC: the morning the detox began.
    private let began = Date(timeIntervalSince1970: 1_793_865_180)

    private func at(_ days: Double, _ hours: Double = 0) -> Date { began.addingTimeInterval(days * 86_400 + hours * 3600) }

    private func event(_ payload: Payload, by author: Author = "weeju", at when: Date) -> Event {
        Event(id: ids.next(at: when), author: author, device: "test", at: when, payload: payload)
    }

    private func line(_ text: String, at when: Date) -> (ULID, Event) {
        let id = ids.next(at: when)
        return (id, Event(id: id, author: me, device: "phone", at: when, payload: .entryCreate(.init(entry: id, text: text, startedAt: when))))
    }

    /// Without: every day counts unless a line says it broke. A break said the morning after
    /// names the day it happened. The run starts again the day after a break.
    func testADayCountsUnlessALineSaysItBroke() throws {
        let detox = ULID(timestamp: began)
        let (first, firstEvent) = line("A day without YouTube and TikTok", at: began)
        let (after, afterEvent) = line("YouTube I did watch yesterday in the evening", at: at(2, 7))
        var notebook = Notebook(owner: me, events: [
            firstEvent, afterEvent,
            event(.thingSet(.init(thing: detox, name: "the detox", kind: "streak")), at: began),
            event(.factSet(.init(on: detox, key: "since", value: .moment(began))), at: began),
            event(.link(.init(from: first, to: detox)), at: began),
            event(.link(.init(from: after, to: detox)), at: at(2, 7)),
        ])
        let thing = try XCTUnwrap(notebook.thing(detox))
        XCTAssertTrue(thing.isStreak)

        // Tuesday 10 November, the sixth day, nothing broken.
        var streak = try XCTUnwrap(notebook.streak(notebook.thing(detox)!, at: at(5, 3), calendar: calendar))
        XCTAssertEqual(streak.counts, .without)
        XCTAssertEqual(streak.days.count, 6)
        XCTAssertEqual(streak.run, 6, "the day it began is the first, today the sixth")
        XCTAssertEqual(streak.breaks, 0)
        XCTAssertEqual(streak.state, .running)
        XCTAssertTrue(streak.days.last!.isToday)

        // The line written on the 7th says the 6th broke.
        notebook.apply(event(.factSet(.init(on: after, key: "break", value: .moment(at(1, 12)))), at: at(2, 7)))
        streak = try XCTUnwrap(notebook.streak(notebook.thing(detox)!, at: at(5, 3), calendar: calendar))
        XCTAssertEqual(streak.days.map(\.mark), [.counted, .broken, .counted, .counted, .counted, .counted])
        XCTAssertEqual(streak.days[1].line, after, "the broken day leads to the line that said so")
        XCTAssertEqual(streak.run, 4, "the run starts again the day after")
        XCTAssertEqual(streak.longest, 4)
        XCTAssertEqual(streak.breaks, 1)

        // A break with no moment is the line's own day; broken today, the run is nothing.
        let (today, todayEvent) = line("Opened TikTok", at: at(5, 2))
        notebook.apply(todayEvent)
        notebook.apply(event(.link(.init(from: today, to: detox)), at: at(5, 2)))
        notebook.apply(event(.factSet(.init(on: today, key: "break", value: .words("TikTok"))), at: at(5, 2)))
        streak = try XCTUnwrap(notebook.streak(notebook.thing(detox)!, at: at(5, 3), calendar: calendar))
        XCTAssertEqual(streak.run, 0)
        XCTAssertEqual(streak.longest, 3)

        // The owner takes the break back with one hold, and the day counts again.
        notebook.apply(event(.factRemove(.init(on: today, key: "break", of: "weeju")), by: me, at: at(5, 2.5)))
        XCTAssertEqual(notebook.streak(notebook.thing(detox)!, at: at(5, 3), calendar: calendar)?.run, 4)
    }

    /// A span is an end: the days ahead are shown, and it is complete when they are behind.
    /// Stopped, it counts no further; begun again, it starts from the new moment.
    func testASpanAnEndAndBeginningAgain() throws {
        let week = ULID(timestamp: began)
        var notebook = Notebook(owner: me, events: [
            event(.thingSet(.init(thing: week, name: "no alcohol week", kind: "streak")), at: began),
            event(.factSet(.init(on: week, key: "since", value: .moment(began))), at: began),
            event(.factSet(.init(on: week, key: "span", value: .span(7 * 86_400))), at: began),
        ])
        var streak = try XCTUnwrap(notebook.streak(notebook.thing(week)!, at: at(2), calendar: calendar))
        XCTAssertEqual(streak.goal, 7)
        XCTAssertEqual(streak.days.count, 7, "three behind and today, four ahead")
        XCTAssertEqual(streak.days.map(\.mark), [.counted, .counted, .counted, .open, .open, .open, .open])
        XCTAssertEqual(streak.run, 3)

        streak = try XCTUnwrap(notebook.streak(notebook.thing(week)!, at: at(30), calendar: calendar))
        XCTAssertEqual(streak.state, .complete)
        XCTAssertEqual(streak.run, 7, "it ran its seven days and counts no further")
        XCTAssertEqual(streak.days.count, 7)

        // Stopped on the third day by the owner.
        notebook.apply(event(.factSet(.init(on: week, key: "ended", value: .moment(at(2, 1)))), by: me, at: at(2, 1)))
        streak = try XCTUnwrap(notebook.streak(notebook.thing(week)!, at: at(4), calendar: calendar))
        XCTAssertEqual(streak.state, .ended(at(2, 1)))
        XCTAssertEqual(streak.days.count, 3, "nothing ahead once it is stopped")
        XCTAssertEqual(streak.run, 3)

        // Begun again: a newer since, and the old end is void.
        notebook.apply(event(.factSet(.init(on: week, key: "since", value: .moment(at(10)))), by: me, at: at(10)))
        streak = try XCTUnwrap(notebook.streak(notebook.thing(week)!, at: at(11), calendar: calendar))
        XCTAssertEqual(streak.state, .running)
        XCTAssertEqual(streak.run, 2)
    }

    /// With: a day counts when a line is with it. A day with none is missed; today, with
    /// nothing said yet, is open and does not end the run.
    func testADayCountsWhenALineIsWithIt() throws {
        let walks = ULID(timestamp: began)
        var events = [
            event(.thingSet(.init(thing: walks, name: "a walk a day", kind: "streak")), at: began),
            event(.factSet(.init(on: walks, key: "since", value: .moment(began))), at: began),
            event(.factSet(.init(on: walks, key: "counts", value: .words("with"))), at: began),
        ]
        // Walked on days 0, 2 and 3; not on 1; today is day 4.
        for day in [0.0, 2, 3] {
            let (id, made) = line("Walk", at: at(day, 5))
            events += [made, event(.link(.init(from: id, to: walks)), at: at(day, 5))]
        }
        let notebook = Notebook(owner: me, events: events)
        let streak = try XCTUnwrap(notebook.streak(notebook.thing(walks)!, at: at(4, 2), calendar: calendar))
        XCTAssertEqual(streak.counts, .with)
        XCTAssertEqual(streak.days.map(\.mark), [.counted, .missed, .counted, .counted, .open])
        XCTAssertEqual(streak.run, 2, "today is not over, so the run stands")
        XCTAssertEqual(streak.longest, 2)
        XCTAssertNotNil(streak.days[2].line)
    }

    /// A thing with no moment it began at is not a streak, whatever it is called.
    func testWithoutSinceItIsNotAStreak() {
        let thing = ULID(timestamp: began)
        let notebook = Notebook(owner: me, events: [
            event(.thingSet(.init(thing: thing, name: "the fig", kind: "plant")), at: began),
            event(.factSet(.init(on: thing, key: "since", value: .words("spring"))), at: began),
        ])
        XCTAssertFalse(notebook.thing(thing)!.isStreak)
        XCTAssertNil(notebook.streak(notebook.thing(thing)!, at: at(3), calendar: calendar))
    }
}
