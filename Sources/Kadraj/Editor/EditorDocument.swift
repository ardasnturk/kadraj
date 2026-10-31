import AppKit

/// The screenshot being edited: a base image, the annotations on top, and snapshot-based undo.
final class EditorDocument {
    private struct Snapshot {
        let image: CGImage
        let annotations: [Annotation]
    }

    var image: CGImage
    var annotations: [Annotation] = []
    /// Image pixels per screen point (2 on Retina displays).
    let pointScale: CGFloat

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private let undoLimit = 100

    init(image: CGImage, pointScale: CGFloat) {
        self.image = image
        self.pointScale = max(1, pointScale)
    }

    var size: CGSize { CGSize(width: image.width, height: image.height) }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Call before every change that should be undoable.
    func checkpoint() {
        undoStack.append(current)
        if undoStack.count > undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(current)
        apply(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(current)
        apply(snapshot)
    }

    func index(of id: UUID?) -> Int? {
        guard let id else { return nil }
        return annotations.firstIndex { $0.id == id }
    }

    func crop(to rect: CGRect) {
        guard let cropped = image.cropping(to: rect) else { return }
        checkpoint()
        image = cropped
        annotations = annotations.map { $0.translated(by: CGPoint(x: -rect.minX, y: -rect.minY)) }
    }

    /// Flattens the image and annotations, optionally limited to `region` (image pixels).
    func render(region: CGRect? = nil) -> CGImage? {
        let width = image.width, height = image.height
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        Renderer.drawDocument(image: image, annotations: annotations, in: ctx, cache: PixelateCache())
        NSGraphicsContext.restoreGraphicsState()

        guard let flattened = ctx.makeImage() else { return nil }
        if let region, let cropped = flattened.cropping(to: region.integral) { return cropped }
        return flattened
    }

    private var current: Snapshot { Snapshot(image: image, annotations: annotations) }

    private func apply(_ snapshot: Snapshot) {
        image = snapshot.image
        annotations = snapshot.annotations
    }
}
