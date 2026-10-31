import CoreGraphics

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }

    func distance(to p: CGPoint) -> CGFloat { hypot(x - p.x, y - p.y) }
    var rounded: CGPoint { CGPoint(x: x.rounded(), y: y.rounded()) }
}

extension CGRect {
    /// The rectangle spanned by two opposite corners, in any order.
    init(corner a: CGPoint, _ b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
    let ab = b - a
    let lengthSquared = ab.x * ab.x + ab.y * ab.y
    guard lengthSquared > 0 else { return p.distance(to: a) }
    let t = max(0, min(1, ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lengthSquared))
    return p.distance(to: CGPoint(x: a.x + t * ab.x, y: a.y + t * ab.y))
}

/// Snaps the line from `start` to `end` to the nearest multiple of 45°.
func constrainToAngle(from start: CGPoint, to end: CGPoint) -> CGPoint {
    let d = end - start
    let step = CGFloat.pi / 4
    let angle = (atan2(d.y, d.x) / step).rounded() * step
    let length = hypot(d.x, d.y)
    return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
}

/// Moves `end` so that `start`…`end` spans a square.
func constrainToSquare(from start: CGPoint, to end: CGPoint) -> CGPoint {
    let d = end - start
    let side = max(abs(d.x), abs(d.y))
    return CGPoint(x: start.x + (d.x < 0 ? -side : side), y: start.y + (d.y < 0 ? -side : side))
}
