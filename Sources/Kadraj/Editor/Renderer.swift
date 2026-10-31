import AppKit

/// Draws a document into a CGContext whose user space is image pixels with a top-left origin.
/// Used both on screen (`CanvasView`) and for export (`EditorDocument.render`), so what you see is what you get.
/// Text drawing needs `NSGraphicsContext.current` to wrap the same context, flipped.
enum Renderer {
    static func drawDocument(image: CGImage, annotations: [Annotation], hiding hiddenID: UUID? = nil,
                             in ctx: CGContext, cache: PixelateCache) {
        drawUpright(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), ctx: ctx)
        for annotation in annotations where annotation.id != hiddenID {
            draw(annotation, base: image, in: ctx, cache: cache)
        }
    }

    static func draw(_ a: Annotation, base: CGImage, in ctx: CGContext, cache: PixelateCache) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let color = a.color.cgColor

        switch a.shape {
        case let .pixelate(rect):
            let area = rect.integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
            guard !area.isNull, let image = cache.image(for: a.id, rect: area, base: base, block: max(6, a.lineWidth * 3))
            else { return }
            ctx.interpolationQuality = .none
            drawUpright(image, in: area, ctx: ctx)

        case let .arrow(from, to):
            applyShadow(ctx, a)
            ctx.setFillColor(color)
            ctx.addPath(arrowPath(from: from, to: to, width: a.lineWidth))
            ctx.fillPath()

        case let .rectangle(r):
            applyShadow(ctx, a)
            ctx.setStrokeColor(color)
            ctx.setLineWidth(a.lineWidth)
            ctx.addPath(roundedPath(r, radius: a.lineWidth))
            ctx.strokePath()

        case let .oval(r):
            applyShadow(ctx, a)
            ctx.setStrokeColor(color)
            ctx.setLineWidth(a.lineWidth)
            ctx.strokeEllipse(in: r)

        case let .text(origin, string):
            let bubble = textBubbleRect(origin: origin, string: string, fontSize: a.fontSize)
            applyShadow(ctx, a)
            ctx.setFillColor(color)
            ctx.addPath(roundedPath(bubble, radius: a.fontSize * 0.3))
            ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            let pad = textPadding(a.fontSize)
            NSAttributedString(string: string, attributes: textAttributes(a.fontSize, color: a.color.contrastingTextColor))
                .draw(at: CGPoint(x: bubble.minX + pad.width, y: bubble.minY + pad.height))

        case let .step(center, number):
            let r = stepRadius(a.fontSize)
            let circle = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
            applyShadow(ctx, a)
            ctx.setFillColor(color)
            ctx.fillEllipse(in: circle)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(r * 0.12)
            ctx.strokeEllipse(in: circle.insetBy(dx: r * 0.06, dy: r * 0.06))
            let label = NSAttributedString(string: "\(number)", attributes: [
                .font: NSFont.systemFont(ofSize: r * 1.05, weight: .bold),
                .foregroundColor: a.color.contrastingTextColor,
            ])
            let size = label.size()
            label.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
        }
    }

    /// Draws a CGImage right side up in a flipped (top-left origin) context.
    static func drawUpright(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    // MARK: - Shapes

    /// A tapered arrow with a notched head, as one filled outline.
    static func arrowPath(from a: CGPoint, to b: CGPoint, width w: CGFloat) -> CGPath {
        let length = a.distance(to: b)
        let headLength = min(length, w * 3.5 + 8)
        let headWidth = headLength * 0.85
        let half = w / 2
        let points = [
            CGPoint(x: 0, y: -half * 0.5),
            CGPoint(x: length - headLength * 0.8, y: -half),
            CGPoint(x: length - headLength, y: -headWidth / 2),
            CGPoint(x: length, y: 0),
            CGPoint(x: length - headLength, y: headWidth / 2),
            CGPoint(x: length - headLength * 0.8, y: half),
            CGPoint(x: 0, y: half * 0.5),
        ]
        let transform = CGAffineTransform(translationX: a.x, y: a.y).rotated(by: atan2(b.y - a.y, b.x - a.x))
        let path = CGMutablePath()
        path.addLines(between: points, transform: transform)
        path.closeSubpath()
        return path
    }

    private static func roundedPath(_ r: CGRect, radius: CGFloat) -> CGPath {
        let radius = max(0, min(radius, r.width / 2, r.height / 2))
        return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private static func applyShadow(_ ctx: CGContext, _ a: Annotation) {
        ctx.setShadow(offset: .zero, blur: max(2, a.lineWidth), color: NSColor.black.withAlphaComponent(0.35).cgColor)
    }

    // MARK: - Text and steps

    static func textAttributes(_ fontSize: CGFloat, color: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: color]
    }

    static func textPadding(_ fontSize: CGFloat) -> CGSize {
        CGSize(width: fontSize * 0.4, height: fontSize * 0.2)
    }

    static func textBubbleRect(origin: CGPoint, string: String, fontSize: CGFloat) -> CGRect {
        let size = NSAttributedString(string: string.isEmpty ? " " : string,
                                      attributes: textAttributes(fontSize, color: .white)).size()
        let pad = textPadding(fontSize)
        return CGRect(origin: origin, size: CGSize(width: ceil(size.width) + 2 * pad.width,
                                                   height: ceil(size.height) + 2 * pad.height))
    }

    static func stepRadius(_ fontSize: CGFloat) -> CGFloat { fontSize * 0.8 }

    // MARK: - Pixelation

    /// Averages `rect` of `base` into blocks of `block` pixels; draw the result scaled up without interpolation.
    static func pixelated(_ base: CGImage, rect: CGRect, block: CGFloat) -> CGImage? {
        guard rect.width >= 1, rect.height >= 1, let crop = base.cropping(to: rect),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = max(1, Int((rect.width / block).rounded(.up)))
        let height = max(1, Int((rect.height / block).rounded(.up)))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}

/// Keeps pixelated tiles around so dragging and zooming don't recompute them every frame.
final class PixelateCache {
    private var entries: [UUID: (key: String, image: CGImage)] = [:]

    func image(for id: UUID, rect: CGRect, base: CGImage, block: CGFloat) -> CGImage? {
        let key = "\(rect)|\(ObjectIdentifier(base).hashValue)|\(block)"
        if let entry = entries[id], entry.key == key { return entry.image }
        guard let image = Renderer.pixelated(base, rect: rect, block: block) else { return nil }
        entries[id] = (key, image)
        return image
    }
}
