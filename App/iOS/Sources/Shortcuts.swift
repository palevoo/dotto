import AppIntents

/// The two presses, offered to Siri, Shortcuts and the Action button by name.
struct MarginShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WriteIntent(),
            phrases: ["Write in \(.applicationName)"],
            shortTitle: "Write",
            systemImageName: "pencil.line"
        )
        AppShortcut(
            intent: SpeakIntent(),
            phrases: ["Speak in \(.applicationName)", "Speak to \(.applicationName)"],
            shortTitle: "Speak",
            systemImageName: "mic"
        )
        AppShortcut(
            intent: PhotoIntent(),
            phrases: ["Photo in \(.applicationName)", "Take a photo in \(.applicationName)"],
            shortTitle: "Photo",
            systemImageName: "camera"
        )
    }
}
