import AppKit
import Core
import SwiftUI

/// The window: where the notebook is, whether the door is open, and who holds a key.
struct GrantsView: View {
    @Bindable var model: MacModel
    @State private var newName = "Claude Code"
    @State private var copied: ULID?
    @State private var readerAuthor: Author?
    @State private var openRuns: Set<ULID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                notebookSection
                doorSection
                grantsSection
                readerSection
                pushSection
                inboxSection
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
            // Which build this is, to hold against git log.
            if let build = Build.label() {
                Text(build)
                    .font(MacTheme.mono)
                    .foregroundStyle(MacTheme.faint)
            }
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
            Text("Only a program holding one of the keys below gets in. It can read the notebook, write notes, labels and links between lines, keep a page of its own lines, and choose its name. It cannot touch your lines.")
                .font(MacTheme.body)
                .foregroundStyle(MacTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var grantsSection: some View {
        Section("Grants") {
            if model.grants.isEmpty {
                Text("Nobody holds a key yet.")
                    .font(MacTheme.body)
                    .foregroundStyle(MacTheme.muted)
            }
            ForEach(model.grants) { grant in
                GrantCard(grant: grant, name: model.notebook?.name(of: grant.author), command: model.connectCommand(for: grant), copied: copied == grant.id) {
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

    /// The reader: the author that wakes on its own when something lands, runs one headless
    /// session through the door, and stops. Runs as one of the grants' authors.
    private var readerSection: some View {
        Section("Reader") {
            switch model.readerState {
            case .off:
                Text("Wakes when something lands in the notebook and runs one Claude Code session through the door, with the door as its only tool, then stops. Runs as the author of a grant below, so it is the same being as a session started by hand; Logs say which hand.")
                    .font(MacTheme.body)
                    .foregroundStyle(MacTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if model.readerCandidates.isEmpty {
                    Text("Make a grant first.")
                        .font(MacTheme.mono)
                        .foregroundStyle(MacTheme.faint)
                } else {
                    HStack(spacing: 8) {
                        Picker("As", selection: $readerAuthor) {
                            ForEach(model.readerCandidates) { grant in
                                Text(grant.name).tag(Optional(grant.author))
                            }
                        }
                        .frame(maxWidth: 220)
                        Button("Turn On") {
                            if let author = readerAuthor ?? model.readerCandidates.first?.author { model.turnReaderOn(as: author) }
                        }
                        .controlSize(.small)
                        .disabled(model.folderURL == nil)
                    }
                }
            case .needsApproval:
                Text("Registered. macOS wants you to allow it under Login Items before it runs.")
                    .font(MacTheme.body)
                    .foregroundStyle(MacTheme.muted)
                HStack(spacing: 8) {
                    Button("Open Login Items") { model.openLoginItems() }.controlSize(.small)
                    Button("Check Again") { model.refreshReader() }.controlSize(.small)
                    Button("Turn Off", role: .destructive) { model.turnReaderOff() }.controlSize(.small)
                }
            case .failed(let why):
                Text("Could not register the reader: \(why)")
                    .font(MacTheme.body)
                    .foregroundStyle(MacTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { model.refreshReader() }.controlSize(.small)
            case .on:
                VStack(alignment: .leading, spacing: 8) {
                    // Who it is, and whether the process is actually there.
                    HStack(spacing: 6) {
                        Text("On, as")
                            .foregroundStyle(MacTheme.muted)
                        if let grant = model.readerGrant {
                            Text(model.name(of: grant.author))
                                .foregroundStyle(MacTheme.ink(for: grant.author, owner: model.notebook?.owner))
                        }
                        Text("· device reader")
                            .foregroundStyle(MacTheme.faint)
                    }
                    .font(MacTheme.mono)
                    if let status = model.readerStatus {
                        HStack(spacing: 6) {
                            MacTheme.square(6)
                                .fill(model.readerAlive ? (status.state == .running ? MacTheme.accent : MacTheme.muted) : MacTheme.recording)
                                .frame(width: 6, height: 6)
                            Text(aliveLine(status))
                                .foregroundStyle(model.readerAlive ? MacTheme.muted : MacTheme.recording)
                        }
                        .font(MacTheme.mono)
                        if let trouble = status.trouble {
                            Text(trouble)
                                .font(MacTheme.mono)
                                .foregroundStyle(MacTheme.recording)
                        }
                        if let wake = status.lastWake {
                            Text("Woke \(Self.stamp(wake.at)) · \(wake.new) new · \(wake.ran ? "ran" : "nothing to do")")
                                .font(MacTheme.mono)
                                .foregroundStyle(MacTheme.faint)
                        }
                    } else {
                        Text("Registered. Waiting for it to start and say so.")
                            .font(MacTheme.mono)
                            .foregroundStyle(MacTheme.faint)
                    }

                    // Each run, step by step, newest first. A run under way is at the top, growing.
                    if !model.readerRuns.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(model.readerRuns) { run in
                                DisclosureGroup(isExpanded: binding(for: run.id)) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        ForEach(Array(run.steps.enumerated()), id: \.offset) { _, step in
                                            HStack(alignment: .top, spacing: 8) {
                                                Text(Self.clock(step.at))
                                                    .foregroundStyle(MacTheme.faint)
                                                    .frame(width: 60, alignment: .leading)
                                                Text(step.what)
                                                    .foregroundStyle(step.what == "got" || step.what == "said" ? MacTheme.faint : MacTheme.foreground)
                                                    .frame(width: 84, alignment: .leading)
                                                Text(step.detail)
                                                    .foregroundStyle(MacTheme.muted)
                                                    .lineLimit(2)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                            .font(MacTheme.mono)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                } label: {
                                    Text(Self.runLine(run))
                                        .font(MacTheme.mono)
                                        .foregroundStyle(run.isRunning ? MacTheme.accent : (run.ok == false ? MacTheme.recording : MacTheme.muted))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Model (default)", text: $model.readerModel)
                            .textFieldStyle(.roundedBorder)
                            .font(MacTheme.mono)
                            .frame(maxWidth: 200)
                            .onSubmit { model.saveReaderModel() }
                        Button("Look Now") { model.lookNow() }.controlSize(.small).disabled(!model.readerAlive)
                        Button("Show Log") { NSWorkspace.shared.activateFileViewerSelecting([model.readerLogURL]) }.controlSize(.small)
                        Button("Turn Off", role: .destructive) { model.turnReaderOff() }.controlSize(.small)
                    }
                }
            }
        }
    }

    private func binding(for id: ULID) -> Binding<Bool> {
        Binding(get: { openRuns.contains(id) }, set: { open in if open { openRuns.insert(id) } else { openRuns.remove(id) } })
    }

    /// "Alive · pid 4812 · since 4 Nov 13:21", "Running since 13:40", or that it is gone.
    private func aliveLine(_ status: ReaderStatus) -> String {
        guard model.readerAlive else { return "Not running. launchd should bring it back; if not, Turn Off and on again." }
        switch status.state {
        case .running: return "Running since \(Self.clock(status.lastRun?.startedAt ?? status.startedAt)) · pid \(status.pid)"
        case .waiting: return "Alive, waiting · pid \(status.pid) · since \(Self.stamp(status.startedAt))\(status.build.map { " · build \($0)" } ?? "")"
        }
    }

    /// "4 Nov 13:21 · 6 turns · $0.31 · answered under two lines", or, while running, how far it is.
    private static func runLine(_ run: ReaderRun) -> String {
        var parts = [stamp(run.startedAt)]
        if run.isRunning {
            parts.append("running")
            let calls = run.calls
            if !calls.isEmpty { parts.append(calls.joined(separator: ", ")) }
            return parts.joined(separator: " · ")
        }
        if let turns = run.turns { parts.append("\(turns) turn\(turns == 1 ? "" : "s")") }
        if let cost = run.costUSD { parts.append(String(format: "$%.2f", cost)) }
        let calls = run.calls
        if !calls.isEmpty { parts.append(calls.joined(separator: ", ")) }
        parts.append(run.summary)
        return parts.joined(separator: " · ")
    }

    /// "13:21:04".
    private static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("HH:mm:ss")
        return formatter.string(from: date)
    }

    /// What others left that may want the owner: what asks and has no answer first, then the
    /// newest of the rest, with a mark on what the owner has not looked at.
    private var inboxSection: some View {
        Section("Inbox") {
            let asks = model.inbox.filter(\.wantsYou)
            let rest = Array(model.inbox.filter { !$0.wantsYou }.prefix(8))
            let unread = model.inbox.filter(\.unread).count
            if model.inbox.isEmpty {
                Text("Nothing for you yet.")
                    .font(MacTheme.body)
                    .foregroundStyle(MacTheme.muted)
            } else {
                Text(unread == 0 ? "Nothing new since you last looked." : "\(unread) new since you last looked.")
                    .font(MacTheme.mono)
                    .foregroundStyle(unread == 0 ? MacTheme.muted : MacTheme.accent)
            }
            ForEach(asks + rest) { item in
                HStack(alignment: .top, spacing: 12) {
                    HStack(spacing: 6) {
                        MacTheme.square(5)
                            .fill(item.unread ? MacTheme.accent : .clear)
                            .frame(width: 5, height: 5)
                        Text(Self.stamp(item.at))
                            .font(MacTheme.mono)
                            .foregroundStyle(MacTheme.faint)
                    }
                    .frame(width: 96, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(model.name(of: item.author))
                                .foregroundStyle(MacTheme.ink(for: item.author, owner: model.notebook?.owner))
                            Text(item.what)
                                .foregroundStyle(MacTheme.muted)
                            if item.wantsYou {
                                Text("for you")
                                    .foregroundStyle(MacTheme.accent)
                            }
                        }
                        .font(MacTheme.mono)
                        if !item.text.isEmpty {
                            Text(item.text)
                                .font(MacTheme.body)
                                .foregroundStyle(item.unread || item.wantsYou ? MacTheme.foreground : MacTheme.muted)
                                .lineLimit(2)
                        }
                        if let about = item.about {
                            Text(about)
                                .font(MacTheme.mono)
                                .foregroundStyle(MacTheme.faint)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    /// The last things done through the door, newest first: every read, note and label, with the line.
    private var logSection: some View {
        Section("Logs") {
            let traces = Array((model.notebook?.trail ?? []).suffix(12).reversed())
            if traces.isEmpty {
                Text("Nobody has been through the door yet.")
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
                            Text(model.name(of: trace.author))
                                .foregroundStyle(MacTheme.ink(for: trace.author, owner: model.notebook?.owner))
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
    /// What the grant's author has chosen to be called, if anything yet.
    let name: String?
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
                    .fill(MacTheme.ink(for: grant.author, owner: nil))
                    .frame(width: 8, height: 8)
                Text(name.map { "called \($0)" } ?? "no name yet · id \(grant.author.rawValue)")
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
