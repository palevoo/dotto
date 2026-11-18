// Makes everything that is drawn from design/: the app icons, and the dot as files for the
// site, for print and for anyone who wants one. Run from anywhere:
//
//     swift run --package-path design dot
//
// It reads tokens.json and dots.json beside it and writes into App/ and design/assets/. A
// file that already says the same is left alone, so a run with nothing new changes nothing.

import AppKit
import Core
import Foundation

struct Problem: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: What is read

/// tokens.json, as far as this program needs it: the colours.
struct Tokens: Decodable {
    struct Colours: Decodable {
        let tokens: [Token]
    }

    struct Token: Decodable {
        let name: String
        let value: Value
    }

    /// One value for every theme, or one a theme.
    enum Value: Decodable {
        case one(String)
        case themed([String: String])

        init(from decoder: Decoder) throws {
            let box = try decoder.singleValueContainer()
            if let text = try? box.decode(String.self) {
                self = .one(text)
            } else {
                self = .themed(try box.decode([String: String].self))
            }
        }
    }

    let color: Colours

    /// A colour by name in a theme, as "#rrggbb". A value written "{another}" is that one's.
    func hex(_ name: String, _ theme: String, depth: Int = 0) throws -> String {
        guard depth < 8 else { throw Problem("\(name) names itself in tokens.json") }
        guard let token = color.tokens.first(where: { $0.name == name }) else {
            throw Problem("no colour called \(name) in tokens.json")
        }
        let text: String
        switch token.value {
        case .one(let value): text = value
        case .themed(let values):
            guard let value = values[theme] ?? values["light"] else { throw Problem("\(name) has no \(theme) value") }
            text = value
        }
        if text.hasPrefix("{"), text.hasSuffix("}") {
            return try hex(String(text.dropFirst().dropLast()), theme, depth: depth + 1)
        }
        guard text.hasPrefix("#"), text.count == 7, UInt32(text.dropFirst(), radix: 16) != nil else {
            throw Problem("\(name) is \(text), which is not #rrggbb")
        }
        return text.lowercased()
    }

    func colour(_ name: String, _ theme: String) throws -> CGColor {
        let value = UInt32(try hex(name, theme).dropFirst(), radix: 16)!
        return CGColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// dots.json: the dots there are to choose from, which is Dotto's own, and how much of a
/// sheet a dot takes.
struct Dots: Decodable {
    struct Entry: Decodable {
        /// Where the arcs meet on the top, right, bottom and left sides, in hundredths.
        let meets: [Double]
        let proportion: Double
        let turn: Double
    }

    struct Worn: Decodable {
        /// Which of the dots, counted from one.
        let dot: Int
        let colour: String
    }

    let size: Double
    let dotto: Worn
    let dev: Worn
    let dots: [Entry]

    func dot(_ number: Int) throws -> Dot {
        guard dots.indices.contains(number - 1) else { throw Problem("dots.json has no dot \(number)") }
        let entry = dots[number - 1]
        guard entry.meets.count == 4 else { throw Problem("dot \(number) needs four numbers in meets") }
        return Dot(
            top: entry.meets[0] / 100, right: entry.meets[1] / 100, bottom: entry.meets[2] / 100, left: entry.meets[3] / 100,
            proportion: entry.proportion, turn: entry.turn
        )
    }
}

// MARK: Drawing

func path(_ dot: Dot, size: CGFloat, centre: CGPoint) -> CGPath {
    let outline = dot.outline(size: Double(size), centre: Dot.Point(x: Double(centre.x), y: Double(centre.y)))
    func point(_ point: Dot.Point) -> CGPoint { CGPoint(x: point.x, y: point.y) }
    let path = CGMutablePath()
    path.move(to: point(outline.start))
    for curve in outline.curves {
        path.addCurve(to: point(curve.end), control1: point(curve.control1), control2: point(curve.control2))
    }
    path.closeSubpath()
    return path
}

/// A square of pixels to draw on, with y growing downward as the dot's own numbers do.
func canvas(_ pixels: Int, alpha: Bool) -> CGContext {
    let info: CGImageAlphaInfo = alpha ? .premultipliedLast : .noneSkipLast
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info.rawValue
    )!
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: 1, y: -1)
    return context
}

