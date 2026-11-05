import Core
import SwiftUI
import UIKit

/// Where a photo sits on the page at the moment it is tapped, in the window's coordinates,
/// so the viewer can grow out of that place and shrink back into it.
struct PhotoSource: Hashable {
    var frame: CGRect
    var radius: CGFloat
}

/// A line's photo, opened, with the place it was opened from.
struct PhotoOpening: Identifiable {
    let entry: ULID
    let index: Int
    /// The place of the photo that was tapped, by hash. Other photos of the line, reached by
    /// paging, have no place and fade out instead.
    let sources: [String: PhotoSource]
    var id: String { "\(entry)-\(index)" }
}

/// The viewer draws its own way in and out, so the cover that holds it must not.
func withoutAnimation(_ change: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, change)
}

/// Photos of one line, on the page's own background. The photo lifts off its thumbnail and
/// settles fitted to the screen; a drag in any direction carries it, the page showing
/// through, and letting go past a point sets it back where it came from. A sideways drag
/// pages. Pinch or double-tap to zoom. No pager of its own, so nothing competes for the
/// first movement.
struct PhotoViewer: View {
    let opening: PhotoOpening
    let model: NotebookModel
    let onClose: () -> Void

    @State private var index: Int
    /// False while the photo is at its place on the page, before it has grown and after it
    /// has shrunk back.
    @State private var shown = false
    @State private var images: [String: UIImage]
    @State private var full: Set<String> = []
    @State private var drag: CGSize = .zero
    @State private var axis: Axis?
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var settledPan: CGSize = .zero
    @State private var words = ""
    @State private var editing = false
    /// The words in the photo selectable, to take a quote from a page.
    @State private var reading = false
    @State private var selected = ""
    @FocusState private var focused: Bool

    private let gap: CGFloat = 24

    init(opening: PhotoOpening, model: NotebookModel, onClose: @escaping () -> Void) {
        self.opening = opening
        self.model = model
        self.onClose = onClose
        _index = State(initialValue: opening.index)
        // The first frame must be the thumbnail the page already shows, with no wait.
        var first: [String: UIImage] = [:]
        for photo in model.notebook.entry(opening.entry)?.media ?? [] where photo.mime.hasPrefix("image") {
            if let thumb = Thumbs.cached(photo.hash) { first[photo.hash] = thumb }
        }
        _images = State(initialValue: first)
    }

    private var entry: Entry? { model.notebook.entry(opening.entry) }
    private var photos: [Media] { entry?.media.filter { $0.mime.hasPrefix("image") } ?? [] }
    private var zoomed: Bool { scale > 1 }

