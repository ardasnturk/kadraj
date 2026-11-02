import AppKit
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, permission, shortcuts, tour
}

/// The welcome guide: shown at first launch, whenever a capture lacks the Screen Recording
/// permission, and from the menu bar.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private let model = OnboardingModel()

    private init() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(model: model)))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.title = "Welcome to Kadraj"
        super.init(window: window)
        window.delegate = self
        model.onFinish = { [weak self] in self?.close() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Opens the guide at `step`, or where it was left.
    func present(at step: OnboardingStep? = nil) {
        // Until the window closes, a relaunch (for the permission, or macOS's own "Quit & Reopen")
        // brings the guide back at the same page.
        Settings.onboardingCompleted = false
        model.step = step ?? OnboardingStep(rawValue: Settings.onboardingStep) ?? .welcome
        if window?.isVisible != true { window?.center() }
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Closing early counts as done: a capture without permission brings the guide back anyway.
        Settings.onboardingCompleted = true
        Settings.onboardingStep = OnboardingStep.welcome.rawValue
        model.stopWatchingPermission()
    }
}

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var step = OnboardingStep.welcome {
        didSet {
            Settings.onboardingStep = step.rawValue
            step == .permission ? watchPermission() : stopWatchingPermission()
        }
    }
    @Published private(set) var permission = Permissions.canCapture ? ScreenRecordingStatus.granted : .denied
    @Published private(set) var requested = false
    var onFinish: (() -> Void)?

    private var watcher: Task<Void, Never>?

    func next() {
        if let next = OnboardingStep(rawValue: step.rawValue + 1) { step = next } else { finish() }
    }

    func back() {
        if let previous = OnboardingStep(rawValue: step.rawValue - 1) { step = previous }
    }

    func finish() {
        Settings.onboardingCompleted = true
        Settings.onboardingStep = OnboardingStep.welcome.rawValue
        onFinish?()
    }

    func requestPermission() {
        requested = true
        Task { await Permissions.requestScreenRecording() }
    }

    /// Keeps `permission` current while the permission page is open, as the user flips the switch
    /// in System Settings.
    private func watchPermission() {
        guard watcher == nil else { return }
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                let status = await Permissions.screenRecordingStatus()
                guard let self else { return }
                if status != permission { permission = status }
                if status == .granted { break }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopWatchingPermission() {
        watcher?.cancel()
        watcher = nil
    }
}

// MARK: - Views

private struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case .welcome: WelcomePage()
                case .permission: PermissionPage(model: model)
                case .shortcuts: ShortcutsPage()
                case .tour: TourPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)
            .padding(.top, 44)
            .transition(.opacity)
            .id(model.step)

            Divider()
            footer
        }
        .frame(width: 600, height: 540)
        .animation(.easeInOut(duration: 0.2), value: model.step)
    }

    private var footer: some View {
        HStack {
            if model.step != .welcome {
                Button("Back", action: model.back)
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            if model.step == .permission, model.permission != .granted {
                Button("Skip for Now", action: model.next)
            } else {
                Button(model.step == .tour ? "Start Capturing" : model.step == .welcome ? "Get Started" : "Continue",
                       action: model.next)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay {
            // Page dots stay centered whatever buttons sit beside them.
            HStack(spacing: 7) {
                ForEach(OnboardingStep.allCases, id: \.self) { step in
                    Circle()
                        .fill(step == model.step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
        }
    }
}

private struct PageHeader: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(height: 42)
            Text(title)
                .font(.title.weight(.semibold))
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
    }
}

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .padding(.bottom, 12)
            Text("Welcome to Kadraj")
                .font(.largeTitle.weight(.semibold))
            Text("Screenshots that are quick to take and easy to mark up.")
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                .padding(.bottom, 30)

            VStack(alignment: .leading, spacing: 18) {
                Feature(symbol: "viewfinder", title: "Capture anything",
                        text: "An area, a window or the whole screen, with a keyboard shortcut.")
                Feature(symbol: "pencil.and.outline", title: "Mark it up",
                        text: "Arrows, shapes, text, numbered steps and pixelation, with pixel-precise cropping.")
                Feature(symbol: "square.and.arrow.up", title: "Share it fast",
                        text: "Drag it out, copy it, pin it on top of other windows or pull the text out of it.")
            }
            .frame(maxWidth: 400)
            Spacer(minLength: 0)
        }
    }
}

