import Foundation

/// A dot drawn by hand: the mark that stands for someone. It is four arcs that meet at four
/// points, one on each side of a box. Where a point sits along its side is one number, so
/// four numbers, a proportion and a turn are a dot, and no two need be alike. All four at a
/// half and a proportion of one is a circle. Since 16 November 2026.
public struct Dot: Hashable, Codable, Sendable {
    /// Where the arcs meet on the top side, as a share of the width from the left.
    public var top: Double
    /// Where they meet on the right side, as a share of the height from the top.
    public var right: Double
    /// Where they meet on the bottom side, as a share of the width from the left.
    public var bottom: Double
    /// Where they meet on the left side, as a share of the height from the top.
    public var left: Double
    /// Its width over its height.
    public var proportion: Double
    /// How far it is turned, in degrees, clockwise.
    public var turn: Double

    public init(top: Double, right: Double, bottom: Double, left: Double, proportion: Double = 1, turn: Double = 0) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
        self.proportion = proportion
        self.turn = turn
    }

    public struct Point: Hashable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// One arc, as a path takes it: two points that pull the curve, and where it ends.
    public struct Curve: Hashable, Sendable {
        public var control1: Point
        public var control2: Point
        public var end: Point

        public init(control1: Point, control2: Point, end: Point) {
            self.control1 = control1
            self.control2 = control2
            self.end = end
        }
    }

    /// The whole edge: where it starts, and the four curves that come back to it.
    public struct Outline: Hashable, Sendable {
        public var start: Point
        public var curves: [Curve]

        /// The same edge as the `d` of an SVG path, to two places.
        public var svg: String {
            var d = "M\(Self.number(start.x)) \(Self.number(start.y))"
            for curve in curves {
                let values = [curve.control1.x, curve.control1.y, curve.control2.x, curve.control2.y, curve.end.x, curve.end.y]
                d += " C" + values.map(Self.number).joined(separator: " ")
            }
            return d + " Z"
        }

        private static func number(_ value: Double) -> String {
            let rounded = (value * 100).rounded() / 100
            return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        }
    }

    /// The edge of this dot at a size, around a centre, with y growing downward as on a
    /// screen. The size is the side of the square it would fill at a proportion of one: a
    /// wider dot is as much shorter, so dots of one size weigh the same.
    public func outline(size: Double, centre: Point) -> Outline {
        let root = proportion.squareRoot()
        let width = size * root
        let height = size / root
        // How far along a quarter of an ellipse a curve's pull sits.
        let pull = 0.552_284_749_830_793_4
        let minX = -width / 2
        let minY = -height / 2

        let onTop = Point(x: minX + top * width, y: minY)
        let onRight = Point(x: minX + width, y: minY + right * height)
        let onBottom = Point(x: minX + bottom * width, y: minY + height)
        let onLeft = Point(x: minX, y: minY + left * height)

        let curves = [
            Curve(
                control1: Point(x: onLeft.x, y: onLeft.y - pull * left * height),
                control2: Point(x: onTop.x - pull * top * width, y: onTop.y),
                end: onTop
            ),
            Curve(
                control1: Point(x: onTop.x + pull * (1 - top) * width, y: onTop.y),
                control2: Point(x: onRight.x, y: onRight.y - pull * right * height),
                end: onRight
            ),
            Curve(
                control1: Point(x: onRight.x, y: onRight.y + pull * (1 - right) * height),
                control2: Point(x: onBottom.x + pull * (1 - bottom) * width, y: onBottom.y),
                end: onBottom
            ),
            Curve(
                control1: Point(x: onBottom.x - pull * bottom * width, y: onBottom.y),
                control2: Point(x: onLeft.x, y: onLeft.y + pull * (1 - left) * height),
                end: onLeft
            ),
        ]

        let angle = turn * .pi / 180
        let sine = sin(angle)
        let cosine = cos(angle)
        func placed(_ point: Point) -> Point {
            Point(x: centre.x + point.x * cosine - point.y * sine, y: centre.y + point.x * sine + point.y * cosine)
        }
        return Outline(
            start: placed(onLeft),
            curves: curves.map { Curve(control1: placed($0.control1), control2: placed($0.control2), end: placed($0.end)) }
        )
    }
}

extension Author {
    /// A dot that follows from the id, as the hue does, so an originator has a mark of their
    /// own shape everywhere, on every device, from the first thing they do, without anyone
    /// choosing. The notebook's own originator wears Dotto's dot.
    public var dot: Dot {
        if self == .dotto { return .dotto }
        var state: UInt64 = 14_695_981_039_346_656_037
        for byte in rawValue.utf8 {
            state ^= UInt64(byte)
            state = state &* 1_099_511_628_211
        }
        // One more number out of the id each time it is asked, between two bounds.
        func next(_ low: Double, _ high: Double) -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let share = Double(state >> 11) / Double(UInt64(1) << 53)
            return low + share * (high - low)
        }
        return Dot(
            top: next(0.36, 0.64), right: next(0.36, 0.64), bottom: next(0.36, 0.64), left: next(0.36, 0.64),
            proportion: next(0.86, 1.16), turn: next(-24, 24)
        )
    }
}
