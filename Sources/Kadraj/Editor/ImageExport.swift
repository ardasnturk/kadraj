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

    /// Saves into the save folder in the preferred format, without overwriting existing files.
    static func quickSave(_ image: CGImage, pointScale: CGFloat) throws -> URL {
        let format = Settings.imageFormat
        guard let data = data(image, type: format.type, pointScale: pointScale) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let folder = Settings.saveDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = uniqueURL(in: folder, base: "Kadraj \(timestamp())", fileExtension: format.fileExtension)
        try data.write(to: url)
        return url
    }

    /// Writes a PNG to a temporary folder, for dragging into other apps.
    static func temporaryFile(_ image: CGImage, pointScale: CGFloat) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Kadraj", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
              let data = data(image, type: .png, pointScale: pointScale) else { return nil }
        let url = uniqueURL(in: folder, base: "Kadraj \(timestamp())", fileExtension: "png")
        return (try? data.write(to: url)) != nil ? url : nil
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: Date())
    }

    private static func uniqueURL(in folder: URL, base: String, fileExtension: String) -> URL {
        var url = folder.appendingPathComponent("\(base).\(fileExtension)")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) (\(counter)).\(fileExtension)")
            counter += 1
        }
        return url
    }

    static func copyString(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
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
