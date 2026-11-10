import Core
import SwiftUI

/// A thing's page: its name and kind, who made it, its facts as its state, and the lines
/// that belong to it by day. A tag's page is the same, headed by its word, made by nobody.
/// Hold a fact to take it off; hold the name to drop the thing, which for a tag takes
/// every line out from under it. Tap a line to open it.
struct ThingPage: View {
    let id: ULID
    @Bindable var model: NotebookModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let thing = model.notebook.thing(id) {
            content(thing)
        } else {
            Text("This thing is gone.")
                .font(Theme.serifSmall)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background.ignoresSafeArea())
        }
    }

    private func content(_ thing: Thing) -> some View {
        let lines = thing.lines.compactMap { model.notebook.entry($0) }
        let days = Notebook.days(of: lines, calendar: model.calendar)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(thing.isTag ? "#\(thing.name)" : thing.name)
                        .font(Theme.title)
                        .foregroundStyle(Theme.foreground)
                        .accessibilityIdentifier("thing-name")
                    HStack(spacing: 6) {
                        if let kind = thing.kind {
                            Text(kind)
                                .font(Theme.mono)
                                .foregroundStyle(Theme.muted)
                            Text("·")
                                .font(Theme.mono)
                                .foregroundStyle(Theme.faint)
                        }
                        if let author = thing.author {
                            Text("by")
                                .font(Theme.mono)
                                .foregroundStyle(Theme.faint)
                            Who(author: author, model: model)
                        } else {
                            Text("a tag")
                                .font(Theme.mono)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Button(thing.isTag ? "Take every line out" : "Drop", systemImage: "trash", role: .destructive) {
                        model.removeThing(thing.id)
                        dismiss()
                    }
                }

                // What it is, in a few sentences, as a paragraph; where it comes from, as a link;
                // then the rest of what is known of it, as a list.
                ForEach(thing.facts.filter { $0.key == "about" }) { fact in
                    Text(fact.value.words(calendar: model.calendar))
                        .font(Theme.serif)
                        .foregroundStyle(Theme.foreground)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("thing-about")
                        .contextMenu {
                            Button("Take it off", systemImage: "minus.circle", role: .destructive) {
                                withAnimation(Motion.settle) { model.removeFact(fact) }
                            }
                        }
                }
                let sources = thing.facts.filter { $0.key == "source" }
                let rest = thing.facts.filter { $0.key != "about" && $0.key != "source" }
                let kept = lines.flatMap { entry in entry.media.filter(\.isKept).map { (entry.id, $0) } }
                if !sources.isEmpty || !kept.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sources) { fact in
                            let words = fact.value.words(calendar: model.calendar)
                            if let url = URL(string: words), url.scheme?.hasPrefix("http") == true {
                                Link(destination: url) { ThingPage.pointer("source", url.host.map { $0 + url.path } ?? words) }
                                    .accessibilityIdentifier("thing-source")
                            } else {
                                ThingPage.pointer("source", words)
                            }
                        }
                        // What its lines pointed at, kept: read here, whatever became of the address.
                        ForEach(kept, id: \.1.hash) { entry, page in
                            NavigationLink(value: Route.kept(entry: entry, hash: page.hash)) {
                                ThingPage.pointer("kept", page.title ?? page.source ?? "a page")
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("thing-kept")
                        }
                    }
                }
                if !rest.isEmpty {
                    FactList(facts: rest, model: model)
                }

                if days.isEmpty {
                    Text("No lines belong to it yet.")
                        .font(Theme.serifSmall)
                        .foregroundStyle(Theme.muted)
                }
                ForEach(days) { day in
                    VStack(alignment: .leading, spacing: 14) {
                        Text(Format.day(day.key, calendar: model.calendar, withYear: false))
                            .font(Theme.mono)
                            .foregroundStyle(Theme.faint)
                        ForEach(day.entries) { entry in
                            NavigationLink(value: entry.id) {
                                row(entry)
                            }
                            .buttonStyle(.plain)
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

    /// One way out of the page: what it is, and where it leads, in the one colour.
    static func pointer(_ what: String, _ whereTo: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(what)
                .font(Theme.mono)
                .foregroundStyle(Theme.muted)
                .frame(minWidth: 44, alignment: .leading)
            Text(whereTo)
                .font(Theme.sansSmall)
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func row(_ entry: Entry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(Format.time(entry.startedAt, calendar: model.calendar))
                .font(Theme.mono)
                .foregroundStyle(Theme.muted)
                .frame(width: 44, alignment: .leading)
                .monospacedDigit()
                .padding(.top, 4)
            Text(entry.text.isEmpty ? "a photo" : entry.text)
                .font(Theme.serif)
                .foregroundStyle(entry.text.isEmpty ? Theme.faint : Theme.foreground)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Facts as a plain list: the key, the value, and who put it there. Hold one to take it off.
struct FactList: View {
    let facts: [Fact]
    @Bindable var model: NotebookModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(facts) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(fact.key)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.muted)
                        .frame(minWidth: 44, alignment: .leading)
                    Text(fact.value.words(calendar: model.calendar))
                        .font(Theme.sansSmall)
                        .foregroundStyle(Theme.foreground)
                    Spacer(minLength: 0)
                    Who(author: fact.author, model: model)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityIdentifier("fact-\(fact.key)")
                .contextMenu {
                    Button("Take it off", systemImage: "minus.circle", role: .destructive) {
                        withAnimation(Motion.settle) { model.removeFact(fact) }
                    }
                }
            }
        }
    }
}
