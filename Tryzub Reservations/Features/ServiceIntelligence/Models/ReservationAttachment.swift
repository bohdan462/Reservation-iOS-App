//
//  ReservationAttachment.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 5 (Attachments MVP).
//
//  AttachmentLabel: staff-assigned category for an attachment.
//  AttachmentFeatureFlag: controls feature visibility.
//
//  The persistence model is ReservationAttachmentRecord (Persistence/ReservationAttachmentRecord.swift).
//  Images are stored as JPEG files via AttachmentFileStore (Persistence/AttachmentFileStore.swift).
//
//  BACKEND STATUS: No remote attachment endpoint exists.
//  Images are local-only. Backend endpoint needed before remote sync is possible.
//
//  Required future backend endpoints:
//    POST   /wp-json/tryzub/v1/reservation-attachments   (multipart upload)
//    GET    /wp-json/tryzub/v1/reservation-attachments?reservation_id={id}
//    DELETE /wp-json/tryzub/v1/reservation-attachments/{id}
//

import Foundation

/// Staff-assigned category for what the attachment represents.
enum AttachmentLabel: String, Codable, CaseIterable, Identifiable {
    case deposit         = "Deposit"
    case preorder        = "Preorder"
    case banquet         = "Banquet"
    case guestScreenshot = "Guest screenshot"
    case receipt         = "Receipt"
    case setup           = "Setup"
    case other           = "Other"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .deposit:         return "banknote"
        case .preorder:        return "cart"
        case .banquet:         return "fork.knife"
        case .guestScreenshot: return "person.crop.rectangle"
        case .receipt:         return "doc.text"
        case .setup:           return "checklist"
        case .other:           return "paperclip"
        }
    }

    /// Brief staff instruction displayed alongside the attachment.
    var reviewInstruction: String {
        switch self {
        case .deposit:         return "Manager should verify deposit."
        case .preorder:        return "Kitchen should review preorder."
        case .banquet:         return "Kitchen should review banquet details."
        case .guestScreenshot: return "Check guest screenshot."
        case .receipt:         return "Review receipt."
        case .setup:           return "Check setup requirements."
        case .other:           return "Review attachment."
        }
    }
}

/// Controls whether attachment upload/photo picker is active.
/// Local storage is ready. Backend upload endpoint is not yet live.
enum AttachmentFeatureFlag {
    /// Local device storage: always true — images are stored in Application Support.
    static let localStorageEnabled: Bool = true

    /// Remote upload to backend: false until the backend endpoint is confirmed.
    static let remoteUploadEnabled: Bool = false

    /// Apple Vision OCR text extraction from attached images.
    /// Safe to enable — runs on-device, no network, no PII leaves the device.
    static let ocrEnabled: Bool = true
}
