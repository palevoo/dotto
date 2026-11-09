import Core
import SwiftUI

/// What a line is, in one place: the things it is with, done and by what, the facts on it,
/// the tags it is filed under. Every row is someone's mark, signed where it matters, and
/// every one goes with a hold. Tap a thing to open its page, a tag to see its lines.
struct MarksBlock: View {
    let entry: Entry
    @Bindable var model: NotebookModel
    var onFilter: ((String) -> Void)? = nil

    /// Whether there is anything to show at all.
    static func has(_ entry: Entry) -> Bool {
        !entry.belongsTo.isEmpty || entry.done != nil || !entry.facts.isEmpty || !entry.labels.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(entry.belongsTo) { link in
                thingRow(link)
            }
            if let done = entry.done {
                doneRow(done)
            }
            if !entry.facts.isEmpty {
                FactList(facts: entry.facts, model: model)
            }
            if !entry.labels.isEmpty {
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

    /// Tags, each a way to every line under it.
    private var tags: some View {
        HStack(spacing: 8) {
            ForEach(entry.labels, id: \.self) { label in
                Button {
                    onFilter?(label)
                } label: {
                    Text("#\(label)")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Theme.square(26).fill(Theme.paper))
                        .overlay(Theme.square(26).strokeBorder(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tag-\(label)")
            }
        }
    }
}
