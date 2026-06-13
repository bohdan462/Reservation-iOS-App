//
//  GuestMessageDraftSampleFactory.swift
//  Tryzub Reservations
//
//  DEBUG-only fixtures for message draft diagnostics (no UI in Phase 4A).
//

import Foundation

#if DEBUG
enum GuestMessageDraftSampleFactory {

    enum Sample: String, CaseIterable {
        case confirmation
        case reminder
        case tableReady
        case tableReadyNoTable
        case largeParty
        case validWithRestaurantPhone
        case unsafeGuestPhone
        case unsafeGuestPhoneDashed
        case unsafeGuestPhoneParentheses
        case unsafeGuestPhoneInternational
    }

    enum FormattedGuestPhoneStyle: String, CaseIterable {
        case dashed = "513-555-0199"
        case parentheses = "(513) 555-0199"
        case international = "+1 513 555 0199"
        case dotted = "513.555.0199"
        case spaced = "513 555 0199"
    }

    static func packet(for sample: Sample) -> GuestMessageDraftPacket {
        switch sample {
        case .confirmation:
            return basePacket(kind: .confirmation, firstName: "Olena", partySize: 4, tableName: "12")
        case .reminder:
            return basePacket(kind: .reminder, firstName: "Mark", partySize: 2, tableName: nil)
        case .tableReady:
            return basePacket(kind: .tableReady, firstName: "Iryna", partySize: 3, tableName: "7")
        case .tableReadyNoTable:
            return basePacket(kind: .tableReady, firstName: "Iryna", partySize: 3, tableName: nil)
        case .largeParty:
            return basePacket(kind: .largePartyConfirmation, firstName: "Alex", partySize: 10, tableName: nil)
        case .validWithRestaurantPhone,
             .unsafeGuestPhone,
             .unsafeGuestPhoneDashed,
             .unsafeGuestPhoneParentheses,
             .unsafeGuestPhoneInternational:
            return basePacket(kind: .confirmation, firstName: "Olena", partySize: 4, tableName: nil)
        }
    }

    static func draft(for sample: Sample) -> GuestMessageDraft {
        switch sample {
        case .validWithRestaurantPhone:
            return draftIncludingRestaurantPhone(packet: packet(for: sample))
        case .unsafeGuestPhone:
            return unsafeDraftWithGuestPhone()
        case .unsafeGuestPhoneDashed:
            return unsafeDraftWithFormattedGuestPhone(.dashed)
        case .unsafeGuestPhoneParentheses:
            return unsafeDraftWithFormattedGuestPhone(.parentheses)
        case .unsafeGuestPhoneInternational:
            return unsafeDraftWithFormattedGuestPhone(.international)
        default:
            return GuestMessageDraftTemplateWriter.draft(from: packet(for: sample))
        }
    }

    static func validationResult(forFormattedGuestPhone style: FormattedGuestPhoneStyle) -> GuestMessageDraftValidationResult {
        let packet = packet(for: .confirmation)
        return GuestMessageDraftValidator.validate(
            unsafeDraftWithFormattedGuestPhone(style),
            packet: packet
        )
    }

    static func validationResult(for sample: Sample) -> GuestMessageDraftValidationResult {
        GuestMessageDraftValidator.validate(draft(for: sample), packet: packet(for: sample))
    }

    static func fencedJSONResponse(for sample: Sample) -> String {
        let template = draft(for: sample)
        let payload = """
        {
          "emailSubject": "\(escapeJSON(template.emailSubject))",
          "emailBody": "\(escapeJSON(template.emailBody))",
          "shortMessageBody": "\(escapeJSON(template.shortMessageBody))",
          "safetyNote": null,
          "blockedReason": null
        }
        """
        return "```json\n\(payload)\n```"
    }

    /// Template draft that includes the allowlisted restaurant phone (should validate).
    static func draftIncludingRestaurantPhone(packet: GuestMessageDraftPacket) -> GuestMessageDraft {
        let base = GuestMessageDraftTemplateWriter.draft(from: packet)
        guard let phone = packet.restaurantPhone, !phone.isEmpty else { return base }

        return GuestMessageDraft(
            emailSubject: base.emailSubject,
            emailBody: base.emailBody + "\n\nQuestions? \(phone)",
            shortMessageBody: base.shortMessageBody + " Questions? \(phone)",
            safetyNote: base.safetyNote,
            blockedReason: base.blockedReason,
            source: .template
        )
    }

    /// Draft with a guest phone number not in the packet (should fail validation).
    static func unsafeDraftWithGuestPhone() -> GuestMessageDraft {
        unsafeDraftWithFormattedGuestPhone(.dashed)
    }

    /// Draft with a formatted guest phone number not in the packet (should fail validation).
    static func unsafeDraftWithFormattedGuestPhone(_ style: FormattedGuestPhoneStyle) -> GuestMessageDraft {
        GuestMessageDraft(
            emailSubject: "Reservation follow-up",
            emailBody: "Please call us at \(style.rawValue) if your plans change.",
            shortMessageBody: "Questions? Call \(style.rawValue).",
            safetyNote: nil,
            blockedReason: nil,
            source: .localModel
        )
    }

    /// Draft with typical reservation date/time text (should not trip phone validation).
    static func safeDraftWithDateAndTime(packet: GuestMessageDraftPacket) -> GuestMessageDraft {
        GuestMessageDraft(
            emailSubject: "Reservation reminder",
            emailBody: """
            Hi \(packet.guestFirstName ?? "there"),

            Your reservation is on 2026-06-10 at 18:30 for party of \(packet.partySize).
            """,
            shortMessageBody: "Reminder: 2026-06-10 at 18:30, party of \(packet.partySize).",
            safetyNote: nil,
            blockedReason: nil,
            source: .template
        )
    }

    private static func basePacket(
        kind: GuestMessageDraftKind,
        firstName: String,
        partySize: Int,
        tableName: String?
    ) -> GuestMessageDraftPacket {
        GuestMessageDraftPacket(
            version: GuestMessageDraftPacket.currentVersion,
            kind: kind,
            createdAt: Date(),
            restaurantName: ReservationEmailWorkflow.restaurantName,
            restaurantPhone: ReservationEmailWorkflow.restaurantPhone,
            restaurantAddress: ReservationEmailWorkflow.restaurantAddressLine,
            reservationManageURL: "https://example.com/manage/sample",
            guestFirstName: firstName,
            reservationDateDisplay: "Friday, June 6, 2026",
            reservationTimeDisplay: "7:00 PM",
            partySize: partySize,
            tableName: tableName,
            isLargeParty: partySize >= GuestMessageDraftPacketBuilder.largePartyMinimumPartySize,
            hasSpecialOccasionFlag: false,
            occasion: .none,
            hasBirthdayFlag: false,
            hasAnniversaryFlag: false,
            hasCelebrationFlag: false,
            hasDietaryFlag: false,
            hasAccessibilityFlag: false,
            hasSeatingPreferenceFlag: false,
            hasAllergyOrAccessibilityFlag: false,
            needsReview: false,
            tone: .warmProfessional,
            language: .english,
            policyHints: [
                "Staff sends the message manually after review.",
                "Sample packet for diagnostics only.",
            ],
            blockedFields: GuestMessageDraftPacketBuilder.excludedFieldMarkers
        )
    }

    private static func escapeJSON(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
#endif
