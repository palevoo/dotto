import Core
import SwiftUI
import UIKit

/// One line on the page: its time in the margin, its words, what sits behind them,
/// and a reader's note in one quiet line. Tap the time to open the line.
struct EntryRow: View {
    let entry: Entry
    @Bindable var model: NotebookModel
    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink(value: entry.id) {
                Text(Format.time(entry.startedAt, calendar: model.calendar))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 28, alignment: .leading)
                    .monospacedDigit()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open this line")
            VStack(alignment: .leading, spacing: 10) {
                if !entry.media.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(entry.media) { media in
                            MediaView(media: media, entry: entry.id, model: model)
                        }
                    }
                }
                if editing {
                    TextField("", text: $text, axis: .vertical)
                        .font(Theme.serif)
                        .foregroundStyle(Theme.foreground)
                        .lineSpacing(4)
                        .focused($focused)
                        .submitLabel(.done)
                        .onChange(of: text) { _, value in
                            guard value.contains("\n") else { return }
                            text = value.replacingOccurrences(of: "\n", with: " ")
                            focused = false
                        }
                        .onChange(of: focused) { _, isFocused in
                            if !isFocused {
                                editing = false
                                model.edit(entry.id, text: text)
                            }
                        }
                } else if !entry.text.isEmpty {
                    Text(entry.text)
                        .font(Theme.serif)
                        .foregroundStyle(Theme.foreground)
                        .lineSpacing(4)
                        .onTapGesture {
                            text = entry.text
                            editing = true
                            focused = true
                        }
                        .contextMenu {
                            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = entry.text }
                            Button("Edit", systemImage: "pencil") { text = entry.text; editing = true; focused = true }
                            Button("Delete", systemImage: "trash", role: .destructive) { model.delete(entry.id) }
                        }
                }
                ForEach(entry.notes) { note in
                    NavigationLink(value: entry.id) {
                        NoteLine(note: note)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

struct MediaView: View {
    let media: Media
    let entry: ULID
    let model: NotebookModel

    var body: some View {
        if media.mime.hasPrefix("image") {
            NavigationLink(value: entry) {
                ThumbView(hash: media.hash, original: model.mediaURL(media), side: 180)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Delete line", systemImage: "trash", role: .destructive) { model.delete(entry) }
            }
        } else if media.mime.hasPrefix("audio") {
            VoiceChip(hash: media.hash, duration: media.duration ?? 0, url: model.mediaURL(media))
        } else {
            Text(media.mime)
                .font(Theme.mono)
                .foregroundStyle(Theme.muted)
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

/// A reader's note as one line on the page. The whole note lives on the line's own page.
struct NoteLine: View {
    let note: Note

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Theme.square(8)
                .fill(Theme.agent)
                .frame(width: 8, height: 8)
                .offset(y: -1)
            Text(note.text)
                .font(Theme.sansSmall)
                .foregroundStyle(Theme.agent)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.top, 2)
        .contentShape(Rectangle())
    }
}