/// The phone's icon: a sheet filled to its edges, and the dot in the middle of it. With no
/// sheet it is the dot alone on nothing, which is what the phone tints.
///
/// A sheet filled edge to edge is written with no alpha channel at all: the store refuses
/// one on an app's main icon, even when every pixel is solid.
func phoneIcon(_ dot: Dot, colour: CGColor, sheet: CGColor?, share: Double) -> CGImage {
    let pixels = 1024
    let side = CGFloat(pixels)
    let context = canvas(pixels, alpha: sheet == nil)
    if let sheet {
        context.setFillColor(sheet)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    }
    context.addPath(path(dot, size: side * share, centre: CGPoint(x: side / 2, y: side / 2)))
    context.setFillColor(colour)
    context.fillPath()
    return context.makeImage()!
}

/// The same on the Mac: the sheet as a rounded square with room around it and a soft shadow
/// under it, as Mac icons sit in the Dock, drawn at each size the Mac asks for rather than
/// scaled down from one.
func macIcon(_ dot: Dot, colour: CGColor, sheet: CGColor, share: Double, pixels: Int) -> CGImage {
    let side = CGFloat(pixels)
    let context = canvas(pixels, alpha: true)
    // The Mac's own proportions: a body of 824 in a canvas of 1024, corners of about 185.
    let body = CGRect(x: side * 100 / 1024, y: side * 100 / 1024, width: side * 824 / 1024, height: side * 824 / 1024)
    let edge = CGPath(roundedRect: body, cornerWidth: side * 185 / 1024, cornerHeight: side * 185 / 1024, transform: nil)
    context.saveGState()
    // A shadow's offset is measured on the pixels, not on the page: down is negative.
    context.setShadow(offset: CGSize(width: 0, height: -side * 10 / 1024), blur: side * 22 / 1024, color: CGColor(gray: 0, alpha: 0.28))
    context.addPath(edge)
    context.setFillColor(sheet)
    context.fillPath()
    context.restoreGState()
    // A hairline, so a white sheet has an edge on a white wall.
    context.addPath(edge)
    context.setStrokeColor(CGColor(gray: 0, alpha: 0.08))
    context.setLineWidth(max(1, side * 2 / 1024))
    context.strokePath()

    context.addPath(path(dot, size: body.width * share, centre: CGPoint(x: body.midX, y: body.midY)))
    context.setFillColor(colour)
    context.fillPath()
    return context.makeImage()!
}

func png(_ image: CGImage) throws -> Data {
    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw Problem("could not write a picture as PNG")
    }
    return data
}

/// A dot on a hundred by a hundred, as an SVG. A sheet, when there is one, lies under it.
func svg(_ dot: Dot, fill: String, size: Double, sheet: String? = nil) -> Data {
    var lines = ["<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">"]
    if let sheet {
        lines.append("  <rect width=\"100\" height=\"100\" rx=\"22\" fill=\"\(sheet)\"/>")
    }
    let d = dot.outline(size: size, centre: Dot.Point(x: 50, y: 50)).svg
    lines.append("  <path fill=\"\(fill)\" d=\"\(d)\"/>")
    lines.append("</svg>")
    return Data((lines.joined(separator: "\n") + "\n").utf8)
}

/// The dot alone as a one-page PDF, a hundred points square, for print. Written out by hand
/// so that it carries no date and comes out the same every time.
func pdf(_ dot: Dot, hex: String, size: Double) -> Data {
    let value = UInt32(hex.dropFirst(), radix: 16)!
    func channel(_ shift: UInt32) -> String { String(format: "%.4f", Double((value >> shift) & 0xFF) / 255) }
    func number(_ value: Double) -> String { String(format: "%.3f", value) }
    // A PDF's y grows upward, so every y is counted from the top.
    func point(_ point: Dot.Point) -> String { "\(number(point.x)) \(number(100 - point.y))" }

    let outline = dot.outline(size: size, centre: Dot.Point(x: 50, y: 50))
    var drawing = "\(channel(16)) \(channel(8)) \(channel(0)) rg\n\(point(outline.start)) m\n"
    for curve in outline.curves {
        drawing += "\(point(curve.control1)) \(point(curve.control2)) \(point(curve.end)) c\n"
    }
    drawing += "h f\n"

    let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R /Resources << >> >>",
        "<< /Length \(drawing.utf8.count) >>\nstream\n\(drawing)endstream",
    ]
    var file = "%PDF-1.4\n"
    var offsets: [Int] = []
    for (index, object) in objects.enumerated() {
        offsets.append(file.utf8.count)
        file += "\(index + 1) 0 obj\n\(object)\nendobj\n"
    }
    let table = file.utf8.count
    file += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
    for offset in offsets {
        file += String(format: "%010d 00000 n \n", offset)
    }
    file += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(table)\n%%EOF\n"
    return Data(file.utf8)
}

