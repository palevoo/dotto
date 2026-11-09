import Core
import SwiftUI

/// Replies as the page shows them: one quiet line, the latest reply's words, with the count
/// before it when there is more than one. The conversation waits on the line's page.
struct ReplyPreview: View {
    let notes: [Note]

    var body: some View {
        if let last = notes.last {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if notes.count > 1 {
                    Text("\(notes.count)")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.faint)
                        .monospacedDigit()
                }
                Text(last.text)
                    .font(Theme.sansSmall)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

/// The replies under a line, opened: each one who, then the words, with space between.
/// Hold one of yours to change or take it back.
struct Conversation: View {
    let notes: [Note]
    @Bindable var model: NotebookModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(notes) { note in
                ReplyBlock(note: note, model: model)
            }
        }
    }
}

struct ReplyBlock: View {
    let note: Note
    @Bindable var model: NotebookModel
    @State private var editing = false
    @State private var text = ""
    @State private var focused = false

    private var mine: Bool { note.author == model.store.manifest.owner }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Who(author: note.author, model: model)
                Text(Format.time(note.at, calendar: model.calendar))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.faint)
                if note.editedAt != nil {
                    Text("changed")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.faint)
                }
            }
            if editing {
                WordsField(placeholder: "Reply", text: $text, size: 15, lineSpacing: 3, focused: $focused) { finish() }
                    .editingSurface()
                    .onAppear { focused = true }
                    .onChange(of: focused) { _, isFocused in if !isFocused, editing { finish() } }
            } else {
                Text(note.text)
                    .font(Theme.serifSmall)
                    .foregroundStyle(Theme.foreground)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            if mine {
                Button("Edit", systemImage: "pencil") {
                    text = note.text
                    editing = true
                }
            }
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = note.text }
            Button(mine ? "Delete" : "Take it back", systemImage: "trash", role: .destructive) {
                withAnimation(Motion.settle) { model.removeNote(note) }
            }
        }
    }

    private func finish() {
        guard editing else { return }
        editing = false
        focused = false
        model.editNote(note, text: text)
    }
}

/// The place to reply, pinned above the keyboard at the foot of the line's page.
struct ReplyBar: View {
    let entry: ULID
    @Bindable var model: NotebookModel
    @State private var text = ""
    @State private var focused = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            WordsField(placeholder: "Reply", text: $text, size: 15, lineSpacing: 3, focused: $focused) {
                let words = text
                text = ""
                withAnimation(Motion.settle) { model.reply(to: entry, text: words) }
                Haptic.store()
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Theme.background)
        .overlay(alignment: .top) { Theme.line.frame(height: 1) }
        // The keyboard goes with the page it was raised on, not back to the main page.
        .onDisappear { focused = false }
    }
}

/// The lines this one is joined to, as a plain list: each by its day and first words, and
/// "done" where the link says so. Tap one to go there; hold one to take the link back.
struct ThreadList: View {
    let entry: Entry
    @Bindable var model: NotebookModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(entry.earlier) { link in
                row(link, other: link.earlier, label: "from", mark: link.closes ? "done by this line" : nil)
            }
            ForEach(entry.later) { link in
                row(link, other: link.later, label: "on to", mark: link.closes ? "done" : nil)
            }
        }
    }

    @ViewBuilder
    private func row(_ link: Core.Link, other id: ULID, label: String, mark: String?) -> some View {
        if let other = model.notebook.entry(id) {
            NavigationLink(value: other.id) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(label)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.faint)
                        .frame(width: 44, alignment: .leading)
                    Text(Format.shortDay(other.startedAt, calendar: model.calendar))
                        .font(Theme.mono)
                        .foregroundStyle(Theme.muted)
                    Text(other.text.isEmpty ? "a photo" : other.text)
                        .font(Theme.sansSmall)
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let mark {
                        Text(mark)
                            .font(Theme.mono)
                            .foregroundStyle(Theme.accent)
                            .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Take the link back", systemImage: "minus.circle", role: .destructive) {
                    withAnimation(Motion.settle) { model.unlink(link) }
                }
            }
        }
    }
}

/// Your earlier lines, newest first, to pick the one this line carries on from.
struct EarlierPicker: View {
    let entry: Entry
    let model: NotebookModel
    let onPick: (ULID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var candidates: [Entry] {
        let joined = Set(entry.earlier.map(\.earlier))
        let before = model.notebook.entries
            .filter { line in (line.startedAt, line.id) < (entry.startedAt, entry.id) && !joined.contains(line.id) }
            .reversed()
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return Array(before) }
        return before.filter { $0.text.lowercased().contains(needle) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(candidates) { line in
                        Button {
                            onPick(line.id)
                            dismiss()
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Text(Format.shortDay(line.startedAt, calendar: model.calendar))
                                    .font(Theme.mono)
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 52, alignment: .leading)
                                    .padding(.top, 3)
                                Text(line.text.isEmpty ? "a photo" : line.text)
                                    .font(Theme.serifSmall)
                                    .foregroundStyle(Theme.foreground)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Theme.background.ignoresSafeArea())
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Earlier lines")
            .navigationTitle("Carries on from")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
        }
        .presentationBackground(Theme.background)
    }
}
