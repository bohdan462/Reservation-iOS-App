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
//  Remote attachment endpoints are staff-authenticated under:
//    /wp-json/tryzub/v1/managed-reservations/{id}/attachments
//  Slice C adds DTO/API/cache foundations only; UI remains local-first until Slice D.
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
    case signedAgreement = "Signed agreement"
    case referenceImage  = "Reference image"
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
        case .signedAgreement: return "signature"
        case .referenceImage:  return "photo"
        case .other:           return "paperclip"
        }
    }

    var backendValue: String {
        switch self {
        case .deposit:         return "deposit"
        case .preorder:        return "preorder"
        case .banquet:         return "banquet"
        case .guestScreenshot: return "guest_screenshot"
        case .receipt:         return "receipt"
        case .setup:           return "setup_photo"
        case .signedAgreement: return "signed_agreement"
        case .referenceImage:  return "reference_image"
        case .other:           return "other"
        }
    }

    init(backendValue: String?) {
        switch backendValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "deposit": self = .deposit
        case "preorder": self = .preorder
        case "banquet": self = .banquet
        case "guest_screenshot": self = .guestScreenshot
        case "receipt": self = .receipt
        case "setup_photo", "setup": self = .setup
        case "signed_agreement": self = .signedAgreement
        case "reference_image": self = .referenceImage
        default: self = .other
        }
    }

    /// Brief staff instruction displayed alongside the attachment.
    var reviewInstruction: String {
        switch self {
        case .deposit:         return "Manager should verify deposit."
        case .preorder:        return "Kitchen should review preorder."
        case .banquet:         return "Kitchen should review group details."
        case .guestScreenshot: return "Check guest screenshot."
        case .receipt:         return "Review receipt."
        case .setup:           return "Check setup requirements."
        case .signedAgreement: return "Review signed agreement."
        case .referenceImage:  return "Review reference image."
        case .other:           return "Review attachment."
        }
    }
}

/// Controls whether attachment upload/photo picker is active.
/// Local storage is ready. Backend upload endpoint is not yet live.
enum AttachmentFeatureFlag {
    /// Local device storage: always true — images are stored in Application Support.
    static let localStorageEnabled: Bool = true

    /// Remote upload to backend: false until Slice D wires the Reservation Detail UI.
    static let remoteUploadEnabled: Bool = false

    /// Apple Vision OCR text extraction from attached images.
    /// Safe to enable — runs on-device, no network, no PII leaves the device.
    static let ocrEnabled: Bool = true
}
