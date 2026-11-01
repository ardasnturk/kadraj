import AppKit
import ScreenCaptureKit

/// A frozen capture of one display.
struct DisplayShot {
    let screen: NSScreen
    let displayID: CGDirectDisplayID
    let image: CGImage
    /// The display's frame in global CoreGraphics coordinates (top-left origin).
    let globalFrame: CGRect

    /// Image pixels per screen point.
    var pointScale: CGFloat { CGFloat(image.width) / screen.frame.width }

    /// Cuts out `rect`, given in points relative to the display's top-left corner.
    func crop(_ rect: CGRect) -> CGImage? {
        let s = pointScale
        return image.cropping(to: CGRect(x: rect.minX * s, y: rect.minY * s,
                                         width: rect.width * s, height: rect.height * s).integral)
    }

    /// Converts a display-local, top-left-origin rect into Cocoa global coordinates.
    func screenRect(for rect: CGRect) -> CGRect {
        CGRect(x: screen.frame.minX + rect.minX, y: screen.frame.maxY - rect.maxY,
               width: rect.width, height: rect.height)
    }
}

struct CapturableWindow {
    let scWindow: SCWindow
    /// Window frame in global CoreGraphics coordinates (top-left origin).
    var frame: CGRect { scWindow.frame }

    /// Window frame in Cocoa global coordinates (bottom-left origin).
    @MainActor
    var screenRect: CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}

enum ScreenCapturer {
    private static var ownPID: pid_t { ProcessInfo.processInfo.processIdentifier }

    static func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// Captures every connected display at native resolution, leaving out Kadraj's own windows.
    static func captureDisplays(_ content: SCShareableContent) async throws -> [DisplayShot] {
        let ownApps = content.applications.filter { $0.processID == ownPID }
        var shots: [DisplayShot] = []
        for screen in NSScreen.screens {
            guard let id = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration(for: filter))
            shots.append(DisplayShot(screen: screen, displayID: id, image: image, globalFrame: CGDisplayBounds(id)))
        }
        return shots
    }

    /// Captures a single window on its own, even if other windows cover it.
    /// - Returns: The image and its pixels-per-point scale.
    static func capture(_ window: CapturableWindow) async throws -> (CGImage, CGFloat) {
        let filter = SCContentFilter(desktopIndependentWindow: window.scWindow)
        let config = configuration(for: filter)
        config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (image, CGFloat(filter.pointPixelScale))
    }

    /// Normal app windows on screen, front-most first.
    static func windows(_ content: SCShareableContent) -> [CapturableWindow] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let order = info.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

        return content.windows
            .filter {
                $0.isOnScreen && $0.windowLayer == 0
                    && $0.frame.width >= 40 && $0.frame.height >= 40
                    && $0.owningApplication.map { $0.processID != ownPID } ?? false
            }
            .sorted { (rank[$0.windowID] ?? .max) < (rank[$1.windowID] ?? .max) }
            .map(CapturableWindow.init)
    }

    private static func configuration(for filter: SCContentFilter) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int((filter.contentRect.width * scale).rounded())
        config.height = Int((filter.contentRect.height * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        return config
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
