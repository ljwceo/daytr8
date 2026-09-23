import Foundation
import CoreGraphics
import ImageIO
import Vision

/// Leest tekstregels uit een afbeelding. Protocol zodat het tradeformulier
/// in tests een nep-herkenner kan krijgen.
public protocol ScreenshotTextRecognizing: Sendable {
    /// Tekstregels van boven naar beneden; woorden op dezelfde hoogte staan
    /// op één regel (van links naar rechts).
    func recognizeLines(in imageData: Data) async throws -> [String]
}

public enum ScreenshotOCRError: Error, Equatable {
    case unreadableImage
}

/// On-device OCR met Apple Vision (`VNRecognizeTextRequest`). Volledig
/// offline: geen netwerk, geen externe dependencies.
public struct VisionTextRecognizer: ScreenshotTextRecognizing {

    public init() {}

    public func recognizeLines(in imageData: Data) async throws -> [String] {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ScreenshotOCRError.unreadableImage
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up

        return try await withCheckedThrowingContinuation { continuation in
            // Vision is synchroon en zwaar: niet op de main thread.
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let boxes = try Self.recognize(image, orientation: orientation)
                    continuation.resume(returning: ScreenshotLineBuilder.lines(from: boxes))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> [RecognizedTextBox] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Taalcorrectie "verbetert" tickers en getallen tot woorden; uit.
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedTextBox(text: candidate.string, boundingBox: observation.boundingBox)
        }
    }
}

/// Eén door Vision herkend tekstblok. `boundingBox` is genormaliseerd (0...1)
/// met de oorsprong linksonder, zoals Vision hem levert.
public struct RecognizedTextBox: Equatable, Sendable {
    public var text: String
    public var boundingBox: CGRect

    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

/// Zet losse Vision-tekstblokken om naar leesbare regels.
///
/// Vision levert "Entry Price" en "21,450.25" vaak als aparte blokken. Door
/// blokken op dezelfde hoogte samen te voegen ("Entry Price  21,450.25")
/// kunnen de template-regexen label en waarde samen matchen.
public enum ScreenshotLineBuilder {

    /// Scheiding tussen blokken op dezelfde regel.
    public static let columnSeparator = "  "

    public static func lines(from boxes: [RecognizedTextBox]) -> [String] {
        let sorted = boxes
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        var rows: [[RecognizedTextBox]] = []
        for box in sorted {
            if let anchor = rows.last?.first,
               abs(anchor.boundingBox.midY - box.boundingBox.midY) < min(anchor.boundingBox.height, box.boundingBox.height) * 0.5 {
                rows[rows.count - 1].append(box)
            } else {
                rows.append([box])
            }
        }

        return rows.map { row in
            row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                .map { $0.text.trimmingCharacters(in: .whitespaces) }
                .joined(separator: columnSeparator)
        }
    }
}
