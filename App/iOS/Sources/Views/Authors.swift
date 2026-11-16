import Core
import SwiftUI

/// Everyone has a colour of their own, from their id, before they have a name. Yours is
/// the colour of the page's own text.
extension Theme {
    static func colour(for author: Author, owner: Author) -> Color {
        guard author != owner else { return foreground }
        // The notebook's own wears the one colour the app has.
        if author == .dotto { return Theme.accent }
        let hue = author.hue
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hue: hue, saturation: 0.38, brightness: 0.78, alpha: 1)
                : UIColor(hue: hue, saturation: 0.48, brightness: 0.52, alpha: 1)
        })
    }
}

/// Who did something, as the page says it: "you", the name they chose in their colour, or,
/// until they choose one, their mark alone.
struct Who: View {
    let author: Author
    let model: NotebookModel
    var font: Font = Theme.mono

    var body: some View {
        let owner = model.store.manifest.owner
        if author == owner {
            Text("you").font(font).foregroundStyle(Theme.foreground)
        } else if let name = model.notebook.name(of: author) {
            Text(name).font(font).foregroundStyle(Theme.colour(for: author, owner: owner))
        } else {
            AuthorMark(author: author, model: model)
        }
    }
}

/// Someone's own dot in their colour, for where their name would go.
struct AuthorMark: View {
    let author: Author
    let model: NotebookModel
    var side: CGFloat = 11

    var body: some View {
        DotShape(author.dot)
            .fill(Theme.colour(for: author, owner: model.store.manifest.owner))
            .frame(width: side, height: side)
    }
}

/// Someone's mark and their name, or their mark and the plain fact that there is no name
/// yet. For rows that stand for a person.
struct AuthorLabel: View {
    let author: Author
    let model: NotebookModel

    var body: some View {
        HStack(spacing: 7) {
            AuthorMark(author: author, model: model, side: 10)
            if let name = model.notebook.name(of: author) {
                Text(name)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.colour(for: author, owner: model.store.manifest.owner))
            } else {
                Text("no name yet")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.faint)
            }
        }
    }
}
