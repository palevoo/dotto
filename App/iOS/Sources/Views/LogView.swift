import Core
import SwiftUI

/// Pages reachable from the main page that are not lines.
enum Route: Hashable {
    case log
    case setup
    /// Someone else's page: their own lines, with your replies under them.
    case author(Author)
}

/// Everything anyone else did in the notebook, newest first: each read, note, label and
/// link, with the line it was about. Tap a row to open the line.
struct LogView: View {
    @Bindable var model: NotebookModel

    var body: some View {
        let days = Self.days(of: model.notebook.trail.reversed(), calendar: model.calendar)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Logs")
                    .font(Theme.title)
                    .foregroundStyle(Theme.foreground)
                if days.isEmpty {
                    Text("Nothing yet. What anyone else does in the notebook is listed here.")
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
            VStack(alignment: .leading, spacing: 4) {
                // One sentence: who, what, and from where.
                let via = trace.author == owner ? "" : ", via \(trace.device.rawValue)"
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Who(author: trace.author, model: model)
                    Text("\(trace.what)\(via)")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.muted)
                }
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

    /// "13:21 · read 4 lines", or with the day when it was not today. Who comes before it,
    /// as a name or a mark.
    static func summary(of visit: Visit, calendar: Calendar) -> String {
        let today = DayKey(Date(), calendar: calendar) == DayKey(visit.at, calendar: calendar)
        let when = today
            ? Format.time(visit.at, calendar: calendar)
            : "\(Format.shortDay(visit.at, calendar: calendar)) \(Format.time(visit.at, calendar: calendar))"
        return "\(when) · \(visit.what)"
    }
}
