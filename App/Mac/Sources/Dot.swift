import AppKit
import Carbon.HIToolbox
import Core
import Observation

/// dotto in the menu bar: one dot. At rest it is the menu bar's own colour, a quiet place
/// that is ready to take a line or a drop. It takes dotto's colour only while dotto is
/// working, a reading or a loop under way, and is hollow when the door is closed. One dot
/// and not two: two coloured dots read as eyes, and eyes that are always on look back at
/// you. A click opens the live line under it; anything dragged onto it lands in the line.
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
        // its drags land, which is how the dot takes a drop.
        button.window?.registerForDraggedTypes(Offered.pasteboardTypes)
        button.window?.delegate = self
        watch()
    }

    /// Where the dot is on the screen, for the line to open under it.
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
        // dotto dev wears its colour always, so it is never taken for the home.
        let coloured = running != nil || Identity.isDevelopment
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let colour = coloured ? NSColor(Identity.isDevelopment ? MacTheme.agent : MacTheme.accent) : NSColor.black
            // Dotto's own dot, as on the icon. Its numbers count down from the top and this
            // picture counts up from the bottom, so every height is taken from 18.
            func edge(_ size: Double) -> NSBezierPath {
                let outline = Core.Dot.dotto.outline(size: size, centre: Core.Dot.Point(x: 9, y: 9))
                func point(_ point: Core.Dot.Point) -> NSPoint { NSPoint(x: point.x, y: 18 - point.y) }
                let path = NSBezierPath()
                path.move(to: point(outline.start))
                for curve in outline.curves {
                    path.curve(to: point(curve.end), controlPoint1: point(curve.control1), controlPoint2: point(curve.control2))
                }
                path.close()
                return path
            }
            if open {
                colour.setFill()
                edge(9).fill()
            } else {
                // The door is closed: the dot is only its outline.
                colour.setStroke()
                let ring = edge(7.5)
                ring.lineWidth = 1.5
                ring.stroke()
            }
            return true
        }
        // At rest the dot takes the menu bar's own colour; working, it keeps dotto's.
        image.isTemplate = !coloured
        button.image = image
        var words: String
        switch door {
        case .open: words = "\(Identity.name) · the door is open"
        case .closed: words = "\(Identity.name) · the door is closed"
        case .failed(let why): words = "\(Identity.name) · \(why)"
        }
        if let running { words += " · \(running) is running" }
        button.toolTip = words
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            let menu = NSMenu()
            let open = NSMenuItem(title: "Open \(Identity.name)", action: #selector(openApp), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quit \(Identity.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
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

    // MARK: - Drops on the dot

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
    /// Option, Shift and Space; dotto dev adds Control, so the two can run side by side.
    static let words = Identity.isDevelopment ? "⌃⌥⇧Space" : "⌥⇧Space"
    private static let modifiers = UInt32(Identity.isDevelopment ? optionKey | shiftKey | controlKey : optionKey | shiftKey)

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
        let registered = RegisterEventHotKey(UInt32(kVK_Space), Self.modifiers, id, GetApplicationEventTarget(), 0, &key)
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
