import Core
import Foundation
import HealthKit

/// Walks, runs, hikes and rides from Health, each one a line on its day with its distance
/// and time, from the day you switch it on. Health wakes the app when a workout ends,
/// even in the background, so the line is there before you look.
@MainActor
@Observable
final class Walks {
    private static let onKey = "walks.on"
    /// The start of the day walks were switched on. That whole day counts, nothing older.
    private static let fromKey = "walks.from"
    private static let anchorKey = "walks.anchor.1"
    /// Keys from the first build, where only workouts after the exact moment counted.
    private static let oldKeys = ["walks.since", "walks.anchor"]

    struct Walk: Sendable {
        let id: UUID
        let kind: HKWorkoutActivityType
        let start: Date
        let end: Date
        let meters: Double?
    }

    private let health = HKHealthStore()
    private var observer: HKObserverQuery?
    private(set) var isOn = UserDefaults.standard.bool(forKey: Walks.onKey)
    /// What Health said when it refused, in its own words, so the page can show it.
    private(set) var trouble: String?

    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Asked once. Workouts from the start of today on come in; earlier ones stay where they are.
    /// Call with nothing else presented: Health shows its permission sheet from here.
    func turnOn(_ handler: @escaping @MainActor ([Walk]) -> Void) async {
        guard available else { return }
        trouble = nil
        do {
            try await health.requestAuthorization(toShare: [], read: [HKObjectType.workoutType()])
            _ = firstDay()   // fixed now: the day the switch was flipped
            UserDefaults.standard.set(true, forKey: Self.onKey)
            isOn = true
            try await health.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate)
            resume(handler)
        } catch {
            NSLog("health failed: \(error)")
            trouble = error.localizedDescription
        }
    }

    /// Picks up where it left off: watches for new workouts and fetches any that arrived
    /// while the app was away. A no-op until switched on.
    func resume(_ handler: @escaping @MainActor ([Walk]) -> Void) {
        guard isOn, available, observer == nil else { return }
        let query = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { [weak self] _, done, error in
            if let error { NSLog("health observer: \(error)") }
            Task { @MainActor in
                await self?.fetchNew(handler)
                done()
            }
        }
        observer = query
        health.execute(query)
        Task { await fetchNew(handler) }
    }

    /// The start of the day walks were switched on, fixed the first time it is asked for.
    private func firstDay() -> Date {
        let defaults = UserDefaults.standard
        if let date = defaults.object(forKey: Self.fromKey) as? Date { return date }
        let date = Calendar.current.startOfDay(for: Date())
        defaults.set(date, forKey: Self.fromKey)
        Self.oldKeys.forEach(defaults.removeObject(forKey:))
        return date
    }

    /// Only what has not been seen before, by Health's own anchor.
    private func fetchNew(_ handler: @MainActor ([Walk]) -> Void) async {
        let predicate = HKQuery.predicateForSamples(withStart: firstDay(), end: nil, options: .strictStartDate)
        let anchor = UserDefaults.standard.data(forKey: Self.anchorKey)
            .flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
        let (samples, newAnchor): ([HKSample], HKQueryAnchor?) = await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: .workoutType(), predicate: predicate, anchor: anchor,
                                              limit: HKObjectQueryNoLimit) { _, samples, _, newAnchor, error in
                if let error { NSLog("health query: \(error)") }
                continuation.resume(returning: (samples ?? [], newAnchor))
            }
            health.execute(query)
        }
        if let newAnchor, let data = try? NSKeyedArchiver.archivedData(withRootObject: newAnchor, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: Self.anchorKey)
        }
        let walks = samples.compactMap { $0 as? HKWorkout }.map { workout in
            let walked = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()
            let cycled = workout.statistics(for: HKQuantityType(.distanceCycling))?.sumQuantity()
            return Walk(id: workout.uuid, kind: workout.workoutActivityType, start: workout.startDate, end: workout.endDate,
                        meters: (walked ?? cycled)?.doubleValue(for: .meter()))
        }
        if !walks.isEmpty { handler(walks) }
    }

    /// "Walk, 4.2 km, 52 min". The line as it reads on the page.
    static func sentence(for walk: Walk, locale: Locale) -> String {
        var parts = [name(of: walk.kind)]
        if let meters = walk.meters, meters >= 50 {
            let distance = Measurement(value: meters, unit: UnitLength.meters)
            parts.append(distance.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1))).locale(locale)))
        }
        let minutes = Int((walk.end.timeIntervalSince(walk.start) / 60).rounded())
        if minutes >= 60 {
            parts.append("\(minutes / 60) h \(minutes % 60) min")
        } else if minutes > 0 {
            parts.append("\(minutes) min")
        }
        return parts.joined(separator: ", ")
    }

    private static func name(of kind: HKWorkoutActivityType) -> String {
        switch kind {
        case .walking: "Walk"
        case .hiking: "Hike"
        case .running: "Run"
        case .cycling: "Ride"
        case .swimming: "Swim"
        default: "Workout"
        }
    }
}
