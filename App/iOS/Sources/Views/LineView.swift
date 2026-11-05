import Core
import SwiftUI
import UIKit

/// One line, opened: the words at full width and selectable, the photos large, the voice,
/// the lines it carries on from and the ones that carry on from it, the thread of replies
/// with a place to answer, the labels, and the history of who did what to it.
struct LineView: View {
    let entryID: ULID
    @Bindable var model: NotebookModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var text = ""
    @State private var replyText = ""
    @State private var viewing: PhotoOpening?
    @FocusState private var focused: Bool
    @FocusState private var replying: Bool

    var body: some View {
        if let entry = model.notebook.entry(entryID) {
            content(entry)
        } else {
            Text("This line is gone.")
                .font(Theme.serifSmall)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background.ignoresSafeArea())
        }
    }

    private func content(_ entry: Entry) -> some View {
        let photos = entry.media.filter { $0.mime.hasPrefix("image") }
        let owner = model.store.manifest.owner
        return ScrollViewReader { proxy in
            ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Format.day(DayKey(entry.startedAt, calendar: model.calendar), calendar: model.calendar))
                        .font(Theme.mono)
                        .foregroundStyle(Theme.muted)
                    Text(Format.time(entry.startedAt, calendar: model.calendar))
                        .font(Theme.title)
                        .foregroundStyle(Theme.foreground)
                        .monospacedDigit()
                    if let place = entry.location {
                        // Where, as the line knows it. A name for it comes later, from a reader.
                        Text(Format.place(place))
                            .font(Theme.mono)
                            .foregroundStyle(Theme.faint)
                            .padding(.top, 2)
                    }
                }

                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    LargePhoto(media: photo, url: model.mediaURL(photo))
                        .onPhotoTap(radius: LargePhoto.radius) { source in
                            withoutAnimation { viewing = PhotoOpening(entry: entry.id, index: index, sources: [photo.hash: source]) }
                        }
                }

                ForEach(entry.media.filter { $0.mime.hasPrefix("audio") }) { voice in
                    VoiceChip(hash: voice.hash, duration: voice.duration ?? 0, url: model.mediaURL(voice))
                }

                if editing {
                    // The words stay where they are, at their size and spacing; the paper
                    // under them says they are being changed.
                    WordsField(placeholder: "Words for this", text: $text, font: .system(size: 20, design: .serif),
                               color: Theme.foreground, focused: $focused) {
                        focused = false
                    }
                    .lineSpacing(5)
                    .editingSurface()
                    .id("words")
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused {
                            editing = false
                            model.edit(entry.id, text: text)
                        }
                    }
                } else if !entry.text.isEmpty {
                    Text(entry.text)
                        .font(.system(size: 20, design: .serif))
                        .foregroundStyle(Theme.foreground)
                        .strikethrough(entry.closedBy != nil, color: Theme.muted)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                } else {
                    // A photo or voice without words: the place for them is visible, not hidden behind Edit.
                    Button {
                        text = ""
                        editing = true
                        focused = true
                    } label: {
                        Text("Words for this")
                            .font(.system(size: 20, design: .serif))
                            .foregroundStyle(Theme.faint)
                    }
                    .buttonStyle(.plain)
                }

                if !entry.earlier.isEmpty || !entry.later.isEmpty {
                    ThreadView(entry: entry, model: model)
                }

                VStack(alignment: .leading, spacing: 12) {
                    if !entry.notes.isEmpty {
                        ReplyThread(notes: entry.notes, owner: owner, calendar: model.calendar)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        Theme.square(4)
                            .fill(replying || !replyText.isEmpty ? Theme.foreground.opacity(0.4) : Theme.line)
                            .frame(width: 2)
                        WordsField(placeholder: "Reply", text: $replyText, font: Theme.serifSmall,
                                   color: Theme.foreground, focused: $replying) {
                            let words = replyText
                            replyText = ""
                            withAnimation(Motion.settle) { model.reply(to: entry.id, text: words) }
                            Haptic.store()
                        }
                    }
                    .padding(.top, entry.notes.isEmpty ? 0 : 4)
                    .id("reply")
                }

                if !entry.labels.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(entry.labels, id: \.self) { label in
                            Text("#\(label)")
                                .font(Theme.mono)
                                .foregroundStyle(Theme.muted)
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .background(Theme.square(26).fill(Theme.paper))
                                .overlay(Theme.square(26).strokeBorder(Theme.line, lineWidth: 1))
                        }
                    }
                }

                let history = history(of: entry, owner: owner)
                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("History")
                            .font(Theme.mono)
                            .foregroundStyle(Theme.faint)
                        ForEach(history) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(Format.time(item.at, calendar: model.calendar))
                                    .font(Theme.mono)
                                    .foregroundStyle(Theme.faint)
                                    .frame(width: 44, alignment: .leading)
                                Text(item.text)
                                    .font(Theme.mono)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .padding(.top, 6)
                }

                HStack(spacing: 18) {
                    Button("Copy") { UIPasteboard.general.string = entry.text }
                    Button("Edit") { text = entry.text; editing = true; focused = true }
                    Button("Delete", role: .destructive) {
                        model.delete(entry.id)
                        dismiss()
                    }
                }
                .font(Theme.mono)
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
                .padding(.top, 10)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            // The field being written in stays above the keyboard.
            .onChange(of: focused) { _, isFocused in if isFocused { show("words", proxy) } }
            .onChange(of: replying) { _, isReplying in if isReplying { show("reply", proxy) } }
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbarBackground(Theme.background, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewing) { opening in
            PhotoViewer(opening: opening, model: model) { withoutAnimation { viewing = nil } }
        }
    }

    private func show(_ id: String, _ proxy: ScrollViewProxy) {
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(Motion.settle) { proxy.scrollTo(id, anchor: .center) }
        }
    }

    private struct HistoryItem: Identifiable {
        let id: ULID
        let at: Date
        let text: String
    }

    /// What was done to the line and who read it, in one order.
    private func history(of entry: Entry, owner: Author) -> [HistoryItem] {
        let done = entry.activity.map { HistoryItem(id: $0.id, at: $0.at, text: describe($0, owner: owner)) }
        let read = model.notebook.reads(of: entry, calendar: model.calendar).map { visit in
            HistoryItem(id: visit.id, at: visit.at,
                        text: "\(visit.author.rawValue) \(visit.read.what == .photo ? "looked at a photo" : "read this"), via \(visit.device.rawValue)")
        }
        return (done + read).sorted { $0.id < $1.id }
    }

    private func describe(_ item: Activity, owner: Author) -> String {
        if item.author == owner {
            return "you \(item.what)"
        }
        return "\(item.author.rawValue) \(item.what), via \(item.device.rawValue)"
    }
}

