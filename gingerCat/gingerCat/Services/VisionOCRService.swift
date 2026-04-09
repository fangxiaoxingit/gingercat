import Foundation
@preconcurrency import Vision
#if canImport(UIKit)
import UIKit
#endif

enum VisionOCRServiceError: Error {
    case invalidImage
    case noRecognizedText
}

struct OCRLineBox: Codable, Hashable {
    let text: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct OCRRecognitionResult: Hashable {
    let text: String
    let lineBoxes: [OCRLineBox]
}

#if canImport(UIKit)
enum VisionOCRService {
    static func recognizeText(from image: UIImage) async throws -> String {
        let result = try await recognize(from: image)
        return result.text
    }

    static func recognize(from image: UIImage) async throws -> OCRRecognitionResult {
        guard let cgImage = image.cgImage else {
            throw VisionOCRServiceError.invalidImage
        }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lineBoxes: [OCRLineBox] = observations.compactMap { (observation: VNRecognizedTextObservation) -> OCRLineBox? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard text.isEmpty == false else { return nil }
                    let box = observation.boundingBox
                    return OCRLineBox(
                        text: text,
                        x: box.origin.x,
                        y: box.origin.y,
                        width: box.width,
                        height: box.height
                    )
                }
                let normalized = lineBoxes
                    .map(\.text)
                    .joined(separator: "\n")

                guard normalized.isEmpty == false else {
                    continuation.resume(throwing: VisionOCRServiceError.noRecognizedText)
                    return
                }

                continuation.resume(
                    returning: OCRRecognitionResult(
                        text: normalized,
                        lineBoxes: lineBoxes
                    )
                )
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private extension CGImagePropertyOrientation {
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
#endif
