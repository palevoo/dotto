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
    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    private var photos: [Media] { entry.media.filter { $0.mime.hasPrefix("image") } }
    private var voices: [Media] { entry.media.filter { $0.mime.hasPrefix("audio") } }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(Format.time(entry.startedAt, calendar: model.calendar))
                .font(Theme.mono)
                .foregroundStyle(Theme.muted)
                .frame(width: 44, alignment: .leading)
                .monospacedDigit()
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 10) {
                if !photos.isEmpty {
                    // Several photos run past the edge; the row scrolls sideways.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                                ThumbView(hash: photo.hash, original: model.mediaURL(photo), side: 180)
                                    .onPhotoTap(radius: 180 * 0.22) { source in
                                        onOpenPhoto(PhotoOpening(entry: entry.id, index: index, sources: [photo.hash: source]))
                                    }
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
                ForEach(voices) { voice in
                    VoiceChip(hash: voice.hash, duration: voice.duration ?? 0, url: model.mediaURL(voice))
                }
                if editing {
                    // The words stay where they are, at their size and spacing, on paper.
                    WordsField(placeholder: "Words for this", text: $text, font: Theme.serif,
                               color: Theme.foreground, focused: $focused) {
                        focused = false
                    }
                    .lineSpacing(4)
                    .editingSurface()
                    .onChange(of: focused) { _, isFocused in
                        guard !isFocused else { return }
                        editing = false
                        if editingRow == entry.id { editingRow = nil }
                        model.edit(entry.id, text: text)
                    }
                    .onChange(of: editingRow) { _, row in
                        if row != entry.id { focused = false }
                    }
                } else if !entry.text.isEmpty {
                    // A line a later line finished is struck through, and that is all the page says.
                    let done = entry.closedBy != nil
                    Text(entry.text)
                        .font(Theme.serif)
                        .foregroundStyle(done ? Theme.muted : Theme.foreground)
                        .strikethrough(done, color: Theme.muted)
                        .lineSpacing(4)
                }
                if !entry.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(entry.notes) { note in
                            ReplyMark(note: note, mine: note.author == model.store.manifest.owner)
                        }
                    }
                    .padding(.top, 2)
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
            Button("Edit", systemImage: "pencil") {
                text = entry.text
                editing = true
                editingRow = entry.id
                focused = true
            }
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = entry.text }
            Button("Delete", systemImage: "trash", role: .destructive) { model.delete(entry.id) }
        }
    }
}

/// A reply as it sits on the page: a dot of its writer's ink, then the words, at most two
/// lines. Who and when wait on the line's page.
struct ReplyMark: View {
    let note: Note
    let mine: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Theme.square(6)
                .fill(mine ? Theme.faint : Theme.agent.opacity(0.65))
                .frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
            Text(note.text)
                .font(mine ? Theme.serifSmall : Theme.sansSmall)
                .foregroundStyle(mine ? Theme.foreground : Theme.agent)
                .lineSpacing(2)
                .lineLimit(2)
                .truncationMode(.tail)
        }
    }
}

/// Replies under a line, opened. A hairline runs down the left; each reply says who wrote
/// it and when.
struct ReplyThread: View {
    let notes: [Note]
    let model: NotebookModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Theme.square(4)
                .fill(Theme.agent.opacity(0.5))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(notes) { note in
                    ReplyLine(note: note, model: model)
                }
            }
        }
        .padding(.top, 2)
    }
}

/// One reply: who and when in small type, then the words, selectable.
struct ReplyLine: View {
    let note: Note
    let model: NotebookModel

    private var mine: Bool { note.author == model.store.manifest.owner }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Who(author: note.author, model: model)
                Text("· \(Format.time(note.at, calendar: model.calendar))")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.faint)
            }
            Text(note.text)
                .font(mine ? Theme.serifSmall : Theme.sansSmall)
                .foregroundStyle(mine ? Theme.foreground : Theme.agent)
                .lineSpacing(2)
                .textSelection(.enabled)
        }
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
