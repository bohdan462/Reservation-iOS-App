//
//  GuestMessageDraftPacketBuilder.swift
//  Tryzub Reservations
//

import Foundation

enum GuestMessageDraftPacketBuilder {
    /// Matches common large-party handling in staff workflows (see also Host `largePartyThreshold` default 7).
    static let largePartyMinimumPartySize = 7

    static let excludedFieldMarkers = [
        "raw_email",
        "raw_phone",
        "guest_notes",
        "staff_notes",
        "backend_evidence",
    ]

    static func build(
        kind: GuestMessageDraftKind,
        reservation: ReservationRecord,
        restaurantProfile: ReservationEmailRestaurantProfile = .workflowDefault,
        manageURL: String? = nil,
        tone: GuestMessageTone = .warmProfessional,
        language: GuestMessageLanguage = .english
    ) -> GuestMessageDraftPacket {
        GuestMessageDraftPacket(
            version: GuestMessageDraftPacket.currentVersion,
            kind: kind,
            createdAt: Date(),
            restaurantName: restaurantProfile.name,
            restaurantPhone: restaurantProfile.phone,
            restaurantAddress: restaurantProfile.address,
            reservationManageURL: sanitizedOptional(manageURL),
            guestFirstName: guestFirstName(from: reservation.guestName),
            reservationDateDisplay: ManualEmailDraftService.emailDateLine(for: reservation),
            reservationTimeDisplay: ManualEmailDraftService.emailTimeLine(for: reservation),
            partySize: max(reservation.partySize, 1),
            tableName: sanitizedOptional(reservation.tableName),
            isLargeParty: reservation.partySize >= largePartyMinimumPartySize,
            hasSpecialOccasionFlag: false,
            hasSeatingPreferenceFlag: false,
            hasAllergyOrAccessibilityFlag: false,
            needsReview: reservation.statusValue == .needsReview,
            tone: tone,
            language: language,
            policyHints: policyHints(for: kind),
            blockedFields: excludedFieldMarkers
        )
    }

    // MARK: - Private

    private static func guestFirstName(from guestName: String) -> String? {
        let trimmed = guestName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let first = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        return first.isEmpty ? nil : first
    }

    private static func sanitizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func policyHints(for kind: GuestMessageDraftKind) -> [String] {
        var hints = [
            "Staff sends the message manually after review.",
            "Do not state that the message was already sent.",
            "Reservation policies: \(ReservationEmailWorkflow.reservationPoliciesURL.absoluteString)",
        ]

        switch kind {
        case .confirmation:
            hints.append("Guest may view or manage the reservation using the private link when provided.")
        case .reminder:
            hints.append("Friendly reminder only; do not change reservation status.")
        case .clarificationRequest:
            hints.append("Ask for missing details only; do not invent answers.")
        case .largePartyConfirmation:
            hints.append("Ask guest to confirm party size and arrival time.")
        case .tableReady:
            hints.append("Table-ready notice only; guest should check in with the host.")
        }

        return hints
    }
}
