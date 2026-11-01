import Foundation
import UniformTypeIdentifiers

enum AfterCapture: String, CaseIterable, Identifiable {
    case preview, editor, clipboard

    var id: Self { self }

    var title: String {
        switch self {
        case .preview: "Show floating preview"
        case .editor: "Open editor"
        case .clipboard: "Copy to clipboard only"
        }
    }
}

enum ImageFormat: String, CaseIterable, Identifiable {
    case png, jpeg

    var id: Self { self }
    var title: String { self == .png ? "PNG" : "JPEG" }
    var type: UTType { self == .png ? .png : .jpeg }
    var fileExtension: String { self == .png ? "png" : "jpg" }
}

/// User preferences, stored in `UserDefaults`. The settings window binds to the same keys with `@AppStorage`.
enum Settings {
    enum Keys {
        static let saveDirectory = "saveDirectory"
        static let afterCapture = "afterCapture"
        static let autoCopy = "autoCopy"
        static let autoSave = "autoSave"
        static let previewDuration = "previewDuration"
        static let imageFormat = "imageFormat"
        static func shortcut(_ action: ShortcutAction) -> String { "shortcut.\(action.rawValue)" }
    }

    static let shortcutsDidChange = Notification.Name("KadrajShortcutsDidChange")

    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            Keys.afterCapture: AfterCapture.preview.rawValue,
            Keys.previewDuration: 6.0,
            Keys.imageFormat: ImageFormat.png.rawValue,
        ])
    }

    /// Folder used by quick save (⌘S). Defaults to the Desktop.
    static var saveDirectory: URL {
        get {
            if let path = defaults.string(forKey: Keys.saveDirectory) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        }
        set { defaults.set(newValue.path, forKey: Keys.saveDirectory) }
    }

    static var afterCapture: AfterCapture {
        defaults.string(forKey: Keys.afterCapture).flatMap(AfterCapture.init) ?? .preview
    }

    static var autoCopy: Bool { defaults.bool(forKey: Keys.autoCopy) }
    static var autoSave: Bool { defaults.bool(forKey: Keys.autoSave) }

    /// Seconds before the floating preview hides itself; 0 keeps it until used.
    static var previewDuration: TimeInterval { defaults.double(forKey: Keys.previewDuration) }

    static var imageFormat: ImageFormat {
        defaults.string(forKey: Keys.imageFormat).flatMap(ImageFormat.init) ?? .png
    }

    /// The user's shortcut, the default when never changed, or `nil` when cleared.
    static func shortcut(for action: ShortcutAction) -> Shortcut? {
        guard let data = defaults.data(forKey: Keys.shortcut(action)) else { return action.defaultShortcut }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    static func setShortcut(_ shortcut: Shortcut?, for action: ShortcutAction) {
        // An empty value marks a deliberately cleared shortcut, as opposed to "never set".
        let data = shortcut.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        defaults.set(data, forKey: Keys.shortcut(action))
        NotificationCenter.default.post(name: shortcutsDidChange, object: nil)
    }

    static func resetShortcuts() {
        for action in ShortcutAction.allCases { defaults.removeObject(forKey: Keys.shortcut(action)) }
        NotificationCenter.default.post(name: shortcutsDidChange, object: nil)
    }
}
