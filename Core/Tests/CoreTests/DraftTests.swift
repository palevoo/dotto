import XCTest
@testable import Core

/// The live line as a value: it begins when the first thing lands, ends when the last leaves,
/// takes its photos' moment when they offer one, and stores as one entry with its media.
final class DraftTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return calendar
    }
    private let now = Date(timeIntervalSince1970: 1_794_132_000) // 2026-11-08 10:00 UTC
    private let owner = Author(rawValue: "wiju")
    private let ids = ULIDGenerator()

    func testBeginsOnTheFirstCharacterAndEndsWithTheLast() {
        var draft = Draft()
        XCTAssertTrue(draft.isEmpty)
        XCTAssertNil(draft.begun)

        draft.write("H", now: now)
        XCTAssertEqual(draft.begun, now, "the moment is fixed by the first character")
        draft.write("Hello", now: now.addingTimeInterval(90))
        XCTAssertEqual(draft.begun, now, "and does not move while typing")

        draft.write("", now: now.addingTimeInterval(120))
        XCTAssertTrue(draft.isEmpty)
        XCTAssertNil(draft.begun, "an emptied line has no moment")

        draft.write("Again", now: now.addingTimeInterval(200))
        XCTAssertEqual(draft.begun, now.addingTimeInterval(200), "the next line begins afresh")
    }

    func testAVoiceNoteBeginsTheLineWhenItWasRecordedAndItsWordsFollow() {
        var draft = Draft()
        let recorded = now.addingTimeInterval(-40)
        draft.add(DraftMedia(hash: "v1", mime: "audio/mp4", duration: 40, at: recorded), beginning: recorded, now: now, calendar: calendar)
        draft.append("  what I said\n", now: now)
        XCTAssertEqual(draft.begun, recorded)
        XCTAssertEqual(draft.text, "what I said")

        draft.append("a passage", quoted: true, now: now)
        XCTAssertEqual(draft.text, "what I said \u{201C}a passage\u{201D}")
        draft.append("   ", now: now)
        XCTAssertEqual(draft.text, "what I said \u{201C}a passage\u{201D}", "blank words change nothing")
    }

    func testAPhotoFromBeforeOffersItsMomentAndTheLineTakesIt() {
        var draft = Draft()
        let yesterday = now.addingTimeInterval(-86_400)
        let there = Location(latitude: 38.7, longitude: -9.1)
        draft.add(DraftMedia(hash: "p1", mime: "image/jpeg", at: yesterday, location: there, fromBefore: true),
                  beginning: now, now: now, calendar: calendar)
        XCTAssertEqual(draft.photoMoment(now: now, calendar: calendar), yesterday)
        XCTAssertTrue(draft.keepsPhotoMoment, "the first photo from before is taken at its word")
        XCTAssertEqual(draft.moment(now: now, calendar: calendar), yesterday)

        draft.toggleMoment(now: now, calendar: calendar)
        XCTAssertFalse(draft.keepsPhotoMoment)
        XCTAssertEqual(draft.moment(now: now, calendar: calendar), now, "told otherwise, the line is of now")
        draft.toggleMoment(now: now, calendar: calendar)
        XCTAssertTrue(draft.keepsPhotoMoment)

        // A second photo from another day: the photos no longer agree on a moment.
        draft.add(DraftMedia(hash: "p2", mime: "image/jpeg", at: now.addingTimeInterval(-3 * 86_400), fromBefore: true),
                  beginning: now, now: now, calendar: calendar)
        XCTAssertNil(draft.photoMoment(now: now, calendar: calendar))
        XCTAssertEqual(draft.moment(now: now, calendar: calendar), now)

        draft.remove("p2", now: now, calendar: calendar)
        XCTAssertEqual(draft.moment(now: now, calendar: calendar), yesterday, "one day again, and the choice held")

        draft.remove("p1", now: now, calendar: calendar)
        XCTAssertTrue(draft.isEmpty)
        XCTAssertNil(draft.begun)
        XCTAssertFalse(draft.keepsPhotoMoment, "the moment goes with the last photo from before")
    }

    func testAPhotoOfTodayOffersNoMoment() {
        var draft = Draft()
        draft.add(DraftMedia(hash: "p1", mime: "image/jpeg", at: now.addingTimeInterval(-3600), fromBefore: true),
                  beginning: now, now: now, calendar: calendar)
        XCTAssertNil(draft.photoMoment(now: now, calendar: calendar), "earlier today is still today")
        XCTAssertFalse(draft.keepsPhotoMoment)
        XCTAssertEqual(draft.moment(now: now, calendar: calendar), now)
    }

    func testStoredIsOneEntryWithItsMediaAtItsMomentAndPlace() throws {
        var draft = Draft()
        let begun = now.addingTimeInterval(-300)
        draft.write(" Olives in, at last \n", now: begun)
        draft.add(DraftMedia(hash: "p1", mime: "image/jpeg", width: 4000, height: 3000, at: now), beginning: now, now: now, calendar: calendar)
        let here = Location(latitude: 39.0, longitude: -8.0)

        let stored = try XCTUnwrap(draft.stored(by: owner, on: "phone", here: here, ids: ids, now: now, calendar: calendar))
        XCTAssertEqual(stored.events.count, 2)
        guard case .entryCreate(let create) = stored.events[0].payload else { return XCTFail("the first event makes the line") }
        XCTAssertEqual(create.entry, stored.id)
        XCTAssertEqual(create.text, "Olives in, at last", "trimmed")
        XCTAssertEqual(create.startedAt, begun, "stored at the moment it began")
        XCTAssertEqual(create.location, here)
        XCTAssertEqual(stored.id.timestamp.timeIntervalSince1970, begun.timeIntervalSince1970, accuracy: 0.001, "the id carries the moment")
        guard case .mediaAttach(let attach) = stored.events[1].payload else { return XCTFail("the second attaches the photo") }
        XCTAssertEqual(attach.entry, stored.id)
        XCTAssertEqual(attach.hash, "p1")
        XCTAssertEqual(attach.width, 4000)
        XCTAssertEqual(stored.events[1].at, now)
    }

    func testStoredAtThePhotosMomentTakesTheirPlace() throws {
        var draft = Draft()
        let yesterday = now.addingTimeInterval(-86_400)
        let there = Location(latitude: 38.7, longitude: -9.1)
        draft.add(DraftMedia(hash: "p1", mime: "image/jpeg", at: yesterday, location: there, fromBefore: true),
                  beginning: now, now: now, calendar: calendar)
        let stored = try XCTUnwrap(draft.stored(by: owner, on: "phone", here: Location(latitude: 1, longitude: 1), ids: ids, now: now, calendar: calendar))
        guard case .entryCreate(let create) = stored.events[0].payload else { return XCTFail() }
        XCTAssertEqual(create.text, "", "a photo alone is a line")
        XCTAssertEqual(create.startedAt, yesterday)
        XCTAssertEqual(create.location, there, "where the photo was taken, not where the phone is")
    }

    func testNothingToStore() {
        var draft = Draft()
        XCTAssertNil(draft.stored(by: owner, on: "phone", here: nil, ids: ids, now: now, calendar: calendar))
        draft.write("   \n", now: now)
        XCTAssertFalse(draft.isEmpty, "whitespace is in the field")
        XCTAssertNil(draft.stored(by: owner, on: "phone", here: nil, ids: ids, now: now, calendar: calendar), "but it is not a line")
    }

    func testKeptBetweenLaunchesInTheShapeAlreadyOnPhones() throws {
        var draft = Draft()
        draft.write("Waiting", now: now)
        draft.add(DraftMedia(hash: "p1", mime: "image/jpeg", at: now), beginning: now, now: now, calendar: calendar)
        let data = try JSONEncoder().encode(draft)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["text", "media", "startedAt", "keepsPhotoMoment"])
        XCTAssertEqual(try JSONDecoder().decode(Draft.self, from: data), draft)
    }
}
