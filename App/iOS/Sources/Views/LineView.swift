import Core
import SwiftUI
import UIKit

/// One line, opened: the words at full width and selectable, the photos large, the voice,
/// the lines it carries on from and the ones that carry on from it, the thread of replies
/// with a place to answer, the labels, and the history of who did what to it.
struct LineView: View {
    let entryID: ULID
    @Bindable var model: NotebookModel
    /// A tag on the line was tapped: whoever holds the page filters it by that tag.
    var onFilter: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    /// The words while they are being changed; nil when they are not.
    @State private var draft: String?
    @State private var viewing: PhotoOpening?
    @State private var picking = false
    @Namespace private var zoom
    @State private var focused = false

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
                        // Where, as the line knows it. A name for it comes later, through the door.
                        Text(Format.place(place))
                            .font(Theme.mono)
                            .foregroundStyle(Theme.faint)
                            .padding(.top, 2)
                    }
                }

                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    LargePhoto(media: photo, url: model.mediaURL(photo))
                        .matchedTransitionSource(id: PhotoOpening.source(entry.id, photo.hash), in: zoom) { source in
                            source.clipShape(RoundedRectangle(cornerRadius: LargePhoto.radius, style: .continuous))
                        }
                        .onTapGesture {
                            viewing = PhotoOpening(entry: entry.id, hash: photo.hash, index: index)
                        }
                }

                ForEach(entry.media.filter { $0.mime.hasPrefix("audio") }) { voice in
                    VoiceChip(hash: voice.hash, duration: voice.duration ?? 0, url: model.mediaURL(voice))
                }

                if entry.author != owner {
                    // Whose line this is, when it is not yours.
                    AuthorLabel(author: entry.author, model: model)
                }

                if draft != nil {
                    // The words stay where they are, at their size and spacing; the paper
                    // under them says they are being changed.
                    WordsField(placeholder: "Words for this", text: $draft.orEmpty, size: 20, lineSpacing: 5, identifier: "line-words", focused: $focused) {
                        focused = false
                    }
                    .editingSurface()
                    .id("words")
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused, let words = draft {
                            draft = nil
                            model.edit(entry.id, text: words)
                        }
                    }
                } else if !entry.text.isEmpty {
                    Text(entry.text)
                        .font(.system(size: 20, design: .serif))
                        .foregroundStyle(Theme.foreground)
                        .strikethrough(entry.done != nil, color: Theme.muted)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                } else if entry.author == owner {
                    // A photo or voice without words: the place for them is visible, not hidden behind Edit.
                    Button {
                        draft = ""
                        focused = true
                    } label: {
                        Text("Words for this")
                            .font(.system(size: 20, design: .serif))
                            .foregroundStyle(Theme.faint)
                    }
                    .buttonStyle(.plain)
                }

                // The thread: the lines this one is joined to, and, for your own lines, the way
                // to join it to an earlier one yourself.
                let threaded = !entry.carriesOn.isEmpty || !entry.carriedOnBy.isEmpty || !entry.citedBy.isEmpty || entry.done != nil
                    || !entry.belongsTo.isEmpty || !entry.facts.isEmpty
                if threaded || entry.author == owner {
                    VStack(alignment: .leading, spacing: 10) {
                        if threaded {
                            ThreadList(entry: entry, model: model)
                        }
                        if entry.author == owner {
                            Button("Carries on from…") { picking = true }
                                .font(Theme.mono)
                                .foregroundStyle(Theme.accent)
                                .buttonStyle(.plain)
                        }
                    }
                }

                if !entry.notes.isEmpty {
                    Conversation(notes: entry.notes, model: model)
                        .id("replies")
                }

                if !entry.labels.isEmpty {
                    // Tap a tag to see every line under it.
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
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.text)
                                        .font(Theme.mono)
                                        .foregroundStyle(Theme.muted)
                                    if let before = item.before {
                                        // The words as they were, so nothing is lost by changing them.
                                        Text(before)
                                            .font(Theme.serifSmall)
                                            .foregroundStyle(Theme.muted)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                }

                HStack(spacing: 18) {
                    Button("Copy") { UIPasteboard.general.string = entry.text }
                    // Only the line's own author changes it or takes it away.
                    if entry.author == owner {
                        Button("Edit") { draft = entry.text; focused = true }
                        Button("Delete", role: .destructive) {
                            model.delete(entry.id)
                            dismiss()
                        }
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
        }
        // The place to reply is the last row of the page, like the live line on the main one.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ReplyBar(entry: entry.id, model: model)
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbarBackground(Theme.background, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        // Opening the line reads whatever the inbox holds about it.
        .onAppear { model.lookAt(entry.id) }
        .onDisappear { focused = false }
        .fullScreenCover(item: $viewing) { opening in
            PhotoViewer(opening: opening, model: model) { viewing = nil }
                .ignoresSafeArea()
                .navigationTransition(.zoom(sourceID: opening.id, in: zoom))
        }
        .sheet(isPresented: $picking) {
            EarlierPicker(entry: entry, model: model) { earlier in
                withAnimation(Motion.settle) { model.link(entry.id, from: earlier) }
                Haptic.store()
            }
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
        var before: String? = nil
    }

    /// What was done to the line and who read it, in one order.
    private func history(of entry: Entry, owner: Author) -> [HistoryItem] {
        let done = entry.activity.map { HistoryItem(id: $0.id, at: $0.at, text: describe($0, owner: owner), before: $0.before) }
        let read = model.notebook.reads(of: entry, calendar: model.calendar).map { visit in
            HistoryItem(id: visit.id, at: visit.at,
                        text: "\(who(visit.author)) \(visit.read.what == .photo ? "looked at a photo" : "read this"), via \(visit.device.rawValue)")
        }
        return (done + read).sorted { $0.id < $1.id }
    }

    private func describe(_ item: Activity, owner: Author) -> String {
        if item.author == owner {
            return "you \(item.what)"
        }
        return "\(who(item.author)) \(item.what), via \(item.device.rawValue)"
    }

    /// In a sentence, someone with no name yet is "someone": the mark cannot sit inside text.
    private func who(_ author: Author) -> String {
        model.notebook.name(of: author) ?? "someone"
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
