#if canImport(SwiftUI)
import SwiftUI

/// A dot as something a page can fill. It stands in the middle of the room it is given and
/// stays inside it.
public struct DotShape: Shape {
    public var dot: Dot

    public init(_ dot: Dot) {
        self.dot = dot
    }

    public func path(in rect: CGRect) -> Path {
        // A dot at its widest and most turned reaches a tenth past its size.
        let size = min(rect.width, rect.height) / 1.1
        let outline = dot.outline(size: size, centre: Dot.Point(x: rect.midX, y: rect.midY))
        func point(_ point: Dot.Point) -> CGPoint { CGPoint(x: point.x, y: point.y) }
        var path = Path()
        path.move(to: point(outline.start))
        for curve in outline.curves {
            path.addCurve(to: point(curve.end), control1: point(curve.control1), control2: point(curve.control2))
        }
        path.closeSubpath()
        return path
    }
}
#endif
