import SwiftUI

/// The palette from the mock, as dynamic colors, and the one shape everything made with the app takes.
enum Theme {
    static let background = Color(light: 0xF3F4F0, dark: 0x1A1C18)
    static let paper = Color(light: 0xFBFBF8, dark: 0x22251F)
    static let line = Color(light: 0xE2E4DD, dark: 0x30342C)
    static let foreground = Color(light: 0x1F231D, dark: 0xE6E9E1)
    static let muted = Color(light: 0x6B716A, dark: 0x9AA095)
    static let faint = Color(light: 0xC9CDC3, dark: 0x4D534C)
    static let accent = Color(light: 0x3B5A2A, dark: 0x8FB07A)
    static let agent = Color(light: 0x5B4A66, dark: 0xB8A6C6)
    static let warm = Color(light: 0x9A5A2A, dark: 0xD9955A)
    static let recording = Color(light: 0xB5452E, dark: 0xE06A52)

    /// Continuous-curvature rounded square. Radius is a fixed share of the shorter side.
    static func square(_ side: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
    }

    static let serif: Font = .system(size: 18, design: .serif)
    static let serifSmall: Font = .system(size: 15, design: .serif)
    static let mono: Font = .system(size: 12, design: .monospaced)
    static let sansSmall: Font = .system(size: 13)
    static let title: Font = .system(size: 22, weight: .medium, design: .serif)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIFont {
    /// The serif the page is set in, for UIKit views. Scaled follows the person's text size.
    static func serif(_ size: CGFloat, scaled: Bool = false) -> UIFont {
        let base = UIFont.systemFont(ofSize: size)
        let font = base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
        return scaled ? UIFontMetrics(forTextStyle: .body).scaledFont(for: font) : font
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