/// The dots as Swift, for Core: Dotto's own, and all there are to choose from.
func swift(_ dots: Dots) throws -> Data {
    func number(_ value: Double) -> String { String(format: "%g", value) }
    func literal(_ entry: Dots.Entry) -> String {
        "Dot(top: \(number(entry.meets[0] / 100)), right: \(number(entry.meets[1] / 100)), bottom: \(number(entry.meets[2] / 100)), left: \(number(entry.meets[3] / 100)), proportion: \(number(entry.proportion)), turn: \(number(entry.turn)))"
    }
    _ = try dots.dot(dots.dotto.dot)
    var lines = [
        "// Written by `swift run --package-path design dot` from design/dots.json. Change it there.",
        "",
        "extension Dot {",
        "    /// Dotto's own dot.",
        "    public static let dotto = \(literal(dots.dots[dots.dotto.dot - 1]))",
        "",
        "    /// The dots there are to choose from.",
        "    public static let all: [Dot] = [",
    ]
    lines += dots.dots.map { "        \(literal($0))," }
    lines += ["    ]", "}"]
    return Data((lines.joined(separator: "\n") + "\n").utf8)
}

/// The dots as CSS, for the site: a shape, a turn, and how much wider and shorter than
/// round, each as a variable a rule can use. Dotto's own dot always; the rest when `all`.
func css(_ dots: Dots, all: Bool) throws -> String {
    func number(_ value: Double) -> String { String(format: "%g", value) }
    func variables(_ entry: Dots.Entry, _ prefix: String) -> String {
        let (top, right, bottom, left) = (entry.meets[0], entry.meets[1], entry.meets[2], entry.meets[3])
        let radius = "\(number(top))% \(number(100 - top))% \(number(100 - bottom))% \(number(bottom))% / \(number(left))% \(number(right))% \(number(100 - right))% \(number(100 - left))%"
        let root = entry.proportion.squareRoot()
        return "--\(prefix)r: \(radius); --\(prefix)turn: \(number(entry.turn))deg; --\(prefix)w: \(String(format: "%.4g", root)); --\(prefix)h: \(String(format: "%.4g", 1 / root));"
    }
    _ = try dots.dot(dots.dotto.dot)
    var lines = [
        "/* Dotto's own dot. */",
        ":root { \(variables(dots.dots[dots.dotto.dot - 1], "own-")) }",
    ]
    if all {
        lines.append("/* The dots there are: a shape, a turn, and how much wider and shorter than round. */")
        for (index, entry) in dots.dots.enumerated() {
            lines.append(".d\(index + 1) { \(variables(entry, "")) }")
        }
    }
    return lines.joined(separator: "\n")
}

// MARK: Writing

/// Where things are, and what a run wrote.
final class Desk {
    let design = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    var repository: URL { design.deletingLastPathComponent() }
    var changed: [String] = []
    var same = 0

    func read<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: Data(contentsOf: design.appendingPathComponent(name)))
        } catch {
            throw Problem("design/\(name): \(error)")
        }
    }

    /// Writes a file unless it already says the same.
    func put(_ data: Data, _ path: String) throws {
        let url = repository.appendingPathComponent(path)
        if let there = try? Data(contentsOf: url), there == data {
            same += 1
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        changed.append(path)
    }

    /// Where the dots stand in a page of the site: between these two lines of its style.
    static let dotsBegin = "/* The dots. Written by `swift run --package-path design dot` from design/dots.json. Change them there. */"
    static let dotsEnd = "/* The dots end. */"

    /// Puts the dots into a page of the site, in the place its style marks for them, so
    /// the page draws them with no second file to fetch.
    func place(_ dots: String, in path: String) throws {
        let url = repository.appendingPathComponent(path)
        guard let page = try? String(contentsOf: url, encoding: .utf8) else { throw Problem("\(path): not there") }
        guard let begin = page.range(of: Self.dotsBegin),
              let end = page.range(of: Self.dotsEnd, range: begin.upperBound..<page.endIndex) else {
            throw Problem("\(path): no place marked for the dots")
        }
        try put(Data(page.replacingCharacters(in: begin.upperBound..<end.lowerBound, with: "\n" + dots + "\n").utf8), path)
    }
}

