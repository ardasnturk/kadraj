import AppKit
import Carbon.HIToolbox

/// Shows the frozen screen on every display and lets the user drag out an area or pick a window.
@MainActor
final class AreaSelectionController {
    enum Purpose { case capture, text }

    /// A selected area, remembered for "Repeat Last Area".
    struct Region {
        let displayID: CGDirectDisplayID
        /// In points, relative to the display's top-left corner.
        let rect: CGRect
        /// In Cocoa global coordinates.
        let screenRect: CGRect
    }

    enum Outcome {
        /// `region` is `nil` when the whole display was taken.
        case area(CGImage, pointScale: CGFloat, region: Region?)
        /// `fallback` is the window cut out of the frozen screen, used if capturing it on its own fails.
        case window(CapturableWindow, fallback: CGImage?, pointScale: CGFloat)
        case cancelled
    }

    let windows: [CapturableWindow]
    let purpose: Purpose
    var windowMode: Bool {
        didSet { views.forEach { $0.windowModeChanged() } }
    }

    private let shots: [DisplayShot]
    private let completion: (Outcome) -> Void
    private var overlays: [NSWindow] = []
    private var views: [SelectionView] = []

    init(shots: [DisplayShot], windows: [CapturableWindow], windowMode: Bool, purpose: Purpose = .capture,
         completion: @escaping (Outcome) -> Void) {
        self.shots = shots
        self.windows = windows
        self.windowMode = windowMode && purpose == .capture
        self.purpose = purpose
        self.completion = completion
    }

    func show() {
        for shot in shots {
            let window = OverlayWindow(
                contentRect: shot.screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.backgroundColor = .black
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let view = SelectionView(shot: shot, controller: self)
            window.contentView = view
            window.setFrame(shot.screen.frame, display: false)
            window.orderFrontRegardless()
            overlays.append(window)
            views.append(view)
        }
        NSApp.activate()
        let mouse = NSEvent.mouseLocation
        let index = shots.firstIndex { $0.screen.frame.contains(mouse) } ?? 0
        overlays[index].makeKeyAndOrderFront(nil)
        overlays[index].makeFirstResponder(views[index])
    }

    func finish(_ outcome: Outcome) {
        guard !overlays.isEmpty else { return }
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        views.removeAll()
        completion(outcome)
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SelectionView: NSView {
    private let shot: DisplayShot
    private unowned let controller: AreaSelectionController
    private let backdrop: NSImage
    /// Windows on this display, in view coordinates, front-most first.
    private let localWindows: [(window: CapturableWindow, rect: CGRect)]
    private var mouse: CGPoint?
    private var dragStart: CGPoint?
    private var selection: CGRect?

    init(shot: DisplayShot, controller: AreaSelectionController) {
        self.shot = shot
        self.controller = controller
        let size = shot.screen.frame.size
        backdrop = NSImage(cgImage: shot.image, size: size)
        let origin = shot.globalFrame.origin
        let bounds = CGRect(origin: .zero, size: size)
        localWindows = controller.windows
            .map { ($0, $0.frame.offsetBy(dx: -origin.x, dy: -origin.y)) }
            .filter { $0.1.intersects(bounds) }
        super.init(frame: bounds)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var pixelScale: CGFloat { CGFloat(shot.image.width) / bounds.width }

    private var hoveredWindow: (window: CapturableWindow, rect: CGRect)? {
        guard controller.windowMode, let mouse else { return nil }
        return localWindows.first { $0.rect.contains(mouse) }
    }

    func windowModeChanged() {
        dragStart = nil
        selection = nil
        needsDisplay = true
    }

    private func crop(_ rect: CGRect) -> CGImage? { shot.crop(rect) }

    // MARK: - Events

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        NSCursor.crosshair.set()
    }

    override func mouseExited(with event: NSEvent) {
        mouse = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        mouse = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mouse = point
        if controller.windowMode {
            if let hovered = hoveredWindow {
                let visible = hovered.rect.intersection(bounds)
                controller.finish(.window(hovered.window, fallback: crop(visible), pointScale: pixelScale))
            }
            return
        }
        dragStart = point
        selection = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        var point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.shift) { point = constrainToSquare(from: start, to: point) }
        mouse = point
        selection = CGRect(corner: start, point).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        guard let rect = selection, rect.width >= 2, rect.height >= 2, let image = crop(rect) else {
            selection = nil
            needsDisplay = true
            return
        }
        let region = AreaSelectionController.Region(displayID: shot.displayID, rect: rect,
                                                    screenRect: shot.screenRect(for: rect))
        controller.finish(.area(image, pointScale: pixelScale, region: region))
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            controller.finish(.cancelled)
        case kVK_Space where controller.purpose == .capture:
            controller.windowMode.toggle()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            controller.finish(.area(shot.image, pointScale: pixelScale, region: nil))
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        backdrop.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let dim = NSColor.black.withAlphaComponent(0.35)

        if let rect = selection {
            dimOutside(rect, color: dim)
            NSColor.white.setStroke()
            NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5)).stroke()
            let size = "\(Int((rect.width * pixelScale).rounded())) × \(Int((rect.height * pixelScale).rounded()))"
            drawPill(size, at: CGPoint(x: (mouse?.x ?? rect.maxX) + 14, y: (mouse?.y ?? rect.maxY) + 14))
        } else if let hovered = hoveredWindow {
            dimOutside(hovered.rect, color: dim)
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            hovered.rect.fill(using: .sourceOver)
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(rect: hovered.rect.insetBy(dx: 1.5, dy: 1.5))
            outline.lineWidth = 3
            outline.stroke()
        } else if controller.windowMode {
            dim.setFill()
            bounds.fill(using: .sourceOver)
        } else if let mouse {
            drawCrosshair(at: mouse)
        }

        if mouse != nil, selection == nil {
            let hint = if controller.purpose == .text {
                "Drag over text to copy it  ·  Esc: cancel"
            } else if controller.windowMode {
                "Click a window  ·  Space: area mode  ·  Esc: cancel"
            } else {
                "Drag to select  ·  Space: window mode  ·  Return: full screen  ·  Esc: cancel"
            }
            drawPill(hint, centeredAt: CGPoint(x: bounds.midX, y: bounds.maxY - 60))
        }
    }

