import AppKit
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum CaptureMode { case area, window, fullscreen }

    private var statusItem: NSStatusItem!
    private let hotKeys = HotKeyManager()
    private var selection: AreaSelectionController?
    private var editors: [EditorWindowController] = []
    private var launchAtLoginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        setUpStatusItem()
        registerHotKeys()

        // `Kadraj --open <file>` opens an image straight in the editor (handy for development).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--open"), i + 1 < args.count {
            openImage(at: URL(fileURLWithPath: args[i + 1]))
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
        menu.addItem(menuItem("Capture Area", #selector(captureArea), key: "2", modifiers: [.command, .shift]))
        menu.addItem(menuItem("Capture Window", #selector(captureWindow)))
        menu.addItem(menuItem("Capture Full Screen", #selector(captureFullscreen), key: "1", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(menuItem("Open Image…", #selector(openImage(_:))))
        menu.addItem(menuItem("Open Image from Clipboard", #selector(pasteImage(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem("Choose Save Folder…", #selector(chooseSaveFolder)))
        launchAtLoginItem = menuItem("Launch at Login", #selector(toggleLaunchAtLogin))
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())
        menu.addItem(menuItem("About Kadraj", #selector(showAbout)))
        menu.addItem(menuItem("Quit Kadraj", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
        statusItem.menu = menu
    }

    private func menuItem(
        _ title: String, _ action: Selector, key: String = "",
        modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target ?? self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func registerHotKeys() {
        let mods = cmdKey | shiftKey
        let failed = [
            hotKeys.register(keyCode: kVK_ANSI_2, modifiers: mods) { [weak self] in self?.captureArea() },
            hotKeys.register(keyCode: kVK_ANSI_1, modifiers: mods) { [weak self] in self?.captureFullscreen() },
        ].contains(false)
        if failed {
            NSLog("Kadraj: some global shortcuts are already used by another app")
        }
    }

    // MARK: - Capture

    @objc private func captureArea() { startCapture(.area) }
    @objc private func captureWindow() { startCapture(.window) }
    @objc private func captureFullscreen() { startCapture(.fullscreen) }

    private func startCapture(_ mode: CaptureMode) {
        guard selection == nil, Permissions.ensureScreenRecording() else { return }
        Task {
            do {
                let content = try await ScreenCapturer.shareableContent()
                let shots = try await ScreenCapturer.captureDisplays(content)
                guard !shots.isEmpty else { return }

                if mode == .fullscreen {
                    let mouse = NSEvent.mouseLocation
                    let shot = shots.first { $0.screen.frame.contains(mouse) } ?? shots[0]
                    openEditor(image: shot.image, pointScale: shot.pointScale)
                    return
                }

                let controller = AreaSelectionController(
                    shots: shots, windows: ScreenCapturer.windows(content), windowMode: mode == .window
                ) { outcome in self.finishSelection(outcome) }
                selection = controller
                controller.show()
            } catch {
                present(error)
            }
        }
    }

    private func finishSelection(_ outcome: AreaSelectionController.Outcome) {
        selection = nil
        switch outcome {
        case .cancelled:
            break
        case let .area(image, pointScale):
            openEditor(image: image, pointScale: pointScale)
        case let .window(window, fallback, pointScale):
            Task {
                if let (image, scale) = try? await ScreenCapturer.capture(window) {
                    openEditor(image: image, pointScale: scale)
                } else if let fallback {
                    openEditor(image: fallback, pointScale: pointScale)
                }
            }
        }
    }

    // MARK: - Editors

    private func openEditor(image: CGImage, pointScale: CGFloat) {
        let editor = EditorWindowController(image: image, pointScale: pointScale)
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

    private func openImage(at url: URL) {
        guard let (image, scale) = ImageExport.loadImage(at: url) else {
            NSLog("Kadraj: could not open %@", url.path)
            return
        }
        openEditor(image: image, pointScale: scale)
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
        openEditor(image: image, pointScale: scale)
    }

    // MARK: - Settings

    @objc private func chooseSaveFolder() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = Settings.saveDirectory
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            Settings.saveDirectory = url
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            present(error)
        }
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
