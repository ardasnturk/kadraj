# Kadraj

A fast, native, open-source screenshot tool for macOS. Capture an area, a window or the whole screen, then crop with pixel precision and annotate before copying or saving.

*Kadraj* is Turkish for "frame" (as in framing a shot).

## Features

- **Capture** area (⌘⇧2), window (press Space in area mode), or full screen (⌘⇧1). The screen is frozen while you select.
- **Pixel-precise selection** with free zoom and pan. Arrow keys nudge the selection by 1 px (⇧ for 10 px), ⌘+arrows resize it, and Return crops.
- **Annotate** with arrows, rectangles, ovals, text labels, pixelation and numbered steps.
- **Copy** (⌘C) or **save** (⌘S) the result. When a selection is active, only the selection is exported. Retina captures keep their DPI.
- Undo and redo, launch at login, and a configurable save folder.
- Small, with no dependencies: Swift, AppKit and ScreenCaptureKit.

## Requirements

- macOS 14 Sonoma or later
- Xcode 16 or later (to build)

## Build

```bash
./scripts/build-app.sh
open build/Kadraj.app
```

The script builds a release binary with SwiftPM, wraps it in `build/Kadraj.app` and code-signs it. It uses your first *Apple Development* identity, or ad-hoc signing when you have none. Set `SIGN_IDENTITY` to choose an identity. A stable identity matters because macOS ties the Screen Recording permission to the signature. With ad-hoc signing you'll have to grant it again after every rebuild.

For development you can also open `Package.swift` in Xcode. To open an image straight in the editor, run:

```bash
build/Kadraj.app/Contents/MacOS/Kadraj --open path/to/image.png
```

On the first capture, macOS asks for **Screen Recording** permission. Grant it in System Settings › Privacy & Security › Screen & System Audio Recording.

## Shortcuts

| Where | Key | Action |
|---|---|---|
| Global | ⌘⇧2 | Capture area |
| Global | ⌘⇧1 | Capture full screen |
| Area capture | Space | Toggle window mode |
| Area capture | Return | Capture the whole display |
| Area capture | ⇧ while dragging | Square selection |
| Editor | V A R O T B N | Select/crop, arrow, rectangle, oval, text, pixelate, step |
| Editor | B with a selection | Pixelate the selection |
| Editor | ← → ↑ ↓ (⇧, ⌘) | Nudge (10 px, resize) the selection or the selected object |
| Editor | Return / Esc | Crop / clear selection, then close |
| Editor | ⌘0 ⌘1 ⌘= ⌘- | Actual size, fit, zoom in, zoom out |
| Editor | Pinch, ⌘-scroll, mouse wheel | Zoom |
| Editor | Space-drag, right-drag, trackpad scroll | Pan |
| Editor | ⌘C ⌘S ⇧⌘S | Copy, save, save as |

## Project layout

```
Sources/Kadraj/
  App/       App delegate, menu bar item, global hot keys, permissions, settings
  Capture/   ScreenCaptureKit capture and the area/window selection overlay
  Editor/    Document model, renderer, canvas view and editor window
scripts/     build-app.sh
Resources/   Info.plist
```

## Roadmap

- [ ] OCR and QR code reading (Vision)
- [ ] Color picker, ruler and contrast checker
- [ ] Pin screenshots as floating windows
- [ ] Backdrop (gradient background, padding, rounded corners, shadow)
- [ ] Scrolling capture
- [ ] Magnifier loupe in area capture
- [ ] Customizable shortcuts and a preferences window
- [ ] Combine multiple captures and paste images as layers
- [ ] Localization
- [ ] Notarized releases and a Homebrew cask

## Contributing

Issues and pull requests are welcome. Please keep the app small and dependency-free, and match the style of the surrounding code.

## License

[MIT](LICENSE)
