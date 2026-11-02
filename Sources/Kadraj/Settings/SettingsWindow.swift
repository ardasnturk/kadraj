import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = "Kadraj Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 520, height: 610)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(Settings.Keys.afterCapture) private var afterCapture = AfterCapture.preview
    @AppStorage(Settings.Keys.autoCopy) private var autoCopy = false
    @AppStorage(Settings.Keys.autoSave) private var autoSave = false
    @AppStorage(Settings.Keys.previewDuration) private var previewDuration = 6.0
    @AppStorage(Settings.Keys.imageFormat) private var imageFormat = ImageFormat.png
    @State private var saveDirectory = Settings.saveDirectory

    var body: some View {
        Form {
            Section("After capture") {
                Picker("Then", selection: $afterCapture) {
                    ForEach(AfterCapture.allCases) { Text($0.title).tag($0) }
                }
                Picker("Hide preview after", selection: $previewDuration) {
                    Text("3 seconds").tag(3.0)
                    Text("6 seconds").tag(6.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                    Text("Never").tag(0.0)
                }
                .disabled(afterCapture != .preview)
                Toggle("Also copy to clipboard", isOn: $autoCopy)
                    .disabled(afterCapture == .clipboard)
                Toggle("Also save to folder", isOn: $autoSave)
            }

            Section("Saving") {
                LabeledContent("Folder") {
                    HStack {
                        Text(saveDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                Picker("Format", selection: $imageFormat) {
                    ForEach(ImageFormat.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("System") {
                LaunchAtLoginToggle()
            }

            UpdateSettingsSection()
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = saveDirectory
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            Settings.saveDirectory = url
            saveDirectory = url
        }
    }
}

private struct UpdateSettingsSection: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Section("Updates") {
            Toggle("Automatically check for updates", isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.automaticallyChecksForUpdates = $0 }))
            LabeledContent("Version \(Bundle.main.shortVersion)") {
                Button("Check Now", action: updater.checkForUpdates)
                    .disabled(!updater.canCheckForUpdates)
            }
        }
    }
}

private extension Bundle {
    var shortVersion: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–" }
}

/// Also used by the welcome guide.
struct LaunchAtLoginToggle: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Toggle("Launch at login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
        if let loginError {
            Text(loginError).font(.caption).foregroundStyle(.red)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled {
                try service.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = service.status == .enabled
        }
    }
}

private struct ShortcutSettingsView: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    LabeledContent(action.title) {
                        HStack(spacing: 6) {
                            if state.failedShortcuts.contains(action) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                    .help("Another app already uses this shortcut")
                            }
                            ShortcutRecorder(action: action, version: state.shortcutsVersion)
                                .frame(width: 150, height: 24)
                        }
                    }
                }
            } footer: {
                Text("Click a shortcut and press the new keys. Delete clears it, Esc cancels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("While selecting an area") {
                LabeledContent("Switch to window mode", value: "Space")
                LabeledContent("Capture the whole display", value: "Return")
                LabeledContent("Square selection", value: "⇧ while dragging")
            }

            HStack {
                Spacer()
                Button("Restore Defaults") { Settings.resetShortcuts() }
            }
        }
        .formStyle(.grouped)
    }
}
