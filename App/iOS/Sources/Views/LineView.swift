import Core
import SwiftUI
import UIKit

/// One line, opened: the words at full width and selectable, the photos large, the voice,
/// every reader's note in full, the labels, and the history of who did what to it.
struct LineView: View {
    let entryID: ULID
    @Bindable var model: NotebookModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var text = ""
    @State private var viewing: PhotoSelection?
    @Namespace private var zoom
    @FocusState private var focused: Bool

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
                    Button {
                        viewing = PhotoSelection(index: index)
                    } label: {
                        LargePhoto(media: photo, url: model.mediaURL(photo))
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: photo.hash, in: zoom)
                }

                ForEach(entry.media.filter { $0.mime.hasPrefix("audio") }) { voice in
                    VoiceChip(hash: voice.hash, duration: voice.duration ?? 0, url: model.mediaURL(voice))
                }

                if editing {
                    TextField("", text: $text, axis: .vertical)
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
                }

                if !entry.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(entry.notes) { note in
                            HStack(alignment: .top, spacing: 8) {
                                Theme.square(8)
                                    .fill(Theme.agent)
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(note.text)
                                        .font(Theme.sansSmall)
                                        .foregroundStyle(Theme.agent)
                                        .lineSpacing(2)
                                        .textSelection(.enabled)
                                    Text("\(note.author.rawValue) · \(Format.time(note.at, calendar: model.calendar))")
                                        .font(Theme.mono)
                                        .foregroundStyle(Theme.faint)
                                }
                            }
                        }
                    }
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
                                Text(describe(item, owner: model.store.manifest.owner))
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
        let via = item.device.rawValue
        return "\(item.author.rawValue) \(item.what), via \(via)"
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
        .task(id: media.hash) {
            image = await Photo.load(url, maxSide: 1600)
        }
    }
}
