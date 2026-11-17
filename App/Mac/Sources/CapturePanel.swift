import AppKit
import Core
import SwiftUI

/// The live line as a small panel that floats over whatever you are in. It takes the keys
/// without taking the app away from you: the app you were in stays the active one. Opened by
/// the hotkey, by a click on the dot in the menu bar, or by something landing. Return keeps
/// the line and the panel goes; Esc puts it away with the words waiting.
@MainActor
final class CaptureController: NSObject, NSWindowDelegate {
    static let width: CGFloat = 540

    let model: CaptureModel
    /// Opens the app's own window, for when there is no notebook yet.
    var openApp: () -> Void = {}
    /// Where the dot is in the menu bar, when it is there.
    var dots: () -> NSRect? = { nil }

    private var panel: CapturePanel?
    /// Where the panel's top-left corner stays while it grows and shrinks with the words.
    private var corner = NSPoint.zero

    init(model: CaptureModel) {
        self.model = model
    }

    var isOpen: Bool { panel?.isVisible == true }

    /// Click on the dot, or the hotkey: open if closed, away if open.
    func toggle(under anchor: NSRect? = nil) {
        if isOpen { hide() } else { show(under: anchor) }
    }

    /// Opens the line. Under the dot when it is what was touched; otherwise in the upper
    /// part of the screen the pointer is on.
    func show(under anchor: NSRect? = nil) {
        // Opened after being closed: a line left in it begins again now.
        if !isOpen { model.comeBack() }
        let panel = self.panel ?? make()
        self.panel = panel
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        if let anchor {
            let x = min(max(anchor.midX - Self.width / 2, visible.minX + 8), visible.maxX - Self.width - 8)
            corner = NSPoint(x: x, y: anchor.minY - 6)
        } else {
            corner = NSPoint(x: visible.midX - Self.width / 2, y: visible.maxY - visible.height * 0.2)
        }
        place(height: panel.frame.height)
        panel.makeKeyAndOrderFront(nil)
        focusWords()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// The card says how tall it is; the panel follows, its top-left corner where it was.
    func fit(height: CGFloat) {
        guard let panel, height > 0, abs(panel.frame.height - height) > 0.5 else { return }
        place(height: height)
        panel.invalidateShadow()
    }

    private func place(height: CGFloat) {
        panel?.setFrame(NSRect(x: corner.x, y: corner.y - height, width: Self.width, height: height), display: true)
    }

    private func focusWords() {
        guard let panel else { return }
        panel.contentView?.layoutSubtreeIfNeeded()
        if let words = panel.contentView?.firstDescendant(of: WordsView.self) {
            panel.makeFirstResponder(words)
        }
    }

    private func make() -> CapturePanel {
        let panel = CapturePanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 96))
        let surface = DropSurface(frame: panel.contentLayoutRect)
        surface.onDrop = { [weak self] pasteboard in self?.land(pasteboard) }
        let view = CaptureView(model: model,
                               onCommit: { [weak self] in self?.commit() },
                               onCancel: { [weak self] in self?.hide() },
                               onHeight: { [weak self] height in self?.fit(height: height) },
                               onPaste: { [weak self] pasteboard in self?.paste(pasteboard) ?? false },
                               onOpenApp: { [weak self] in self?.hide(); self?.openApp() })
        let hosting = NSHostingView(rootView: view)
        // The panel is sized here, from the card's own height; the hosting view asks for nothing.
        hosting.sizingOptions = []
        hosting.frame = surface.bounds
        hosting.autoresizingMask = [.width, .height]
        surface.addSubview(hosting)
        panel.contentView = surface
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }
        return panel
    }

    private func commit() {
        // An empty line and Return: nothing to keep, the panel goes. Words that could not be
        // written stay where they are, with the reason in the app's window.
        if model.draft.isEmpty || model.commit() { hide() }
    }

    /// A paste into the line. Words go in where the cursor is, as the field does it; anything
    /// else, a picture, a file, lands in the line and the field is told not to paste.
    private func paste(_ pasteboard: NSPasteboard) -> Bool {
        let offered = Offered.read(pasteboard)
        guard !offered.files.isEmpty || offered.picture != nil else { return false }
        Task { await model.take(offered) }
        return true
    }

    /// Something dropped, on the line or on the dot: read now, while the drag's pasteboard is
    /// valid, promised files asked for, and the line opened with it in place.
    func land(_ pasteboard: NSPasteboard, under anchor: NSRect? = nil) {
        var offered = Offered.read(pasteboard)
        let promises = offered.files.isEmpty ? Promised.receivers(on: pasteboard) : []
        if !isOpen { show(under: anchor) }
        Task {
            let promised = await Promised.receive(promises)
            offered.files += promised.files
            // A promised file is the thing itself; whatever else rode along with it is not.
            if !promised.files.isEmpty { offered.picture = nil; offered.link = nil; offered.words = nil }
            await model.take(offered)
            if let folder = promised.folder { try? FileManager.default.removeItem(at: folder) }
            focusWords()
        }
    }

    // MARK: - NSWindowDelegate

    /// A click elsewhere puts an empty line away. A line that has begun waits where it is,
    /// so you can go and fetch what it needs.
    func windowDidResignKey(_ notification: Notification) {
        // A click on the dot is the dot's to answer: it puts the line away, and hiding here
        // first would have it open again.
        if let dots = dots(), dots.contains(NSEvent.mouseLocation) { return }
        if model.draft.isEmpty, model.landing == 0 { hide() }
    }
}

