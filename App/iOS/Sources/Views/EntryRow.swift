import Core
import SwiftUI
import UIKit

/// One line on the page: its time in the margin, its words, what sits behind them, and the
/// thread of replies under it. Tap anywhere to open the line; tap a photo to see it; hold
/// for Edit, which changes the words where they are.
struct EntryRow: View {
    let entry: Entry
    @Bindable var model: NotebookModel
    var revealed = false
    /// The line being edited on the page, if any. The page clears it when a tap lands
    /// elsewhere, and the row lets go of the keyboard.
    @Binding var editingRow: ULID?
    let onOpen: () -> Void
    let onOpenPhoto: (PhotoOpening) -> Void
    /// The namespace the viewer's zoom transition finds the photo in.
    let zoom: Namespace.ID
    /// The words while they are being changed here; nil when they are not.
    @State private var draft: String?
    @State private var focused = false

    /// Who has taken this line in without saying anything under it, on a line of today's.
    /// A reply is its own proof, and older days are quiet; their trail is in History.
    private var readWithNothingSaid: Author? {
        guard entry.author == model.store.manifest.owner,
              DayKey(entry.startedAt, calendar: model.calendar) == model.today,
              let who = model.taken[entry.id],
              !entry.notes.contains(where: { $0.author == who }) else { return nil }
        return who
    }

