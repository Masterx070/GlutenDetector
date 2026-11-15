//
//  OCRService.swift
//  GlutenDetector
//
//  On-device text recognition using Apple's Vision framework.
//  English is always read; Arabic is added when this iPhone's iOS supports it.
//  Everything runs locally (no internet, no personal data leaves the phone),
//  which satisfies NFR5 (offline) and NFR7 (privacy) from the project report.
//

import UIKit
import Vision

/// What OCR gives back: the text plus how sure Vision is about it (0...1).
struct OCROutput {
    let text: String
    let averageConfidence: Float
    let arabicSupported: Bool     // false => this iOS version can't read Arabic
}

enum OCRError: Error {
    case invalidImage
    case failed(String)

    func message(_ lang: AppLanguage) -> String {
        switch self {
        case .invalidImage: return lang.t(.ocrInvalidImage)
        case .failed(let detail): return "\(lang.t(.ocrFailed)) \(detail)"
        }
    }
}

enum OCRService {

    /// Reads all printed text from `image`. Runs off the main thread.
    static func recognizeText(in image: UIImage, preferArabic: Bool) async throws -> OCROutput {
        guard let cgImage = image.cgImage else { throw OCRError.invalidImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate        // slower but far better on small print
            request.usesLanguageCorrection = true

            // Ask Vision which languages THIS iOS version can read.
            var languages = ["en-US"]
            var arabicSupported = false
            if let supported = try? request.supportedRecognitionLanguages(),
               let arabic = supported.first(where: { $0.hasPrefix("ar") }) {
                arabicSupported = true
                languages = preferArabic ? [arabic, "en-US"] : ["en-US", arabic]
            }
            request.recognitionLanguages = languages
            // Helps Vision with unusual words like "semolina" or "triticale".
            request.customWords = GlutenKeywords.singleWords

            let handler = VNImageRequestHandler(cgImage: cgImage,
                                                orientation: orientation,
                                                options: [:])
            do {
                try handler.perform([request])
            } catch {
                throw OCRError.failed(error.localizedDescription)
            }

            let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
            let text = candidates.map(\.string).joined(separator: "\n")
            let confidence = candidates.isEmpty
                ? 0
                : candidates.map(\.confidence).reduce(0, +) / Float(candidates.count)

            return OCROutput(text: text, averageConfidence: confidence, arabicSupported: arabicSupported)
        }.value
    }
}

// Photos taken with the camera are often stored "rotated"; Vision needs to be told.
extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
