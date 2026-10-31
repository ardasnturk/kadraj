import AppKit

/// The menu bar shown while an editor window is open. Editor actions travel the responder chain
/// to `EditorWindowController`; app-level ones reach `AppDelegate`.
@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let holder = NSMenuItem()
            holder.submenu = menu
            main.addItem(holder)
            return menu
        }

        func item(_ title: String, _ action: Selector, _ key: String = "",
                  _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }

        _ = submenu("Kadraj", [
            item("About Kadraj", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide Kadraj", #selector(NSApplication.hide(_:)), "h"),
            item("Quit Kadraj", #selector(NSApplication.terminate(_:)), "q"),
        ])
        _ = submenu("File", [
            item("Open…", #selector(AppDelegate.openImage(_:)), "o"),
            item("Open Image from Clipboard", #selector(AppDelegate.pasteImage(_:)), "v", [.command, .shift]),
            .separator(),
            item("Save", #selector(EditorWindowController.saveImage(_:)), "s"),
            item("Save As…", #selector(EditorWindowController.saveImageAs(_:)), "s", [.command, .shift]),
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])
        // Return and Delete are handled by the canvas, so they get no key equivalents here
        // (that would steal them from the text field while a label is being typed).
        _ = submenu("Edit", [
            item("Undo", #selector(EditorWindowController.undoEdit(_:)), "z"),
            item("Redo", #selector(EditorWindowController.redoEdit(_:)), "z", [.command, .shift]),
            .separator(),
            item("Copy", #selector(EditorWindowController.copy(_:)), "c"),
            item("Delete", #selector(EditorWindowController.delete(_:))),
            .separator(),
            item("Crop to Selection", #selector(EditorWindowController.cropToSelection(_:))),
        ])
        _ = submenu("View", [
            item("Actual Size", #selector(EditorWindowController.zoomToActualSize(_:)), "0"),
            item("Zoom to Fit", #selector(EditorWindowController.zoomToFit(_:)), "1"),
            item("Zoom In", #selector(EditorWindowController.zoomIn(_:)), "="),
            item("Zoom Out", #selector(EditorWindowController.zoomOut(_:)), "-"),
        ])
        let window = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
        ])
        NSApp.windowsMenu = window
        return main
    }
}
