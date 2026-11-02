import Core
import SwiftUI

/// The date, tapped: a month with a mark under every day that has lines.
struct CalendarSheet: View {
    let days: [Day]
    let today: DayKey
    let calendar: Calendar
    let home: String
    let onPick: (DayKey) -> Void
    let onMove: () -> Void

    @State private var month: DateComponents

    init(days: [Day], today: DayKey, calendar: Calendar, home: String, onPick: @escaping (DayKey) -> Void, onMove: @escaping () -> Void) {
        self.days = days
        self.today = today
        self.calendar = calendar
        self.home = home
        self.onPick = onPick
        self.onMove = onMove
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
            Spacer(minLength: 0)

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
        }
        .padding(20)
        .padding(.top, 8)
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
