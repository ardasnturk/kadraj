import AppKit
import Carbon.HIToolbox

/// A screenshot pinned above all windows. Drag to move, scroll to resize, ⌥-scroll to fade,
/// double-click or Esc to close, right-click for more.
final class PinPanel: NSPanel {
    let capture: Capture
    weak var handler: CaptureHandling?
    var onClose: ((PinPanel) -> Void)?

    init(capture: Capture, handler: CaptureHandling?) {
        self.capture = capture
        self.handler = handler
        super.init(contentRect: Self.initialFrame(for: capture), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = PinView(panel: self)
    }

    override var canBecomeKey: Bool { true }

    override func close() {
        super.close()
        onClose?(self)
    }

    /// Scales the pin around its center, keeping the aspect ratio.
    func resize(by factor: CGFloat) {
        let aspect = capture.pointSize.width / max(capture.pointSize.height, 1)
        let width = min(max(frame.width * factor, 48), 8000)
        setSize(CGSize(width: width, height: width / aspect))
    }

    func resetSize() { setSize(capture.pointSize) }

    private func setSize(_ size: CGSize) {
        setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                        width: size.width, height: size.height), display: true)
    }

    /// Exactly where it was captured when known, otherwise centered under the mouse.
    private static func initialFrame(for capture: Capture) -> NSRect {
        if let rect = capture.screenRect { return rect }
        guard let visible = NSScreen.current?.visibleFrame else { return NSRect(origin: .zero, size: capture.pointSize) }
        var size = capture.pointSize
        let fit = min(1, visible.width * 0.7 / size.width, visible.height * 0.7 / size.height)
        size = CGSize(width: size.width * fit, height: size.height * fit)
        let mouse = NSEvent.mouseLocation
        let x = min(max(mouse.x - size.width / 2, visible.minX), visible.maxX - size.width)
        let y = min(max(mouse.y - size.height / 2, visible.minY), visible.maxY - size.height)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

private final class PinView: NSView {
    private unowned let panel: PinPanel
    private let image: NSImage
    private let closeButton: NSButton

    init(panel: PinPanel) {
        self.panel = panel
        image = panel.capture.nsImage
        closeButton = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close") ?? NSImage(),
                               target: nil, action: nil)
        super.init(frame: .zero)
        closeButton.isBordered = false
        closeButton.symbolConfiguration = .init(pointSize: 18, weight: .regular)
            .applying(.init(paletteColors: [.white, NSColor.black.withAlphaComponent(0.6)]))
        closeButton.target = self
        closeButton.action = #selector(closePin)
        closeButton.isHidden = true
        closeButton.toolTip = "Close (Esc)"
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        closeButton.frame = NSRect(x: 4, y: bounds.maxY - 26, width: 22, height: 22)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { closeButton.isHidden = false }
    override func mouseExited(with event: NSEvent) { closeButton.isHidden = true }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds)
        NSColor.black.withAlphaComponent(0.2).setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        if event.clickCount == 2 {
            panel.close()
        } else {
            panel.performDrag(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        if event.modifierFlags.contains(.option) {
            panel.alphaValue = min(max(panel.alphaValue + delta * 0.005, 0.15), 1)
        } else {
            panel.resize(by: exp(delta * 0.01))
        }
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            panel.close()
        } else if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
            copyImage()
        } else {
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        add("Copy", #selector(copyImage))
        add("Save", #selector(saveImage))
        add("Open in Editor", #selector(openEditor))
        add("Copy Text (OCR)", #selector(recognizeText))
        menu.addItem(.separator())
        let opacity = NSMenu()
        for percent in [100, 75, 50, 25] {
            let item = NSMenuItem(title: "\(percent)%", action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.tag = percent
            item.target = self
            item.state = Int((panel.alphaValue * 100).rounded()) == percent ? .on : .off
            opacity.addItem(item)
        }
        let opacityItem = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacity
        menu.addItem(opacityItem)
        add("Actual Size", #selector(resetSize))
        menu.addItem(.separator())
        add("Close", #selector(closePin))
        return menu
    }

    @objc private func copyImage() {
        if ImageExport.copyToPasteboard(panel.capture.image, pointScale: panel.capture.pointScale) {
            Toast.show("Copied to clipboard")
        }
    }

    @objc private func saveImage() {
        do {
            let url = try ImageExport.quickSave(panel.capture.image, pointScale: panel.capture.pointScale)
            Toast.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)", symbol: "square.and.arrow.down")
        } catch {
            Toast.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
        }
    }

    @objc private func openEditor() { panel.handler?.edit(panel.capture) }
    @objc private func recognizeText() { panel.handler?.recognizeText(in: panel.capture) }
    @objc private func setOpacity(_ sender: NSMenuItem) { panel.alphaValue = CGFloat(sender.tag) / 100 }
    @objc private func resetSize() { panel.resetSize() }
    @objc private func closePin() { panel.close() }
}
