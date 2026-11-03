import Core
import SwiftUI

/// The date, tapped: a month with a mark under every day that has lines, and the labels
/// readers have filed lines under. Tap a label to see only those lines.
struct CalendarSheet: View {
    let days: [Day]
    let today: DayKey
    let calendar: Calendar
    let labels: [String: Int]
    let filter: String?
    let home: String
    let walksOn: Bool
    let walksAvailable: Bool
    let onPick: (DayKey) -> Void
    let onFilter: (String?) -> Void
    let onMove: () -> Void
    let onWalks: () -> Void

    @State private var month: DateComponents
    @State private var height: CGFloat = 480
    @State private var showsPresses = false

    init(days: [Day], today: DayKey, calendar: Calendar, labels: [String: Int], filter: String?, home: String,
         walksOn: Bool, walksAvailable: Bool,
         onPick: @escaping (DayKey) -> Void, onFilter: @escaping (String?) -> Void, onMove: @escaping () -> Void,
         onWalks: @escaping () -> Void) {
        self.days = days
        self.today = today
        self.calendar = calendar
        self.labels = labels
        self.filter = filter
        self.home = home
        self.walksOn = walksOn
        self.walksAvailable = walksAvailable
        self.onPick = onPick
        self.onFilter = onFilter
        self.onMove = onMove
        self.onWalks = onWalks
        _month = State(initialValue: DateComponents(year: today.year, month: today.month))
    }

    private var withEntries: Set<DayKey> { Set(days.map(\.key)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(monthTitle)
                    .font(Theme.title)
                    .foregroundStyle(Theme.foreground)
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .frame(width: 44, height: 44)
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .frame(width: 44, height: 44)
                    .disabled(isCurrentMonth)
            }
            .foregroundStyle(Theme.muted)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.faint)
                        .frame(height: 24)
                }
                ForEach(cells, id: \.self) { cell in
                    if let key = cell {
                        let has = withEntries.contains(key)
                        let isToday = key == today
                        let future = key > today
                        Button {
                            if has || isToday { onPick(key) }
                        } label: {
                            VStack(spacing: 3) {
                                Text("\(key.day)")
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundStyle(isToday ? Theme.background : (future ? Theme.faint : Theme.foreground))
                                    .frame(width: 30, height: 30)
                                    .background(Theme.square(30).fill(isToday ? Theme.foreground : .clear))
                                Theme.square(4)
                                    .fill(has ? Theme.accent : .clear)
                                    .frame(width: 4, height: 4)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(!has && !isToday)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }

            if !labels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(labels.keys.sorted(), id: \.self) { label in
                            LabelChip(label: label, count: labels[label] ?? 0, selected: filter == label) {
                                onFilter(filter == label ? nil : label)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Text(home)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.muted)
                Text("·")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.faint)
                Button(action: onMove) {
                    Text("Move to a folder")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 4)

            // Where the one-press ways in are switched on. Tap to see the path through Settings.
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(Motion.settle) { showsPresses.toggle() }
                } label: {
                    Text("Write or take a photo with one press")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                if showsPresses {
                    Text("Action button: Settings · Action Button · Controls · Margin")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.muted)
                    Text("Lock screen or Control Center: hold, Add a Control, Margin")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.muted)
                    Text("Siri: “Write in Margin”, “Photo in Margin”")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Walks from Health, once you say so. A line per walk, from then on.
            if walksAvailable {
                if walksOn {
                    Text("Walks from Health arrive as lines")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.muted)
                } else {
                    Button(action: onWalks) {
                        Text("Bring walks from Health")
                            .font(Theme.mono)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // The sheet is exactly as tall as the month, so nothing is cropped or centred.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.hidden)
    }

    private var isCurrentMonth: Bool {
        month.year == today.year && month.month == today.month
    }

    private var monthTitle: String {
        guard let date = calendar.date(from: month) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.setLocalizedDateFormatFromTemplate(month.year == today.year ? "MMMM" : "MMMM yyyy")
        return formatter.string(from: date)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Leading blanks then every day of the month.
    private var cells: [DayKey?] {
        guard let year = month.year, let monthNumber = month.month,
              let firstDate = calendar.date(from: DateComponents(year: year, month: monthNumber, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: firstDate)
        else { return [] }
        let weekday = calendar.component(.weekday, from: firstDate)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.map { DayKey(year: year, month: monthNumber, day: $0) }
    }

    private func shift(_ delta: Int) {
        guard let date = calendar.date(from: month),
              let moved = calendar.date(byAdding: .month, value: delta, to: date) else { return }
        month = calendar.dateComponents([.year, .month], from: moved)
    }
}

struct LabelChip: View {
    let label: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("#\(label)")
                Text("\(count)")
                    .foregroundStyle(selected ? Theme.background.opacity(0.7) : Theme.faint)
            }
            .font(Theme.mono)
            .foregroundStyle(selected ? Theme.background : Theme.foreground)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Theme.square(30).fill(selected ? Theme.foreground : .clear))
            .overlay(Theme.square(30).strokeBorder(selected ? .clear : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
