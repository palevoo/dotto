import Core
import SwiftUI

/// The date, tapped: a month with a mark under every day that has lines, the pages over
/// shapes, the tags, the latest read, and the way to Setup. Tap a tag for its page.
struct CalendarSheet: View {
    let days: [Day]
    let today: DayKey
    let calendar: Calendar
    /// The tags with lines under them, by word.
    let tags: [Thing]
    /// The kinds of things there are, with how many of each.
    let kinds: [(kind: String?, count: Int)]
    /// The moments still ahead: events and what is due.
    let coming: [Date]
    /// How many lines are still to do; nil when the todos page would be empty.
    let todos: Int?
    /// The latest read, as who and one line. Nil until someone has been.
    let lastVisit: (author: Author, text: String)?
    /// Everyone else who has left anything, each with a page of their own.
    let others: [Author]
    /// How much arrived for you since you last looked at the inbox.
    let unread: Int
    let model: NotebookModel
    let onPick: (DayKey) -> Void
    let onTag: (ULID) -> Void
    let onInbox: () -> Void
    let onSearch: () -> Void
    let onLog: () -> Void
    let onSetup: () -> Void
    let onTodos: () -> Void
    let onComing: () -> Void
    let onKind: (String?) -> Void
    let onAuthor: (Author) -> Void

    @State private var month: DateComponents
    @State private var height: CGFloat = 480

    init(days: [Day], today: DayKey, calendar: Calendar, tags: [Thing], kinds: [(kind: String?, count: Int)], coming: [Date] = [], todos: Int?,
         lastVisit: (author: Author, text: String)?, others: [Author], unread: Int, model: NotebookModel,
         onPick: @escaping (DayKey) -> Void, onTag: @escaping (ULID) -> Void, onInbox: @escaping () -> Void,
         onSearch: @escaping () -> Void, onLog: @escaping () -> Void, onSetup: @escaping () -> Void, onTodos: @escaping () -> Void, onComing: @escaping () -> Void = {},
         onKind: @escaping (String?) -> Void, onAuthor: @escaping (Author) -> Void) {
        self.days = days
        self.today = today
        self.calendar = calendar
        self.tags = tags
        self.kinds = kinds
        self.todos = todos
        self.coming = coming
        self.onComing = onComing
        self.lastVisit = lastVisit
        self.others = others
        self.unread = unread
        self.model = model
        self.onPick = onPick
        self.onTag = onTag
        self.onInbox = onInbox
        self.onSearch = onSearch
        self.onLog = onLog
        self.onSetup = onSetup
        self.onTodos = onTodos
        self.onKind = onKind
        self.onAuthor = onAuthor
        _month = State(initialValue: DateComponents(year: today.year, month: today.month))
    }

    private var withEntries: Set<DayKey> { Set(days.map(\.key)) }
    /// The days something is coming on.
    private var ahead: Set<DayKey> { Set(coming.map { DayKey($0, calendar: calendar) }) }

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
                                // A dot under a day with lines; a ring under one with something coming.
                                ZStack {
                                    Circle().fill(has ? Theme.accent : .clear)
                                    Circle().strokeBorder(ahead.contains(key) && !has ? Theme.accent : .clear, lineWidth: 1)
                                }
                                .frame(width: has ? 4 : 5, height: has ? 4 : 5)
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

            // The shapes: what is to do, and the things by kind, each a page. Then the tags.
            if todos != nil || !kinds.isEmpty || !coming.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if !coming.isEmpty {
                            ShapeChip(title: "coming", count: coming.count) { onComing() }
                                .accessibilityIdentifier("coming")
                        }
                        if let todos {
                            ShapeChip(title: "todos", count: todos, accent: todos > 0) { onTodos() }
                                .accessibilityIdentifier("todos")
                        }
                        ForEach(Array(kinds.enumerated()), id: \.offset) { _, kind in
                            ShapeChip(title: kind.kind.map { ThingsPage.plural($0).lowercased() } ?? "things", count: kind.count) {
                                onKind(kind.kind)
                            }
                            .accessibilityIdentifier("kind-\(kind.kind ?? "things")")
                        }
                    }
                }
            }

            // The tags, each a thing with a page of its own.
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags) { tag in
                            LabelChip(label: tag.name, count: tag.lines.count) { onTag(tag.id) }
                                .accessibilityIdentifier("tag-\(tag.name)")
                        }
                    }
                }
            }

            // Everyone else's page: their colour, and their name or the fact there is none yet.
            if !others.isEmpty {
                HStack(spacing: 18) {
                    ForEach(others, id: \.rawValue) { author in
                        Button { onAuthor(author) } label: {
                            AuthorLabel(author: author, model: model)
                                .frame(minHeight: 30)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }

            // The inbox: what others left that may want you, with how much is new. Beside it,
            // the way to find any line by its words.
            HStack(spacing: 18) {
                Button(action: onInbox) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Inbox")
                            .font(Theme.mono)
                            .foregroundStyle(unread > 0 ? Theme.accent : Theme.muted)
                        if unread > 0 {
                            Text("\(unread)")
                                .font(Theme.mono)
                                .foregroundStyle(Theme.accent)
                                .monospacedDigit()
                        }
                    }
                    .frame(minHeight: 30)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("inbox")
                Button(action: onSearch) {
                    Text("Search")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.muted)
                        .frame(minHeight: 30)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search")
            }

            // The latest read, and the way to everything else.
            HStack(alignment: .firstTextBaseline) {
                if let lastVisit {
                    Button(action: onLog) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Who(author: lastVisit.author, model: model)
                            Text("· \(lastVisit.text)")
                                .font(Theme.mono)
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button(action: onSetup) {
                    Text("Setup")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
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

/// A page over shapes, as a chip: its name and how many it holds.
struct ShapeChip: View {
    let title: String
    let count: Int
    var accent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .foregroundStyle(accent ? Theme.accent : Theme.foreground)
                Text("\(count)")
                    .foregroundStyle(Theme.faint)
            }
            .font(Theme.mono)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .overlay(Theme.square(30).strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// A tag as a chip: its word and how many lines are under it.
struct LabelChip: View {
    let label: String
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("#\(label)")
                Text("\(count)")
                    .foregroundStyle(Theme.faint)
            }
            .font(Theme.mono)
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .overlay(Theme.square(30).strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
