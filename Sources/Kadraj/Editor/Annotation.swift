import AppKit

enum Tool: Int, CaseIterable {
    case select, arrow, rectangle, oval, text, pixelate, step

    var title: String {
        switch self {
        case .select: "Select & Crop (V)"
        case .arrow: "Arrow (A)"
        case .rectangle: "Rectangle (R)"
        case .oval: "Oval (O)"
        case .text: "Text (T)"
        case .pixelate: "Pixelate (B)"
        case .step: "Step Counter (N)"
        }
    }

    var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .oval: "circle"
        case .text: "textformat"
        case .pixelate: "checkerboard.rectangle"
        case .step: "1.circle"
        }
    }

    var shortcut: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .rectangle: "r"
        case .oval: "o"
        case .text: "t"
        case .pixelate: "b"
        case .step: "n"
        }
    }
}

enum StrokeSize: Int, CaseIterable {
    case small, medium, large

    var title: String { ["S", "M", "L"][rawValue] }
    /// In points; multiplied by the image's point scale.
    var lineWidth: CGFloat { [2, 4, 7][rawValue] }
    var fontSize: CGFloat { [14, 20, 28][rawValue] }
}

/// A vector object drawn over the screenshot. All geometry is in image pixels, top-left origin.
struct Annotation: Identifiable {
    enum Shape {
        case arrow(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case oval(CGRect)
        /// `origin` is the top-left corner of the label bubble.
        case text(origin: CGPoint, string: String)
        case pixelate(CGRect)
        case step(center: CGPoint, number: Int)
    }

    let id = UUID()
    var shape: Shape
    var color: NSColor
    var lineWidth: CGFloat
    var fontSize: CGFloat

    func translated(by d: CGPoint) -> Annotation {
        var copy = self
        switch shape {
        case let .arrow(a, b): copy.shape = .arrow(from: a + d, to: b + d)
        case let .rectangle(r): copy.shape = .rectangle(r.offsetBy(dx: d.x, dy: d.y))
        case let .oval(r): copy.shape = .oval(r.offsetBy(dx: d.x, dy: d.y))
        case let .text(o, s): copy.shape = .text(origin: o + d, string: s)
        case let .pixelate(r): copy.shape = .pixelate(r.offsetBy(dx: d.x, dy: d.y))
        case let .step(c, n): copy.shape = .step(center: c + d, number: n)
        }
        return copy
    }

    var bounds: CGRect {
        switch shape {
        case let .arrow(a, b):
            CGRect(corner: a, b).insetBy(dx: -lineWidth * 2, dy: -lineWidth * 2)
        case let .rectangle(r), let .oval(r):
            r.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        case let .pixelate(r):
            r
        case let .text(o, s):
            Renderer.textBubbleRect(origin: o, string: s, fontSize: fontSize)
        case let .step(c, _):
            CGRect(x: c.x, y: c.y, width: 0, height: 0)
                .insetBy(dx: -Renderer.stepRadius(fontSize), dy: -Renderer.stepRadius(fontSize))
        }
    }

    /// Rectangles and ovals only respond near their outline so that clicks inside them can start a selection.
    func hitTest(_ p: CGPoint, tolerance t: CGFloat) -> Bool {
        switch shape {
        case let .arrow(a, b):
            return distance(from: p, toSegment: a, b) <= lineWidth * 1.5 + t
        case let .rectangle(r), let .oval(r):
            let outer = r.insetBy(dx: -lineWidth - t, dy: -lineWidth - t)
            let inner = r.insetBy(dx: lineWidth + t, dy: lineWidth + t)
            return outer.contains(p) && !(inner.width > 0 && inner.height > 0 && inner.contains(p))
        default:
            return bounds.insetBy(dx: -t, dy: -t).contains(p)
        }
    }

    /// Whether a freshly dragged shape is big enough to keep.
    var isMeaningful: Bool {
        switch shape {
        case let .arrow(a, b): a.distance(to: b) >= 4
        case let .rectangle(r), let .oval(r), let .pixelate(r): r.width >= 3 && r.height >= 3
        case .text, .step: true
        }
    }
}

extension NSColor {
    /// Black or white, whichever reads better on top of this color.
    var contrastingTextColor: NSColor {
        guard let c = usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return luminance > 0.65 ? .black : .white
    }
}
