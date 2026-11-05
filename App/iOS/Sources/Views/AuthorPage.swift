import Core
import SwiftUI

/// Someone else's page: the lines they wrote for themselves and for you, by day, with your
/// replies under them. The same shape as your page, read the other way round. Tap a line to
/// open it and reply.
struct AuthorPage: View {
    let author: Author
    @Bindable var model: NotebookModel

    var body: some View {
        let days = model.notebook.days(of: author, calendar: model.calendar)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // The name they chose, or, until they choose one, only their mark.
                if let name = model.notebook.name(of: author) {
                    Text(name)
                        .font(Theme.title)
                        .foregroundStyle(Theme.foreground)
                } else {
                    AuthorMark(side: 22)
                        .padding(.vertical, 4)
                }
                if days.isEmpty {
                    Text("Nothing written here yet.")
                        .font(Theme.serifSmall)
                        .foregroundStyle(Theme.muted)
                }
                ForEach(days) { day in
                    VStack(alignment: .leading, spacing: 14) {
                        Text(Format.day(day.key, calendar: model.calendar, withYear: false))
                            .font(Theme.mono)
                            .foregroundStyle(Theme.faint)
                        ForEach(day.entries) { entry in
                            NavigationLink(value: entry.id) {
                                row(entry)
                            }
                            .buttonStyle(.plain)
                        }
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
    }

    private func row(_ entry: Entry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(Format.time(entry.startedAt, calendar: model.calendar))
                .font(Theme.mono)
                .foregroundStyle(Theme.muted)
                .frame(width: 44, alignment: .leading)
                .monospacedDigit()
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.text)
                    .font(Theme.serif)
                    .foregroundStyle(Theme.foreground)
                    .lineSpacing(4)
                if !entry.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(entry.notes) { note in
                            ReplyMark(note: note, mine: note.author == model.store.manifest.owner)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