    private var photos: [Media] { entry.media.filter { $0.mime.hasPrefix("image") } }
    private var voices: [Media] { entry.media.filter { $0.mime.hasPrefix("audio") } }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(Format.time(entry.startedAt, calendar: model.calendar))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
                // One place under the time for what was made of the line. Something to do
                // wears its mark there, and the mark is proof enough that it was read.
                if entry.todo != nil {
                    TodoMark(entry: entry, model: model)
                        .padding(.top, -3)
                } else if let who = readWithNothingSaid {
                    // Read, and nothing said: the dot of whoever read, in their colour, so silence
                    // after a line is told apart from a line nobody has got to yet.
                    DotShape(who.dot)
                        .fill(Theme.colour(for: who, owner: model.store.manifest.owner))
                        .frame(width: 6, height: 6)
                        .padding(.leading, 1)
                        .accessibilityElement()
                        .accessibilityLabel("Read by \(model.notebook.name(of: who) ?? "someone")")
                        .accessibilityIdentifier("read-mark")
                }
            }
            .frame(width: 44, alignment: .leading)
            .padding(.top, 6)
            VStack(alignment: .leading, spacing: 10) {
                if entry.author != model.store.manifest.owner {
                    // A line another originator put on your page wears its name.
                    Who(author: entry.author, model: model)
                        .accessibilityIdentifier("by-\(entry.author.rawValue)")
                }
                if !photos.isEmpty {
                    // Several photos run past the edge; the row scrolls sideways.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                                ThumbView(hash: photo.hash, original: model.mediaURL(photo), side: 180)
                                    .matchedTransitionSource(id: PhotoOpening.source(entry.id, photo.hash), in: zoom) { source in
                                        source.clipShape(Theme.square(180))
                                    }
                                    .accessibilityIdentifier("thumbnail")
                                    .onTapGesture {
                                        onOpenPhoto(PhotoOpening(entry: entry.id, hash: photo.hash, index: index))
                                    }
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
                ForEach(voices) { voice in
                    VoiceChip(hash: voice.hash, duration: voice.duration ?? 0, url: model.mediaURL(voice))
                }
                if draft != nil {
                    // The words stay where they are, at their size and spacing, on paper.
                    // Return stores; so does a tap anywhere else, through the page.
                    WordsField(placeholder: "Words for this", text: $draft.orEmpty, identifier: "line-words", focused: $focused) {
                        finishEditing()
                    }
                    .editingSurface()
                    // Focus is asked for once the field exists, not while the menu is still closing.
                    .onAppear { focused = true }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { finishEditing() }
                    }
                    .onChange(of: editingRow) { _, row in
                        if row != entry.id { finishEditing() }
                    }
                    // A row that leaves the page mid-edit keeps what was typed.
                    .onDisappear { finishEditing() }
                } else if !entry.text.isEmpty {
                    // A finished line is struck through, and that is all the page says of it.
                    let done = entry.done != nil
                    Text(entry.text)
                        .font(Theme.serif)
                        .foregroundStyle(done ? Theme.muted : Theme.foreground)
                        .strikethrough(done, color: Theme.muted)
                        .lineSpacing(4)
                }
                if !entry.notes.isEmpty {
                    ReplyPreview(notes: entry.notes)
                        .padding(.top, 2)
                }
                if let hint = threadHint {
                    // The thread, as one quiet line: a count and the nearest linked line's first words.
                    Text(hint)
                        .font(Theme.sansSmall)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, 2)
                }
                if let hint = shapeHint {
                    // What the line is, as one quiet line: the things it belongs to and its facts.
                    Text(hint)
                        .font(Theme.sansSmall)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, 2)
                        .accessibilityIdentifier("shapes")
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background {
            Theme.square(12)
                .fill(Theme.accent.opacity(revealed ? 0.09 : 0))
                .padding(.horizontal, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu {
            if entry.author == model.store.manifest.owner {
                Button("Edit", systemImage: "pencil") {
                    draft = entry.text
                    editingRow = entry.id
                }
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = entry.text }
                todoButton
                Button("Delete", systemImage: "trash", role: .destructive) { model.delete(entry.id) }
            } else {
                // Someone else's line on your page: yours to drop, never to change.
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = entry.text }
                todoButton
                Button("Drop", systemImage: "trash", role: .destructive) { model.delete(entry.id) }
            }
        }
    }

    /// Your word on whether the line is something to do, when the reading got it wrong or
    /// has not got to it.
    @ViewBuilder
    private var todoButton: some View {
        if entry.todo == nil {
            Button("To do", systemImage: "circle") {
                withAnimation(Motion.settle) { model.setTodo(entry, true) }
            }
        } else {
            Button("Not to do", systemImage: "circle.slash") {
                withAnimation(Motion.settle) { model.setTodo(entry, false) }
            }
        }
    }

    private var threadHint: String? {
        let links = entry.carriesOn + entry.carriedOnBy
        guard let last = links.max(by: { $0.id < $1.id }) else { return nil }
        let other = last.from == entry.id ? last.toEntry : last.fromEntry
        let words = model.notebook.entry(other)?.text.replacingOccurrences(of: "\n", with: " ") ?? ""
        let count = links.count > 1 ? "\(links.count) · " : ""
        return "\(count)\(last.from == entry.id ? "from" : "on to") \(words.isEmpty ? "a photo" : words)"
    }

    /// What the line is, in a few words, as every list of lines says it.
    private var shapeHint: String? { LineHint.words(of: entry, model: model) }

    /// Stores the words and leaves the edit, whichever way it ended. Safe to call twice.
    private func finishEditing() {
        guard let words = draft else { return }
        draft = nil
        focused = false
        if editingRow == entry.id { editingRow = nil }
        model.edit(entry.id, text: words)
    }
}

/// A photo in the app's shape, from the thumbnail cache.
struct ThumbView: View {
    let hash: String
    let original: URL
    let side: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.paper
            }
        }
        .frame(width: side, height: side)
        .clipShape(Theme.square(side))
        .overlay(Theme.square(side).strokeBorder(Theme.line, lineWidth: 1))
        .contentShape(Theme.square(side))
        .task(id: hash) {
            image = await Thumbs.image(hash: hash, original: original)
        }
    }
}

/// A voice note: tap to hear it.
struct VoiceChip: View {
    let hash: String
    let duration: Double
    let url: URL

    var body: some View {
        Button {
            AudioPlayer.shared.toggle(url: url, hash: hash)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: AudioPlayer.shared.playingHash == hash ? "stop.fill" : "play.fill")
                    .font(.system(size: 10))
                Text("Voice · \(Format.duration(duration))")
                    .font(Theme.mono)
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Theme.square(32).fill(Theme.paper))
            .overlay(Theme.square(32).strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
