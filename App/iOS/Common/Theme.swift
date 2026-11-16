import SwiftUI

/// The palette: a cool near-white ground, neutral black text, hairlines barely
/// there, and nothing coloured but the dot. Persimmon is this notebook's dotto; every other
/// originator has a colour of its own from its id. The rounded square is the shape of things
/// made with the app, photos and buttons; a mark that stands for someone is a dot.
enum Theme {
    static let background = Color(light: 0xF6F6F4, dark: 0x111213)
    static let paper = Color(light: 0xFFFFFF, dark: 0x191B1C)
    static let line = Color(light: 0xE6E7E5, dark: 0x262829)
    static let foreground = Color(light: 0x141618, dark: 0xECEDEA)
    static let muted = Color(light: 0x6B7075, dark: 0x9EA3A1)
    static let faint = Color(light: 0xC9CCCA, dark: 0x4A4E4D)
    static let accent = Color(light: 0xE4572E, dark: 0xFF6A3D)
    static let warm = Color(light: 0xB8741A, dark: 0xE0A33F)
    static let recording = Color(light: 0xC62828, dark: 0xFF5252)

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
