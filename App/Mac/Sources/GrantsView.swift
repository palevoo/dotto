import AppKit
import Core
import SwiftUI

/// The window: where the notebook is, whether the door is open, and who holds a key.
struct GrantsView: View {
    @Bindable var model: MacModel
    /// The ways in, as the app has them now.
    let ways: Ways
    @State private var newName = "Claude Code"
    /// Who the new key is for: nil for a new author.
    @State private var newAuthor: Author?
    @State private var copied: ULID?
    @State private var readerGrantID: ULID?
    @State private var openRuns: Set<ULID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                notebookSection
                waysInSection
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
            // dotto, looking: the smallest face there is.
            HStack(spacing: 5) {
                Circle().fill(MacTheme.accent).frame(width: 9, height: 9)
                Circle().fill(MacTheme.accent).frame(width: 9, height: 9)
            }
            .accessibilityLabel("dotto")
            Text(Identity.name)
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
                Text("Pick the folder that holds your notebook. dotto can see that folder and nothing else.")
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

    /// How a line gets written from this Mac, each with where it is.
    private var waysInSection: some View {
        Section("Ways in") {
            switch ways.hotKey {
            case .registered(let keys):
                way(keys, "opens the line over whatever you are in. Return keeps it, Esc puts it away.")
            case .refused:
                way("Hotkey", "the system would not register \(HotKey.words); another app may hold it.")
            case .asking:
                EmptyView()
            }
            way("The two dots in the menu bar", "click for the line; drag a picture, a screenshot's thumbnail, a link or words onto them.")
            way("Paste", "into the line: words, a link, or a picture. The clipboard is read only when you paste.")
            way("Services", "select words in any app, then its menu · Services · Keep in dotto.")
        }
    }

