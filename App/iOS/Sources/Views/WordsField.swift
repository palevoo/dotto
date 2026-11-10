import Core
import SwiftUI
import UIKit

/// Words for a line, wherever they are typed: the live line, a line being changed, a reply,
/// a name. Return stores and never lands in the words. A passage pasted or dictated with
/// line breaks keeps its words and loses the breaks, and waits in the field like anything
/// typed, until Return. The field grows with the words up to eight lines, then scrolls.
///
/// A UIKit text view, because that is where the Return key is told apart from a newline
/// arriving inside other text: the key comes alone as "\n" in `shouldChangeTextIn`, a paste
/// comes as the whole passage.
///
/// `focused` mirrors the keyboard: true while this field is the first responder. The caller
/// sets it to raise or dismiss the keyboard and reads it to know. It is a plain Bool, not a
/// FocusState, because SwiftUI's focus system owns a FocusState and clears one that no
/// SwiftUI view claims, which a UIKit field never does.
struct WordsField: View {
    let placeholder: String
    @Binding var text: String
    var size: CGFloat = 18
    var lineSpacing: CGFloat = 4
    var color: Color = Theme.foreground
    /// What this field is, for assistive technology and the UI tests: "live-line", "line-words".
    var identifier: String? = nil
    @Binding var focused: Bool
    let onCommit: () -> Void

    var body: some View {
        WordsTextView(text: $text, size: size, lineSpacing: lineSpacing, color: color, identifier: identifier,
                      focused: $focused, onCommit: onCommit)
            .background(alignment: .topLeading) {
                if text.isEmpty, !placeholder.isEmpty {
                    Text(placeholder)
                        .font(.system(size: size, design: .serif))
                        .foregroundStyle(Theme.faint)
                        .lineSpacing(lineSpacing)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension Binding where Value == String? {
    /// Words while they are being changed: nil, no edit, reads as empty; writing sets them.
    var orEmpty: Binding<String> {
        Binding<String>(get: { wrappedValue ?? "" }, set: { wrappedValue = $0 })
    }
}

extension View {
    /// Words being changed: in the same place at the same size, on a sheet of paper that
    /// says so.
    func editingSurface() -> some View {
        padding(10)
            .background(Theme.square(44).fill(Theme.paper))
            .overlay(Theme.square(44).strokeBorder(Theme.line, lineWidth: 1))
            .padding(-10)
    }
}

private struct WordsTextView: UIViewRepresentable {
    @Binding var text: String
    let size: CGFloat
    let lineSpacing: CGFloat
    let color: Color
    let identifier: String?
    @Binding var focused: Bool
    let onCommit: () -> Void

    private static let maxLines: CGFloat = 8

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.accessibilityIdentifier = identifier
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.showsVerticalScrollIndicator = false
        view.alwaysBounceVertical = false
        view.returnKeyType = .done
        view.autocapitalizationType = .sentences
        view.adjustsFontForContentSizeCategory = false
        view.font = Self.font(size)
        view.typingAttributes = attributes
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.textColor = UIColor(color)
        view.typingAttributes = attributes
        if view.text != text {
            // Set from outside: cleared after Return, a quote or a transcript appended.
            // The words land with their style and the cursor goes to the end of them.
            view.attributedText = NSAttributedString(string: text, attributes: attributes)
            view.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
        let wantsKeyboard = focused
        if wantsKeyboard != view.isFirstResponder {
            DispatchQueue.main.async {
                guard wantsKeyboard != view.isFirstResponder else { return }
                if wantsKeyboard { view.becomeFirstResponder() } else { view.resignFirstResponder() }
            }
        }
    }

    /// As tall as the words, one line at least, eight at most; then the words scroll inside.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0, width.isFinite else { return nil }
        let line = Self.font(size).lineHeight
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let most = line * Self.maxLines + lineSpacing * (Self.maxLines - 1)
        return CGSize(width: width, height: min(max(fitted, line), most).rounded(.up))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    static func font(_ size: CGFloat) -> UIFont { .serif(size) }

    var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        return [.font: Self.font(size), .foregroundColor: UIColor(color), .paragraphStyle: paragraph]
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: WordsTextView

        init(parent: WordsTextView) {
            self.parent = parent
        }

        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            // The Return key arrives alone.
            if replacement == "\n" {
                parent.onCommit()
                return false
            }
            // A passage with breaks in it arrives whole: a paste, dictation, a drop. Each
            // break becomes one space and the passage lands where the cursor is.
            guard replacement.rangeOfCharacter(from: .newlines) != nil else { return true }
            let flat = Words.flattened(replacement)
            view.textStorage.replaceCharacters(in: range, with: NSAttributedString(string: flat, attributes: parent.attributes))
            view.selectedRange = NSRange(location: range.location + (flat as NSString).length, length: 0)
            textViewDidChange(view)
            return false
        }

        func textViewDidChange(_ view: UITextView) {
            if parent.text != view.text { parent.text = view.text }
            view.invalidateIntrinsicContentSize()
        }

        func textViewDidBeginEditing(_ view: UITextView) {
            if !parent.focused { parent.focused = true }
        }

        func textViewDidEndEditing(_ view: UITextView) {
            if parent.focused { parent.focused = false }
        }
    }
}
