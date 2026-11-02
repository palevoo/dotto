// Draws the Margin app icon. Run: swift App/Design/icon.swift App/Sources/Assets.xcassets/AppIcon.appiconset
//
// A page. The margin is a hairline a third of the way in. The one green square is the mark
// that waits at the end of today's page. Nothing else.

import AppKit
import CoreGraphics

struct Palette {
    let paper: CGColor
    let line: CGColor
    let mark: CGColor
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let light = Palette(paper: color(0xFBFBF8), line: color(0xC9CDC3), mark: color(0x3B5A2A))
let dark = Palette(paper: color(0x1A1C18), line: color(0x3A3F36), mark: color(0x8FB07A))
// Tinted icons are a grayscale image on transparent; iOS colours them.
let tinted = Palette(paper: CGColor(gray: 0, alpha: 0), line: CGColor(gray: 0.55, alpha: 1), mark: CGColor(gray: 1, alpha: 1))

func draw(_ palette: Palette, size: CGFloat, transparentBackground: Bool) -> CGImage {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let w = size

    if !transparentBackground {
        context.setFillColor(palette.paper)
        context.fill(CGRect(x: 0, y: 0, width: w, height: w))
    }

    // The margin line.
    let lineX = w * 0.34
    let lineWidth = max(2, w * 0.012)
    context.setFillColor(palette.line)
    context.fill(CGRect(x: lineX - lineWidth / 2, y: 0, width: lineWidth, height: w))

    // The mark, in the margin, where today's page ends. Continuous-curvature rounded square.
    let side = w * 0.17
    let center = CGPoint(x: lineX / 2, y: w * (1 - 0.66))
    let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    let path = CGPath(roundedRect: rect, cornerWidth: side * 0.22, cornerHeight: side * 0.22, transform: nil)
    context.setFillColor(palette.mark)
    context.addPath(path)
    context.fillPath()

    return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "icon", code: 1) }
    try data.write(to: url)
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try write(draw(light, size: 1024, transparentBackground: false), to: output.appendingPathComponent("icon-light.png"))
try write(draw(dark, size: 1024, transparentBackground: false), to: output.appendingPathComponent("icon-dark.png"))
try write(draw(tinted, size: 1024, transparentBackground: true), to: output.appendingPathComponent("icon-tinted.png"))
print("wrote 3 icons to \(output.path)")