    private func way(_ name: String, _ how: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(MacTheme.mono)
                .foregroundStyle(MacTheme.foreground)
            Text(how)
                .font(MacTheme.mono)
                .foregroundStyle(MacTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var doorColour: Color {
        switch model.door {
        case .closed: MacTheme.faint
        case .open: MacTheme.accent
        case .failed: MacTheme.recording
        }
    }

    private var doorWords: String {
        switch model.door {
        case .closed: "Closed"
        case .open(let port): "Open on 127.0.0.1:\(port)"
        case .failed(let why): why
        }
    }

    private var doorSection: some View {
        Section("Door") {
            HStack(spacing: 8) {
                Circle()
                    .fill(doorColour)
                    .frame(width: 8, height: 8)
                Text(doorWords)
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
                GrantCard(grant: grant, name: model.notebook?.name(of: grant.author), command: model.connectCommand(for: grant), copied: copied == grant.id,
                          others: model.authors.filter { $0 != grant.author }.map { ($0, model.name(of: $0)) }) {
                    guard let command = model.connectCommand(for: grant) else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = grant.id
                } onRevoke: {
                    model.revoke(grant)
                } onReassign: { author in
                    model.reassign(grant, to: author)
                } onReissue: {
                    model.reissue(grant)
                }
            }
            HStack(spacing: 8) {
                TextField("Who gets a key", text: $newName)
                    .textFieldStyle(.roundedBorder)
                Picker("as", selection: $newAuthor) {
                    Text("a new author").tag(Optional<Author>.none)
                    ForEach(model.authors, id: \.self) { author in
                        Text(model.name(of: author)).tag(Optional(author))
                    }
                }
                .frame(maxWidth: 220)
                Button("Add Grant") {
                    model.addGrant(name: newName, as: newAuthor)
                }
                .disabled(model.store == nil)
            }
            .padding(.top, 6)
            Text("A grant is a key for an author. A new author starts with a fresh id and no name; an author who has already written can be handed another key and stays the same being. Grants are your events in the notebook; only the key stays on this Mac.")
                .font(MacTheme.mono)
                .foregroundStyle(MacTheme.faint)
                .fixedSize(horizontal: false, vertical: true)
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

    /// Loops: a sentence said once, kept in the notebook, run by this app. Each runs as one
    /// of the grants' authors, so it is the same being as a session started by hand, and
    /// each leaves a receipt in the notebook when it has run.
    private var readerSection: some View {
        Section("Loops") {
            if model.loops.isEmpty {
                Text("A loop wakes when a line lands, or at an hour every day, and runs one Claude Code session through the door, with the door as its only tool, then stops. It runs inside this app while it is open, under one of the grants above; Logs say which hand, and each run leaves a receipt.")
                    .font(MacTheme.body)
                    .foregroundStyle(MacTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.notebook?.loopProposals ?? []) { proposal in
                proposalRow(proposal)
            }
            ForEach(model.loops) { loop in
                loopRow(loop)
            }
            if model.grants.isEmpty {
                Text("Make a grant first.")
                    .font(MacTheme.mono)
                    .foregroundStyle(MacTheme.faint)
            } else {
                newLoop
            }
            HStack(spacing: 8) {
                TextField("Model (default)", text: $model.readerModel)
                    .textFieldStyle(.roundedBorder)
                    .font(MacTheme.mono)
                    .frame(maxWidth: 200)
                Button("Show Log") { NSWorkspace.shared.activateFileViewerSelecting([model.readerLogURL]) }.controlSize(.small)
            }
        }
    }

    @State private var newLoopName = ""
    @State private var newLoopWake = "line"
    @State private var newLoopHour = 9
    @State private var newLoopMinute = 0
    @State private var newLoopBrief = ""

    /// Setting a loop: its name, the grant it runs as, what wakes it, and a brief in your words.
    private var newLoop: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Name", text: $newLoopName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
                Picker("as", selection: $readerGrantID) {
                    ForEach(model.grants) { grant in
                        Text(grant.name).tag(Optional(grant.id))
                    }
                }
                .frame(maxWidth: 200)
                Picker("wakes", selection: $newLoopWake) {
                    Text("when a line lands").tag("line")
                    Text("every day at").tag("clock")
                }
                .frame(maxWidth: 220)
                if newLoopWake == "clock" {
                    Stepper(value: $newLoopHour, in: 0...23) { Text(String(format: "%02d", newLoopHour)).font(MacTheme.mono) }
                    Text(":").font(MacTheme.mono)
                    Stepper(value: $newLoopMinute, in: 0...59, step: 5) { Text(String(format: "%02d", newLoopMinute)).font(MacTheme.mono) }
                }
            }
            HStack(spacing: 8) {
                TextField("Brief, in your words (optional)", text: $newLoopBrief)
                    .textFieldStyle(.roundedBorder)
                Button("Set") {
                    guard let grant = model.grants.first(where: { $0.id == readerGrantID }) ?? model.grants.first else { return }
                    let wake: Loop.Wake = newLoopWake == "clock" ? .clock(hour: newLoopHour, minute: newLoopMinute) : .line
                    let name = newLoopName.trimmingCharacters(in: .whitespaces)
                    model.addLoop(name: name.isEmpty ? (wake == .line ? "The reader" : "At the hour") : name, grant: grant, wake: wake, brief: newLoopBrief)
                    newLoopName = ""
                    newLoopBrief = ""
                }
                .controlSize(.small)
                .disabled(model.folderURL == nil)
            }
        }
        .font(MacTheme.body)
    }

    /// A loop someone proposed through the door, waiting for one click.
    private func proposalRow(_ proposal: LoopProposal) -> some View {
        let runnable = proposal.grant.map { id in model.grants.contains { $0.id == id } } ?? false
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("proposed")
                    .foregroundStyle(MacTheme.accent)
                Text(proposal.name)
                    .foregroundStyle(MacTheme.foreground)
                Text("· \(proposal.wake.words) · by")
                    .foregroundStyle(MacTheme.muted)
                Text(model.name(of: proposal.author))
                    .foregroundStyle(MacTheme.ink(for: proposal.author, owner: model.notebook?.owner))
                Spacer()
                Button("Set It") { model.takeProposal(proposal) }.controlSize(.small).disabled(!runnable)
                Button("Not Now") { model.declineProposal(proposal) }.controlSize(.small)
            }
            .font(MacTheme.mono)
            if let brief = proposal.brief, !brief.isEmpty {
                Text(brief)
                    .font(MacTheme.body)
                    .foregroundStyle(MacTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !runnable {
                Text("Its grant is gone; it cannot run.")
                    .font(MacTheme.mono)
                    .foregroundStyle(MacTheme.recording)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func loopRow(_ loop: Loop) -> some View {
        let status = model.status(of: loop)
        let runs = model.runs(of: loop)
        let grant = model.grants.first { $0.id == loop.grant }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(status?.state == .running ? MacTheme.accent : (status == nil ? MacTheme.faint : MacTheme.muted))
                    .frame(width: 6, height: 6)
                Text(loop.name)
                    .foregroundStyle(MacTheme.foreground)
                Text("· \(loop.wake.words)")
                    .foregroundStyle(MacTheme.muted)
                if let grant {
                    Text("· as")
                        .foregroundStyle(MacTheme.faint)
                    Text(model.name(of: grant.author))
                        .foregroundStyle(MacTheme.ink(for: grant.author, owner: model.notebook?.owner))
                }
                Spacer()
                Button("Look Now") { model.lookNow(loop) }.controlSize(.small).disabled(status == nil)
                Button("Stop", role: .destructive) { model.stopLoop(loop) }.controlSize(.small)
            }
            .font(MacTheme.mono)
            if let brief = loop.brief, !brief.isEmpty {
                Text(brief)
                    .font(MacTheme.body)
                    .foregroundStyle(MacTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if status == nil {
                Text(grant == nil ? "Its grant is gone; stop this loop." : "Its grant's key is not on this Mac. Issue a new key for \(grant!.name) and the loop runs.")
                    .font(MacTheme.mono)
                    .foregroundStyle(MacTheme.recording)
            } else if let trouble = status?.trouble {
                Text(trouble)
                    .font(MacTheme.mono)
                    .foregroundStyle(MacTheme.recording)
            }
            if let status {
                HStack(spacing: 12) {
                    if status.state == .running {
                        Text("Running since \(Self.clock(status.lastRun?.startedAt ?? status.startedAt))")
                    } else if let wake = status.lastWake {
                        Text("Woke \(Self.stamp(wake.at)) · \(wake.new) new · \(wake.ran ? "ran" : "nothing to do")")
                    } else {
                        Text("On, waiting")
                    }
                    if let next = status.nextWake { Text("· next \(Self.stamp(next))") }
                }
                .font(MacTheme.mono)
                .foregroundStyle(MacTheme.faint)
            }

            // Each run, step by step, newest first. A run under way is at the top, growing.
            if !runs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(runs.prefix(6)) { run in
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
                                .foregroundStyle(Self.colour(of: run.outcome))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func binding(for id: ULID) -> Binding<Bool> {
        Binding(get: { openRuns.contains(id) }, set: { open in if open { openRuns.insert(id) } else { openRuns.remove(id) } })
    }

    private static func colour(of outcome: ReaderRun.Outcome) -> Color {
        switch outcome {
        case .running: MacTheme.accent
        case .failed: MacTheme.recording
        case .done: MacTheme.muted
        }
    }

    /// "4 Nov 13:21 · 6 turns · $0.31 · answered under two lines", or, while running, how far it is.
    private static func runLine(_ run: ReaderRun) -> String {
        var parts = [stamp(run.startedAt)]
        let calls = run.calls
        switch run.outcome {
        case .running:
            parts.append("running")
            if !calls.isEmpty { parts.append(calls.joined(separator: ", ")) }
        case .done(let said), .failed(let said):
            if let turns = run.turns { parts.append("\(turns) turn\(turns == 1 ? "" : "s")") }
            if let cost = run.costUSD { parts.append(String(format: "$%.2f", cost)) }
            if !calls.isEmpty { parts.append(calls.joined(separator: ", ")) }
            parts.append(said)
        }
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
                        Circle()
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
    /// The connect command, or nil when this Mac does not hold the key.
    let command: String?
    let copied: Bool
    /// The other authors this key could be handed to instead, with what they are called.
    let others: [(Author, String)]
    let onCopy: () -> Void
    let onRevoke: () -> Void
    let onReassign: (Author) -> Void
    let onReissue: () -> Void

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
                Circle()
                    .fill(MacTheme.ink(for: grant.author, owner: nil))
                    .frame(width: 8, height: 8)
                // The author this key is for. The menu hands the same key to another author instead.
                Menu {
                    ForEach(others, id: \.0) { author, called in
                        Button("Same author as \(called)") { onReassign(author) }
                    }
                    if others.isEmpty {
                        Text("No other author has written yet.")
                    }
                } label: {
                    Text(name.map { "called \($0)" } ?? "no name yet · id \(grant.author.rawValue)")
                        .font(MacTheme.mono)
                        .foregroundStyle(MacTheme.muted)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Text("·")
                    .foregroundStyle(MacTheme.faint)
                Text(grant.scopes)
                    .font(MacTheme.mono)
                    .foregroundStyle(MacTheme.muted)
            }
            if let command {
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
            } else {
                HStack(spacing: 8) {
                    Text("The key is not on this Mac; the notebook holds only its hash. Whoever has the key still gets in.")
                        .font(MacTheme.mono)
                        .foregroundStyle(MacTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("New Key", action: onReissue)
                        .controlSize(.small)
                }
            }
        }
        .padding(.bottom, 6)
    }
}
