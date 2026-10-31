import AppKit

enum Permissions {
    private static let requestedKey = "requestedScreenRecording"

    /// Returns `true` when screen capture is allowed. Otherwise asks for it: the first time through
    /// the system prompt, afterwards with an alert that links to System Settings.
    @MainActor
    static func ensureScreenRecording() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }

        if !UserDefaults.standard.bool(forKey: requestedKey) {
            UserDefaults.standard.set(true, forKey: requestedKey)
            return CGRequestScreenCaptureAccess()
        }

        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Kadraj needs Screen Recording permission"
        alert.informativeText = """
            Allow Kadraj in System Settings › Privacy & Security › Screen & System Audio Recording, \
            then try capturing again.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }
}
