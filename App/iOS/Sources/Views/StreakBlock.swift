import Core
import SwiftUI

/// A streak as its page shows it: the run in days, a few quiet words, and every day since it
/// began as a dot, seven to a row, so a row is a week of it. A day that counts is filled; a day
/// that broke is an empty ring; a day missed is faint; a day still open is a faint ring.
/// Today wears the one colour. A day with a line behind it, the one that broke it or the one
/// that made it count, is a way to that line.
///
/// It shows what happened and nothing more: no flame, no warning, nothing that asks to be
/// kept. Hold the number to stop it, or to begin again from today.
struct StreakBlock: View {
    let thing: Thing
    let streak: Streak
    @Bindable var model: NotebookModel

    private static let dot: CGFloat = 12
    private static let gap: CGFloat = 12
    /// Half a year of rows at most; a longer one shows its latest days.
    private static let most = 26 * 7

    private var shown: [Streak.Day] {
        guard streak.days.count > Self.most else { return streak.days }
        // Whole weeks from its start are dropped, so the rows still begin where its weeks do.
        let dropped = ((streak.days.count - Self.most + 6) / 7) * 7
        return Array(streak.days.dropFirst(dropped))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(streak.run)")
                        .font(.system(size: 46, weight: .medium, design: .serif))
                        .foregroundStyle(Theme.foreground)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("streak-run")
                    Text(streak.run == 1 ? "day" : "days")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.muted)
                }
                Text(summary)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("streak-summary")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .contextMenu {
                if case .running = streak.state {
                    Button("Stop it", systemImage: "stop") {
                        withAnimation(Motion.settle) { model.endStreak(thing.id) }
                    }
                }
                Button("Begin again from today", systemImage: "arrow.counterclockwise") {
                    withAnimation(Motion.settle) { model.beginStreak(thing.id) }
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.dot), spacing: Self.gap), count: 7), alignment: .leading, spacing: Self.gap) {
                ForEach(shown) { day in
                    if let line = day.line {
                        NavigationLink(value: line) { dot(day) }
                            .buttonStyle(.plain)
                    } else {
                        dot(day)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("streak-days")
        }
    }

    /// "since 5 Nov · of 7 · 1 broken · longest 4", only what there is to say.
    private var summary: String {
        var parts = ["since \(Format.shortDay(streak.since, calendar: model.calendar))"]
        if let goal = streak.goal { parts.append("of \(goal)") }
        if streak.breaks > 0 { parts.append("\(streak.breaks) broken") }
        if streak.longest > streak.run { parts.append("longest \(streak.longest)") }
        switch streak.state {
        case .running: break
        case .complete: parts.append("complete")
        case .ended(let at): parts.append("stopped \(Format.shortDay(at, calendar: model.calendar))")
        }
        return parts.joined(separator: " · ")
    }

    private func dot(_ day: Streak.Day) -> some View {
        let colour = day.isToday ? Theme.accent : Theme.foreground
        return ZStack {
            switch day.mark {
            case .counted:
                Circle().fill(colour)
            case .broken:
                Circle().strokeBorder(day.isToday ? Theme.accent : Theme.muted, lineWidth: 1.5)
            case .missed:
                Circle().fill(Theme.faint).padding(3.5)
            case .open:
                Circle().strokeBorder(day.isToday ? Theme.accent : Theme.faint, lineWidth: 1)
            }
        }
        .frame(width: Self.dot, height: Self.dot)
        // Room for a thumb around a small dot, without moving its neighbours.
        .contentShape(Rectangle().inset(by: -Self.gap / 2))
        .accessibilityElement()
        .accessibilityIdentifier("streak-day")
        .accessibilityLabel("\(Format.shortDay(day.key.date(in: model.calendar) ?? streak.since, calendar: model.calendar)), \(Self.words(day.mark))")
    }

    private static func words(_ mark: Streak.Mark) -> String {
        switch mark {
        case .counted: "counts"
        case .broken: "broken"
        case .missed: "missed"
        case .open: "open"
        }
    }
}
