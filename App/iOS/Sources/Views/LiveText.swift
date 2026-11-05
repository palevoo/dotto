import SwiftUI
import UIKit
import VisionKit

/// A photo with the words in it selectable, by Apple's Live Text, on the phone, in the
/// phone's languages. Touching words selects them; a touch anywhere else is left to whatever
/// holds the photo, so a drag still pages or closes. The selected words are read out as the
/// selection changes, and emptying them from outside clears the selection in the photo.
struct LiveTextView: UIViewRepresentable {
    let image: UIImage
    @Binding var selected: String

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
        context.coordinator.onChange = { selected = $0 }
        if selected.isEmpty, let interaction = context.coordinator.interaction, interaction.hasActiveTextSelection {
            interaction.resetTextSelection()
        }
    }

    /// The size it is given, not the photo's own pixel size, which an image view would
    /// otherwise insist on and show only its middle.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: uiView.image?.size ?? .zero)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator { selected = $0 }
    }

    final class Coordinator: NSObject, ImageAnalysisInteractionDelegate {
        var onChange: (String) -> Void
        var interaction: ImageAnalysisInteraction?

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        /// Only words start a selection. Everywhere else the touch belongs to the viewer.
        func interaction(_ interaction: ImageAnalysisInteraction, shouldBeginAt point: CGPoint,
                         for interactionType: ImageAnalysisInteraction.InteractionTypes) -> Bool {
            interaction.hasInteractiveItem(at: point) || interaction.hasActiveTextSelection
        }

        func textSelectionDidChange(_ interaction: ImageAnalysisInteraction) {
            onChange(interaction.selectedText)
        }
    }
}

/// "12 words", for the passage about to be quoted.
func wordCount(_ passage: String) -> String {
    let count = passage.split(whereSeparator: \.isWhitespace).count
    return "\(count) word\(count == 1 ? "" : "s")"
}
