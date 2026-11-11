import Core
import Foundation
import Network
import Observation

/// The weather of each line that has a place, found out from the phone once it is switched
/// on in Setup. Nothing is asked of the person and nothing is captured: a line already has
/// its when and where, and the weather follows from those, so it is asked for when the
/// phone can reach the source, now or days later, and the answer is the same.
///
/// Off until switched on, because asking sends something out: a place rounded to about a
/// kilometre and a span of days, to Open-Meteo. Nothing else leaves.
@MainActor
@Observable
final class WeatherKeeper {
    private static let onKey = "weather.on"

    private(set) var isOn = UserDefaults.standard.bool(forKey: WeatherKeeper.onKey)
    /// What the source said when it refused, in its own words. No signal is not trouble.
    private(set) var trouble: String?

    /// The notebook as it reads now, and the way to write into it. Set by the model.
    @ObservationIgnored var notebook: () -> Notebook? = { nil }
    @ObservationIgnored var write: ([Event]) -> Bool = { _ in false }
    /// How the source is asked. The tests put their own answer here.
    @ObservationIgnored var ask: (Weather.Ask) async throws -> Weather.Hours = { try await Weather.fetch($0) }

    @ObservationIgnored private let device: DeviceID
    @ObservationIgnored private let ids = ULIDGenerator()
    /// One filling at a time; a call while one runs means: look once more when it ends.
    @ObservationIgnored private var filling = false
    @ObservationIgnored private var again = false
    /// Lines asked about since the app started. One the source knew nothing of is not
    /// asked about again until the app next starts.
    @ObservationIgnored private var asked: Set<ULID> = []
    /// Says when the phone can reach the network again, which is when what waited is asked for.
    @ObservationIgnored private var reach: NWPathMonitor?

    init(device: DeviceID) {
        self.device = device
    }

    /// Switched on from Setup. Every line with a place gets its weather, the old ones too.
    func turnOn() {
        UserDefaults.standard.set(true, forKey: Self.onKey)
        isOn = true
        resume()
    }

    /// Switched off: nothing more is asked. What lines already say stays.
    func turnOff() {
        UserDefaults.standard.set(false, forKey: Self.onKey)
        isOn = false
        trouble = nil
        reach?.cancel()
        reach = nil
    }

    /// Picks up where it left off, and from then on whenever the phone becomes reachable.
    /// A no-op until switched on.
    func resume() {
        guard isOn, reach == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.fill() }
        }
        monitor.start(queue: .main)
        reach = monitor
    }

    /// How many lines have a place and no weather yet.
    func waiting(in notebook: Notebook) -> Int {
        Weather.waiting(in: notebook, now: Date()).count
    }

    /// Asks for the weather of every line still waiting, a place and a run of days at a
    /// time, and writes what comes back in Weather's name. Called when the notebook is read,
    /// when a line is written, and when the phone becomes reachable. With no signal it
    /// stops at the first question and what waits is asked for next time.
    func fill() {
        guard isOn else { return }
        guard !filling else { again = true; return }
        filling = true
        Task { [weak self] in
            await self?.work()
            self?.filling = false
        }
    }

    private func work() async {
        repeat {
            again = false
            guard let notebook = notebook() else { return }
            let lines = Weather.waiting(in: notebook, now: Date()).filter { !asked.contains($0.id) }
            for question in Weather.asks(for: lines) {
                guard isOn else { return }
                do {
                    let hours = try await ask(question)
                    asked.formUnion(question.lines.map(\.entry))
                    trouble = nil
                    let events = Weather.events(for: question, from: hours, device: device, ids: ids, now: Date())
                    guard events.isEmpty || write(events) else { return }
                } catch let refusal as Weather.Trouble {
                    trouble = refusal.errorDescription
                    return
                } catch {
                    // No signal, or the source out of reach. Nothing to say; asked again
                    // when the phone is next reachable.
                    return
                }
            }
        } while again
    }
}