private struct Feature: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PermissionPage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(symbol: "rectangle.dashed.badge.record", title: "Allow screen recording",
                       subtitle: "macOS asks before any app can see your screen. Kadraj only looks when you take a screenshot, and nothing leaves your Mac.")

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    switch model.permission {
                    case .granted:
                        status("checkmark.circle.fill", .green, "Screen recording is allowed.",
                               "You're all set. Continue to choose your shortcuts.")
                    case .needsRestart:
                        status("arrow.clockwise.circle.fill", .orange, "Almost there: restart Kadraj.",
                               "macOS applies the permission after Kadraj restarts. The guide picks up where you left off.")
                        Button("Restart Kadraj", action: Permissions.relaunch)
                            .controlSize(.large)
                            .buttonStyle(.borderedProminent)
                    case .denied:
                        Step(number: 1, text: "Click the button below. macOS opens System Settings.")
                        Step(number: 2, text: "Turn on Kadraj under Screen & System Audio Recording.")
                        Step(number: 3, text: "Come back here. This page notices the change by itself.")
                        HStack(spacing: 12) {
                            Button(model.requested ? "Open System Settings" : "Allow Screen Recording",
                                   action: model.requestPermission)
                                .controlSize(.large)
                                .buttonStyle(.borderedProminent)
                            if model.requested {
                                ProgressView().controlSize(.small)
                                Text("Waiting for permission…").foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .frame(maxWidth: 440)

            if model.permission == .denied {
                Text("Kadraj missing from the list? Click + under it and choose Kadraj in Applications. Switched on but still asked? Remove it with −, then add it again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .padding(.top, 14)
            }
            Spacer(minLength: 0)
        }
    }

    private func status(_ symbol: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            Text(text)
        }
    }
}

private struct ShortcutsPage: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(symbol: "keyboard", title: "Choose your shortcuts",
                       subtitle: "They work from any app. Click one and press the keys you want, or keep the suggestions.")

            VStack(spacing: 0) {
                ForEach(Array(ShortcutAction.allCases.enumerated()), id: \.element) { index, action in
                    if index > 0 { Divider() }
                    HStack {
                        Text(action.title)
                        Spacer()
                        if state.failedShortcuts.contains(action) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .help("Another app already uses this shortcut")
                        }
                        ShortcutRecorder(action: action, version: state.shortcutsVersion)
                            .frame(width: 150, height: 24)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
            .frame(maxWidth: 440)

            Text("Delete clears a shortcut, Esc cancels. You can change them later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            Spacer(minLength: 0)
        }
    }
}

private struct TourPage: View {
    var body: some View {
        VStack(spacing: 0) {
            PageHeader(symbol: "sparkles", title: "How Kadraj works",
                       subtitle: "Four things worth knowing before your first capture.")

            VStack(alignment: .leading, spacing: 16) {
                Feature(symbol: "crop", title: "Select an area\(shortcut(.captureArea))",
                        text: "Drag across the screen. Hold ⇧ for a square, press Space to pick a window, Return for the whole display, Esc to cancel.")
                Feature(symbol: "rectangle.on.rectangle", title: "Use the floating preview",
                        text: "After a capture, drag the thumbnail into any app, or edit, copy, save, pin it or copy its text.")
                Feature(symbol: "pencil.tip.crop.circle", title: "Mark it up in the editor",
                        text: "Arrow A, Rectangle R, Oval O, Text T, Pixelate B, Step N. Crop with V, then copy with ⌘C.")
                Feature(symbol: "menubar.arrow.up.rectangle", title: "Find everything in the menu bar",
                        text: "The camera icon at the top of the screen has every capture, Settings and this guide.")
            }
            .frame(maxWidth: 460)

            Form {
                LaunchAtLoginToggle()
            }
            .formStyle(.columns)
            .padding(.top, 20)
            Spacer(minLength: 0)
        }
    }

    private func shortcut(_ action: ShortcutAction) -> String {
        Settings.shortcut(for: action).map { " · \($0.displayString)" } ?? ""
    }
}
