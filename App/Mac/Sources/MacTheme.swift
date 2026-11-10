import AppKit
import Core
import SwiftUI

/// The same inks as the phone, as dynamic Mac colors.
enum MacTheme {
    static let background = Color(light: 0xF6F6F4, dark: 0x111213)
    static let paper = Color(light: 0xFFFFFF, dark: 0x191B1C)
    static let line = Color(light: 0xE6E7E5, dark: 0x262829)
    static let foreground = Color(light: 0x141618, dark: 0xECEDEA)
    static let muted = Color(light: 0x6B7075, dark: 0x9EA3A1)
    static let faint = Color(light: 0xC9CCCA, dark: 0x4A4E4D)
    static let accent = Color(light: 0xE4572E, dark: 0xFF6A3D)
    static let agent = Color(light: 0x7A4E8C, dark: 0xB78BC9)
    static let recording = Color(light: 0xC62828, dark: 0xFF5252)

    static func square(_ side: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
    }

    /// Everyone's own colour, from their id, the same as on the phone. The owner is the ink.
    static func ink(for author: Author, owner: Author?) -> Color {
        guard author != owner else { return foreground }
        // The notebook's own wears the one colour the app has.
        guard author != .dotto else { return accent }
        let hue = author.hue
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark
                ? NSColor(hue: hue, saturation: 0.38, brightness: 0.78, alpha: 1)
                : NSColor(hue: hue, saturation: 0.48, brightness: 0.52, alpha: 1)
        })
    }

    static let title: Font = .system(size: 22, weight: .medium, design: .serif)
    static let heading: Font = .system(size: 15, weight: .medium, design: .serif)
    static let body: Font = .system(size: 13)
    static let mono: Font = .system(size: 11.5, design: .monospaced)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
