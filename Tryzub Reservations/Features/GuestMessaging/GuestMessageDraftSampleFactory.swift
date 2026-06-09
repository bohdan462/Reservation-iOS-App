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
        case largeParty
    }

    static func packet(for sample: Sample) -> GuestMessageDraftPacket {
        switch sample {
        case .confirmation:
            return basePacket(kind: .confirmation, firstName: "Olena", partySize: 4, tableName: "12")
        case .reminder:
            return basePacket(kind: .reminder, firstName: "Mark", partySize: 2, tableName: nil)
        case .tableReady:
            return basePacket(kind: .tableReady, firstName: "Iryna", partySize: 3, tableName: "7")
        case .largeParty:
            return basePacket(kind: .largePartyConfirmation, firstName: "Alex", partySize: 10, tableName: nil)
        }
    }

    static func fencedJSONResponse(for sample: Sample) -> String {
        let template = GuestMessageDraftTemplateWriter.draft(from: packet(for: sample))
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
