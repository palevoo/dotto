import AppKit
import Core
import SwiftUI

/// The window: where the notebook is, whether the door is open, and who holds a key.
struct GrantsView: View {
    @Bindable var model: MacModel
    @State private var newName = "Claude Code"
    @State private var copied: ULID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                notebookSection
                doorSection
                grantsSection
                pushSection
                logSection
            }
            .padding(28)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            MacTheme.square(18)
                .fill(MacTheme.accent)
                .frame(width: 18, height: 18)
            Text("margin")
                .font(.system(size: 30, weight: .medium, design: .serif))
                .foregroundStyle(MacTheme.foreground)
            Spacer()
        }
    }

    private var notebookSection: some View {
        Section("Notebook") {
            if let url = model.folderURL {
                VStack(alignment: .leading, spacing: 6) {
                    Text(url.lastPathComponent)
                        .font(MacTheme.heading)
                        .foregroundStyle(MacTheme.foreground)
                    Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(MacTheme.mono)
                        .foregroundStyle(MacTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !model.summary.isEmpty {
                        Text(model.summary)
                            .font(MacTheme.mono)
                            .foregroundStyle(MacTheme.muted)
                    }
                }
                Button("Change Folder…") { model.chooseFolder() }
                    .controlSize(.small)
            } else {
                Text("Pick the folder that holds your notebook. Margin can see that folder and nothing else.")
                    .font(MacTheme.body)
                    .foregroundStyle(MacTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Choose Folder…") { model.chooseFolder() }
            }
            if let problem = model.problem {
                Text(problem)
                    .font(MacTheme.mono)
                    .foregroundStyle(MacTheme.recording)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var doorSection: some View {
        Section("Door") {
            HStack(spacing: 8) {
                MacTheme.square(8)
                    .fill(model.port == nil ? MacTheme.faint : MacTheme.accent)
                    .frame(width: 8, height: 8)
                Text(model.port.map { "Open on 127.0.0.1:\($0)" } ?? "Closed")
                    .font(MacTheme.mono)
                    .foregroundStyle(MacTheme.foreground)
            }
            Text("Only a program holding one of the keys below gets in. It can read the notebook and write notes, labels and links between lines in its own ink. It cannot touch your lines.")
                .font(MacTheme.body)
                .foregroundStyle(MacTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var grantsSection: some View {
        Section("Grants") {
            if model.grants.isEmpty {
                Text("No readers yet.")
                    .font(MacTheme.body)
                    .foregroundStyle(MacTheme.muted)
            }
            ForEach(model.grants) { grant in
                GrantCard(grant: grant, command: model.connectCommand(for: grant), copied: copied == grant.id) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.connectCommand(for: grant), forType: .string)
                    copied = grant.id
                } onRevoke: {
                    model.revoke(grant)
                }
            }
            HStack(spacing: 8) {
                TextField("Who gets a key", text: $newName)
                    .textFieldStyle(.roundedBorder)
                Button("Add Grant") {
                    model.addGrant(name: newName)
                }
                .disabled(model.store == nil)
            }
            .padding(.top, 6)
        }
    }

    /// A note written through the door reaches the phone, if this Mac holds the push key.
    private var pushSection: some View {
        Section("Pushes") {
            if let key = model.pushKey {
                Text("Key \(key.keyID) · team \(key.teamID)")
                    .font(MacTheme.mono)
                    .foregroundStyle(MacTheme.foreground)
                if model.pushAddresses.isEmpty {
                    Text("No phone has written its address yet. On the phone, Setup · Notifications · Allow.")
                        .font(MacTheme.body)
                        .foregroundStyle(MacTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(model.pushAddresses) { address in
                        Text("\(address.device.rawValue) · \(address.environment) · \(Self.stamp(address.updatedAt))")
                            .font(MacTheme.mono)
                            .foregroundStyle(MacTheme.muted)
                    }
                }
                HStack(spacing: 8) {
                    Button("Send Test Push") { model.sendTestPush() }
                        .controlSize(.small)
                        .disabled(model.pushAddresses.isEmpty)
                    Button("Remove Key", role: .destructive) { model.removePushKey() }
                        .controlSize(.small)
                }
            } else {
                Text("A note written under a line reaches the phone as a push. The key comes from the developer account: Certificates, Identifiers & Profiles · Keys · a key with Apple Push Notifications service, downloaded once as AuthKey_<id>.p8. It stays in this Mac's keychain.")
                    .font(MacTheme.body)
                    .foregroundStyle(MacTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Choose Push Key…") { model.choosePushKey() }
                    .controlSize(.small)
            }
            if let report = model.pushReport {
                Text(report)
                    .font(MacTheme.mono)
                    .foregroundStyle(MacTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The last things readers did, newest first: every read, note and label, with the line.
    private var logSection: some View {
        Section("Log") {
            let traces = Array((model.notebook?.trail ?? []).suffix(12).reversed())
            if traces.isEmpty {
                Text("No reader has been here yet.")
                    .font(MacTheme.body)
                    .foregroundStyle(MacTheme.muted)
            }
            ForEach(traces) { trace in
                HStack(alignment: .top, spacing: 12) {
                    Text(Self.stamp(trace.at))
                        .font(MacTheme.mono)
                        .foregroundStyle(MacTheme.faint)
                        .frame(width: 96, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(trace.author.rawValue)
                                .foregroundStyle(trace.author == model.notebook?.owner ? MacTheme.foreground : MacTheme.agent)
                            Text(trace.what)
                                .foregroundStyle(MacTheme.muted)
                            Text("via \(trace.device.rawValue)")
                                .foregroundStyle(MacTheme.faint)
                        }
                        .font(MacTheme.mono)
                        if let entry = trace.entry.flatMap({ model.notebook?.entry($0) }) {
                            Text(entry.text.isEmpty ? "a photo" : entry.text)
                                .font(MacTheme.body)
                                .foregroundStyle(MacTheme.muted)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    /// "4 Nov 13:21".
    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
        return formatter.string(from: date)
    }
}

/// A labelled group with a hairline, in the app's own style rather than the system's.
struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(1)
                .foregroundStyle(MacTheme.muted)
            MacTheme.line.frame(height: 1)
            content
        }
    }
}

struct GrantCard: View {
    let grant: Grant
    let command: String
    let copied: Bool
    let onCopy: () -> Void
    let onRevoke: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(grant.name)
                    .font(MacTheme.heading)
                    .foregroundStyle(MacTheme.foreground)
                Spacer()
                Button("Revoke", role: .destructive, action: onRevoke)
                    .controlSize(.small)
            }
            HStack(spacing: 8) {
                MacTheme.square(8)
                    .fill(grant.author == .weeju ? MacTheme.agent : MacTheme.accent)
                    .frame(width: 8, height: 8)
                Text("writes as \(grant.author.rawValue)")
                    .font(MacTheme.mono)
                    .foregroundStyle(MacTheme.muted)
                Text("·")
                    .foregroundStyle(MacTheme.faint)
                Text(grant.scopes)
                    .font(MacTheme.mono)
                    .foregroundStyle(MacTheme.muted)
            }
            HStack(alignment: .top, spacing: 8) {
                Text(command)
                    .font(MacTheme.mono)
                    .foregroundStyle(MacTheme.foreground)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(copied ? "Copied" : "Copy", action: onCopy)
                    .controlSize(.small)
            }
            .padding(10)
            .background(MacTheme.square(14).fill(MacTheme.paper))
            .overlay(MacTheme.square(14).strokeBorder(MacTheme.line, lineWidth: 1))
            Text("Run this once in a terminal. Claude Code then reaches your notebook through this door, with this key.")
                .font(MacTheme.mono)
                .foregroundStyle(MacTheme.muted)
        }
        .padding(.bottom, 6)
    }
}
