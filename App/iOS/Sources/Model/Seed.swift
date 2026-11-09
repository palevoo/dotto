#if DEBUG
import Core
import UIKit

/// Lines for the UI tests, made on launch when asked for with `-uitest-seed-photos`: one
/// line with two photos of printed words, so the viewer has pages to turn and words for
/// Live Text to find. Debug builds only; made once per notebook.
@MainActor
enum Seed {
    static let words = "Two pages from a book, for the viewer"
    static let pages = [
        "Writing costs nothing. One gesture, no categories, no decisions, no audience.",
        "Meaning comes later. What a line is, what it connects to, what it should trigger, is decided after it is written.",
    ]

    static func runIfAsked(_ model: NotebookModel) async {
        guard ProcessInfo.processInfo.arguments.contains("-uitest-seed-photos"),
              !model.notebook.entries.contains(where: { $0.text == words }) else { return }
        for page in pages {
            await model.addPhoto(render(page))
        }
        model.draftText = words
        model.commitDraft()
    }

    /// A page of a book: black serif on white, large enough for Live Text.
    static func render(_ text: String) -> Data {
        let size = CGSize(width: 1200, height: 1600)
        return UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 18
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.serif(56), .foregroundColor: UIColor.black, .paragraphStyle: paragraph,
            ]
            (text as NSString).draw(in: CGRect(x: 120, y: 220, width: 960, height: 1200), withAttributes: attributes)
        }
    }
}
#endif
