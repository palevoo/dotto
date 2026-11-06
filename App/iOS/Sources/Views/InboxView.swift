import Core
import SwiftUI

/// What others left that may want you, in one place. What asks and has no answer yet comes
/// first; then everything else, newest first, with a mark on what arrived since you last
/// looked. Each row is a door to the line it is about, where you answer. Opening the inbox is
/// the look: what is new now stays marked while you read, and is read from then on.
struct InboxView: View {
    @Bindable var model: NotebookModel
    /// The inbox as it was when this page opened, so the marks do not vanish under your eyes.
    @State private var shown: [InboxItem]?

    var body: some View {
        let items = shown ?? model.inbox
        let asks = items.filter(\.wantsYou)
        let rest = items.filter { !$0.wantsYou }
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
                if !asks.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("For you")
                            .font(Theme.mono)
                            .foregroundStyle(Theme.accent)
                        ForEach(asks) { item in row(item) }
                    }
                }
                ForEach(Self.days(of: rest, calendar: model.calendar), id: \.key) { day in
                    VStack(alignment: .leading, spacing: 14) {
                        Text(Format.day(day.key, calendar: model.calendar, withYear: false))
                            .font(Theme.mono)
                            .foregroundStyle(Theme.faint)
                        ForEach(day.items) { item in row(item) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbarBackground(Theme.background, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard shown == nil else { return }
            shown = model.inbox
            model.lookAtInbox()
        }
    }

    @ViewBuilder
    private func row(_ item: InboxItem) -> some View {
        let content = HStack(alignment: .top, spacing: 10) {
            // The time, with a mark before it while the item is new.
            ZStack(alignment: .leading) {
                Text(Format.time(item.at, calendar: model.calendar))
                    .font(Theme.mono)
                    .foregroundStyle(item.unread ? Theme.muted : Theme.faint)
                    .monospacedDigit()
                if item.unread {
                    Theme.square(5)
                        .fill(Theme.accent)
                        .frame(width: 5, height: 5)
                        .offset(x: -11, y: 5)
                }
            }
            .frame(width: 44, alignment: .leading)
            .padding(.top, 3)
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
                }
                if let about = item.about {
                    Text(about)
                        .font(Theme.sansSmall)
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        if let entry = item.entry, model.notebook.entry(entry) != nil {
            NavigationLink(value: entry) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
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
