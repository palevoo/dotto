import Core
import SwiftUI

/// Everything about the app that is not a line, on one page: where the notebook is and how
/// far iCloud is with it, walks from Health, the one-press ways in, and who has read. Each
/// group is a fact and at most one thing to do.
struct SetupView: View {
    @Bindable var model: NotebookModel
    let onRelocate: (URL) -> Void
    @State private var showMove = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Setup")
                    .font(Theme.title)
                    .foregroundStyle(Theme.foreground)
                notebook
                walks
                presses
                readers
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

    private var notebook: some View {
        Block("Notebook") {
            Text(Library.describe(model.store))
                .font(Theme.serifSmall)
                .foregroundStyle(Theme.foreground)
            if let cloud = model.cloud {
                Text(Self.sync(cloud))
                    .font(Theme.mono)
                    .foregroundStyle(cloud.settled ? Theme.muted : Theme.warm)
                if let trouble = cloud.trouble {
                    // iCloud's refusal, in its words, where it can be read and reported.
                    Text("iCloud: \(trouble)")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.muted)
                }
            }
            Action("Move to a folder") { showMove = true }
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

    @ViewBuilder
    private var walks: some View {
        if model.walks.available {
            Block("Walks") {
                if model.walks.isOn {
                    Text("Walks from Health arrive as lines, at the moment each one began.")
                        .font(Theme.serifSmall)
                        .foregroundStyle(Theme.foreground)
                } else {
                    Text("Each walk can be a line, with its distance and time.")
                        .font(Theme.serifSmall)
                        .foregroundStyle(Theme.foreground)
                    Action("Bring walks from Health") { model.turnOnWalks() }
                    // Health's refusal, in its words, where it can be read and reported.
                    if let trouble = model.walks.trouble {
                        Text("Health: \(trouble)")
                            .font(Theme.mono)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }

    private var presses: some View {
        Block("One press") {
            Text("Write, take a photo or speak without opening the app first.")
                .font(Theme.serifSmall)
                .foregroundStyle(Theme.foreground)
            Way("Action button", "Settings · Action Button · Controls · Margin")
            Way("Lock screen and Control Center", "Hold, Add a Control, Margin")
            Way("Siri", "“Write in Margin”, “Photo in Margin”, “Speak in Margin”")
        }
    }

    private var readers: some View {
        Block("Readers") {
            if let last = model.notebook.visits.last {
                Text(LogView.summary(of: last, calendar: model.calendar))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.agent)
                NavigationLink(value: Route.log) {
                    Text("Everything readers did")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            } else {
                Text("No reader has been here yet.")
                    .font(Theme.serifSmall)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    /// A titled group: a small name, a hairline, then its lines.
    private struct Block<Content: View>: View {
        let title: String
        @ViewBuilder let content: Content

        init(_ title: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.faint)
                Theme.line.frame(height: 1)
                content
            }
        }
    }

    /// The one thing a group lets you do.
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
            .padding(.top, 2)
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
