import Core
import SwiftUI

/// Loops: a sentence said once, kept in the notebook, run by the Mac, with a receipt each
/// time. What others proposed waits at the top for one tap; the loops that run follow, hold
/// one to stop it; and at the foot, the place to set one yourself.
struct LoopsView: View {
    @Bindable var model: NotebookModel
    @State private var name = ""
    @State private var grant: ULID?
    @State private var wakesByClock = false
    @State private var hour = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var brief = ""

    var body: some View {
        let proposals = model.notebook.loopProposals
        let loops = model.notebook.loops
        let grants = model.notebook.grants
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Loops")
                    .font(Theme.title)
                    .foregroundStyle(Theme.foreground)

                if !proposals.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Proposed")
                            .font(Theme.mono)
                            .foregroundStyle(Theme.accent)
                        ForEach(proposals) { proposal in proposalRow(proposal, grants: grants) }
                    }
                }

                if loops.isEmpty {
                    Text("A loop wakes when a line lands, or at an hour every day, runs as one of the grants through the door, and leaves a receipt. The Mac runs it while it is open.")
                        .font(Theme.serifSmall)
                        .foregroundStyle(Theme.muted)
                        .lineSpacing(3)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(loops) { loop in loopRow(loop, grants: grants) }
                    }
                }

                form(grants: grants)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbarBackground(Theme.background, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if grant == nil { grant = grants.first?.id } }
    }

    /// A proposal: who asks, for what, and the two answers.
    private func proposalRow(_ proposal: LoopProposal, grants: [Grant]) -> some View {
        let runnable = proposal.grant.map { id in grants.contains { $0.id == id } } ?? false
        return VStack(alignment: .leading, spacing: 6) {
            Text(proposal.name)
                .font(Theme.serif)
                .foregroundStyle(Theme.foreground)
                .accessibilityIdentifier("proposal-\(proposal.name)")
            HStack(spacing: 5) {
                Text(proposal.wake.words)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.muted)
                Text("· by")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.faint)
                Who(author: proposal.author, model: model)
            }
            // What it asks to be allowed each run, seen before it is set.
            Text("up to \(proposal.turns) turns and $\(String(format: "%.2f", proposal.budget)) a run")
                .font(Theme.mono)
                .foregroundStyle(Theme.muted)
            if let brief = proposal.brief, !brief.isEmpty {
                Text(brief)
                    .font(Theme.sansSmall)
                    .foregroundStyle(Theme.muted)
            }
            if !runnable {
                Text("Its grant is gone; it cannot run.")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.recording)
            }
            HStack(spacing: 18) {
                Button("Set it") { withAnimation(Motion.settle) { model.takeProposal(proposal) } }
                    .foregroundStyle(Theme.accent)
                    .disabled(!runnable)
                    .accessibilityIdentifier("take-\(proposal.name)")
                Button("Not now") { withAnimation(Motion.settle) { model.declineProposal(proposal) } }
                    .foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("decline-\(proposal.name)")
            }
            .font(Theme.mono)
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A loop that runs: what wakes it, who it runs as, its brief, its last run. Hold to stop.
    private func loopRow(_ loop: Loop, grants: [Grant]) -> some View {
        let author = grants.first { $0.id == loop.grant }?.author
        return VStack(alignment: .leading, spacing: 6) {
            Text(loop.name)
                .font(Theme.serif)
                .foregroundStyle(Theme.foreground)
                .accessibilityIdentifier("loop-\(loop.name)")
            HStack(spacing: 5) {
                Text(loop.wake.words)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.muted)
                if let author {
                    Text("· as")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.faint)
                    Who(author: author, model: model)
                } else {
                    Text("· its grant is gone")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.recording)
                }
            }
            if let brief = loop.brief, !brief.isEmpty {
                Text(brief)
                    .font(Theme.sansSmall)
                    .foregroundStyle(Theme.muted)
            }
            if let run = loop.lastRun {
                Text("\(run.ok ? "ran" : "failed") \(Format.shortDay(run.endedAt, calendar: model.calendar)) \(Format.time(run.endedAt, calendar: model.calendar)) · \(run.summary)")
                    .font(Theme.mono)
                    .foregroundStyle(run.ok ? Theme.faint : Theme.recording)
                    .lineLimit(2)
            } else {
                Text("has not run yet")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.faint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Stop", systemImage: "stop.circle", role: .destructive) {
                withAnimation(Motion.settle) { model.stopLoop(loop.id) }
            }
        }
    }

    /// Setting a loop: a name, who it runs as, what wakes it, and a brief in your words.
    @ViewBuilder
    private func form(grants: [Grant]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set a loop")
                .font(Theme.mono)
                .foregroundStyle(Theme.faint)
            if grants.isEmpty {
                Text("Make a grant on the Mac first; a loop runs as one.")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.muted)
            } else {
                TextField("Name", text: $name)
                    .font(Theme.serif)
                    .foregroundStyle(Theme.foreground)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Theme.square(44).fill(Theme.paper))
                    .overlay(Theme.square(44).strokeBorder(Theme.line, lineWidth: 1))
                    .accessibilityIdentifier("loop-name")
                HStack(spacing: 8) {
                    Text("as")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.faint)
                    Picker("as", selection: $grant) {
                        ForEach(grants) { grant in
                            Text(model.notebook.name(of: grant.author) ?? grant.name).tag(Optional(grant.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                    .accessibilityIdentifier("loop-grant")
                }
                Picker("wakes", selection: $wakesByClock) {
                    Text("when a line lands").tag(false)
                    Text("every day at").tag(true)
                }
                .pickerStyle(.segmented)
                if wakesByClock {
                    DatePicker("at", selection: $hour, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(Theme.accent)
                }
                TextField("Brief, in your words", text: $brief, axis: .vertical)
                    .font(Theme.serifSmall)
                    .foregroundStyle(Theme.foreground)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(Theme.square(44).fill(Theme.paper))
                    .overlay(Theme.square(44).strokeBorder(Theme.line, lineWidth: 1))
                    .accessibilityIdentifier("loop-brief")
                Button("Set") {
                    guard let grant else { return }
                    let parts = model.calendar.dateComponents([.hour, .minute], from: hour)
                    let wake: Loop.Wake = wakesByClock ? .clock(hour: parts.hour ?? 0, minute: parts.minute ?? 0) : .line
                    withAnimation(Motion.settle) { model.setLoop(name: name, grant: grant, wake: wake, brief: brief) }
                    name = ""
                    brief = ""
                }
                .font(Theme.mono)
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || grant == nil)
                .accessibilityIdentifier("loop-set")
            }
        }
        .padding(.top, 6)
    }
}
