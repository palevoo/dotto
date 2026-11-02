import Core
import SwiftUI
import UIKit

/// Photos of one line, full screen. Swipe sideways between them, pinch or double-tap to
/// zoom. Closing is the system's own: drag the photo down or pinch it shut, and it returns
/// to where it came from. The line's words sit under the photo, and can be written here.
struct PhotoViewer: View {
    let entryID: ULID
    @State var index: Int
    let model: NotebookModel
    @Environment(\.dismiss) private var dismiss
    @State private var words = ""
    @State private var editing = false
    @FocusState private var focused: Bool

    private var entry: Entry? { model.notebook.entry(entryID) }
    private var photos: [Media] { entry?.media.filter { $0.mime.hasPrefix("image") } ?? [] }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { position, photo in
                    ZoomableImage(hash: photo.hash, url: model.mediaURL(photo))
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .never))
            .ignoresSafeArea()

            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 44, height: 44)
                    .background(Theme.square(44).fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            .padding(.top, 8)
            .accessibilityLabel("Close")
        }
        .overlay(alignment: .bottom) { caption }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .onChange(of: focused) { _, isFocused in
            if !isFocused, editing { store() }
        }
    }

    /// The words of the line, or the place for them. Return stores.
    private var caption: some View {
        Group {
            if editing {
                WordsField(placeholder: "Words for this", text: $words, font: Theme.serif, color: .white, focused: $focused) {
                    store()
                }
            } else {
                Button {
                    words = entry?.text ?? ""
                    editing = true
                    focused = true
                } label: {
                    let text = entry?.text ?? ""
                    Text(text.isEmpty ? "Words for this" : text)
                        .font(Theme.serif)
                        .foregroundStyle(Color.white.opacity(text.isEmpty ? 0.4 : 0.92))
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func store() {
        editing = false
        focused = false
        model.edit(entryID, text: words)
    }

    private func close() {
        if editing { store() }
        dismiss()
    }
}

/// One photo: pinch or double-tap to zoom, drag to pan when zoomed. Unzoomed it has no
/// drag of its own, so the system's pull-to-close and the pager's swipe are the only hands
/// on it. The first frame is the thumbnail already in memory; the full photo replaces it.
struct ZoomableImage: View {
    let hash: String
    let url: URL
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        scale = max(1, min(5, settledScale * value.magnification))
                    }
                    .onEnded { _ in
                        settledScale = scale
                        if scale <= 1.02 {
                            withAnimation(Motion.settle) { reset() }
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        offset = CGSize(width: settledOffset.width + value.translation.width,
                                        height: settledOffset.height + value.translation.height)
                    }
                    .onEnded { _ in
                        settledOffset = offset
                    },
                isEnabled: scale > 1
            )
            .onTapGesture(count: 2) {
                withAnimation(Motion.settle) {
                    if scale > 1 {
                        reset()
                    } else {
                        scale = 2.5
                        settledScale = 2.5
                    }
                }
            }
        }
        .onAppear {
            if image == nil { image = Thumbs.cached(hash) }
        }
        .task(id: url) {
            if let full = await Photo.load(url) { image = full }
        }
    }

    private func reset() {
        scale = 1
        settledScale = 1
        offset = .zero
        settledOffset = .zero
    }
}

/// Words for a line, edited in place. Return stores them; a newline never lands in a line.
struct WordsField: View {
    let placeholder: String
    @Binding var text: String
    let font: Font
    let color: Color
    var focused: FocusState<Bool>.Binding
    let onCommit: () -> Void

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1...8)
            .focused(focused)
            .submitLabel(.done)
            .textInputAutocapitalization(.sentences)
            .onChange(of: text) { _, value in
                guard value.contains("\n") else { return }
                text = value.replacingOccurrences(of: "\n", with: " ")
                onCommit()
            }
    }
}
