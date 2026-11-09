import Core
import SwiftUI

/// Plain words over the notebook. Every word typed must appear, case and accents aside, a
/// word found inside a longer one; a line is found through its own words, a reply under it,
/// a thing it is with or a tag it is under. Things whose names match come first, then the
/// lines by day, newest first. Tap one to open it.
struct SearchPage: View {
    @Bindable var model: NotebookModel
    @State private var words = ""
    @FocusState private var focused: Bool

    var body: some View {
        let hits = model.notebook.search(words)
        let things = model.notebook.things(matching: words)
        let days = Notebook.days(of: hits.map(\.entry), calendar: model.calendar).reversed()
        let via = Dictionary(uniqueKeysWithValues: hits.compactMap { hit in hit.via.map { (hit.id, $0) } })
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TextField("Words", text: $words)
                    .font(Theme.serif)
                    .foregroundStyle(Theme.foreground)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($focused)
                    .onSubmit { focused = false }
                    .padding(10)
                    .background(Theme.square(44).fill(Theme.paper))
                    .overlay(Theme.square(44).strokeBorder(Theme.line, lineWidth: 1))
                    .accessibilityIdentifier("search-words")

                if Notebook.terms(words).isEmpty {
                    Text("Words from any line, a reply under it, a thing it is with or a tag it is under. Every word must appear.")
                        .font(Theme.serifSmall)
                        .foregroundStyle(Theme.muted)
                        .lineSpacing(3)
                } else if hits.isEmpty, things.isEmpty {
                    Text("Nothing for “\(words.trimmingCharacters(in: .whitespaces))”.")
                        .font(Theme.serifSmall)
                        .foregroundStyle(Theme.muted)
                }

                if !things.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(things) { thing in
                            NavigationLink(value: Route.thing(thing.id)) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(thing.isTag ? "#\(thing.name)" : thing.name)
                                        .font(Theme.serif)
                                        .foregroundStyle(Theme.foreground)
                                    Text(thing.isTag ? "tag" : (thing.kind ?? "thing"))
                                        .font(Theme.mono)
                                        .foregroundStyle(Theme.faint)
                                    Spacer(minLength: 0)
                                    Text("\(thing.lines.count)")
                                        .font(Theme.mono)
                                        .foregroundStyle(Theme.faint)
                                        .monospacedDigit()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("found-thing-\(thing.name)")
                        }
                    }
                }

                ForEach(days) { day in
                    VStack(alignment: .leading, spacing: 14) {
                        Text(Format.day(day.key, calendar: model.calendar, withYear: false))
                            .font(Theme.mono)
                            .foregroundStyle(Theme.faint)
                        ForEach(day.entries.sorted { ($0.startedAt, $0.id) > ($1.startedAt, $1.id) }) { entry in
                            NavigationLink(value: entry.id) {
                                row(entry, via: via[entry.id])
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
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .toolbarBackground(Theme.background, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
    }

    /// A line found: its time, its words, and the reply that held the words when its own did not.
    private func row(_ entry: Entry, via: Note?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(Format.time(entry.startedAt, calendar: model.calendar))
                .font(Theme.mono)
                .foregroundStyle(Theme.muted)
                .frame(width: 44, alignment: .leading)
                .monospacedDigit()
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text.isEmpty ? "a photo" : entry.text)
                    .font(Theme.serif)
                    .foregroundStyle(entry.text.isEmpty ? Theme.faint : Theme.foreground)
                    .lineSpacing(4)
                    .lineLimit(3)
                    .accessibilityIdentifier("found")
                if let via {
                    Text(via.text)
                        .font(Theme.sansSmall)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
