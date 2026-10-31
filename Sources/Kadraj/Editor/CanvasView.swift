import AppKit
import Carbon.HIToolbox

/// Displays the document with free zoom and pan, and turns mouse and keyboard input into edits.
/// The select tool doubles as the crop tool: drag on empty space to make a pixel-snapped selection.
final class CanvasView: NSView, NSTextFieldDelegate {
    let document: EditorDocument
    var onChange: (() -> Void)?
    var onClose: (() -> Void)?

    var tool: Tool = .select {
        didSet {
            guard tool != oldValue else { return }
            commitText()
            if tool != .select {
                selectedID = nil
                cropRect = nil
            }
            window?.invalidateCursorRects(for: self)
            changed()
        }
    }
    private(set) var color: NSColor = .systemRed
    private(set) var strokeSize: StrokeSize = .medium
    /// Selection in image pixels, always on whole pixels.
    private(set) var cropRect: CGRect?
    private(set) var selectedID: UUID?

    private enum Drag {
        case newCrop(start: CGPoint)
        case resizeCrop(edges: Edges, original: CGRect, start: CGPoint)
        case moveCrop(original: CGRect, start: CGPoint)
        case moveAnnotation(original: Annotation, start: CGPoint, checkpointed: Bool)
        case drawing(start: CGPoint)
        case pan(start: CGPoint, originalOffset: CGPoint)
    }

