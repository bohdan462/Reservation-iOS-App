//
//  GuestCommunicationTraces.swift
//  Tryzub Reservations
//
//  DEBUG traces for guest email templates and staff message review.
//

import Foundation

enum GuestCommunicationTrace {
    static func emailTemplate(
        type: GuestEmailTemplateKind,
        reservationID: Int,
        privateLink: Bool,
        rescheduleLink: Bool
    ) {
        #if DEBUG
        print(
            """
            [EMAIL_TEMPLATE_TRACE] type=\(type.rawValue) reservation=\(reservationID) fields=date,time,partySize,guestName privateLink=\(privateLink) rescheduleLink=\(rescheduleLink) internalFields=false
            """
        )
        #endif
    }

    static func emailPrivacy(
        reservationID: Int,
        type: GuestEmailTemplateKind,
        leakedInternalFields: Bool = false
    ) {
        #if DEBUG
        print(
            "[EMAIL_PRIVACY_TRACE] reservation=\(reservationID) type=\(type.rawValue) leakedInternalFields=\(leakedInternalFields)"
        )
        #endif
    }

    static func messageReview(
        reservationID: Int,
        type: String,
        phase: String,
        aiDraft: Bool? = nil,
        edited: Bool? = nil
    ) {
        #if DEBUG
        var parts = [
            "[GUEST_MESSAGE_REVIEW_TRACE]",
            "reservation=\(reservationID)",
            "type=\(type)",
            "phase=\(phase)"
        ]
        if let aiDraft {
            parts.append("aiDraft=\(aiDraft)")
        }
        if let edited {
            parts.append("edited=\(edited)")
        }
        print(parts.joined(separator: " "))
        #endif
    }

    static func manualEmailLogSkipped(
        reservationID: Int,
        type: GuestEmailTemplateKind,
        reason: String = "unsupported_email_type"
    ) {
        #if DEBUG
        print(
            "[MANUAL_EMAIL_LOG_TRACE] reservation=\(reservationID) skipped=true reason=\(reason) type=\(type.rawValue)"
        )
        #endif
    }
}
