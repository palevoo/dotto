import Core
import SwiftUI
import UIKit

/// Photos of one line, full screen, with one hand on all of it. A sideways drag pages; a
/// drag in any other direction, at any angle, throws the photo while the page shows through
/// behind it, and letting go past a point closes it back into its thumbnail. Pinch or
/// double-tap to zoom. No pager of its own, so nothing competes for the first movement.
struct PhotoViewer: View {
    let entryID: ULID
    @State var index: Int
    let model: NotebookModel
    @Environment(\.dismiss) private var dismiss
    @State private var drag: CGSize = .zero
    @State private var axis: Axis?
    @State private var zoomed = false
    @State private var words = ""
    @State private var editing = false
    @FocusState private var focused: Bool

    private var entry: Entry? { model.notebook.entry(entryID) }
    private var photos: [Media] { entry?.media.filter { $0.mime.hasPrefix("image") } ?? [] }

    private var thrown: CGFloat { axis == .vertical ? abs(drag.height) : 0 }
    private var fade: Double { 1 - min(Double(thrown) / 320, 0.85) }
    private var shrink: CGFloat { 1 - min(thrown / 1200, 0.25) }
    private var neighbours: [Int] { [index - 1, index, index + 1].filter { $0 >= 0 && $0 < photos.count } }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let width = geometry.size.width
                let gap: CGFloat = 24
                ZStack {
                    ForEach(neighbours, id: \.self) { position in
                        let photo = photos[position]
                        let current = position == index
                        ZoomableImage(hash: photo.hash, url: model.mediaURL(photo), zoomed: current ? $zoomed : .constant(false))
                            .frame(width: width, height: geometry.size.height)
                            .scaleEffect(current ? shrink : 1)
                            .offset(
                                x: CGFloat(position - index) * (width + gap) + (axis == .horizontal ? drag.width : 0),
                                y: current && axis == .vertical ? drag.height : 0
                            )
                    }
                }
                .frame(width: width, height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(hand(step: width + gap, width: width), isEnabled: !zoomed)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                top
                Spacer(minLength: 0)
                caption
            }
            .opacity(axis == nil ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: axis == nil)
        }
        .background(Color.black.opacity(fade).ignoresSafeArea())
        .presentationBackground(.clear)
        .statusBarHidden()
        .onChange(of: focused) { _, isFocused in
            if !isFocused, editing { store() }
        }
    }

    /// Which photo this is, and the way out for a thumb that would rather tap.
    private var top: some View {
        HStack {
            if photos.count > 1 {
                Text("\(index + 1) / \(photos.count)")
                    .font(Theme.mono)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .monospacedDigit()
                    .padding(.leading, 20)
            }
            Spacer()
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
            .accessibilityLabel("Close")
        }
        .padding(.top, 8)
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

    /// One drag for paging and closing. The first movement decides which it is.
    private func hand(step: CGFloat, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                if axis == nil {
                    axis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                }
                drag = value.translation
            }
            .onEnded { value in
                switch axis {
                case .horizontal:
                    let predicted = value.predictedEndTranslation.width
                    var turn = 0
                    if predicted < -width / 3, index < photos.count - 1 { turn = 1 }
                    if predicted > width / 3, index > 0 { turn = -1 }
                    withAnimation(.snappy(duration: 0.32, extraBounce: 0)) {
                        drag.width = -CGFloat(turn) * step
                    } completion: {
                        index += turn
                        drag = .zero
                        axis = nil
                    }
                case .vertical:
                    if abs(value.predictedEndTranslation.height) > 140 {
                        close()
                    } else {
                        withAnimation(.snappy(duration: 0.32, extraBounce: 0)) {
                            drag = .zero
                        } completion: {
                            axis = nil
                        }
                    }
                case nil:
                    drag = .zero
                }
            }
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
/// drag of its own; the viewer's one hand does the rest. The first frame is the thumbnail
/// already in memory; the full photo replaces it.
struct ZoomableImage: View {
    let hash: String
    let url: URL
    @Binding var zoomed: Bool
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
                        zoomed = scale > 1
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
                        zoomed = true
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
        zoomed = false
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
