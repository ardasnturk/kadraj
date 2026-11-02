import AppKit

enum ScreenRecordingStatus {
    /// Kadraj can capture right now.
    case granted
    /// Allowed in System Settings, but this process only sees it after a restart.
    case needsRestart
    case denied
}

/// Screen Recording permission. macOS answers `CGPreflightScreenCaptureAccess` once per process, so
/// a permission granted after launch is checked in a fresh copy of the app (`--check-screen-recording`).
@MainActor
enum Permissions {
    static let checkArgument = "--check-screen-recording"

    static var canCapture: Bool { CGPreflightScreenCaptureAccess() }

    static func screenRecordingStatus() async -> ScreenRecordingStatus {
        if canCapture { return .granted }
        return await systemAllowsCapture() ? .needsRestart : .denied
    }

    /// Asks macOS for the permission, which also puts Kadraj in the list in System Settings. That
    /// entry is gone after a reset or on a new Mac, so the request is made every time. macOS shows
    /// its prompt (with its own button to System Settings) only when it hasn't asked before; when
    /// no prompt takes focus, Kadraj opens System Settings itself.
    static func requestScreenRecording() async {
        CGRequestScreenCaptureAccess()
        try? await Task.sleep(for: .milliseconds(800))
        if NSApp.isActive { openSystemSettings() }
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Starts a fresh copy of the app once this one has quit, then quits.
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open \"$0\"",
                          Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    private static func systemAllowsCapture() async -> Bool {
        guard let executable = Bundle.main.executableURL else { return false }
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = executable
            task.arguments = [checkArgument]
            task.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do {
                try task.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}
