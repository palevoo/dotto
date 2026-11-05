import SwiftUI
import UIKit
import VisionKit

/// A photo with the words in it selectable, by Apple's Live Text, on the phone, in the
/// phone's languages. Touching words selects them; a touch anywhere else is left to whatever
/// holds the photo, so a drag still pages or closes. Says only whether something is
/// selected, so the selection can move without the rest of the screen following; the words
/// themselves are read when they are wanted.
struct LiveTextView: UIViewRepresentable {
    let image: UIImage
    @Binding var hasSelection: Bool
    /// Hands over the way to read the selected words and to clear them.
    let hold: (Selection) -> Void

    struct Selection {
        let words: () -> String
        let clear: () -> Void
    }

    static var isSupported: Bool { ImageAnalyzer.isSupported }
    /// One analyser for every photo, as Apple asks.
    private static let analyzer = ImageAnalyzer()

    /// The phone's languages, as Live Text names them. The phone says "ru-PT" for Russian
    /// on a phone set to Portugal; Live Text knows only "ru-RU", and ignores what it does not
    /// know, so each language is matched by its code.
    static var languages: [String] {
        let known = ImageAnalyzer.supportedTextRecognitionLanguages.map { ($0, Locale(identifier: $0).language.languageCode?.identifier) }
        var found: [String] = []
        for identifier in Locale.preferredLanguages {
            guard let code = Locale(identifier: identifier).language.languageCode?.identifier,
                  let match = known.first(where: { $0.1 == code })?.0, !found.contains(match) else { continue }
            found.append(match)
        }
        return found
    }

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.isUserInteractionEnabled = true
        let interaction = ImageAnalysisInteraction()
        interaction.preferredInteractionTypes = [.textSelection]
        interaction.delegate = context.coordinator
        view.addInteraction(interaction)
        context.coordinator.interaction = interaction
        hold(Selection(words: { interaction.selectedText }, clear: { interaction.resetTextSelection() }))
        Task {
            var configuration = ImageAnalyzer.Configuration([.text])
            configuration.locales = Self.languages
            if let analysis = try? await Self.analyzer.analyze(image, configuration: configuration) {
                interaction.analysis = analysis
            }
        }
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        context.coordinator.onChange = { hasSelection = $0 }
    }

    /// The size it is given, not the photo's own pixel size, which an image view would
    /// otherwise insist on and show only its middle.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: uiView.image?.size ?? .zero)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator { hasSelection = $0 }
    }

    final class Coordinator: NSObject, ImageAnalysisInteractionDelegate {
        var onChange: (Bool) -> Void
        var interaction: ImageAnalysisInteraction?
        private var had = false

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
        }

        /// Only words start a selection. Everywhere else the touch belongs to the viewer.
        func interaction(_ interaction: ImageAnalysisInteraction, shouldBeginAt point: CGPoint,
                         for interactionType: ImageAnalysisInteraction.InteractionTypes) -> Bool {
            interaction.hasInteractiveItem(at: point) || interaction.hasActiveTextSelection
        }

        func textSelectionDidChange(_ interaction: ImageAnalysisInteraction) {
            let has = !interaction.selectedText.isEmpty
            guard has != had else { return }
            had = has
            onChange(has)
        }
    }
}
