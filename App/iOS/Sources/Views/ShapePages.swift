import Core
import SwiftUI

/// What is to do. Lines with a due moment first, soonest first; then the rest, newest
/// first. Each line wears the same mark it wears on its day: tap it and the line is done,
/// where it stands, and stays there until the day ends. What has waited three weeks with no
/// moment of its own steps back into Someday, out of the way and never late.
struct TodosPage: View {
    @Bindable var model: NotebookModel
    @State private var showsSomeday = false

    var body: some View {
        let todos = model.notebook.todos(at: Date(), calendar: model.calendar)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Todos")
                    .font(Theme.title)
                    .foregroundStyle(Theme.foreground)
                if todos.isEmpty {
                    Text("Nothing to do.")
                        .font(Theme.serifSmall)
                        .foregroundStyle(Theme.muted)
                }
                if !todos.now.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(todos.now) { entry in
                            row(entry)
                        }
                    }
                }
                if !todos.someday.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Button {
                            withAnimation(Motion.settle) { showsSomeday.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Someday")
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .rotationEffect(.degrees(showsSomeday ? 90 : 0))
                            }
                            .font(Theme.mono)
                            .foregroundStyle(Theme.muted)
                            .frame(height: 30)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("someday")
                        if showsSomeday {
                            ForEach(todos.someday) { entry in
                                row(entry)
                            }
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

    /// The mark, the words, and one quiet line under them: when it is due, or else the day
    /// it was written. Only a moment that has passed looks late.
    private func row(_ entry: Entry) -> some View {
        HStack(alignment: .top, spacing: 0) {
            TodoMark(entry: entry, model: model)
            NavigationLink(value: entry.id) {
                VStack(alignment: .leading, spacing: 4) {
                    LineWords(entry: entry)
                        .accessibilityIdentifier("todo")
                    Group {
                        if let due = entry.due {
                            Text("\(Format.shortDay(due, calendar: model.calendar)) \(Format.time(due, calendar: model.calendar))")
                                .foregroundStyle(entry.done != nil ? Theme.faint : due < Date() ? Theme.recording : Theme.muted)
                        } else {
                            Text(Format.shortDay(entry.startedAt, calendar: model.calendar))
                                .foregroundStyle(Theme.faint)
                        }
                    }
                    .font(Theme.mono)
                    .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button("Not to do", systemImage: "circle.slash") {
                withAnimation(Motion.settle) { model.setTodo(entry, false) }
            }
        }
    }
}

/// What is coming, by day, soonest first: events at the moment they happen and what is due
/// at the moment it is due. An event passes by itself and leaves the page; something to do
/// wears its mark here as everywhere, and is finished here as everywhere.
struct ComingPage: View {
    @Bindable var model: NotebookModel

    private struct ComingDay: Identifiable {
        let key: DayKey
        var entries: [Entry]
        var id: DayKey { key }
    }

    private var days: [ComingDay] {
        var days: [ComingDay] = []
        for entry in model.notebook.coming(after: Date()) {
            guard let moment = entry.moment else { continue }
            let key = DayKey(moment, calendar: model.calendar)
            if days.last?.key == key {
                days[days.count - 1].entries.append(entry)
            } else {
                days.append(ComingDay(key: key, entries: [entry]))
            }
        }
        return days
    }

    var body: some View {
        let days = days
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Coming")
                    .font(Theme.title)
                    .foregroundStyle(Theme.foreground)
                if days.isEmpty {
                    Text("Nothing coming.")
                        .font(Theme.serifSmall)
                        .foregroundStyle(Theme.muted)
                }
                ForEach(days) { day in
                    VStack(alignment: .leading, spacing: 14) {
                        Text(day.key == model.today ? "Today" : Format.day(day.key, calendar: model.calendar, withYear: day.key.year != model.today.year))
                            .font(Theme.mono)
                            .foregroundStyle(Theme.faint)
                        ForEach(day.entries) { entry in
                            row(entry)
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

    /// A line as its day draws it, with the moment it is about where its own time would be.
    private func row(_ entry: Entry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.moment.map { Format.time($0, calendar: model.calendar) } ?? "")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
                if entry.todo != nil {
                    TodoMark(entry: entry, model: model)
                }
            }
            .frame(width: 44, alignment: .leading)
            .padding(.top, 4)
            NavigationLink(value: entry.id) {
                ListedLine(entry: entry, model: model, moment: false)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Every thing of one kind, or every thing at all: the shelf, the garden, the people.
/// Each with its facts as its state and how many lines it holds. Tap one for its page.
struct ThingsPage: View {
    /// A kind, or nil for everything.
    let kind: String?
    @Bindable var model: NotebookModel

    var body: some View {
        let things = kind.map { model.notebook.things(kind: $0) } ?? model.notebook.madeThings
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(kind.map { Self.plural($0) } ?? "Things")
                        .font(Theme.title)
                        .foregroundStyle(Theme.foreground)
                    // What a thing of this kind has, as its shape says. Hold it to drop the
                    // shape; the things keep their facts and are drawn by what each looks like.
                    if let kind, let shape = model.notebook.shape(of: kind) {
                        Text("a \(kind) has " + shape.has.map(\.key).joined(separator: " · "))
                            .font(Theme.mono)
                            .foregroundStyle(Theme.muted)
                            .accessibilityIdentifier("kind-shape")
                            .contextMenu {
                                Button("Drop what a \(kind) has", systemImage: "trash", role: .destructive) {
                                    withAnimation(Motion.settle) { model.removeShape(kind) }
                                }
                            }
                    }
                }
                if things.isEmpty {
                    Text("Nothing here yet.")
                        .font(Theme.serifSmall)
                        .foregroundStyle(Theme.muted)
                }
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(things) { thing in
                        NavigationLink(value: Route.thing(thing.id)) {
                            row(thing)
                        }
                        .buttonStyle(.plain)
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

    private func row(_ thing: Thing) -> some View {
        let last = thing.lines.compactMap { model.notebook.entry($0) }.map(\.startedAt).max()
        return VStack(alignment: .leading, spacing: 4) {
            Text(thing.name)
                .font(Theme.serif)
                .foregroundStyle(Theme.foreground)
                .accessibilityIdentifier("thing-\(thing.name)")
            HStack(spacing: 6) {
                Text("\(thing.lines.count) line\(thing.lines.count == 1 ? "" : "s")")
                if let last {
                    Text("· last \(Format.shortDay(last, calendar: model.calendar))")
                }
                // A streak says its run, worked out; the facts it comes from are left to its page.
                let streak = model.notebook.streak(thing, at: Date(), calendar: model.calendar)
                if let streak {
                    Text("· \(streak.run) day\(streak.run == 1 ? "" : "s")")
                        .foregroundStyle(Theme.foreground)
                }
                // The short facts, in the order its shape gives them; a paragraph is for its page.
                ForEach(model.notebook.drawn(thing).filter { $0.what != .text && $0.what != .link && (streak == nil || !Notebook.streakKeys.contains($0.key)) }.prefix(3)) { item in
                    Text("· \(item.key) \(item.fact.value.words(calendar: model.calendar))")
                }
            }
            .font(Theme.mono)
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// "book" reads "Books" at the head of its page; irregulars as English has them.
    static func plural(_ kind: String) -> String {
        let word: String
        switch kind {
        case "person": word = "people"
        default: word = kind.hasSuffix("s") ? kind : kind + "s"
        }
        return word.prefix(1).uppercased() + word.dropFirst()
    }
}
