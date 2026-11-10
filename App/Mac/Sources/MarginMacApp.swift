import AppKit
import Core
import SwiftUI

/// dotto on the Mac. The home: it holds the grants, opens the door and runs the loops, in
/// its window. And a way in: the live line, from anywhere, by the hotkey, the two dots in the
/// menu bar, a drop on them, or a selection sent through Services.
@main
struct MarginMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window(Identity.name, id: AppDelegate.windowID) {
            MainWindow(delegate: delegate)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 560, height: 680)
    }
}

/// The app's one window, which also hands the delegate the way to open it again once closed.
private struct MainWindow: View {
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GrantsView(model: delegate.model, ways: delegate.ways)
            .frame(width: 560)
            .frame(minHeight: 520)
            .background(MacTheme.background)
            .onAppear {
                delegate.openWindow = { openWindow(id: AppDelegate.windowID) }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let windowID = "main"

    let model = MacModel()
    private(set) lazy var capture = CaptureController(model: CaptureModel(mac: model))
    private var dot: Dot?
    private var hotKey: HotKey?
    /// What the window says about the ways in.
    let ways = Ways()
    /// Opens the window again after it was closed. Set by the window when it first appears.
    var openWindow: () -> Void = {}

    func applicationDidFinishLaunching(_ notification: Notification) {
        capture.openApp = { [weak self] in self?.showWindow() }

        let dot = Dot(model: model)
        dot.onClick = { [weak self] anchor in self?.capture.toggle(under: anchor) }
        dot.onDrop = { [weak self] pasteboard, anchor in self?.capture.land(pasteboard, under: anchor) }
        dot.onOpenApp = { [weak self] in self?.showWindow() }
        self.dot = dot
        capture.dots = { [weak dot] in dot?.anchor }

        hotKey = HotKey { [weak self] in
            // The system calls on the main thread.
            MainActor.assumeIsolated { self?.capture.toggle() }
        }
        ways.hotKey = hotKey == nil ? .refused : .registered(HotKey.words)

        // "Keep in dotto" in the Services menu of any app, for what is selected there.
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// No session outlives the app.
    func applicationWillTerminate(_ notification: Notification) {
        model.stopLoops()
    }

    /// The home keeps running with its window closed: the door, the loops and the dots stay.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow()
    }

    /// The service: what was selected in another app lands in the live line, which opens.
    @objc func keepInDotto(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        capture.land(pasteboard)
    }
}

/// The ways in whose state the window shows. The hotkey is asked for once the app has
/// launched, which may be after the window is first drawn.
@MainActor
@Observable
final class Ways {
    enum HotKeyState: Equatable {
        case asking
        case registered(String)
        case refused
    }
    var hotKey: HotKeyState = .asking
}
