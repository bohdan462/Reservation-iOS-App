//
//  AttachmentOCRService.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 9 (Attachment OCR / Image Intelligence).
//
//  Pure async helper. Loads a saved attachment image from disk and runs
//  Apple Vision text recognition on it. No network. No PII leaves the device.
//
//  Called from ReservationDetailView after a photo is saved. Result is stored
//  in ReservationAttachmentRecord.extractedText so OCR only runs once per image.
//
//  Feature gate: AttachmentFeatureFlag.ocrEnabled
//

import Foundation
import Vision
import UIKit

enum AttachmentOCRService {

    /// Extracts text from a saved attachment image. Returns nil if the image
    /// cannot be loaded, Vision fails, or the result is empty.
    ///
    /// Safe to call from a `Task.detached` — does no main-actor work.
    static func extractText(filename: String) async -> String? {
        await Task.detached(priority: .utility) {
            let url = AttachmentFileStore.attachmentsDirectory
                .appendingPathComponent(filename)
            guard let data = try? Data(contentsOf: url),
                  let uiImage = UIImage(data: data),
                  let cgImage = uiImage.cgImage else { return nil }

            var recognizedLines: [String] = []
            let request = VNRecognizeTextRequest { req, _ in
                recognizedLines = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])

            let text = recognizedLines.joined(separator: "\n")
            return text.isEmpty ? nil : text
        }.value
    }
}
