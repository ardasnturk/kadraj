import Carbon.HIToolbox

/// Registers system-wide keyboard shortcuts through the Carbon hot key API,
/// which needs no Accessibility permission.
@MainActor
final class HotKeyManager {
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
            // Carbon delivers hot key events on the main thread.
            MainActor.assumeIsolated { manager.handlers[hotKeyID.id]?() }
            return noErr
        }, 1, &spec, context, &eventHandler)
    }

    /// - Parameters:
    ///   - keyCode: A virtual key code such as `kVK_ANSI_2`.
    ///   - modifiers: Carbon modifier flags such as `cmdKey | shiftKey`.
    /// - Returns: `false` when another app already owns the shortcut.
    @discardableResult
    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) -> Bool {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4B44_524A) /* KDRJ */, id: id)
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs.append(ref)
        handlers[id] = handler
        return true
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handlers.removeAll()
    }
}

/// State shared between the app delegate and the SwiftUI settings window.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// Shortcuts that could not be registered because another app owns them.
    @Published var failedShortcuts: Set<ShortcutAction> = []
    /// Bumped whenever shortcuts are re-registered, so recorders refresh.
    @Published var shortcutsVersion = 0
    /// Called with `true` while a shortcut recorder listens, so the current shortcuts don't fire.
    var onSuspendHotKeys: ((Bool) -> Void)?
}
