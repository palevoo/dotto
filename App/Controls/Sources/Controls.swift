import AppIntents
import SwiftUI
import WidgetKit

/// Two controls for Control Center, the lock screen corners and the Action button:
/// write, and photo. Each is one press into the app.
@main
struct MarginControls: WidgetBundle {
    var body: some Widget {
        WriteControl()
        PhotoControl()
    }
}

struct WriteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "social.interface.notebook.write") {
            ControlWidgetButton(action: WriteIntent()) {
                Label("Write", systemImage: "pencil.line")
            }
        }
        .displayName("Write")
        .description("Margin, with the line ready.")
    }
}

struct PhotoControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "social.interface.notebook.photo") {
            ControlWidgetButton(action: PhotoIntent()) {
                Label("Photo", systemImage: "camera")
            }
        }
        .displayName("Photo")
        .description("Margin's camera.")
    }
}
