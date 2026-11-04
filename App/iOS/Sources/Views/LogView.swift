import Core
import SwiftUI

/// Pages reachable from the main page that are not lines.
enum Route: Hashable {
    case log
}

/// Everything readers did, newest first: each visit, note and label, with the line it was
/// about. Tap a row to open the line.
struct LogView: View {
    @Bindable var model: NotebookModel

    var body: some View {
        let days = Self.days(of: model.notebook.trail.reversed(), calendar: model.calendar)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Readers")
                    .font(Theme.title)
                    .foregroundStyle(Theme.foreground)
                if days.isEmpty {
                    Text("No reader has been here yet.")
                        .font(Theme.serifSmall)
                        .foregroundStyle(Theme.muted)
                }
                ForEach(days, id: \.key) { day in
                    VStack(alignment: .leading, spacing: 14) {
                        Text(Format.day(day.key, calendar: model.calendar, withYear: false))
                            .font(Theme.mono)
                            .foregroundStyle(Theme.faint)
                        ForEach(day.traces) { trace in
                            row(trace)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbarBackground(Theme.background, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(_ trace: Trace) -> some View {
        let owner = model.store.manifest.owner
        let line = trace.entry.flatMap { model.notebook.entry($0) }
        let content = HStack(alignment: .top, spacing: 10) {
            Text(Format.time(trace.at, calendar: model.calendar))
                .font(Theme.mono)
                .foregroundStyle(Theme.faint)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(trace.author == owner ? "you" : trace.author.rawValue)
                        .foregroundStyle(trace.author == owner ? Theme.foreground : Theme.agent)
                    Text(trace.what)
                        .foregroundStyle(Theme.muted)
                    if trace.author != owner {
                        Text("via \(trace.device.rawValue)")
                            .foregroundStyle(Theme.faint)
                    }
                }
                .font(Theme.mono)
                if let line {
                    Text(line.text.isEmpty ? "a photo" : line.text)
                        .font(Theme.serifSmall)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                } else if trace.entry != nil {
                    Text("a line that is gone")
                        .font(Theme.serifSmall)
                        .foregroundStyle(Theme.faint)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        if let line {
            NavigationLink(value: line.id) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    struct DayOfTraces {
        let key: DayKey
        var traces: [Trace]
    }

    /// Consecutive traces grouped by their day, in the order given.
    static func days(of traces: some Sequence<Trace>, calendar: Calendar) -> [DayOfTraces] {
        var days: [DayOfTraces] = []
        for trace in traces {
            let key = DayKey(trace.at, calendar: calendar)
            if days.last?.key == key {
                days[days.count - 1].traces.append(trace)
            } else {
                days.append(DayOfTraces(key: key, traces: [trace]))
            }
        }
        return days
    }

    /// "weeju · 13:21 · read 4 lines", or with the day when it was not today.
    static func summary(of visit: Visit, calendar: Calendar) -> String {
        let today = DayKey(Date(), calendar: calendar) == DayKey(visit.at, calendar: calendar)
        let when = today
            ? Format.time(visit.at, calendar: calendar)
            : "\(Format.shortDay(visit.at, calendar: calendar)) \(Format.time(visit.at, calendar: calendar))"
        return "\(visit.author.rawValue) · \(when) · \(visit.what)"
    }
}