/// The lines this one carries on from, and the ones that carry on from it, as a reader
/// placed them: in the reader's ink, each a day and the line's first words. Tap one to go
/// there; hold one to take the link back.
struct ThreadView: View {
    let entry: Entry
    @Bindable var model: NotebookModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Theme.square(4)
                .fill(Theme.agent.opacity(0.5))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 10) {
                group("earlier", entry.earlier, side: \.earlier) { $0.closes ? "done by this line" : nil }
                group("later", entry.later, side: \.later) { $0.closes ? "done" : nil }
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func group(_ title: String, _ links: [Core.Link], side: KeyPath<Core.Link, ULID>, mark: @escaping (Core.Link) -> String?) -> some View {
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.agent.opacity(0.7))
                ForEach(links) { link in
                    if let other = model.notebook.entry(link[keyPath: side]) {
                        NavigationLink(value: other.id) {
                            ThreadRow(line: other, mark: mark(link), calendar: model.calendar)
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
        }
    }
}

/// One line of the thread: when, then its first words, then what the link says about it.
struct ThreadRow: View {
    let line: Entry
    let mark: String?
    let calendar: Calendar

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Format.shortDay(line.startedAt, calendar: calendar))
                .font(Theme.mono)
                .foregroundStyle(Theme.agent.opacity(0.7))
                .frame(width: 44, alignment: .leading)
            Text(line.text.isEmpty ? "a photo" : line.text)
                .font(Theme.sansSmall)
                .foregroundStyle(Theme.agent)
                .lineLimit(2)
                .truncationMode(.tail)
            if let mark {
                Text(mark)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.agent.opacity(0.7))
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A photo at the width of the page, in its own proportions.
struct LargePhoto: View {
    let media: Media
    let url: URL
    @State private var image: UIImage?

    static let radius: CGFloat = 96 * 0.22

    private var ratio: CGFloat {
        guard let width = media.width, let height = media.height, width > 0, height > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }

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
        .aspectRatio(ratio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .task(id: media.hash) {
            image = await Photo.load(url, maxSide: 1600)
        }
    }
}
