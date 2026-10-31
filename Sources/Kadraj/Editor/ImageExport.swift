import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageExport {
    /// Encodes `image`, tagging it with a DPI that matches `pointScale` so Retina captures keep their size.
    static func data(_ image: CGImage, type: UTType, pointScale: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil)
        else { return nil }
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: 72 * pointScale,
            kCGImagePropertyDPIHeight: 72 * pointScale,
        ]
        if type == .jpeg { properties[kCGImageDestinationLossyCompressionQuality] = 0.9 }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func copyToPasteboard(_ image: CGImage, pointScale: CGFloat) -> Bool {
        guard let png = data(image, type: .png, pointScale: pointScale) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setData(png, forType: .png)
    }

    /// - Returns: The image and its pixels-per-point scale, read from the file's DPI.
    static func loadImage(at url: URL) -> (CGImage, CGFloat)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = (properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        return (image, max(1, (dpi / 72).rounded()))
    }

    static func imageFromPasteboard() -> (CGImage, CGFloat)? {
        guard let image = NSImage(pasteboard: .general) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return (cgImage, max(1, (CGFloat(cgImage.width) / max(image.size.width, 1)).rounded()))
    }
}
