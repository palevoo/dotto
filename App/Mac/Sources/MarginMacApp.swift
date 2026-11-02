import SwiftUI

/// Margin on the Mac, first version: the grant holder. It knows one folder and opens one door.
@main
struct MarginMacApp: App {
    @State private var model = MacModel()

    var body: some Scene {
        WindowGroup("Margin") {
            GrantsView(model: model)
                .frame(width: 560)
                .frame(minHeight: 520)
                .background(MacTheme.background)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 560, height: 680)
    }
}