    private var thrown: CGFloat { axis == .vertical ? abs(drag.height) : 0 }
    private var fade: Double { 1 - min(Double(thrown) / 320, 0.85) }
    private var shrink: CGFloat { 1 - min(thrown / 1200, 0.25) }
    private var neighbours: [Int] { [index, index - 1, index + 1].filter { $0 >= 0 && $0 < photos.count } }
    private var calm: Bool { shown && axis == nil }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let size = geometry.size
                ZStack {
                    Theme.background.opacity(shown ? fade : 0)
                    ForEach(neighbours, id: \.self) { position in
                        photo(at: position, in: size)
                    }
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(hand(step: size.width + gap, width: size.width), isEnabled: !zoomed && !reading)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                top
                Spacer(minLength: 0)
                caption
            }
            .opacity(calm ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: calm)
        }
        .presentationBackground(.clear)
        .onAppear {
            withAnimation(.snappy(duration: 0.38, extraBounce: 0)) { shown = true }
        }
        .task(id: index) { await loadFull() }
        .onChange(of: focused) { _, isFocused in
            if !isFocused, editing { store() }
        }
    }

    /// One photo where it belongs now: at its place on the page before it is shown and after
    /// it is closed, fitted to the screen in between, a page-width to the side when it is a
    /// neighbour. The frame and corners animate between the two, so the thumbnail becomes
    /// the photo and back.
    @ViewBuilder
    private func photo(at position: Int, in size: CGSize) -> some View {
        let photo = photos[position]
        let current = position == index
        let fitted = fitted(photo, in: size)
        let source = current && !shown ? opening.sources[photo.hash] : nil
        let rect = source?.frame ?? (current && !shown ? fitted.shrunk(to: 0.6) : fitted)
        let radius = source?.radius ?? 0
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if current, reading, let image = images[photo.hash] {
                LiveTextView(image: image) { selected = $0 }
            } else if let image = images[photo.hash] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.paper
            }
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(shape)
        .contentShape(shape)
        // A photo with no place to go back to fades out instead.
        .opacity(current && !shown && source == nil ? 0 : 1)
        .scaleEffect(current ? scale * shrink : 1)
        .offset(current ? pan : .zero)
        .position(
            x: rect.midX + CGFloat(position - index) * (size.width + gap) + (axis == .horizontal ? drag.width : 0),
            y: rect.midY + (current && axis == .vertical ? drag.height : 0)
        )
        .gesture(pinch, isEnabled: current && calm && !reading)
        .simultaneousGesture(panning, isEnabled: current && zoomed)
        .onTapGesture(count: 2) {
            guard current, calm, !reading else { return }
            withAnimation(Motion.settle) {
                if zoomed {
                    resetZoom()
                } else {
                    scale = 2.5
                    settledScale = 2.5
                }
            }
        }
    }

    /// The photo at the width or height of the screen, whichever it reaches first, centred.
    private func fitted(_ photo: Media, in size: CGSize) -> CGRect {
        var ratio: CGFloat = 1
        if let width = photo.width, let height = photo.height, width > 0, height > 0 {
            ratio = CGFloat(width) / CGFloat(height)
        } else if let image = images[photo.hash], image.size.height > 0 {
            ratio = image.size.width / image.size.height
        }
        let width = min(size.width, size.height * ratio)
        let height = width / ratio
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    /// The photo on screen at viewing size, then its neighbours, each once.
    private func loadFull() async {
        for position in neighbours {
            let photo = photos[position]
            guard !full.contains(photo.hash) else { continue }
            if let image = await Photo.load(model.mediaURL(photo)) {
                images[photo.hash] = image
                full.insert(photo.hash)
            }
        }
    }

    /// Which photo this is, the words in it, and the way out for a thumb that would rather tap.
    /// While reading, the selected words can be taken as a quote into the line.
    private var top: some View {
        HStack(spacing: 8) {
            if reading {
                Button {
                    quote()
                } label: {
                    Text("Quote")
                        .font(Theme.sansSmall.weight(.medium))
                        .foregroundStyle(selected.isEmpty ? Theme.faint : Theme.background)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Theme.square(36).fill(selected.isEmpty ? Theme.paper : Theme.accent))
                }
                .buttonStyle(.plain)
                .disabled(selected.isEmpty)
                .padding(.leading, 12)
                Text(selected.isEmpty ? "Select words in the photo" : "\(selected.split(separator: " ").count) words")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            } else if photos.count > 1 {
                Text("\(index + 1) / \(photos.count)")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
                    .padding(.leading, 20)
            }
            Spacer()
            if reading {
                button("xmark", label: "Done reading") {
                    reading = false
                    selected = ""
                }
            } else {
                if LiveTextView.isSupported, full.contains(photos[index].hash) {
                    button("text.viewfinder", label: "Read the words in the photo") {
                        withAnimation(Motion.settle) { resetZoom() }
                        selected = ""
                        reading = true
                    }
                }
                button("xmark", label: "Close") { close() }
            }
        }
        .padding(.top, 8)
        .padding(.trailing, 12)
    }

    private func button(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.foreground)
                .frame(width: 44, height: 44)
                .background(Theme.square(44).fill(Theme.background.opacity(0.85)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// The selected words join the line's, in quotes. An edit like any other: the words
    /// before stay in the line's history.
    private func quote() {
        let passage = selected.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        guard !passage.isEmpty else { return }
        let quoted = "\u{201C}\(passage)\u{201D}"
        let words = (entry?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        model.edit(opening.entry, text: words.isEmpty ? quoted : "\(words) \(quoted)")
        Haptic.store()
        reading = false
        selected = ""
    }

    /// The words of the line, or the place for them. Return stores.
    private var caption: some View {
        Group {
            if editing {
                WordsField(placeholder: "Words for this", text: $words, font: Theme.serif, color: Theme.foreground, focused: $focused) {
                    store()
                }
                .lineSpacing(4)
                .editingSurface()
            } else {
                Button {
                    words = entry?.text ?? ""
                    editing = true
                    focused = true
                } label: {
                    let text = entry?.text ?? ""
                    Text(text.isEmpty ? "Words for this" : text)
                        .font(Theme.serif)
                        .foregroundStyle(text.isEmpty ? Theme.faint : Theme.foreground)
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
            // So the words read over a photo that reaches the bottom.
            LinearGradient(colors: [Theme.background.opacity(0), Theme.background.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Hands

    /// One drag for paging and closing. The first movement decides which it is.
    private func hand(step: CGFloat, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard shown else { return }
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

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = max(1, min(5, settledScale * value.magnification))
            }
            .onEnded { _ in
                settledScale = scale
                if scale <= 1.02 {
                    withAnimation(Motion.settle) { resetZoom() }
                }
            }
    }

    private var panning: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                pan = CGSize(width: settledPan.width + value.translation.width,
                             height: settledPan.height + value.translation.height)
            }
            .onEnded { _ in
                settledPan = pan
            }
    }

    private func resetZoom() {
        scale = 1
        settledScale = 1
        pan = .zero
        settledPan = .zero
    }

    private func store() {
        editing = false
        focused = false
        model.edit(opening.entry, text: words)
    }

    /// Back to the page: the photo returns to its place from wherever the hand left it, the
    /// page comes through behind, and only then does the cover go, with no motion of its own.
    private func close() {
        if editing { store() }
        reading = false
        withAnimation(.snappy(duration: 0.36, extraBounce: 0)) {
            shown = false
            drag = .zero
            resetZoom()
        } completion: {
            onClose()
        }
    }
}

private extension CGRect {
    /// The same centre, a share of the size.
    func shrunk(to share: CGFloat) -> CGRect {
        insetBy(dx: width * (1 - share) / 2, dy: height * (1 - share) / 2)
    }
}

extension View {
    /// A tap on a photo that also says where the photo is on screen at that moment.
    func onPhotoTap(radius: CGFloat, _ action: @escaping (PhotoSource) -> Void) -> some View {
        overlay {
            GeometryReader { geometry in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        action(PhotoSource(frame: geometry.frame(in: .global), radius: radius))
                    }
            }
        }
    }

    /// Words being changed: in the same place at the same size, on a sheet of paper that
    /// says so.
    func editingSurface() -> some View {
        padding(10)
            .background(Theme.square(44).fill(Theme.paper))
            .overlay(Theme.square(44).strokeBorder(Theme.line, lineWidth: 1))
            .padding(-10)
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
