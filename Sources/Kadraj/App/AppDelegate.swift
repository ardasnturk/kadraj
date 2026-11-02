import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, CaptureHandling {
    private enum CaptureMode { case area, window, fullscreen, repeatArea, text }

    private var statusItem: NSStatusItem!
    private var shortcutItems: [ShortcutAction: NSMenuItem] = [:]
    private var updateItem: NSMenuItem!
    private let hotKeys = HotKeyManager()
    private var hotKeysSuspended = false
    private var selection: AreaSelectionController?
    private var lastRegion: AreaSelectionController.Region?
    private let previews = PreviewManager()
    private var editors: [EditorWindowController] = []
    private var pins: [PinPanel] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        _ = Updater.shared
        NSApp.mainMenu = MainMenu.build()
        previews.handler = self
        setUpStatusItem()

        NotificationCenter.default.addObserver(forName: Settings.shortcutsDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.registerHotKeys() }
        }
        AppState.shared.onSuspendHotKeys = { [weak self] suspended in
            self?.hotKeysSuspended = suspended
            self?.registerHotKeys()
        }
        registerHotKeys()

        // Development shortcuts: `--open <file>` opens the editor, `--preview <file>` shows the
        // floating preview, `--settings` opens the settings window, `--onboarding` the welcome guide.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--open"), i + 1 < args.count {
            openImage(at: URL(fileURLWithPath: args[i + 1]))
        }
        if let i = args.firstIndex(of: "--preview"), i + 1 < args.count,
           let (image, scale) = ImageExport.loadImage(at: URL(fileURLWithPath: args[i + 1])) {
            previews.show(Capture(image: image, pointScale: scale))
        }
        if args.contains("--settings") {
            openSettings(nil)
        }

        if !Settings.onboardingCompleted || args.contains("--onboarding") {
            OnboardingWindowController.shared.present()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(openImage(at:))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Kadraj")

        let menu = NSMenu()
        menu.delegate = self
        let captures: [(ShortcutAction, Selector)] = [
            (.captureArea, #selector(captureArea)),
            (.captureWindow, #selector(captureWindow)),
            (.captureFullscreen, #selector(captureFullscreen)),
            (.repeatArea, #selector(repeatArea)),
            (.captureText, #selector(captureText)),
        ]
        for (action, selector) in captures {
            let item = menuItem(action.title, selector)
            shortcutItems[action] = item
            menu.addItem(item)
        }
        menu.addItem(menuItem("Capture Full Screen in 3 Seconds", #selector(captureDelayed)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Open Image…", #selector(openImage(_:))))
        menu.addItem(menuItem("Open Image from Clipboard", #selector(pasteImage(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…", #selector(openSettings(_:)), key: ","))
        menu.addItem(menuItem("Welcome Guide", #selector(openOnboarding)))
        updateItem = menuItem("Check for Updates…", #selector(checkForUpdates(_:)))
        menu.addItem(updateItem)
        menu.addItem(menuItem("About Kadraj", #selector(showAbout)))
        menu.addItem(menuItem("Quit Kadraj", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
        statusItem.menu = menu
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let version = Updater.shared.pendingVersion {
            updateItem.title = "Update to Kadraj \(version)…"
            updateItem.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
        } else {
            updateItem.title = "Check for Updates…"
            updateItem.image = nil
        }
        for (action, item) in shortcutItems {
            let shortcut = Settings.shortcut(for: action)
            item.keyEquivalent = shortcut?.keyEquivalent ?? ""
            item.keyEquivalentModifierMask = shortcut?.modifierFlags ?? []
        }
    }

    private func registerHotKeys() {
        hotKeys.unregisterAll()
        if !hotKeysSuspended {
            var failed = Set<ShortcutAction>()
            for action in ShortcutAction.allCases {
                guard let shortcut = Settings.shortcut(for: action) else { continue }
                let ok = hotKeys.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
                    self?.perform(action)
                }
                if !ok { failed.insert(action) }
            }
            AppState.shared.failedShortcuts = failed
        }
        AppState.shared.shortcutsVersion += 1
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .captureArea: startCapture(.area)
        case .captureWindow: startCapture(.window)
        case .captureFullscreen: startCapture(.fullscreen)
        case .repeatArea: startCapture(.repeatArea)
        case .captureText: startCapture(.text)
        }
    }

    // MARK: - Capture

    @objc private func captureArea() { startCapture(.area) }
    @objc private func captureWindow() { startCapture(.window) }
    @objc private func captureFullscreen() { startCapture(.fullscreen) }
    @objc private func repeatArea() { startCapture(.repeatArea) }
    @objc private func captureText() { startCapture(.text) }

    @objc private func captureDelayed() {
        Task {
            for second in stride(from: 3, to: 0, by: -1) {
                Toast.show("Capturing in \(second)…", symbol: "timer", duration: 0.9)
                try? await Task.sleep(for: .seconds(1))
            }
            startCapture(.fullscreen)
        }
    }

    private func startCapture(_ mode: CaptureMode) {
        guard selection == nil else { return }
        // Without the permission, ScreenCaptureKit would raise its own system prompt on every try;
        // the welcome guide explains what to do instead.
        guard Permissions.canCapture else {
            OnboardingWindowController.shared.present(at: .permission)
            return
        }
        Task { [self] in
            do {
                let content = try await ScreenCapturer.shareableContent()
                let shots = try await ScreenCapturer.captureDisplays(content)
                guard !shots.isEmpty else { return }
                let mouse = NSEvent.mouseLocation

                switch mode {
                case .fullscreen:
                    let shot = shots.first { $0.screen.frame.contains(mouse) } ?? shots[0]
                    deliver(Capture(image: shot.image, pointScale: shot.pointScale, screenRect: shot.screen.frame))
                    return
                case .repeatArea:
                    if let region = lastRegion,
                       let shot = shots.first(where: { $0.displayID == region.displayID }),
                       let image = shot.crop(region.rect) {
                        deliver(Capture(image: image, pointScale: shot.pointScale, screenRect: region.screenRect))
                        return
                    }
                case .area, .window, .text:
                    break
                }

                let purpose: AreaSelectionController.Purpose = mode == .text ? .text : .capture
                let controller = AreaSelectionController(
                    shots: shots, windows: ScreenCapturer.windows(content), windowMode: mode == .window, purpose: purpose
                ) { outcome in self.finishSelection(outcome, purpose: purpose) }
                selection = controller
                controller.show()
            } catch {
                present(error)
            }
        }
    }

    private func finishSelection(_ outcome: AreaSelectionController.Outcome, purpose: AreaSelectionController.Purpose) {
        selection = nil
        switch outcome {
        case .cancelled:
            break
        case let .area(image, pointScale, region):
            if let region { lastRegion = region }
            let capture = Capture(image: image, pointScale: pointScale, screenRect: region?.screenRect)
            if purpose == .text {
                recognizeText(in: capture)
            } else {
                deliver(capture)
            }
        case let .window(window, fallback, pointScale):
            let screenRect = window.screenRect
            Task {
                if let (image, scale) = try? await ScreenCapturer.capture(window) {
                    deliver(Capture(image: image, pointScale: scale, screenRect: screenRect))
                } else if let fallback {
                    deliver(Capture(image: fallback, pointScale: pointScale, screenRect: screenRect))
                }
            }
        }
    }

    /// Applies the "after capture" preferences to a new screenshot.
    private func deliver(_ capture: Capture) {
        let after = Settings.afterCapture
        var copied = false
        if Settings.autoCopy || after == .clipboard {
            copied = ImageExport.copyToPasteboard(capture.image, pointScale: capture.pointScale)
        }
        var saved = false
        if Settings.autoSave {
            do {
                _ = try ImageExport.quickSave(capture.image, pointScale: capture.pointScale)
                saved = true
            } catch {
                Toast.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }

        switch after {
        case .preview:
            previews.show(capture)
        case .editor:
            edit(capture)
        case .clipboard:
            if copied || saved {
                Toast.show(copied && saved ? "Copied and saved" : copied ? "Copied to clipboard" : "Saved")
            }
        }
    }

    // MARK: - CaptureHandling

    func edit(_ capture: Capture) {
        let editor = EditorWindowController(capture: capture, handler: self)
        editor.onClose = { [weak self] closed in
            guard let self else { return }
            editors.removeAll { $0 === closed }
            if editors.isEmpty { NSApp.setActivationPolicy(.accessory) }
        }
        editors.append(editor)
        // Become a regular app while an editor is open so it gets a Dock icon and menu bar.
        NSApp.setActivationPolicy(.regular)
        editor.showWindow(nil)
        NSApp.activate()
    }

    func pin(_ capture: Capture) {
        let pin = PinPanel(capture: capture, handler: self)
        pin.onClose = { [weak self] closed in self?.pins.removeAll { $0 === closed } }
        pins.append(pin)
        pin.orderFrontRegardless()
    }

    func recognizeText(in capture: Capture) {
        Task {
            switch await TextRecognizer.recognize(capture.image) {
            case let .text(text, lineCount):
                ImageExport.copyString(text)
                Toast.show(lineCount == 1 ? "Copied text" : "Copied \(lineCount) lines of text", symbol: "text.viewfinder")
            case let .code(payload):
                ImageExport.copyString(payload)
                Toast.show("Copied code: \(payload)", symbol: "qrcode")
            case .nothing:
                Toast.show("No text found", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    // MARK: - Opening images

    private func openImage(at url: URL) {
        guard let (image, scale) = ImageExport.loadImage(at: url) else {
            NSLog("Kadraj: could not open %@", url.path)
            return
        }
        edit(Capture(image: image, pointScale: scale))
    }

    @objc func openImage(_ sender: Any?) {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(openImage(at:))
    }

    @objc func pasteImage(_ sender: Any?) {
        guard let (image, scale) = ImageExport.imageFromPasteboard() else {
            NSSound.beep()
            return
        }
        edit(Capture(image: image, pointScale: scale))
    }

    // MARK: - Other

    @objc func openSettings(_ sender: Any?) {
        SettingsWindowController.shared.present()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        Updater.shared.checkForUpdates()
    }

    @objc private func openOnboarding() {
        OnboardingWindowController.shared.present(at: .welcome)
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    private func present(_ error: Error) {
        NSApp.activate()
        NSAlert(error: error).runModal()
    }
}
