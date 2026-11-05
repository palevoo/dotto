import SwiftUI
import UIKit
import VisionKit

/// A photo with the words in it selectable, by Apple's Live Text, on the phone, in the
/// phone's languages. Touching words selects them; a touch anywhere else is left to whatever
/// holds the photo, so a drag still pages or closes. The selection is read out as it changes,
/// and emptying it from outside clears it in the photo.
struct LiveTextView: UIViewRepresentable {
    let image: UIImage
    @Binding var selected: String

    static var isSupported: Bool { ImageAnalyzer.isSupported }
    /// One analyser for every photo, as Apple asks.
    private static let analyzer = ImageAnalyzer()

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
            configuration.locales = Locale.preferredLanguages
            if let analysis = try? await Self.analyzer.analyze(image, configuration: configuration) {
                interaction.analysis = analysis
            }
        }
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        context.coordinator.onSelection = { selected = $0 }
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
        var onSelection: (String) -> Void
        var interaction: ImageAnalysisInteraction?

        init(onSelection: @escaping (String) -> Void) {
            self.onSelection = onSelection
        }

        /// Only words start a selection. Everywhere else the touch belongs to the viewer.
        func interaction(_ interaction: ImageAnalysisInteraction, shouldBeginAt point: CGPoint,
                         for interactionType: ImageAnalysisInteraction.InteractionTypes) -> Bool {
            interaction.hasInteractiveItem(at: point) || interaction.hasActiveTextSelection
        }

        func textSelectionDidChange(_ interaction: ImageAnalysisInteraction) {
            onSelection(interaction.selectedText)
        }
    }
}
