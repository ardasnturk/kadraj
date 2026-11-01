import AppKit

/// Stacks floating previews in the bottom-left corner of the screen and routes their buttons.
@MainActor
final class PreviewManager {
    weak var handler: CaptureHandling?
    private var panels: [PreviewPanel] = []
    private let maxVisible = 3

    func show(_ capture: Capture) {
        let panel = PreviewPanel(capture: capture, manager: self)
        panels.insert(panel, at: 0)
        while panels.count > maxVisible, let oldest = panels.last { dismiss(oldest) }
        layout(entering: panel)
        panel.present()
    }

    func dismiss(_ panel: PreviewPanel) {
        guard let index = panels.firstIndex(where: { $0 === panel }) else { return }
        panels.remove(at: index)
        panel.fadeOut()
        layout(entering: nil)
    }

    /// Newest at the bottom, older ones pushed up.
    private func layout(entering newPanel: PreviewPanel?) {
        guard let visible = NSScreen.current?.visibleFrame else { return }
        var y = visible.minY + 16
        for panel in panels {
            let frame = NSRect(origin: CGPoint(x: visible.minX + 16, y: y), size: panel.frame.size)
            if panel === newPanel {
                panel.setFrame(frame.offsetBy(dx: -24, dy: 0), display: false)
                panel.targetFrame = frame
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    panel.animator().setFrame(frame, display: true)
                }
            }
            y += frame.height + 10
        }
    }

    // MARK: - Actions

    func copy(_ panel: PreviewPanel) {
        let capture = panel.capture
        if ImageExport.copyToPasteboard(capture.image, pointScale: capture.pointScale) {
            Toast.show("Copied to clipboard")
        }
        dismiss(panel)
    }

    func save(_ panel: PreviewPanel) {
        let capture = panel.capture
        do {
            let url = try ImageExport.quickSave(capture.image, pointScale: capture.pointScale)
            Toast.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)", symbol: "square.and.arrow.down")
            dismiss(panel)
        } catch {
            Toast.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
        }
    }

    func edit(_ panel: PreviewPanel) {
        dismiss(panel)
        handler?.edit(panel.capture)
    }

    func pin(_ panel: PreviewPanel) {
        dismiss(panel)
        handler?.pin(panel.capture)
    }

    func recognizeText(_ panel: PreviewPanel) {
        dismiss(panel)
        handler?.recognizeText(in: panel.capture)
    }
}

/// The small floating window shown after a capture: drag the image out, or act on it with one click.
final class PreviewPanel: NSPanel {
    let capture: Capture
    var targetFrame: NSRect = .zero

    private unowned let manager: PreviewManager
    private var timer: Timer?
    private var isHovered = false
    private var isDragging = false

    init(capture: Capture, manager: PreviewManager) {
        self.capture = capture
        self.manager = manager

        let width: CGFloat = 300
        let inner = width - 24
        let aspect = capture.pointSize.height / max(capture.pointSize.width, 1)
        let imageHeight = min(max((inner * aspect).rounded(), 70), 220)
        let footerHeight: CGFloat = 36
        let headerHeight: CGFloat = 26
        let height = 8 + footerHeight + 6 + imageHeight + 4 + headerHeight

        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = .roundedMask(radius: 16)
        contentView = effect

        // Header: close button and a grip that hints the panel can be moved.
        let close = button("xmark", "Close", #selector(closeClicked))
        close.frame = NSRect(x: 8, y: height - headerHeight, width: 24, height: 22)
        effect.addSubview(close)
        let grip = NSImageView(image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil) ?? NSImage())
        grip.contentTintColor = .tertiaryLabelColor
        grip.frame = NSRect(x: width / 2 - 12, y: height - headerHeight, width: 24, height: 22)
        effect.addSubview(grip)

        let thumbnail = ThumbnailView(frame: NSRect(x: 12, y: 8 + footerHeight + 6, width: inner, height: imageHeight))
        thumbnail.image = capture.nsImage
        thumbnail.toolTip = "Drag into another app · Double-click to edit"
        thumbnail.makeFile = { ImageExport.temporaryFile(capture.image, pointScale: capture.pointScale) }
        thumbnail.onDragStarted = { [weak self] in self?.isDragging = true }
        thumbnail.onDragEnded = { [weak self] dropped in
            guard let self else { return }
            isDragging = false
            if dropped { manager.dismiss(self) } else { restartTimer() }
        }
        thumbnail.onDoubleClick = { [weak self] in
            guard let self else { return }
            manager.edit(self)
        }
        effect.addSubview(thumbnail)

        let buttons = NSStackView(views: [
            button("pencil", "Edit", #selector(editClicked)),
            button("doc.on.doc", "Copy", #selector(copyClicked)),
            button("square.and.arrow.down", "Save", #selector(saveClicked)),
            button("text.viewfinder", "Copy Text (OCR)", #selector(textClicked)),
            button("pin", "Pin to Screen", #selector(pinClicked)),
        ])
        buttons.distribution = .fillEqually
        buttons.frame = NSRect(x: 12, y: 8, width: inner, height: footerHeight)
        effect.addSubview(buttons)

        effect.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                              owner: self))
    }

    func present() {
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            animator().alphaValue = 1
            animator().setFrame(targetFrame, display: true)
        }
        restartTimer()
    }

    func fadeOut() {
        timer?.invalidate()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            animator().alphaValue = 0
        }) {
            MainActor.assumeIsolated { self.orderOut(nil) }
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        let duration = Settings.previewDuration
        guard duration > 0, !isHovered, !isDragging else { return }
        timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isHovered, !self.isDragging else { return }
                self.manager.dismiss(self)
            }
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        timer?.invalidate()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        restartTimer()
    }

    private func button(_ symbol: String, _ title: String, _ action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.isBordered = false
        button.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        button.contentTintColor = .labelColor
        button.toolTip = title
        return button
    }

    @objc private func closeClicked() { manager.dismiss(self) }
    @objc private func editClicked() { manager.edit(self) }
    @objc private func copyClicked() { manager.copy(self) }
    @objc private func saveClicked() { manager.save(self) }
    @objc private func textClicked() { manager.recognizeText(self) }
    @objc private func pinClicked() { manager.pin(self) }
}

/// Shows the capture and lets it be dragged out as a PNG file.
private final class ThumbnailView: NSImageView, NSDraggingSource {
    var makeFile: (() -> URL?)?
    var onDragStarted: (() -> Void)?
    var onDragEnded: ((Bool) -> Void)?
    var onDoubleClick: (() -> Void)?
    private var mouseDownEvent: NSEvent?

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            mouseDownEvent = event
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent,
              hypot(event.locationInWindow.x - down.locationInWindow.x,
                    event.locationInWindow.y - down.locationInWindow.y) > 3,
              let url = makeFile?() else { return }
        mouseDownEvent = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        onDragStarted?()
        beginDraggingSession(with: [item], event: down, source: self)
    }

    override func mouseUp(with event: NSEvent) { mouseDownEvent = nil }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragEnded?(operation != [])
    }
}
