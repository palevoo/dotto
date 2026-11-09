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
            if !note.cites.isEmpty {
                // The lines the note speaks of, each a jump: its day and first words.
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(note.cites) { link in
                        NavigationLink(value: link.to) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(Format.shortDay(link.toAt, calendar: model.calendar))
                                    .font(Theme.mono)
                                    .foregroundStyle(Theme.muted)
                                Text(words(of: link.to))
                                    .font(Theme.sansSmall)
                                    .foregroundStyle(Theme.ink(for: note.author, owner: model.store.manifest.owner))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("cite-\(link.to.string)")
                    }
                }
                .padding(.top, 2)
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

    private func words(of line: ULID) -> String {
        let text = model.notebook.entry(line)?.text.replacingOccurrences(of: "\n", with: " ") ?? ""
        return text.isEmpty ? "a photo" : text
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

/// What this line is joined to, as a plain list, grouped: the thread back and forward, done,
/// and the notes that cite it, each by its day and first words. Tap one to go there; hold
/// one to take it back.
struct ThreadList: View {
    let entry: Entry
    @Bindable var model: NotebookModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(entry.carriesOn) { link in
                row(link, other: link.toEntry, label: "from")
            }
            ForEach(entry.carriedOnBy) { link in
                row(link, other: link.fromEntry, label: "on to")
            }
            if let done = entry.done {
                doneRow(done)
            }
            ForEach(entry.citedBy) { link in
                row(link, other: link.fromEntry, label: "cited")
            }
        }
    }

    @ViewBuilder
    private func row(_ link: Core.Link, other id: ULID, label: String) -> some View {
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
}

/// Your earlier lines, newest first, to pick the one this line carries on from.
struct EarlierPicker: View {
    let entry: Entry
    let model: NotebookModel
    let onPick: (ULID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var candidates: [Entry] {
        let joined = Set(entry.carriesOn.map(\.to))
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
