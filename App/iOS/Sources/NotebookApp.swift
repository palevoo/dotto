import Core
import SwiftUI

@main
struct NotebookApp: App {
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
                case .active: model?.reload()
                case .background, .inactive: model?.commitDraft()
                @unknown default: break
                }
            }
        }
    }
}
