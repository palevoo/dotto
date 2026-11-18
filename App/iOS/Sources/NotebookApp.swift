import Core
import SwiftUI

@main
struct NotebookApp: App {
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
    @State private var model: NotebookModel? = Library.openAtLaunch()
    @Environment(\.scenePhase) private var scenePhase
    /// Whether the app has been out of sight since it was last in front.
    @State private var wasAway = false

    var body: some Scene {
        WindowGroup {
            Group {
                if let model {
                    PageView(model: model) { root in
                        if let moved = Library.move(model.store, to: root) {
                            self.model = moved
                        }
                    }
                    .task {
                        #if DEBUG
                        await Seed.runIfAsked(model)
                        #endif
                    }
                } else {
                    ChooseFolderView { root in
                        model = Library.openNotebook(at: root)
                    }
                }
            }
            .tint(Theme.accent)
            .background(Theme.background.ignoresSafeArea())
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    // A line left unsent keeps its words and takes this sitting's moment.
                    if wasAway { model?.comeBackToLine() }
                    wasAway = false
                    model?.reloadAside()
                    model?.takeInbox()
                    Pushes.shared.refresh()
                    model?.photos.refresh()
                    model?.refreshPlace()
                // The live line keeps its words across a switch away; it is saved as it is typed.
                case .background: wasAway = true
                case .inactive: break
                @unknown default: break
                }
            }
        }
    }
}
