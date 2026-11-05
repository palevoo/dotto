import SwiftUI
import UIKit
import VisionKit

/// A photo with the words in it selectable, by Apple's Live Text, on the phone, in the
/// phone's languages. Says what is selected as the selection changes.
struct LiveTextView: UIViewRepresentable {
    let image: UIImage
    let onSelection: (String) -> Void

    static var isSupported: Bool { ImageAnalyzer.isSupported }

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = true
        let interaction = ImageAnalysisInteraction()
        interaction.preferredInteractionTypes = [.textSelection]
        interaction.delegate = context.coordinator
        view.addInteraction(interaction)
        context.coordinator.interaction = interaction
        Task {
            var configuration = ImageAnalyzer.Configuration([.text])
            configuration.locales = Locale.preferredLanguages
            if let analysis = try? await ImageAnalyzer().analyze(image, configuration: configuration) {
                interaction.analysis = analysis
            }
        }
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        context.coordinator.onSelection = onSelection
    }

    /// The size it is given, not the photo's own pixel size, which an image view would
    /// otherwise insist on and show only its middle.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: uiView.image?.size ?? .zero)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection)
    }

    final class Coordinator: NSObject, ImageAnalysisInteractionDelegate {
        var onSelection: (String) -> Void
        var interaction: ImageAnalysisInteraction?

        init(onSelection: @escaping (String) -> Void) {
            self.onSelection = onSelection
        }

        func textSelectionDidChange(_ interaction: ImageAnalysisInteraction) {
            onSelection(interaction.selectedText)
        }
    }
}
