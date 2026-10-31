import AppKit
import UniformTypeIdentifiers

final class EditorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    var onClose: ((EditorWindowController) -> Void)?

    private let editorDocument: EditorDocument
    private let canvas: CanvasView
    private let toolControl: NSSegmentedControl
    private let sizeControl: NSSegmentedControl
    private let colorWell = NSColorWell(style: .minimal)
    private let cropButton: NSButton
    private let infoLabel = NSTextField(labelWithString: "")
    private let hud = NSTextField(labelWithString: "")
    private var hudTimer: Timer?

    init(image: CGImage, pointScale: CGFloat) {
        editorDocument = EditorDocument(image: image, pointScale: pointScale)
        canvas = CanvasView(document: editorDocument)
        toolControl = NSSegmentedControl(
            images: Tool.allCases.map { Self.symbol($0.symbolName, $0.title) },
            trackingMode: .selectOne, target: nil, action: nil)
        sizeControl = NSSegmentedControl(
            labels: StrokeSize.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
        cropButton = NSButton(image: Self.symbol("crop", "Crop to Selection (Return)"), target: nil, action: nil)

        let window = NSWindow(
            contentRect: Self.initialFrame(for: editorDocument),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Kadraj"
        window.minSize = NSSize(width: 640, height: 360)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self

        buildLayout()
        canvas.onChange = { [weak self] in self?.refresh() }
        canvas.onClose = { [weak self] in self?.close() }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(canvas)
    }

    func windowWillClose(_ notification: Notification) {
        hudTimer?.invalidate()
        onClose?(self)
    }

    // MARK: - Layout

    private func buildLayout() {
        toolControl.target = self
        toolControl.action = #selector(toolChanged(_:))
        for tool in Tool.allCases { toolControl.setToolTip(tool.title, forSegment: tool.rawValue) }

        sizeControl.target = self
        sizeControl.action = #selector(sizeChanged(_:))
        sizeControl.selectedSegment = canvas.strokeSize.rawValue
        sizeControl.toolTip = "Stroke and text size"

        colorWell.color = canvas.color
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        colorWell.toolTip = "Color"

        cropButton.target = self
        cropButton.action = #selector(cropToSelection(_:))
        cropButton.bezelStyle = .texturedRounded
        cropButton.toolTip = "Crop to Selection (Return)"

        let copyButton = NSButton(image: Self.symbol("doc.on.doc", "Copy (⌘C)"), target: self, action: #selector(copy(_:)))
        copyButton.bezelStyle = .texturedRounded
        copyButton.toolTip = "Copy (⌘C)"
        let saveButton = NSButton(image: Self.symbol("square.and.arrow.down", "Save (⌘S)"), target: self,
                                  action: #selector(saveImage(_:)))
        saveButton.bezelStyle = .texturedRounded
        saveButton.toolTip = "Save (⌘S)"

        infoLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        infoLabel.textColor = .secondaryLabelColor

        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        for view in [toolControl, colorWell, sizeControl, cropButton] { bar.addView(view, in: .leading) }
        for view in [infoLabel, copyButton, saveButton] { bar.addView(view, in: .trailing) }

        let separator = NSBox()
        separator.boxType = .separator

        hud.font = .systemFont(ofSize: 13, weight: .medium)
        hud.textColor = .white
        hud.alignment = .center
        hud.wantsLayer = true
        hud.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        hud.layer?.cornerRadius = 8
        hud.isHidden = true

        let content = NSView()
        for view in [bar, separator, canvas, hud] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            separator.topAnchor.constraint(equalTo: bar.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: separator.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            hud.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            hud.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -24),
            hud.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            hud.heightAnchor.constraint(equalToConstant: 30),
        ])
        window?.contentView = content
    }

    private func refresh() {
        toolControl.selectedSegment = canvas.tool.rawValue
        cropButton.isEnabled = canvas.cropRect != nil
        let size = editorDocument.size
        if let crop = canvas.cropRect {
            infoLabel.stringValue = "\(Int(crop.width)) × \(Int(crop.height)) of \(Int(size.width)) × \(Int(size.height))"
        } else {
            infoLabel.stringValue = "\(Int(size.width)) × \(Int(size.height))  ·  \(canvas.zoomPercent)%"
        }
    }

    private func showHUD(_ message: String) {
        hud.stringValue = "   \(message)   "
        hud.isHidden = false
        hudTimer?.invalidate()
        hudTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hud.isHidden = true }
        }
    }

    // MARK: - Toolbar actions

    @objc private func toolChanged(_ sender: NSSegmentedControl) {
        canvas.tool = Tool(rawValue: sender.selectedSegment) ?? .select
        window?.makeFirstResponder(canvas)
    }

    @objc private func sizeChanged(_ sender: NSSegmentedControl) {
        canvas.setStrokeSize(StrokeSize(rawValue: sender.selectedSegment) ?? .medium)
        window?.makeFirstResponder(canvas)
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        canvas.setColor(sender.color)
    }

    // MARK: - Menu actions

    @objc func copy(_ sender: Any?) {
        guard let image = canvas.exportImage(),
              ImageExport.copyToPasteboard(image, pointScale: editorDocument.pointScale) else {
            NSSound.beep()
            return
        }
        showHUD("Copied to clipboard")
    }

    @objc func saveImage(_ sender: Any?) {
        guard let image = canvas.exportImage(),
              let data = ImageExport.data(image, type: .png, pointScale: editorDocument.pointScale) else { return }
        let folder = Settings.saveDirectory
        let url = folder.appendingPathComponent("Kadraj \(Self.timestamp()).png")
        do {
            try data.write(to: url)
            showHUD("Saved to \(folder.lastPathComponent)")
        } catch {
            presentError(error)
        }
    }

    @objc func saveImageAs(_ sender: Any?) {
        guard let window, let image = canvas.exportImage() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "Kadraj \(Self.timestamp()).png"
        panel.directoryURL = Settings.saveDirectory
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let type: UTType = ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) ? .jpeg : .png
            do {
                guard let data = ImageExport.data(image, type: type, pointScale: editorDocument.pointScale) else { return }
                try data.write(to: url)
                showHUD("Saved \(url.lastPathComponent)")
            } catch {
                presentError(error)
            }
        }
    }

    @objc func undoEdit(_ sender: Any?) { canvas.undo() }
    @objc func redoEdit(_ sender: Any?) { canvas.redo() }
    @objc func delete(_ sender: Any?) { canvas.deleteSelection() }
    @objc func cropToSelection(_ sender: Any?) { canvas.applyCrop() }
    @objc func zoomToActualSize(_ sender: Any?) { canvas.zoomToActualSize() }
    @objc func zoomToFit(_ sender: Any?) { canvas.zoomToFit() }
    @objc func zoomIn(_ sender: Any?) { canvas.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { canvas.zoomOut() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undoEdit(_:)): editorDocument.canUndo
        case #selector(redoEdit(_:)): editorDocument.canRedo
        case #selector(delete(_:)): canvas.selectedID != nil
        case #selector(cropToSelection(_:)): canvas.cropRect != nil
        default: true
        }
    }

    // MARK: - Helpers

    private static func symbol(_ name: String, _ description: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage()
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: Date())
    }

    /// Fits the image at actual size when possible, on the screen under the mouse.
    private static func initialFrame(for document: EditorDocument) -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let points = CGSize(width: document.size.width / document.pointScale,
                            height: document.size.height / document.pointScale)
        let width = min(max(points.width + 48, 720), visible.width * 0.9)
        let height = min(max(points.height + 48 + 44, 420), visible.height * 0.9)
        return NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
    }
}
