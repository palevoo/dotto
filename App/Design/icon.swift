// Draws the app icon. Run: swift App/Design/icon.swift App/iOS/Sources/Assets.xcassets/AppIcon.appiconset
//
// A sheet, looking back: two dots a little above centre, dotto's eyes, in its colour. The
// smallest face there is. Nothing else. The tinted icon is a grayscale image on transparent,
// which iOS colours itself.

import AppKit
import CoreGraphics

struct Palette {
    let sheet: CGColor
    let eyes: CGColor
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let light = Palette(sheet: color(0xFFFFFF), eyes: color(0xE4572E))
let dark = Palette(sheet: color(0x141618), eyes: color(0xFF6A3D))
let tinted = Palette(sheet: CGColor(gray: 0, alpha: 0), eyes: CGColor(gray: 1, alpha: 1))

func draw(_ palette: Palette, size: CGFloat, transparentBackground: Bool) -> CGImage {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let w = size

    if !transparentBackground {
        context.setFillColor(palette.sheet)
        context.fill(CGRect(x: 0, y: 0, width: w, height: w))
    }

    // Two eyes: a sixth of the width each, a quarter of the width apart, a little above the middle.
    let radius = w / 12
    let y = w * (1 - 0.46)
    context.setFillColor(palette.eyes)
    for x in [w * 0.375, w * 0.625] {
        context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }

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
