//
//  AttachmentOCRTrace.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 9 (Attachment OCR / Image Intelligence).
//
//  DEBUG-only structured traces for the attachment intelligence pipeline.
//  No raw image content, no raw OCR text — only counts, status tokens,
//  and signal types. No PII.
//

import Foundation
import OSLog

enum AttachmentOCRTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "AttachmentOCR"
    )

    /// Emitted when a new attachment is saved and queued for OCR.
    static func attached(reservationID: Int, filename: String, label: String) {
        guard isEnabled else { return }
        logger.debug(
            "[SERVICE_ATTACHMENT_TRACE] event=saved reservation=\(reservationID, privacy: .public) filename=\(filename, privacy: .public) label=\(label, privacy: .public)"
        )
    }

    /// Emitted when background OCR starts on an attachment image.
    static func ocrStarted(reservationID: Int, filename: String) {
        guard isEnabled else { return }
        logger.debug(
            "[SERVICE_ATTACHMENT_OCR_TRACE] event=started reservation=\(reservationID, privacy: .public) filename=\(filename, privacy: .public)"
        )
    }

    /// Emitted when OCR completes successfully.
    static func ocrCompleted(reservationID: Int, filename: String, textChars: Int, signalCount: Int) {
        guard isEnabled else { return }
        logger.debug(
            "[SERVICE_ATTACHMENT_OCR_TRACE] event=completed reservation=\(reservationID, privacy: .public) filename=\(filename, privacy: .public) textChars=\(textChars, privacy: .public) signals=\(signalCount, privacy: .public)"
        )
    }

    /// Emitted when OCR produces no text (blank image, handwriting too poor, etc.).
    static func ocrEmpty(reservationID: Int, filename: String) {
        guard isEnabled else { return }
        logger.debug(
            "[SERVICE_ATTACHMENT_OCR_TRACE] event=empty reservation=\(reservationID, privacy: .public) filename=\(filename, privacy: .public) result=no_text"
        )
    }

    /// Emitted when OCR fails (image unreadable or Vision error).
    static func ocrFailed(reservationID: Int, filename: String, reason: String) {
        guard isEnabled else { return }
        logger.debug(
            "[SERVICE_ATTACHMENT_OCR_TRACE] event=failed reservation=\(reservationID, privacy: .public) filename=\(filename, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    /// Emitted when an attachment's label generates an immediate signal (no OCR needed).
    static func labelSignal(reservationID: Int, attachmentID: String, signalType: String) {
        guard isEnabled else { return }
        logger.debug(
            "[SERVICE_ATTACHMENT_TRACE] event=label_signal reservation=\(reservationID, privacy: .public) attachment=\(attachmentID, privacy: .public) type=\(signalType, privacy: .public)"
        )
    }
}