do {
    let desk = Desk()
    let put = desk.put
    let tokens = try desk.read(Tokens.self, "tokens.json")
    let dots = try desk.read(Dots.self, "dots.json")
    let own = try dots.dot(dots.dotto.dot)
    let dev = try dots.dot(dots.dev.dot)
    let share = dots.size

    // The phone: light, dark, and the dot alone for the phone to tint.
    let phone = "App/iOS/Sources/Assets.xcassets/AppIcon.appiconset/"
    try put(png(phoneIcon(own, colour: tokens.colour(dots.dotto.colour, "light"), sheet: tokens.colour("icon-sheet", "light"), share: share)), phone + "icon-light.png")
    try put(png(phoneIcon(own, colour: tokens.colour(dots.dotto.colour, "dark"), sheet: tokens.colour("icon-sheet", "dark"), share: share)), phone + "icon-dark.png")
    try put(png(phoneIcon(own, colour: CGColor(gray: 1, alpha: 1), sheet: nil, share: share)), phone + "icon-tinted.png")

    // The Mac: the home, and dotto dev in its own colour, in the Dock as in the menu bar.
    let macs = [
        ("App/Mac/Assets.xcassets/AppIcon.appiconset/", own, dots.dotto.colour),
        ("App/Mac/Assets.xcassets/AppIconDev.appiconset/", dev, dots.dev.colour),
    ]
    for (folder, dot, colour) in macs {
        var images: [String] = []
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = "icon-\(points)\(scale == 2 ? "@2x" : "").png"
                let image = macIcon(dot, colour: try tokens.colour(colour, "light"), sheet: try tokens.colour("icon-sheet", "light"), share: share, pixels: points * scale)
                try put(png(image), folder + name)
                images.append("    { \"filename\" : \"\(name)\", \"idiom\" : \"mac\", \"scale\" : \"\(scale)x\", \"size\" : \"\(points)x\(points)\" }")
            }
        }
        let contents = "{\n  \"images\" : [\n" + images.joined(separator: ",\n") + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
        try put(Data(contents.utf8), folder + "Contents.json")
    }

    // The dot as files: Dotto's own, alone and on its sheet, and each dot there is.
    let persimmon = try tokens.hex(dots.dotto.colour, "light")
    try put(svg(own, fill: persimmon, size: 80), "design/assets/dot.svg")
    try put(pdf(own, hex: persimmon, size: 80), "design/assets/dot.pdf")
    try put(svg(own, fill: persimmon, size: 100 * share, sheet: try tokens.hex("icon-sheet", "light")), "design/assets/icon.svg")
    try put(svg(own, fill: try tokens.hex(dots.dotto.colour, "dark"), size: 100 * share, sheet: try tokens.hex("icon-sheet", "dark")), "design/assets/icon-dark.svg")
    for number in 1...dots.dots.count {
        try put(svg(try dots.dot(number), fill: "currentColor", size: 80), String(format: "design/assets/dots/%02d.svg", number))
    }

    // The same dots where the apps and the site draw their own: Core, and the site's folder.
    try put(swift(dots), "Core/Sources/Core/Dots.swift")
    try desk.place(css(dots, all: true), in: "site/index.html")
    try desk.place(css(dots, all: false), in: "site/privacy/index.html")
    try put(svg(own, fill: persimmon, size: 100 * share, sheet: try tokens.hex("icon-sheet", "light")), "site/icon.svg")

    for path in desk.changed { print("wrote \(path)") }
    print("\(desk.changed.count) written, \(desk.same) already the same")
} catch {
    FileHandle.standardError.write(Data("dot: \(error)\n".utf8))
    exit(1)
}
