import AppKit
import Core
import SwiftUI

/// The same inks as the phone, as dynamic Mac colors.
enum MacTheme {
    static let background = Color(light: 0xF3F4F0, dark: 0x1A1C18)
    static let paper = Color(light: 0xFBFBF8, dark: 0x22251F)
    static let line = Color(light: 0xE2E4DD, dark: 0x30342C)
    static let foreground = Color(light: 0x1F231D, dark: 0xE6E9E1)
    static let muted = Color(light: 0x6B716A, dark: 0x9AA095)
    static let faint = Color(light: 0xC9CDC3, dark: 0x4D534C)
    static let accent = Color(light: 0x3B5A2A, dark: 0x8FB07A)
    static let agent = Color(light: 0x5B4A66, dark: 0xB8A6C6)
    static let recording = Color(light: 0xB5452E, dark: 0xE06A52)

    static func square(_ side: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
    }

    /// Everyone's own colour, from their id, the same as on the phone. The owner is the ink.
    static func ink(for author: Author, owner: Author?) -> Color {
        guard author != owner else { return foreground }
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
