import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click to record a shortcut; press the new keys, Delete to clear, or Esc to cancel.
final class ShortcutRecorderView: NSView {
    var shortcut: Shortcut? {
        didSet { needsDisplay = true }
    }
    var onChange: ((Shortcut?) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?

    private var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            needsDisplay = true
            onRecordingChange?(isRecording)
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }
    // Only a click starts recording; the window must not pick the recorder as its first responder
    // on its own, which would pause every global shortcut while the settings window is open.
    override var acceptsFirstResponder: Bool { isClicked }
    override var canBecomeKeyView: Bool { false }
    private var isClicked = false

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            window?.makeFirstResponder(nil)
        } else {
            isClicked = true
            window?.makeFirstResponder(self)
            isClicked = false
        }
    }

    override func becomeFirstResponder() -> Bool {
        isRecording = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘-combinations arrive here rather than in keyDown.
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        record(event)
    }

    private func record(_ event: NSEvent) {
        let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        switch Int(event.keyCode) {
        case kVK_Escape where plain:
            window?.makeFirstResponder(nil)
        case kVK_Delete where plain, kVK_ForwardDelete where plain:
            shortcut = nil
            onChange?(nil)
            window?.makeFirstResponder(nil)
        default:
            guard let recorded = Shortcut(event: event) else {
                NSSound.beep()
                return
            }
            shortcut = recorded
            onChange?(recorded)
            window?.makeFirstResponder(nil)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text: String
        let color: NSColor
        if isRecording {
            text = "Type shortcut…"
            color = .secondaryLabelColor
        } else if let shortcut {
            text = shortcut.displayString
            color = .labelColor
        } else {
            text = "Record Shortcut"
            color = .tertiaryLabelColor
        }
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: shortcut == nil || isRecording ? .regular : .medium),
            .foregroundColor: color,
        ])
        let size = string.size()
        string.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let action: ShortcutAction
    /// Changes whenever shortcuts change, so SwiftUI refreshes the view.
    let version: Int

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.shortcut = Settings.shortcut(for: action)
        view.onChange = { Settings.setShortcut($0, for: action) }
        view.onRecordingChange = { AppState.shared.onSuspendHotKeys?($0) }
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.shortcut = Settings.shortcut(for: action)
    }
}