    private struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1 << 0)
        static let right = Edges(rawValue: 1 << 1)
        static let top = Edges(rawValue: 1 << 2)
        static let bottom = Edges(rawValue: 1 << 3)
    }

    private var drag: Drag?
    private var draft: Annotation?
    /// View points per image pixel.
    private var zoom: CGFloat = 1
    /// Where the image's top-left corner sits in view coordinates.
    private var offset: CGPoint = .zero
    private var fitsWindow = true
    private var isSpaceDown = false
    private let pixelCache = PixelateCache()

    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero
    private var textColor: NSColor = .systemRed
    private var textFontSize: CGFloat = 20
    private var editingTextID: UUID?

    init(document: EditorDocument) {
        self.document = document
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Zoom relative to the image's actual size on screen.
    var zoomPercent: Int { Int((zoom * document.pointScale * 100).rounded()) }

    private var imageBounds: CGRect { CGRect(origin: .zero, size: document.size) }
    private var lineWidth: CGFloat { strokeSize.lineWidth * document.pointScale }
    private var fontSize: CGFloat { strokeSize.fontSize * document.pointScale }

    // MARK: - Public actions

    func setColor(_ color: NSColor) {
        self.color = color
        updateSelected { $0.color = color }
    }

    func setStrokeSize(_ size: StrokeSize) {
        strokeSize = size
        let lineWidth = lineWidth, fontSize = fontSize
        updateSelected {
            $0.lineWidth = lineWidth
            $0.fontSize = fontSize
        }
    }

    func undo() {
        commitText()
        let oldSize = document.size
        document.undo()
        afterHistoryChange(oldSize: oldSize)
    }

    func redo() {
        commitText()
        let oldSize = document.size
        document.redo()
        afterHistoryChange(oldSize: oldSize)
    }

    func deleteSelection() {
        guard let i = document.index(of: selectedID) else { return }
        document.checkpoint()
        document.annotations.remove(at: i)
        selectedID = nil
        changed()
    }

    func applyCrop() {
        guard let rect = cropRect else { return }
        commitText()
        document.crop(to: rect)
        cropRect = nil
        zoomToFit()
    }

    /// The flattened result; just the selection when there is one.
    func exportImage() -> CGImage? {
        commitText()
        return document.render(region: cropRect)
    }

    // MARK: - Zoom

    func zoomToFit() {
        let available = bounds.insetBy(dx: 24, dy: 24)
        guard available.width > 0, available.height > 0 else { return }
        let size = document.size
        zoom = min(available.width / size.width, available.height / size.height, 1 / document.pointScale)
        offset = CGPoint(x: ((bounds.width - size.width * zoom) / 2).rounded(),
                         y: ((bounds.height - size.height * zoom) / 2).rounded())
        fitsWindow = true
        layoutTextField()
        changed()
    }

    func zoomToActualSize() { setZoom(1 / document.pointScale, around: CGPoint(x: bounds.midX, y: bounds.midY)) }
    func zoomIn() { setZoom(zoom * 1.5, around: CGPoint(x: bounds.midX, y: bounds.midY)) }
    func zoomOut() { setZoom(zoom / 1.5, around: CGPoint(x: bounds.midX, y: bounds.midY)) }

    private func setZoom(_ newZoom: CGFloat, around viewPoint: CGPoint) {
        let anchor = toImage(viewPoint)
        zoom = min(max(newZoom, 0.02), 64)
        offset = CGPoint(x: viewPoint.x - anchor.x * zoom, y: viewPoint.y - anchor.y * zoom)
        fitsWindow = false
        layoutTextField()
        changed()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if fitsWindow { zoomToFit() }
    }

    // MARK: - Coordinates

    private func toView(_ p: CGPoint) -> CGPoint { CGPoint(x: offset.x + p.x * zoom, y: offset.y + p.y * zoom) }
    private func toImage(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - offset.x) / zoom, y: (p.y - offset.y) / zoom) }

    private func toView(_ r: CGRect) -> CGRect {
        CGRect(origin: toView(r.origin), size: CGSize(width: r.width * zoom, height: r.height * zoom))
    }

    private func clampToImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), document.size.width), y: min(max(p.y, 0), document.size.height))
    }

    private func location(of event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()

        let imageRect = toView(imageBounds)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 12, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(imageRect)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.translateBy(x: offset.x, y: offset.y)
        ctx.scaleBy(x: zoom, y: zoom)
        ctx.clip(to: imageBounds)
        // Show crisp pixels when zoomed in, like a pixel editor.
        ctx.interpolationQuality = zoom * document.pointScale >= 2 ? .none : .high
        var annotations = document.annotations
        if let draft { annotations.append(draft) }
        Renderer.drawDocument(image: document.image, annotations: annotations, hiding: editingTextID,
                              in: ctx, cache: pixelCache)
        ctx.restoreGState()

        if let annotation = document.index(of: selectedID).map({ document.annotations[$0] }) {
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(rect: toView(annotation.bounds).insetBy(dx: -4, dy: -4))
            outline.setLineDash([4, 3], count: 2, phase: 0)
            outline.lineWidth = 1.5
            outline.stroke()
        }

        if let cropRect { drawCropOverlay(toView(cropRect), imageRect: imageRect, pixels: cropRect) }
    }

    private func drawCropOverlay(_ rect: CGRect, imageRect: CGRect, pixels: CGRect) {
        let dim = NSBezierPath(rect: imageRect)
        dim.append(NSBezierPath(rect: rect))
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill()
        dim.fill()

        NSColor.white.setStroke()
        NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5)).stroke()

        for point in [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
        ] {
            let handle = NSBezierPath(rect: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
            NSColor.white.setFill()
            handle.fill()
            NSColor.black.withAlphaComponent(0.6).setStroke()
            handle.stroke()
        }

        let label = NSAttributedString(string: "\(Int(pixels.width)) × \(Int(pixels.height))", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
        let size = label.size()
        var pill = CGRect(x: rect.minX, y: rect.maxY + 6, width: ceil(size.width) + 12, height: ceil(size.height) + 4)
        if pill.maxY > bounds.maxY { pill.origin.y = rect.maxY - pill.height - 6 }
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        label.draw(at: CGPoint(x: pill.minX + 6, y: pill.minY + 2))
    }

    override func resetCursorRects() {
        let cursor: NSCursor = switch tool {
        case .select: .arrow
        case .text: .iBeam
        default: .crosshair
        }
        addCursorRect(bounds, cursor: isSpaceDown ? .openHand : cursor)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        commitText()
        window?.makeFirstResponder(self)
        let viewPoint = location(of: event)
        let p = toImage(viewPoint)

        if isSpaceDown {
            drag = .pan(start: viewPoint, originalOffset: offset)
            return
        }

        switch tool {
        case .select:
            if let cropRect {
                let edges = edges(of: toView(cropRect), near: viewPoint)
                if !edges.isEmpty {
                    drag = .resizeCrop(edges: edges, original: cropRect, start: p)
                    return
                }
            }
            if let hit = annotation(at: p) {
                selectedID = hit.id
                if event.clickCount == 2, case .text = hit.shape {
                    beginTextEditing(at: p, editing: hit)
                } else {
                    drag = .moveAnnotation(original: hit, start: p, checkpointed: false)
                }
            } else {
                selectedID = nil
                if let cropRect, cropRect.contains(p) {
                    drag = .moveCrop(original: cropRect, start: p)
                } else {
                    cropRect = nil
                    drag = .newCrop(start: clampToImage(p).rounded)
                }
            }

        case .text:
            if let hit = annotation(at: p), case .text = hit.shape {
                beginTextEditing(at: p, editing: hit)
            } else {
                beginTextEditing(at: clampToImage(p))
            }

        case .step:
            let number = (document.annotations.compactMap { annotation -> Int? in
                if case let .step(_, n) = annotation.shape { return n }
                return nil
            }.max() ?? 0) + 1
            let step = Annotation(shape: .step(center: clampToImage(p), number: number), color: color,
                                  lineWidth: lineWidth, fontSize: fontSize)
            document.checkpoint()
            document.annotations.append(step)
            selectedID = step.id

        case .arrow, .rectangle, .oval, .pixelate:
            drag = .drawing(start: p)
            draft = makeDraft(from: p, to: p)
        }
        changed()
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPoint = location(of: event)
        let p = toImage(viewPoint)
        let shift = event.modifierFlags.contains(.shift)

        switch drag {
        case let .newCrop(start):
            var end = clampToImage(p).rounded
            if shift { end = clampToImage(constrainToSquare(from: start, to: end)) }
            let rect = CGRect(corner: start, end)
            cropRect = rect.width >= 1 && rect.height >= 1 ? rect : nil

        case let .resizeCrop(edges, original, start):
            let d = (p - start).rounded
            var minX = original.minX, maxX = original.maxX, minY = original.minY, maxY = original.maxY
            if edges.contains(.left) { minX += d.x }
            if edges.contains(.right) { maxX += d.x }
            if edges.contains(.top) { minY += d.y }
            if edges.contains(.bottom) { maxY += d.y }
            let rect = CGRect(corner: CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: maxY)).intersection(imageBounds)
            if !rect.isNull, rect.width >= 1, rect.height >= 1 { cropRect = rect }

        case let .moveCrop(original, start):
            let d = (p - start).rounded
            var rect = original.offsetBy(dx: d.x, dy: d.y)
            rect.origin.x = min(max(rect.minX, 0), document.size.width - rect.width)
            rect.origin.y = min(max(rect.minY, 0), document.size.height - rect.height)
            cropRect = rect

        case let .moveAnnotation(original, start, checkpointed):
            guard let i = document.index(of: original.id) else { break }
            if !checkpointed {
                document.checkpoint()
                drag = .moveAnnotation(original: original, start: start, checkpointed: true)
            }
            document.annotations[i] = original.translated(by: p - start)

        case let .drawing(start):
            var end = p
            if shift {
                end = tool == .arrow ? constrainToAngle(from: start, to: p) : constrainToSquare(from: start, to: p)
            }
            draft = makeDraft(from: start, to: end)

        case let .pan(start, originalOffset):
            offset = originalOffset + (viewPoint - start)
            fitsWindow = false

        case nil:
            return
        }
        changed()
    }

    override func mouseUp(with event: NSEvent) {
        if case .drawing = drag, let draft, draft.isMeaningful {
            document.checkpoint()
            document.annotations.append(draft)
            selectedID = draft.id
        }
        draft = nil
        drag = nil
        changed()
    }

    override func rightMouseDown(with event: NSEvent) {
        commitText()
        drag = .pan(start: location(of: event), originalOffset: offset)
    }

    override func rightMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func rightMouseUp(with event: NSEvent) { drag = nil }

    override func scrollWheel(with event: NSEvent) {
        commitText()
        let point = location(of: event)
        if !event.hasPreciseScrollingDeltas {
            // Mouse wheel: zoom.
            setZoom(zoom * exp(event.scrollingDeltaY * 0.08), around: point)
        } else if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            setZoom(zoom * exp(event.scrollingDeltaY * 0.01), around: point)
        } else {
            // Trackpad: pan.
            offset.x += event.scrollingDeltaX
            offset.y += event.scrollingDeltaY
            fitsWindow = false
            changed()
        }
    }

    override func magnify(with event: NSEvent) {
        setZoom(zoom * (1 + event.magnification), around: location(of: event))
    }

    override func smartMagnify(with event: NSEvent) {
        if fitsWindow {
            setZoom(1 / document.pointScale, around: location(of: event))
        } else {
            zoomToFit()
        }
    }

    private func annotation(at p: CGPoint) -> Annotation? {
        let tolerance = 4 / zoom
        return document.annotations.last { $0.hitTest(p, tolerance: tolerance) }
    }

    private func edges(of rect: CGRect, near point: CGPoint) -> Edges {
        let t: CGFloat = 6
        guard rect.insetBy(dx: -t, dy: -t).contains(point) else { return [] }
        var edges: Edges = []
        if abs(point.x - rect.minX) <= t { edges.insert(.left) } else if abs(point.x - rect.maxX) <= t { edges.insert(.right) }
        if abs(point.y - rect.minY) <= t { edges.insert(.top) } else if abs(point.y - rect.maxY) <= t { edges.insert(.bottom) }
        return edges
    }

    private func makeDraft(from a: CGPoint, to b: CGPoint) -> Annotation? {
        let shape: Annotation.Shape
        switch tool {
        case .arrow: shape = .arrow(from: a, to: b)
        case .rectangle: shape = .rectangle(CGRect(corner: a, b))
        case .oval: shape = .oval(CGRect(corner: a, b))
        case .pixelate: shape = .pixelate(CGRect(corner: a, b))
        default: return nil
        }
        if var draft {
            draft.shape = shape
            return draft
        }
        return Annotation(shape: shape, color: color, lineWidth: lineWidth, fontSize: fontSize)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let step: CGFloat = modifiers.contains(.shift) ? 10 : 1
        let resize = modifiers.contains(.command)

        switch Int(event.keyCode) {
        case kVK_Escape:
            if cropRect != nil {
                cropRect = nil
            } else if selectedID != nil {
                selectedID = nil
            } else {
                onClose?()
                return
            }
            changed()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            applyCrop()
        case kVK_Delete, kVK_ForwardDelete:
            deleteSelection()
        case kVK_LeftArrow: nudge(dx: -step, dy: 0, resize: resize)
        case kVK_RightArrow: nudge(dx: step, dy: 0, resize: resize)
        case kVK_UpArrow: nudge(dx: 0, dy: -step, resize: resize)
        case kVK_DownArrow: nudge(dx: 0, dy: step, resize: resize)
        case kVK_Space:
            if !event.isARepeat {
                isSpaceDown = true
                window?.invalidateCursorRects(for: self)
            }
        default:
            guard modifiers.subtracting([.shift, .capsLock]).isEmpty,
                  let key = event.charactersIgnoringModifiers?.lowercased().first else {
                super.keyDown(with: event)
                return
            }
            if key == "b", let cropRect {
                // B with a selection pixelates it right away.
                let blur = Annotation(shape: .pixelate(cropRect), color: color, lineWidth: lineWidth, fontSize: fontSize)
                document.checkpoint()
                document.annotations.append(blur)
                self.cropRect = nil
                changed()
            } else if let match = Tool.allCases.first(where: { $0.shortcut == key }) {
                tool = match
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Space {
            isSpaceDown = false
            window?.invalidateCursorRects(for: self)
        } else {
            super.keyUp(with: event)
        }
    }

    /// Arrow keys move the selection (or resize it with ⌘), or move the selected annotation.
    private func nudge(dx: CGFloat, dy: CGFloat, resize: Bool) {
        if var rect = cropRect {
            if resize {
                rect.size.width = max(1, rect.width + dx)
                rect.size.height = max(1, rect.height + dy)
            } else {
                rect = rect.offsetBy(dx: dx, dy: dy)
            }
            let clamped = rect.intersection(imageBounds)
            if !clamped.isNull, clamped.width >= 1, clamped.height >= 1 { cropRect = clamped }
        } else if let i = document.index(of: selectedID) {
            document.checkpoint()
            document.annotations[i] = document.annotations[i].translated(by: CGPoint(x: dx, y: dy))
        } else {
            return
        }
        changed()
    }

    // MARK: - Text editing

    private func beginTextEditing(at point: CGPoint, editing existing: Annotation? = nil) {
        commitText()
        var string = ""
        if let existing, case let .text(origin, text) = existing.shape {
            string = text
            textOrigin = origin
            textColor = existing.color
            textFontSize = existing.fontSize
            editingTextID = existing.id
        } else {
            textOrigin = point
            textColor = color
            textFontSize = fontSize
            editingTextID = nil
        }

        let field = NSTextField(string: string)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = textColor
        field.textColor = textColor.contrastingTextColor
        field.focusRingType = .none
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self
        textField = field
        addSubview(field)
        layoutTextField()
        window?.makeFirstResponder(field)
        changed()
    }

    private func layoutTextField() {
        guard let field = textField else { return }
        field.font = .systemFont(ofSize: textFontSize * zoom, weight: .semibold)
        let fitting = field.fittingSize
        let origin = toView(textOrigin)
        field.frame = CGRect(x: origin.x, y: origin.y, width: max(fitting.width + 12, 80), height: fitting.height)
    }

    func controlTextDidChange(_ notification: Notification) { layoutTextField() }

    func controlTextDidEndEditing(_ notification: Notification) { commitText() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(cancelOperation(_:)) {
            textField?.stringValue = editingTextID.flatMap { id in
                document.index(of: id).flatMap { i -> String? in
                    if case let .text(_, s) = document.annotations[i].shape { return s }
                    return nil
                }
            } ?? ""
            commitText()
            return true
        }
        return false
    }

    /// Turns the text field into a text annotation. Safe to call when nothing is being edited.
    func commitText() {
        guard let field = textField else { return }
        textField = nil
        let string = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.delegate = nil
        field.removeFromSuperview()

        if let i = document.index(of: editingTextID) {
            if case let .text(origin, old) = document.annotations[i].shape, old != string {
                document.checkpoint()
                if string.isEmpty {
                    document.annotations.remove(at: i)
                } else {
                    document.annotations[i].shape = .text(origin: origin, string: string)
                }
            }
        } else if !string.isEmpty {
            let text = Annotation(shape: .text(origin: textOrigin, string: string), color: textColor,
                                  lineWidth: lineWidth, fontSize: textFontSize)
            document.checkpoint()
            document.annotations.append(text)
            selectedID = text.id
        }
        editingTextID = nil
        window?.makeFirstResponder(self)
        changed()
    }

    // MARK: - Helpers

    private func updateSelected(_ change: (inout Annotation) -> Void) {
        guard let i = document.index(of: selectedID) else { return }
        document.checkpoint()
        change(&document.annotations[i])
        changed()
    }

    private func afterHistoryChange(oldSize: CGSize) {
        if document.index(of: selectedID) == nil { selectedID = nil }
        if document.size != oldSize {
            cropRect = nil
            zoomToFit()
        } else {
            changed()
        }
    }

    private func changed() {
        needsDisplay = true
        onChange?()
    }
}
