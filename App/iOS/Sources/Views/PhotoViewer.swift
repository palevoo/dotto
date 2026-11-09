import Core
import SwiftUI

/// A line's photo, opened: which line, which photo, where it stands in the line's row.
struct PhotoOpening: Identifiable, Hashable {
    let entry: ULID
    let hash: String
    let index: Int

    var id: String { Self.source(entry, hash) }

    /// The id a photo wears on the page, so the viewer grows out of it and shrinks back into it.
    static func source(_ entry: ULID, _ hash: String) -> String { "\(entry.string)-\(hash)" }
}

/// The viewer, for SwiftUI: `PhotoViewerController` with the line's photos and words, kept
/// current as the notebook changes. Present it in a full-screen cover with the zoom
/// transition from the photo's `matchedTransitionSource`.
struct PhotoViewer: UIViewControllerRepresentable {
    let opening: PhotoOpening
    let model: NotebookModel
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> PhotoViewerController {
        let controller = PhotoViewerController(photos: photos, index: opening.index, words: words)
        controller.onClose = onClose
        controller.onWords = { [model, entry = opening.entry] text in model.edit(entry, text: text) }
        return controller
    }

    func updateUIViewController(_ controller: PhotoViewerController, context: Context) {
        controller.show(photos: photos, words: words)
    }

    private var line: Entry? { model.notebook.entry(opening.entry) }

    private var photos: [PhotoViewerController.Photo] {
        (line?.media ?? []).filter { $0.mime.hasPrefix("image") }.map { media in
            PhotoViewerController.Photo(
                hash: media.hash,
                url: model.mediaURL(media),
                size: media.width.flatMap { width in media.height.map { height in CGSize(width: width, height: height) } },
                thumbnail: Thumbs.cached(media.hash)
            )
        }
    }

    private var words: String { line?.text ?? "" }
}
