import Core
import SwiftUI

@main
struct NotebookApp: App {
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
    @State private var model: NotebookModel? = Library.openRememberedNotebook()
    @Environment(\.scenePhase) private var scenePhase

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
                    model?.reload()
                    model?.takeInbox()
                    Pushes.shared.refresh()
                // The live line keeps its words across a switch away; it is saved as it is typed.
                case .background, .inactive: break
                @unknown default: break
                }
            }
        }
    }
}
