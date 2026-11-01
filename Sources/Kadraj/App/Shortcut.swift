import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: a virtual key code plus Carbon modifier flags.
struct Shortcut: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int

    init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Fails for combinations that make poor global shortcuts, such as a plain letter or ⇧ + letter.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = 0
        if flags.contains(.command) { modifiers |= cmdKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        let keyCode = Int(event.keyCode)
        guard modifiers & (cmdKey | optionKey | controlKey) != 0 || Self.functionKeys[keyCode] != nil else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    var displayString: String {
        var result = ""
        if modifiers & controlKey != 0 { result += "⌃" }
        if modifiers & optionKey != 0 { result += "⌥" }
        if modifiers & shiftKey != 0 { result += "⇧" }
        if modifiers & cmdKey != 0 { result += "⌘" }
        return result + Self.keyName(keyCode)
    }

    /// For showing the shortcut next to a menu item.
    var keyEquivalent: String {
        let name = Self.keyName(keyCode)
        return name.count == 1 ? name.lowercased() : ""
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & cmdKey != 0 { flags.insert(.command) }
        if modifiers & optionKey != 0 { flags.insert(.option) }
        if modifiers & controlKey != 0 { flags.insert(.control) }
        if modifiers & shiftKey != 0 { flags.insert(.shift) }
        return flags
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_KeypadEnter: "⌤",
    ]

    /// The key's label on the current keyboard layout, so ⌘⇧Z shows as ⌘⇧Y on a German keyboard when it should.
    static func keyName(_ keyCode: Int) -> String {
        if let name = functionKeys[keyCode] ?? specialKeys[keyCode] { return name }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count,
                                  &length, &characters)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case captureArea, captureWindow, captureFullscreen, repeatArea, captureText

    var id: Self { self }

    var title: String {
        switch self {
        case .captureArea: "Capture Area"
        case .captureWindow: "Capture Window"
        case .captureFullscreen: "Capture Full Screen"
        case .repeatArea: "Repeat Last Area"
        case .captureText: "Capture Text (OCR)"
        }
    }

    var defaultShortcut: Shortcut? {
        switch self {
        case .captureArea: Shortcut(keyCode: kVK_ANSI_2, modifiers: cmdKey | shiftKey)
        case .captureFullscreen: Shortcut(keyCode: kVK_ANSI_1, modifiers: cmdKey | shiftKey)
        case .captureWindow, .repeatArea, .captureText: nil
        }
    }
}
