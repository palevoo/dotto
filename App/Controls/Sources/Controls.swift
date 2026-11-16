import AppIntents
import SwiftUI
import WidgetKit

/// Three controls for Control Center, the lock screen corners and the Action button:
/// speak, write, and photo. Each is one press into the app.
@main
struct DottoControls: WidgetBundle {
    var body: some Widget {
        WriteControl()
        SpeakControl()
        PhotoControl()
    }
}

struct SpeakControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "works.dotto.control.speak") {
            ControlWidgetButton(action: SpeakIntent()) {
                Label("Speak", systemImage: "mic")
            }
        }
        .displayName("Speak")
        .description("dotto, listening.")
    }
}

struct WriteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "works.dotto.control.write") {
            ControlWidgetButton(action: WriteIntent()) {
                Label("Write", systemImage: "pencil.line")
            }
        }
        .displayName("Write")
        .description("dotto, with the line ready.")
    }
}

struct PhotoControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "works.dotto.control.photo") {
            ControlWidgetButton(action: PhotoIntent()) {
                Label("Photo", systemImage: "camera")
            }
        }
        .displayName("Photo")
        .description("dotto's camera.")
    }
}