/// A borderless panel that becomes key without making its app active.
final class CapturePanel: NSPanel {
    var onCancel: () -> Void = {}

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc, when the words field does not have it.
    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }
}

/// The panel's whole face as one place to drop on. The words field gives up its own drops,
/// so a picture let go over the words lands in the line and not as a path among them.
final class DropSurface: NSView {
    var onDrop: (NSPasteboard) -> Void = { _ in }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(Offered.pasteboardTypes)
    }

    required init?(coder: NSCoder) { fatalError("not made from a nib") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDrop(sender.draggingPasteboard)
        return true
    }
}

extension NSView {
    /// The first view of a kind anywhere under this one.
    func firstDescendant<V: NSView>(of kind: V.Type) -> V? {
        for view in subviews {
            if let found = view as? V { return found }
            if let found = view.firstDescendant(of: kind) { return found }
        }
        return nil
    }
}

// MARK: - The card

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The line itself: the moment, the words, what has landed, and one quiet row saying how it
/// is kept. As tall as what is in it.
struct CaptureView: View {
    @Bindable var model: CaptureModel
    let onCommit: () -> Void
    let onCancel: () -> Void
    let onHeight: (CGFloat) -> Void
    let onPaste: (NSPasteboard) -> Bool
    let onOpenApp: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            card
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
                })
            Spacer(minLength: 0)
        }
        .frame(width: CaptureController.width)
        .onPreferenceChange(HeightKey.self) { height in onHeight(height) }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.hasNotebook {
                line
                if !model.draft.media.isEmpty || model.landing > 0 { landed }
            } else {
                Text("There is no notebook on this Mac yet.")
                    .font(.system(size: 17, design: .serif))
                    .foregroundStyle(MacTheme.foreground)
                Button("Pick its folder", action: onOpenApp)
                    .buttonStyle(.plain)
                    .font(MacTheme.mono)
                    .foregroundStyle(MacTheme.accent)
            }
            if let note = model.note {
                Text(note)
                    .font(MacTheme.mono)
                    .foregroundStyle(MacTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.hasNotebook {
                Text("Return keeps it · Esc puts it away · paste or drop a picture, a link, words")
                    .font(MacTheme.mono)
                    .foregroundStyle(MacTheme.faint)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(MacTheme.background))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(MacTheme.line, lineWidth: 1))
    }

    /// The moment in the margin, as on the phone: the minute it is until the line begins,
    /// then the minute it began.
    private var line: some View {
        HStack(alignment: .top, spacing: 14) {
            TimelineView(.everyMinute) { context in
                Text(Self.time(model.draft.begun ?? context.date))
                    .font(MacTheme.mono)
                    .foregroundStyle(MacTheme.muted)
                    .monospacedDigit()
            }
            .frame(width: 40, alignment: .leading)
            // Onto the first line of the words, which are set larger.
            .padding(.top, 5)
            WordsField(text: $model.text, onCommit: onCommit, onCancel: onCancel, onPaste: onPaste)
                .background(alignment: .topLeading) {
                    if model.text.isEmpty {
                        Text("Write it down")
                            .font(.system(size: WordsField.size, design: .serif))
                            .foregroundStyle(MacTheme.faint)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var landed: some View {
        HStack(spacing: 10) {
            ForEach(model.draft.media) { item in
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image = model.thumbs[item.hash] {
                            Image(nsImage: image).resizable().scaledToFill()
                        } else {
                            MacTheme.line
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(MacTheme.square(72))
                    .overlay(MacTheme.square(72).strokeBorder(MacTheme.line, lineWidth: 1))
                    Button {
                        model.remove(item)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(MacTheme.background)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(MacTheme.foreground.opacity(0.75)))
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .accessibilityLabel("Take this picture out")
                }
            }
            if model.landing > 0 {
                Text("…")
                    .font(MacTheme.mono)
                    .foregroundStyle(MacTheme.faint)
            }
        }
        .padding(.leading, 54)
    }

    private static func time(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

// MARK: - The words

/// Words for the line. Return stores and never lands in the words; a passage pasted with
/// line breaks keeps its words and loses the breaks, as on the phone. An AppKit text view,
/// because that is where Return, Esc and a paste of something other than words can be told
/// apart and answered.
struct WordsField: NSViewRepresentable {
    static let size: CGFloat = 17

    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void
    let onPaste: (NSPasteboard) -> Bool

    func makeNSView(context: Context) -> WordsView {
        let view = WordsView(frame: NSRect(x: 0, y: 0, width: 400, height: 22))
        view.delegate = context.coordinator
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.font = Self.font
        view.textColor = NSColor(MacTheme.foreground)
        view.insertionPointColor = NSColor(MacTheme.accent)
        view.setAccessibilityIdentifier("live-line")
        return view
    }

    func updateNSView(_ view: WordsView, context: Context) {
        context.coordinator.parent = self
        view.onPaste = onPaste
        view.onCancel = onCancel
        if view.string != text {
            // Set from outside: cleared after Return, a link or a passage that landed.
            view.string = text
            view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            // What was typed before belongs to other words now; undo starts afresh.
            view.undoManager?.removeAllActions()
        }
    }

    /// As tall as the words at the width offered, one line at least.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: WordsView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite,
              let container = view.textContainer, let layout = view.layoutManager else { return nil }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let line = layout.defaultLineHeight(for: Self.font)
        return CGSize(width: width, height: max(layout.usedRect(for: container).height, line).rounded(.up))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    static var font: NSFont {
        let base = NSFont.systemFont(ofSize: size)
        return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: WordsField

        init(parent: WordsField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            if parent.text != view.string { parent.text = view.string }
        }

        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                parent.onCommit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }

        /// A passage with breaks in it arrives whole, a paste or a dictation. Each run of
        /// breaks becomes one space and the passage lands where the cursor is.
        func textView(_ view: NSTextView, shouldChangeTextIn range: NSRange, replacementString replacement: String?) -> Bool {
            guard let replacement, replacement.rangeOfCharacter(from: .newlines) != nil else { return true }
            view.insertText(Words.flattened(replacement), replacementRange: range)
            return false
        }
    }
}

/// The text view under the words. It answers the editing keys itself, because the panel
/// takes keys while another app is the active one and that app's menus are not ours; it
/// offers a paste to the line before pasting words; and it takes no drops of its own.
final class WordsView: NSTextView {
    var onPaste: (NSPasteboard) -> Bool = { _ in false }
    var onCancel: () -> Void = {}

    /// A drop over the words belongs to the line, not to the text.
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { [] }

    override func paste(_ sender: Any?) {
        if onPaste(.general) { return }
        pasteAsPlainText(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        // By where the key is, not what it types, so they work in any keyboard language.
        switch (flags, event.keyCode) {
        case (.command, 9): paste(nil)                       // V
        case (.command, 8): copy(nil)                        // C
        case (.command, 7): cut(nil)                         // X
        case (.command, 0): selectAll(nil)                   // A
        case (.command, 6): undoManager?.undo()              // Z
        case ([.command, .shift], 6): undoManager?.redo()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }

    /// The cursor is in the words whenever the line is on screen.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window === window, window.firstResponder !== self else { return }
            window.makeFirstResponder(self)
        }
    }
}
