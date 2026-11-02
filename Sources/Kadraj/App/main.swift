import AppKit

// Run by the app itself to read the current Screen Recording permission (see `Permissions`).
if CommandLine.arguments.contains("--check-screen-recording") {
    exit(CGPreflightScreenCaptureAccess() ? 0 : 1)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