    private func dimOutside(_ rect: CGRect, color: NSColor) {
        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(rect: rect))
        path.windingRule = .evenOdd
        color.setFill()
        path.fill()
    }

    private func drawCrosshair(at point: CGPoint) {
        let x = point.x.rounded(.down) + 0.5
        let y = point.y.rounded(.down) + 0.5
        for (color, offset) in [(NSColor.black.withAlphaComponent(0.5), 1.0), (NSColor.white.withAlphaComponent(0.9), 0.0)] {
            color.setStroke()
            let path = NSBezierPath()
            path.move(to: CGPoint(x: x + offset, y: bounds.minY))
            path.line(to: CGPoint(x: x + offset, y: bounds.maxY))
            path.move(to: CGPoint(x: bounds.minX, y: y + offset))
            path.line(to: CGPoint(x: bounds.maxX, y: y + offset))
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawPill(_ text: String, at origin: CGPoint) {
        let size = pillSize(text)
        var rect = CGRect(origin: origin, size: size)
        if rect.maxX > bounds.maxX { rect.origin.x = origin.x - size.width - 28 }
        if rect.maxY > bounds.maxY { rect.origin.y = origin.y - size.height - 28 }
        drawPill(text, in: rect)
    }

    private func drawPill(_ text: String, centeredAt center: CGPoint) {
        let size = pillSize(text)
        drawPill(text, in: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                  width: size.width, height: size.height))
    }

    private static let pillAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    private func pillSize(_ text: String) -> CGSize {
        let size = NSAttributedString(string: text, attributes: Self.pillAttributes).size()
        return CGSize(width: ceil(size.width) + 16, height: ceil(size.height) + 8)
    }

    private func drawPill(_ text: String, in rect: CGRect) {
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        NSAttributedString(string: text, attributes: Self.pillAttributes)
            .draw(at: CGPoint(x: rect.minX + 8, y: rect.minY + 4))
    }
}
