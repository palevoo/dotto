// Draws the app icon. Run: swift App/Design/icon.swift App/iOS/Sources/Assets.xcassets/AppIcon.appiconset
// For the Mac:           swift App/Design/icon.swift --mac App/Mac/Assets.xcassets/AppIcon.appiconset
// For dotto dev:         swift App/Design/icon.swift --mac App/Mac/Assets.xcassets/AppIconDev.appiconset --dev
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
    // A sheet filled edge to edge is written with no alpha channel at all: the store refuses
    // one on an app's main icon, even when every pixel is solid.
    let alpha: CGImageAlphaInfo = transparentBackground ? .premultipliedLast : .noneSkipLast
    let context = CGContext(
        data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: alpha.rawValue
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

/// The same sheet and eyes as a Mac icon: the sheet as a rounded square with room around it
/// and a soft shadow under it, as Mac icons sit in the Dock, drawn at each size the Mac asks
/// for rather than scaled down from one.
func drawMac(_ palette: Palette, pixels: Int) -> CGImage {
    let size = CGFloat(pixels)
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // The Mac's own proportions: a body of 824 in a canvas of 1024, corners of about 185.
    let body = CGRect(x: size * 100 / 1024, y: size * 100 / 1024, width: size * 824 / 1024, height: size * 824 / 1024)
    let path = CGPath(roundedRect: body, cornerWidth: size * 185 / 1024, cornerHeight: size * 185 / 1024, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 10 / 1024), blur: size * 22 / 1024, color: CGColor(gray: 0, alpha: 0.28))
    context.addPath(path)
    context.setFillColor(palette.sheet)
    context.fillPath()
    context.restoreGState()
    // A hairline, so a white sheet has an edge on a white wall.
    context.addPath(path)
    context.setStrokeColor(CGColor(gray: 0, alpha: 0.08))
    context.setLineWidth(max(1, size * 2 / 1024))
    context.strokePath()

    let radius = body.width / 12
    let y = body.minY + body.height * (1 - 0.46)
    context.setFillColor(palette.eyes)
    for x in [body.minX + body.width * 0.375, body.minX + body.width * 0.625] {
        context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }
    return context.makeImage()!
}

var arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--mac" {
    arguments.removeFirst()
    // dotto dev wears plum where dotto wears persimmon, in the Dock as in the menu bar.
    let dev = arguments.contains("--dev")
    arguments.removeAll { $0 == "--dev" }
    let output = URL(fileURLWithPath: arguments.first ?? ".", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let palette = Palette(sheet: color(0xFFFFFF), eyes: color(dev ? 0x7A4E8C : 0xE4572E))
    var images: [String] = []
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = "icon-\(points)\(scale == 2 ? "@2x" : "").png"
            try write(drawMac(palette, pixels: points * scale), to: output.appendingPathComponent(name))
            images.append("    { \"filename\" : \"\(name)\", \"idiom\" : \"mac\", \"scale\" : \"\(scale)x\", \"size\" : \"\(points)x\(points)\" }")
        }
    }
    let contents = "{\n  \"images\" : [\n" + images.joined(separator: ",\n") + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
    try contents.write(to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    print("wrote \(images.count) Mac icons to \(output.path)")
    exit(0)
}

let output = URL(fileURLWithPath: arguments.first ?? ".", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try write(draw(light, size: 1024, transparentBackground: false), to: output.appendingPathComponent("icon-light.png"))
try write(draw(dark, size: 1024, transparentBackground: false), to: output.appendingPathComponent("icon-dark.png"))
try write(draw(tinted, size: 1024, transparentBackground: true), to: output.appendingPathComponent("icon-tinted.png"))
print("wrote 3 icons to \(output.path)")
