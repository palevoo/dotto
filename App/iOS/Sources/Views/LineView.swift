import Core
import SwiftUI
import UIKit

/// One line, opened: the words at full width and selectable, the photos large, the voice,
/// the thread of replies with a place to answer, the labels, and the history of who did
/// what to it.
struct LineView: View {
    let entryID: ULID
    @Bindable var model: NotebookModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var text = ""
    @State private var replyText = ""
    @State private var viewing: PhotoSelection?
    @Namespace private var zoom
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
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Format.day(DayKey(entry.startedAt, calendar: model.calendar), calendar: model.calendar))
                        .font(Theme.mono)
                        .foregroundStyle(Theme.muted)
                    Text(Format.time(entry.startedAt, calendar: model.calendar))
                        .font(Theme.title)
                        .foregroundStyle(Theme.foreground)
                        .monospacedDigit()
                }

                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    LargePhoto(media: photo, url: model.mediaURL(photo))
                        .matchedTransitionSource(id: photo.hash, in: zoom)
                        .onTapGesture { viewing = PhotoSelection(index: index) }
                }

                ForEach(entry.media.filter { $0.mime.hasPrefix("audio") }) { voice in
                    VoiceChip(hash: voice.hash, duration: voice.duration ?? 0, url: model.mediaURL(voice))
                }

                if editing {
                    TextField(entry.text.isEmpty ? "Words for this" : "", text: $text, axis: .vertical)
                        .font(.system(size: 20, design: .serif))
                        .foregroundStyle(Theme.foreground)
                        .lineSpacing(5)
                        .focused($focused)
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

                VStack(alignment: .leading, spacing: 12) {
                    if !entry.notes.isEmpty {
                        ReplyThread(notes: entry.notes, owner: owner, calendar: model.calendar)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        Theme.square(4)
                            .fill(replying || !replyText.isEmpty ? Theme.foreground.opacity(0.4) : Theme.line)
                            .frame(width: 2)
                        TextField("Reply", text: $replyText, axis: .vertical)
                            .font(Theme.serifSmall)
                            .foregroundStyle(Theme.foreground)
                            .focused($replying)
                            .submitLabel(.send)
                            .onChange(of: replyText) { _, value in
                                guard value.contains("\n") else { return }
                                let words = value.replacingOccurrences(of: "\n", with: " ")
                                replyText = ""
                                withAnimation(Motion.settle) { model.reply(to: entry.id, text: words) }
                                Haptic.store()
                            }
                    }
                    .padding(.top, entry.notes.isEmpty ? 0 : 4)
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

                if !entry.activity.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("History")
                            .font(Theme.mono)
                            .foregroundStyle(Theme.faint)
                        ForEach(entry.activity) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(Format.time(item.at, calendar: model.calendar))
                                    .font(Theme.mono)
                                    .foregroundStyle(Theme.faint)
                                    .frame(width: 44, alignment: .leading)
                                Text(describe(item, owner: owner))
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
        .background(Theme.background.ignoresSafeArea())
        .toolbarBackground(Theme.background, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewing) { selection in
            PhotoViewer(photos: photos, index: selection.index, model: model)
                .navigationTransition(.zoom(sourceID: photos[selection.index].hash, in: zoom))
        }
    }

    private func describe(_ item: Activity, owner: Author) -> String {
        if item.author == owner {
            return "you \(item.what)"
        }
        return "\(item.author.rawValue) \(item.what), via \(item.device.rawValue)"
    }
}

struct PhotoSelection: Identifiable {
    let index: Int
    var id: Int { index }
}

/// A photo at the width of the page, in its own proportions.
struct LargePhoto: View {
    let media: Media
    let url: URL
    @State private var image: UIImage?

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
        .clipShape(Theme.square(96))
        .overlay(Theme.square(96).strokeBorder(Theme.line, lineWidth: 1))
        .contentShape(Theme.square(96))
        .task(id: media.hash) {
            image = await Photo.load(url, maxSide: 1600)
        }
    }
}
