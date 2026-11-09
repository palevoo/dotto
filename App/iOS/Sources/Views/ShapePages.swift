import Core
import SwiftUI

/// What is still to do: every line anyone marked todo and nobody marked done. Due first,
/// soonest first; then the rest, newest first. Tap a line to open it; hold to mark it done.
struct TodosPage: View {
    @Bindable var model: NotebookModel

    var body: some View {
        let todos = model.notebook.todos
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Todos")
                    .font(Theme.title)
                    .foregroundStyle(Theme.foreground)
                if todos.isEmpty {
                    Text("Nothing to do. A line becomes a todo when someone marks it one; it leaves when it is done.")
                        .font(Theme.serifSmall)
                        .foregroundStyle(Theme.muted)
                        .lineSpacing(3)
                }
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(todos) { entry in
                        NavigationLink(value: entry.id) {
                            row(entry)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Done", systemImage: "checkmark") {
                                withAnimation(Motion.settle) { model.markDone(entry.id) }
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

    private func row(_ entry: Entry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // The due moment where there is one, else the day the line was written.
            VStack(alignment: .leading, spacing: 2) {
                if let due = entry.due {
                    Text(Format.shortDay(due, calendar: model.calendar))
                        .foregroundStyle(due < Date() ? Theme.recording : Theme.accent)
                    Text(Format.time(due, calendar: model.calendar))
                        .foregroundStyle(Theme.muted)
                } else {
                    Text(Format.shortDay(entry.startedAt, calendar: model.calendar))
                        .foregroundStyle(Theme.faint)
                }
            }
            .font(Theme.mono)
            .monospacedDigit()
            .frame(width: 54, alignment: .leading)
            .padding(.top, 3)
            Text(entry.text.isEmpty ? "a photo" : entry.text)
                .font(Theme.serif)
                .foregroundStyle(Theme.foreground)
                .lineSpacing(4)
                .accessibilityIdentifier("todo")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Every thing of one kind, or every thing at all: the shelf, the nursery, the people.
/// Each with its facts as its state and how many lines it holds. Tap one for its page.
struct ThingsPage: View {
    /// A kind, or nil for everything.
    let kind: String?
    @Bindable var model: NotebookModel

    var body: some View {
        let things = kind.map { model.notebook.things(kind: $0) } ?? model.notebook.allThings
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(kind.map { Self.plural($0) } ?? "Things")
                    .font(Theme.title)
                    .foregroundStyle(Theme.foreground)
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
                ForEach(thing.facts.prefix(3)) { fact in
                    Text("· \(fact.key) \(fact.value.words(calendar: model.calendar))")
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
