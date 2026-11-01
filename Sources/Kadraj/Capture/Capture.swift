import AppKit

/// A finished screenshot on its way to the preview, editor, pin or clipboard.
struct Capture {
    let image: CGImage
    /// Image pixels per screen point (2 on Retina displays).
    let pointScale: CGFloat
    /// Where the captured content sat on screen, in Cocoa global coordinates, when known.
    var screenRect: CGRect?

    var pointSize: CGSize {
        CGSize(width: CGFloat(image.width) / pointScale, height: CGFloat(image.height) / pointScale)
    }

    var nsImage: NSImage { NSImage(cgImage: image, size: pointSize) }
}

/// Actions that the preview, pins and editors hand back to the app.
@MainActor
protocol CaptureHandling: AnyObject {
    func edit(_ capture: Capture)
    func pin(_ capture: Capture)
    func recognizeText(in capture: Capture)
}

extension NSImage {
    /// A stretchable rounded-rectangle mask, e.g. for `NSVisualEffectView.maskImage`.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

extension NSScreen {
    /// The screen under the mouse pointer.
    static var current: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(mouse) } ?? main
    }
}
