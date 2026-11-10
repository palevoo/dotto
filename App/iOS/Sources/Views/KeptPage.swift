import Core
import SwiftUI

/// What a line points at, kept beside it, to read: its title, where it came from, its words.
/// The words are in the notebook, so they are here whatever becomes of the address.
struct KeptPage: View {
    let entry: ULID
    let hash: String
    @Bindable var model: NotebookModel
    /// The words, once read from the file; an empty string when the file is not here yet.
    @State private var words: String?

    private var page: Media? {
        model.notebook.entry(entry)?.media.first { $0.hash == hash }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let page {
                    Text(page.title ?? "A page")
                        .font(Theme.title)
                        .foregroundStyle(Theme.foreground)
                        .accessibilityIdentifier("kept-title")
                    if let source = page.source, let url = URL(string: source) {
                        Link(destination: url) {
                            Text(url.host.map { $0 + url.path } ?? source)
                                .font(Theme.mono)
                                .foregroundStyle(Theme.accent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                switch words {
                case nil:
                    EmptyView()
                case "":
                    Text("Its words are not on this phone yet.")
                        .font(Theme.serifSmall)
                        .foregroundStyle(Theme.muted)
                case let words?:
                    Text(words)
                        .font(Theme.serifSmall)
                        .foregroundStyle(Theme.foreground)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("kept-words")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbarBackground(Theme.background, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: hash) {
            guard let page else { words = ""; return }
            let url = model.mediaURL(page)
            words = await Task.detached(priority: .userInitiated) { Self.words(at: url) }.value
        }
    }

    /// The kept file without the title and the address it opens with, which the page says itself.
    private static func words(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        var lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)[...]
        while let first = lines.first, first.isEmpty || first.hasPrefix("# ") || first.hasPrefix("Kept from ") { lines = lines.dropFirst() }
        // A very long paper is shown from its beginning; the whole is in the file.
        return String(lines.joined(separator: "\n").prefix(60_000)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
