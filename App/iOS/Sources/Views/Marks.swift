import Core
import SwiftUI

/// What a line is, in one place: the things it is with, done and by what, the facts on it,
/// the tags it is under. Every row is someone's mark, signed where it matters, and every
/// one goes with a hold. Tap a thing or a tag to open its page.
struct MarksBlock: View {
    let entry: Entry
    @Bindable var model: NotebookModel

    /// Whether there is anything to show at all.
    static func has(_ entry: Entry) -> Bool {
        !entry.belongsTo.isEmpty || entry.done != nil || !entry.standingFacts.isEmpty
    }

    /// The links to things made by someone, and the links to tags, apart.
    private var things: [Core.Link] { entry.belongsTo.filter { !$0.to.isTag } }
    private var tagLinks: [Core.Link] { entry.belongsTo.filter { $0.to.isTag } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(things) { link in
                thingRow(link)
            }
            if let done = entry.done {
                doneRow(done)
            }
            if !entry.standingFacts.isEmpty {
                FactList(facts: entry.standingFacts, model: model)
            }
            if !tagLinks.isEmpty {
                tags
            }
        }
    }

    /// A thing this line is with: its name and kind, a jump; hold to take the line out.
    @ViewBuilder
    private func thingRow(_ link: Core.Link) -> some View {
        if let thing = model.notebook.thing(link.to) {
            NavigationLink(value: Route.thing(thing.id)) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("with")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.faint)
                        .frame(width: 44, alignment: .leading)
                    Text(thing.name)
                        .font(Theme.sansSmall)
                        .foregroundStyle(Theme.foreground)
                    if let kind = thing.kind {
                        Text(kind)
                            .font(Theme.mono)
                            .foregroundStyle(Theme.faint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("with-\(thing.name)")
            .contextMenu {
                Button("Take it out", systemImage: "minus.circle", role: .destructive) {
                    withAnimation(Motion.settle) { model.unlink(link) }
                }
            }
        }
    }

    /// Finished, and by which line when one did. Hold to open the line again.
    @ViewBuilder
    private func doneRow(_ done: Done) -> some View {
        let by = done.by.flatMap { model.notebook.entry($0) }
        let content = HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("done")
                .font(Theme.mono)
                .foregroundStyle(Theme.accent)
                .frame(width: 44, alignment: .leading)
            if let by {
                Text(Format.shortDay(by.startedAt, calendar: model.calendar))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.muted)
                Text(by.text.isEmpty ? "a photo" : by.text)
                    .font(Theme.sansSmall)
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Who(author: done.author, model: model)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        Group {
            if let by {
                NavigationLink(value: by.id) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
        .contextMenu {
            Button("Open it again", systemImage: "arrow.uturn.backward", role: .destructive) {
                withAnimation(Motion.settle) { model.undone(entry.id) }
            }
        }
    }

    /// Tags, each a way to its page, with every line under it. Hold one to take it off.
    private var tags: some View {
        HStack(spacing: 8) {
            ForEach(tagLinks) { link in
                if let tag = model.notebook.thing(link.to) {
                    NavigationLink(value: Route.thing(tag.id)) {
                        Text("#\(tag.name)")
                            .font(Theme.mono)
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Theme.square(26).fill(Theme.paper))
                            .overlay(Theme.square(26).strokeBorder(Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tag-\(tag.name)")
                    .contextMenu {
                        Button("Take it off", systemImage: "minus.circle", role: .destructive) {
                            withAnimation(Motion.settle) { model.unlink(link) }
                        }
                    }
                }
            }
        }
    }
}

/// The mark on a line that is something to do, the same wherever the line is drawn: a ring
/// in the one colour while it is open, filled and quiet once it is done. Tap it to finish
/// the line where it stands; tap it again to open it. Nothing else on the page moves.
struct TodoMark: View {
    let entry: Entry
    @Bindable var model: NotebookModel
    var size: CGFloat = 15

    var body: some View {
        let done = entry.done != nil
        Button {
            withAnimation(Motion.settle) { model.toggleDone(entry) }
        } label: {
            ZStack {
                Circle().strokeBorder(done ? Theme.faint : Theme.accent, lineWidth: 1.5)
                Circle().fill(Theme.faint).padding(3.5).opacity(done ? 1 : 0)
            }
            .frame(width: size, height: size)
            // A thumb's worth of room around a small mark.
            .frame(width: 36, height: 30, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: done)
        .accessibilityIdentifier("todo-mark")
        .accessibilityLabel(done ? "Done" : "To do")
        .accessibilityHint(done ? "Opens it again" : "Marks it done")
    }
}

/// A line's words as every list of lines draws them: in the serif, struck through and quiet
/// when the line is finished, "a photo" when it has none.
struct LineWords: View {
    let entry: Entry

    var body: some View {
        let done = entry.done != nil
        Text(entry.text.isEmpty ? "a photo" : entry.text)
            .font(Theme.serif)
            .foregroundStyle(done ? Theme.muted : entry.text.isEmpty ? Theme.faint : Theme.foreground)
            .strikethrough(done && !entry.text.isEmpty, color: Theme.muted)
            .lineSpacing(4)
    }
}

/// What a line is, in a few words: the things it is with, its moment, its facts, what was
/// kept beside it, its tags. "fig · due 12 Nov 11:30 · #garden". The same words wherever
/// lines are listed, so a line reads alike on its day, on a thing's page and among what is
/// coming. On a thing's own page the thing is left out, being the page.
enum LineHint {
    @MainActor
    static func words(of entry: Entry, model: NotebookModel, on page: ULID? = nil, moment shown: Bool = true) -> String? {
        let calendar = model.calendar
        let things = entry.belongsTo.compactMap { link -> String? in
            guard link.to != page, let thing = model.notebook.thing(link.to), !thing.isTag else { return nil }
            return thing.name
        }
        var facts: [String] = []
        // Its moment first, while the line is open. An event simply happens then; something
        // to do is due then. That it is to do is said by its mark, not in words.
        if shown, entry.done == nil, let moment = entry.moment {
            let words = "\(Format.shortDay(moment, calendar: calendar)) \(Format.time(moment, calendar: calendar))"
            facts.append(entry.at == nil && entry.todo != nil ? "due \(words)" : words)
        }
        var seen: Set<String> = ["todo", "due", "at"]
        for fact in entry.facts where seen.insert(fact.key).inserted {
            if fact.key == "break" {
                // The day a streak broke, when the line names another day than its own.
                if case .moment(let happened) = fact.value {
                    facts.append("broke \(Format.shortDay(happened, calendar: calendar))")
                } else {
                    facts.append("broke")
                }
            } else {
                facts.append("\(fact.key) \(fact.value.words(calendar: calendar))")
            }
        }
        // What the line points at, once the home has opened it and kept it beside the line.
        let kept = entry.media.filter(\.isKept).map { "kept: \($0.title ?? $0.source ?? "a page")" }
        let tags = entry.belongsTo.compactMap { link -> String? in
            guard link.to != page, let tag = model.notebook.thing(link.to), tag.isTag else { return nil }
            return "#\(tag.name)"
        }
        let parts = things + facts + kept + tags
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A line in a list: its words, and under them what it is, in the same quiet words as on
/// its day.
struct ListedLine: View {
    let entry: Entry
    @Bindable var model: NotebookModel
    /// The thing whose page this is, left out of what the line says of itself.
    var page: ULID?
    /// Whether its moment is said; not where the list is already by moment.
    var moment = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LineWords(entry: entry)
            if let hint = LineHint.words(of: entry, model: model, on: page, moment: moment) {
                Text(hint)
                    .font(Theme.sansSmall)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("line-hint")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
