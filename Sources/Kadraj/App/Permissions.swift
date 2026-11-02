import AppKit
import ScreenCaptureKit

enum Permissions {
    private static let requestedKey = "requestedScreenRecording"

    /// Returns `true` when screen capture is allowed. Otherwise asks for it: the first time through
    /// the system prompt, afterwards with an alert that links to System Settings.
    @MainActor
    static func ensureScreenRecording() async -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        // The preflight answer is fixed for the life of the process, so a permission granted after
        // launch only shows up when ScreenCaptureKit is asked directly.
        if (try? await SCShareableContent.current) != nil { return true }

        if !UserDefaults.standard.bool(forKey: requestedKey) {
            UserDefaults.standard.set(true, forKey: requestedKey)
            return CGRequestScreenCaptureAccess()
        }

        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Kadraj needs Screen Recording permission"
        alert.informativeText = """
            Allow Kadraj in System Settings › Privacy & Security › Screen & System Audio Recording. \
            If Kadraj is already switched on there, remove it with the − button and add it again. \
            macOS applies the change after Kadraj restarts.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Restart Kadraj")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            relaunch()
        default:
            break
        }
        return false
    }

    /// Starts a fresh copy of the app once this one has quit, then quits.
    @MainActor
    private static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open \"$0\"",
                          Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}
