import Foundation

enum Settings {
    private static let saveDirectoryKey = "saveDirectory"

    /// Folder used by quick save (⌘S). Defaults to the Desktop.
    static var saveDirectory: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: saveDirectoryKey) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        }
        set { UserDefaults.standard.set(newValue.path, forKey: saveDirectoryKey) }
    }
}
