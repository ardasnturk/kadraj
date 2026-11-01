import Vision

/// Reads QR/bar codes and text from an image with the Vision framework, on device.
enum TextRecognizer {
    enum Result {
        case text(String, lineCount: Int)
        case code(String)
        case nothing
    }

    static func recognize(_ image: CGImage) async -> Result {
        await Task.detached(priority: .userInitiated) { () -> Result in
            let barcodes = VNDetectBarcodesRequest()
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .accurate
            text.usesLanguageCorrection = true
            text.automaticallyDetectsLanguage = true
            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([barcodes, text])
            } catch {
                return .nothing
            }
            if let payload = barcodes.results?.compactMap(\.payloadStringValue).first {
                return .code(payload)
            }
            let lines = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.isEmpty ? .nothing : .text(lines.joined(separator: "\n"), lineCount: lines.count)
        }.value
    }
}
