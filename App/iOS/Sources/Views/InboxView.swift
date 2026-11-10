import Core
import SwiftUI

/// Everything others left, as one flow, newest first: a reply, a line on your page, a
/// thing made, a fact put, a loop proposed, a name chosen. Each row is the thing itself.
/// What can be answered is answered here: reply under the row, set or decline a loop, drop
/// a mark; the line or thing it is about is one tap away for the rest. A mark stands
/// before the time until the line is opened; what asks and has no answer yet is in ink.
struct InboxView: View {
    @Bindable var model: NotebookModel

    var body: some View {
        let items = model.inbox
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Inbox")
                    .font(Theme.title)
                    .foregroundStyle(Theme.foreground)
                if items.isEmpty {
                    Text("Nothing for you. What others leave that needs you gathers here.")
                        .font(Theme.serifSmall)
                        .foregroundStyle(Theme.muted)
                }
                ForEach(Self.days(of: items, calendar: model.calendar), id: \.key) { day in
                    VStack(alignment: .leading, spacing: 18) {
                        Text(Format.day(day.key, calendar: model.calendar, withYear: false))
                            .font(Theme.mono)
                            .foregroundStyle(Theme.faint)
                        ForEach(day.items) { item in
                            InboxRow(item: item, model: model)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .toolbarBackground(Theme.background, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.lookAtInbox() }
    }

    struct DayOfItems {
        let key: DayKey
        var items: [InboxItem]
    }

    /// Consecutive items grouped by their day, in the order given.
    static func days(of items: [InboxItem], calendar: Calendar) -> [DayOfItems] {
        var days: [DayOfItems] = []
        for item in items {
            let key = DayKey(item.at, calendar: calendar)
            if days.last?.key == key {
                days[days.count - 1].items.append(item)
            } else {
                days.append(DayOfItems(key: key, items: [item]))
            }
        }
        return days
    }
}

/// One row of the inbox: who did what, the words, what it is about, and what you can do
/// about it without leaving.
struct InboxRow: View {
    let item: InboxItem
    @Bindable var model: NotebookModel
    /// Your reply, while you write it here; nil when you are not.
    @State private var reply: String?
    @State private var focused = false

    var body: some View {
        let entry = item.entry.flatMap { model.notebook.entry($0) }
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                // The time, with a mark before it until it is read.
                HStack(spacing: 5) {
                    Circle()
                        .fill(item.unread ? Theme.accent : .clear)
                        .frame(width: 5, height: 5)
                    Text(Format.time(item.at, calendar: model.calendar))
                        .font(Theme.mono)
                        .foregroundStyle(item.unread ? Theme.muted : Theme.faint)
                        .monospacedDigit()
                }
                .frame(width: 54, alignment: .leading)
                .padding(.top, 3)
                VStack(alignment: .leading, spacing: 4) {
                    // The row itself opens what it is about: who, what and the words are
                    // one thing to tap, as the jump under them is.
                    jump {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Who(author: item.author, model: model)
                                Text(item.what)
                                    .font(Theme.mono)
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(1)
                            }
                            if !item.text.isEmpty {
                                Text(item.text)
                                    .font(Theme.serifSmall)
                                    .foregroundStyle(item.unread || item.wantsYou ? Theme.foreground : Theme.muted)
                                    .lineSpacing(3)
                                    .lineLimit(4)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("inbox-row")
                    // Where it is: the line it is about, or the thing, one tap away.
                    if let about = item.about ?? entry.map({ $0.text.isEmpty ? "a photo" : $0.text }), item.entry != nil || item.about != nil {
                        context(about)
                    }
                    actions(entry)
                    if reply != nil, let entry {
                        WordsField(placeholder: "Reply", text: $reply.orEmpty, size: 15, lineSpacing: 3, identifier: "inbox-reply-words", focused: $focused) {
                            send(under: entry.id)
                        }
                        .editingSurface()
                        .onAppear { focused = true }
                        .onChange(of: focused) { _, isFocused in if !isFocused, reply?.isEmpty == true { reply = nil } }
                        .padding(.top, 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The line or thing the row is about, as a jump.
    @ViewBuilder
    private func context(_ words: String) -> some View {
        let label = HStack(spacing: 4) {
            Text(words)
                .font(Theme.sansSmall)
                .foregroundStyle(Theme.faint)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.faint)
        }
        jump { label }
    }

    /// A way to what the row is about: its line, its thing, or the loops; plain when there
    /// is nowhere to go.
    @ViewBuilder
    private func jump<Label: View>(@ViewBuilder _ label: () -> Label) -> some View {
        if let entry = item.entry, model.notebook.entry(entry) != nil {
            NavigationLink(value: entry) { label() }.buttonStyle(.plain)
        } else if let thing = item.thing, model.notebook.thing(thing) != nil {
            NavigationLink(value: Route.thing(thing)) { label() }.buttonStyle(.plain)
        } else if item.kind == .loop {
            NavigationLink(value: Route.loops) { label() }.buttonStyle(.plain)
        } else {
            label()
        }
    }

    /// What can be done from here, in a quiet row: the one thing worth doing in ink, the rest muted.
    @ViewBuilder
    private func actions(_ entry: Entry?) -> some View {
        HStack(spacing: 18) {
            switch item.kind {
            case .reply, .line:
                if let entry {
                    Button("Reply") { withAnimation(Motion.settle) { reply = reply == nil ? "" : nil } }
                        .foregroundStyle(Theme.accent)
                        .accessibilityIdentifier(item.kind == .reply ? "inbox-reply" : "inbox-reply-line")
                    if item.kind == .line, entry.page == model.store.manifest.owner, entry.author != model.store.manifest.owner {
                        Button("Drop") { withAnimation(Motion.settle) { model.delete(entry.id) } }
                            .foregroundStyle(Theme.muted)
                    }
                }
            case .loop:
                if let proposal = model.notebook.loopProposals.first(where: { $0.id == item.id }) {
                    Button("Set it") { withAnimation(Motion.settle) { model.takeProposal(proposal) } }
                        .foregroundStyle(Theme.accent)
                        .accessibilityIdentifier("inbox-set-loop")
                    Button("Not now") { withAnimation(Motion.settle) { model.declineProposal(proposal) } }
                        .foregroundStyle(Theme.muted)
                } else if item.answered {
                    Text(model.notebook.allLoops.contains { $0.id == item.id } ? "set" : "declined")
                        .foregroundStyle(Theme.faint)
                }
            case .shape:
                if let entry, let fact = entry.facts.first(where: { $0.id == item.id }) {
                    Button("Take it off") { withAnimation(Motion.settle) { model.removeFact(fact) } }
                        .foregroundStyle(Theme.muted)
                } else if let thing = item.thing, let made = model.notebook.thing(thing) {
                    if let fact = made.facts.first(where: { $0.id == item.id }) {
                        Button("Take it off") { withAnimation(Motion.settle) { model.removeFact(fact) } }
                            .foregroundStyle(Theme.muted)
                    } else {
                        Button("Drop") { withAnimation(Motion.settle) { model.removeThing(thing) } }
                            .foregroundStyle(Theme.muted)
                    }
                }
            case .link:
                if let entry, let link = (entry.outgoing + entry.incoming).first(where: { $0.id == item.id }) {
                    Button("Take it back") { withAnimation(Motion.settle) { model.unlink(link) } }
                        .foregroundStyle(Theme.muted)
                } else if let entry, entry.done?.id == item.id {
                    Button("Open it again") { withAnimation(Motion.settle) { model.undone(entry.id) } }
                        .foregroundStyle(Theme.muted)
                }
            case .label, .name:
                EmptyView()
            }
        }
        .font(Theme.mono)
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private func send(under entry: ULID) {
        guard let words = reply?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty else {
            reply = nil
            focused = false
            return
        }
        reply = nil
        focused = false
        // Written under a reply, it answers that reply; under a line, the line.
        let answering = item.kind == .reply ? item.id : nil
        withAnimation(Motion.settle) { model.reply(to: entry, text: words, answering: answering) }
        Haptic.store()
    }
}
