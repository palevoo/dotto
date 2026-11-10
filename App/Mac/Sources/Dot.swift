import AppKit
import Carbon.HIToolbox
import Core
import Observation

/// dotto in the menu bar: its two dots. Persimmon while the door is open, plain when it is
/// not. A click opens the live line under them; anything dragged onto them lands in the line.
/// The other click, or a click with Control held, offers the app's window and Quit.
@MainActor
final class Dot: NSObject, NSWindowDelegate, NSDraggingDestination {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: MacModel
    var onClick: (NSRect?) -> Void = { _ in }
    var onDrop: (NSPasteboard, NSRect?) -> Void = { _, _ in }
    var onOpenApp: () -> Void = {}

    init(model: MacModel) {
        self.model = model
        super.init()
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("dotto")
        // The menu bar item lives in a window of its own; a window's delegate may be where
        // its drags land, which is how the dots take a drop.
        button.window?.registerForDraggedTypes(Offered.pasteboardTypes)
        button.window?.delegate = self
        watch()
    }

    /// Where the dots are on the screen, for the line to open under them.
    var anchor: NSRect? { item.button?.window?.frame }

    /// Redrawn whenever the door or a loop changes, and only then.
    private func watch() {
        withObservationTracking {
            render(open: model.port != nil, door: model.door, running: model.runningLoop)
        } onChange: { [weak self] in
            Task { @MainActor in self?.watch() }
        }
    }

    private func render(open: Bool, door: MacModel.Door, running: String?) {
        guard let button = item.button else { return }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            (open ? NSColor(MacTheme.accent) : NSColor.black).setFill()
            let side: CGFloat = 5.5
            let gap: CGFloat = 3
            let left = (18 - side * 2 - gap) / 2
            for x in [left, left + side + gap] {
                NSBezierPath(ovalIn: NSRect(x: x, y: (18 - side) / 2, width: side, height: side)).fill()
            }
            return true
        }
        // Plain dots take the menu bar's own colour; the persimmon ones keep theirs.
        image.isTemplate = !open
        button.image = image
        var words: String
        switch door {
        case .open: words = "dotto · the door is open"
        case .closed: words = "dotto · the door is closed"
        case .failed(let why): words = "dotto · \(why)"
        }
        if let running { words += " · \(running) is running" }
        button.toolTip = words
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            let menu = NSMenu()
            let open = NSMenuItem(title: "Open dotto", action: #selector(openApp), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quit dotto", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
            // Shown once, from here, so the plain click stays the line's.
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            onClick(anchor)
        }
    }

    @objc private func openApp() {
        onOpenApp()
    }

    // MARK: - Drops on the dots

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        item.button?.highlight(true)
        return .copy
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    func draggingExited(_ sender: NSDraggingInfo?) {
        item.button?.highlight(false)
    }

    func draggingEnded(_ sender: NSDraggingInfo) {
        item.button?.highlight(false)
    }

    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        item.button?.highlight(false)
        onDrop(sender.draggingPasteboard, anchor)
        return true
    }
}

/// One key combination, anywhere on the Mac, registered with the system the way launchers
/// do. It needs no permission: the system tells us this one combination was pressed and
/// nothing else about the keyboard.
final class HotKey {
    /// Option, Shift and Space.
    static let words = "⌥⇧Space"

    private var key: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// Nil when the system would not register it.
    init?(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, me, &handler)
        guard installed == noErr else { return nil }
        let id = EventHotKeyID(signature: OSType(0x646F_7474), id: 1)   // "dott"
        let registered = RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey | shiftKey), id, GetApplicationEventTarget(), 0, &key)
        guard registered == noErr else {
            if let handler { RemoveEventHandler(handler) }
            handler = nil
            return nil
        }
    }

    deinit {
        if let key { UnregisterEventHotKey(key) }
        if let handler { RemoveEventHandler(handler) }
    }
}
