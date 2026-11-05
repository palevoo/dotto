import Core
import CoreLocation
import SwiftUI

/// Everything about the app that is not a line, as steps in the order someone new would take
/// them. Each step is a square that fills when it is done, a name, its state in plain words,
/// and at most one thing to do.
struct SetupView: View {
    @Bindable var model: NotebookModel
    let onRelocate: (URL) -> Void
    @State private var showMove = false
    @State private var naming = false
    @State private var newName = ""
    @FocusState private var nameFocused: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Setup")
                    .font(Theme.title)
                    .foregroundStyle(Theme.foreground)
                you
                notebook
                cloud
                location
                notifications
                walks
                voice
                presses
                logs
                build
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbarBackground(Theme.background, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMove) {
            FolderPicker { url in
                showMove = false
                if let url { onRelocate(url) }
            }
            .ignoresSafeArea()
        }
    }

    /// Your name, for whoever else reads: day files, the Mac, anyone through the door. To
    /// yourself you stay "you". Nobody is called anything until they choose.
    private var you: some View {
        let name = model.notebook.name(of: model.store.manifest.owner)
        return Step("Name", done: name != nil) {
            if naming {
                WordsField(placeholder: "What you are called", text: $newName, font: Theme.serif,
                           color: Theme.foreground, focused: $nameFocused) {
                    nameFocused = false
                }
                .lineSpacing(4)
                .editingSurface()
                .onChange(of: nameFocused) { _, isFocused in
                    guard !isFocused else { return }
                    naming = false
                    model.chooseName(newName)
                }
            } else if let name {
                Status("Called \(name) by anyone else who reads")
                Action("Change it") { newName = name; naming = true; nameFocused = true }
            } else {
                Status("No name yet. Anyone else who reads sees only your id")
                Action("Choose a name") { newName = ""; naming = true; nameFocused = true }
            }
        }
    }

    private var notebook: some View {
        Step("Notebook", done: true) {
            Status(Library.describe(model.store))
            Action("Move to a folder") { showMove = true }
        }
    }

    /// Photos and voice notes travel after the lines. This is how far they are.
    private var cloud: some View {
        let state = model.cloud
        return Step("Photos and voice notes in iCloud", done: state?.settled == true) {
            if let state {
                Status(Self.sync(state), pending: !state.settled)
                if let trouble = state.trouble {
                    // iCloud's refusal, in its words, where it can be read and reported.
                    Status("iCloud: \(trouble)")
                }
            } else {
                Status("iCloud has not said yet")
            }
        }
    }

    /// "All 42 photos and voice notes are in iCloud", or how many are not.
    static func sync(_ cloud: CloudState) -> String {
        let things = "photo\(cloud.media == 1 ? "" : "s") and voice note\(cloud.media == 1 ? "" : "s")"
        if cloud.media == 0 { return "No photos or voice notes yet" }
        if cloud.settled { return "All \(cloud.media) \(things) are in iCloud" }
        var parts: [String] = []
        if cloud.leaving > 0 { parts.append("\(cloud.leaving) of \(cloud.media) \(things) still on this phone") }
        if cloud.arriving > 0 { parts.append("\(cloud.arriving)\(parts.isEmpty ? " of \(cloud.media) \(things)" : "") on their way here") }
        return parts.joined(separator: " · ")
    }

    private var location: some View {
        let status = model.locationStatus
        let allowed = status == .authorizedWhenInUse || status == .authorizedAlways
        return Step("Location", done: allowed) {
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                Status("Each line keeps where it was written")
            case .notDetermined:
                Status("A line could keep where it was written")
                Action("Allow location") { model.allowLocation() }
            default:
                Status("Refused. Lines keep no place")
                Action("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        }
    }

    /// A note written under a line reaches the phone, if the phone allows it.
    private var notifications: some View {
        let pushes = Pushes.shared
        return Step("Notifications", done: pushes.allowed) {
            switch pushes.status {
            case .authorized, .provisional, .ephemeral:
                Status("A reply under a line reaches you here")
                // Where the address stands, so a push that never comes can be traced.
                Status(pushes.token == nil ? "Waiting for Apple to give this phone an address" : "Address written to the folder for the Mac",
                       pending: pushes.token == nil)
            case .notDetermined:
                Status("A reply under a line could reach you here")
                Action("Allow notifications") { pushes.allow() }
            default:
                Status("Refused. Replies wait on the page")
                Action("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            if let trouble = pushes.trouble {
                // Apple's refusal, in its words, where it can be read and reported.
                Status("Apple: \(trouble)")
            }
        }
    }

    @ViewBuilder
    private var walks: some View {
        if model.walks.available {
            Step("Walks from Health", done: model.walks.isOn) {
                if model.walks.isOn {
                    Status("Each walk arrives as a line, at the moment it began")
                } else {
                    Status("Each walk could be a line, with its distance and time")
                    Action("Bring walks from Health") { model.turnOnWalks() }
                    // Health's refusal, in its words, where it can be read and reported.
                    if let trouble = model.walks.trouble {
                        Status("Health: \(trouble)")
                    }
                }
            }
        }
    }

    /// Voice notes become words on the phone, in each of the phone's languages that Apple's
    /// models cover. The models are fetched once from here.
    private var voice: some View {
        let voice = Voice.shared
        let heard = voice.languages.filter { $0.state != .unsupported }
        return Step("Voice", done: !heard.isEmpty && heard.allSatisfy { $0.state == .ready }) {
            if voice.languages.isEmpty {
                Status("Looking at the phone's languages", pending: true)
            }
            ForEach(voice.languages) { language in
                switch language.state {
                case .ready:
                    Status("\(language.name) is understood on this phone")
                case .getting:
                    Status("Getting \(language.name)", pending: true)
                case .missing:
                    Status("\(language.name) needs its model on the phone")
                    Action("Get \(language.name)") { voice.get(language) }
                case .unsupported:
                    Status("\(language.name) is not one Apple's models cover")
                }
            }
            if let trouble = voice.trouble {
                Status("Apple: \(trouble)")
            }
            Way("Languages", "Settings · General · Language & Region")
        }
        .task { await voice.refresh() }
    }

    /// The phone does not say whether these are on, so the step never fills.
    private var presses: some View {
        Step("One press", done: false) {
            Status("Write, take a photo or speak without opening the app first")
            Way("Action button", "Settings · Action Button · Controls · Margin")
            Way("Lock screen and Control Center", "Hold, Add a Control, Margin")
            Way("Siri", "“Write in Margin”, “Photo in Margin”, “Speak in Margin”")
        }
    }

    private var logs: some View {
        NavigationLink(value: Route.log) {
            Text("Logs")
                .font(Theme.mono)
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    /// Which build this is, to hold against git log.
    @ViewBuilder
    private var build: some View {
        if let label = Build.label(calendar: model.calendar) {
            Text(label)
                .font(Theme.mono)
                .foregroundStyle(Theme.faint)
        }
    }

    /// One step: the square, the name, then its lines.
    private struct Step<Content: View>: View {
        let title: String
        let done: Bool
        @ViewBuilder let content: Content

        init(_ title: String, done: Bool, @ViewBuilder content: () -> Content) {
            self.title = title
            self.done = done
            self.content = content()
        }

        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                Theme.square(16)
                    .fill(done ? Theme.accent : .clear)
                    .overlay(Theme.square(16).strokeBorder(done ? .clear : Theme.faint, lineWidth: 1.5))
                    .frame(width: 16, height: 16)
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(Theme.serif)
                        .foregroundStyle(Theme.foreground)
                    content
                }
            }
        }
    }

    /// Where the step stands, in plain words. Warm while something is still on its way.
    private struct Status: View {
        let text: String
        var pending = false

        init(_ text: String, pending: Bool = false) {
            self.text = text
            self.pending = pending
        }

        var body: some View {
            Text(text)
                .font(Theme.mono)
                .foregroundStyle(pending ? Theme.warm : Theme.muted)
        }
    }

    /// The one thing a step lets you do.
    private struct Action: View {
        let title: String
        let action: () -> Void

        init(_ title: String, action: @escaping () -> Void) {
            self.title = title
            self.action = action
        }

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    /// A way in and where it is switched on.
    private struct Way: View {
        let name: String
        let path: String

        init(_ name: String, _ path: String) {
            self.name = name
            self.path = path
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.foreground)
                Text(path)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}
