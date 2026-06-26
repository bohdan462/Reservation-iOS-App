//
//  AttachmentSignalAnalyzer.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 9 (Attachment OCR / Image Intelligence).
//
//  PURE + DETERMINISTIC. No network, no model. Converts an attachment label and
//  (optionally) OCR-extracted text into typed ReservationSignals.
//
//  Two signal sources:
//  1. Label-based (immediate, no OCR): fires as soon as an attachment is saved.
//     Source: .attachment. Confidence: .medium.
//  2. OCR-based (additive, after Vision runs): enriches the label signal with
//     evidence from actual image text. Source: .attachmentOCR. Confidence: .medium.
//     OCR signals are deduplicated against label signals by type.
//
//  Language rules:
//  - Never say "deposit paid" — only "deposit mentioned / verify before service."
//  - Never say "allergy confirmed" — only "dietary note in photo — verify."
//  - Staff confirms everything. No auto-complete = true signals here.
//

import Foundation

enum AttachmentSignalAnalyzer {

    struct Input {
        let reservationID: String
        let attachmentID: String
        let label: AttachmentLabel
        /// OCR result from AttachmentOCRService. Nil when OCR has not run yet.
        let extractedText: String?
    }

    /// Returns signals for this attachment. Always safe to call — returns [] if nothing found.
    static func analyze(_ input: Input) -> [ReservationSignal] {
        var signals: [ReservationSignal] = []

        // 1. Label-based signal: fires immediately on attachment save.
        if let labelSignal = labelSignal(for: input) {
            signals.append(labelSignal)
        }

        // 2. OCR-based signals: additive once extractedText is populated.
        if let text = input.extractedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let ocrSignals = ocrSignals(from: text, input: input)
            // Deduplicate by type — label signal takes precedence.
            let existingTypes = Set(signals.map { $0.type })
            signals.append(contentsOf: ocrSignals.filter { !existingTypes.contains($0.type) })
        }

        return signals
    }

    // MARK: - Label-based signals

    private static func labelSignal(for input: Input) -> ReservationSignal? {
        switch input.label {
        case .deposit:
            return ReservationSignal(
                id: "att-label-\(input.attachmentID)-deposit",
                reservationID: input.reservationID,
                type: .depositMentioned,
                title: "Deposit photo attached",
                staffText: "Manager should verify deposit before service.",
                evidence: "Attachment labeled Deposit",
                confidence: .medium,
                source: .attachment,
                priority: .high
            )
        case .preorder:
            return ReservationSignal(
                id: "att-label-\(input.attachmentID)-preorder",
                reservationID: input.reservationID,
                type: .preorderMentioned,
                title: "Preorder photo attached",
                staffText: "Kitchen should review preorder before service.",
                evidence: "Attachment labeled Preorder",
                confidence: .medium,
                source: .attachment,
                priority: .high
            )
        case .banquet:
            return ReservationSignal(
                id: "att-label-\(input.attachmentID)-banquet",
                reservationID: input.reservationID,
                type: .banquetMentioned,
                title: "Banquet photo attached",
                staffText: "Kitchen and manager should review banquet details.",
                evidence: "Attachment labeled Banquet",
                confidence: .medium,
                source: .attachment,
                priority: .high
            )
        case .receipt:
            return ReservationSignal(
                id: "att-label-\(input.attachmentID)-receipt",
                reservationID: input.reservationID,
                type: .depositMentioned,
                title: "Receipt photo attached",
                staffText: "Manager should review receipt before service.",
                evidence: "Attachment labeled Receipt",
                confidence: .medium,
                source: .attachment,
                priority: .medium
            )
        case .setup:
            return ReservationSignal(
                id: "att-label-\(input.attachmentID)-setup",
                reservationID: input.reservationID,
                type: .setupNeeded,
                title: "Setup photo attached",
                staffText: "Check setup requirements before service.",
                evidence: "Attachment labeled Setup",
                confidence: .medium,
                source: .attachment,
                priority: .medium
            )
        case .guestScreenshot, .signedAgreement, .referenceImage, .other:
            return ReservationSignal(
                id: "att-label-\(input.attachmentID)-review",
                reservationID: input.reservationID,
                type: .attachmentNeedsReview,
                title: "Photo attached — review before service",
                staffText: "Check this photo before seating.",
                evidence: "Attachment labeled \(input.label.rawValue)",
                confidence: .low,
                source: .attachment,
                priority: .info
            )
        }
    }

    // MARK: - OCR-based signals

    /// Runs the same keyword scan as NoteSignalAnalyzer on extracted text,
    /// remapping the source to .attachmentOCR and appending "(from photo)" to staffText.
    private static func ocrSignals(from text: String, input: Input) -> [ReservationSignal] {
        let noteInput = NoteSignalAnalyzer.Input(
            reservationID: input.reservationID,
            guestNote: nil,
            staffNote: text
        )
        return NoteSignalAnalyzer.analyze(noteInput).map { signal in
            ReservationSignal(
                id: "att-ocr-\(input.attachmentID)-\(signal.type.rawValue)",
                reservationID: signal.reservationID,
                type: signal.type,
                title: signal.title,
                staffText: signal.staffText + " (from photo)",
                evidence: signal.evidence,
                confidence: .medium,
                source: .attachmentOCR,
                requiresReview: true,
                priority: signal.priority
            )
        }
    }
}
