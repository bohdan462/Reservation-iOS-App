//
//  GuestMessageDraftPromptBuilder.swift
//  Tryzub Reservations
//

import Foundation

enum GuestMessageDraftPromptBuilder {

    static func buildPrompt(from packet: GuestMessageDraftPacket) -> String {
        let packetJSON = serializePacket(packet)

        return """
        You write guest communication drafts for restaurant staff review only.
        Return a single JSON object only. No markdown fences. No commentary.

        Required JSON keys:
        - emailSubject (string)
        - emailBody (string, plain text, short paragraphs)
        - shortMessageBody (string, SMS/iMessage length)
        - safetyNote (string or null)
        - blockedReason (string or null)

        Rules:
        - Use only the allowlisted packet fields below.
        - If information is missing, use a neutral phrase or leave it out. Do not invent.
        - Do not invent restaurant policy, deposits, or payment requirements unless listed in policyHints.
        - Do not mention internal notes, staff notes, backend systems, or evidence.
        - Do not say the message was sent or that the reservation status changed.
        - Do not say the reservation is confirmed unless kind is "confirmation".
        - For kind "cancellation": you may say the reservation has been cancelled and should include the booking link.
        - Do not include guest email or guest phone numbers. Restaurant contact details provided in the packet (phone, address, manage URL) may be included when useful. Do not invent any contact details.
        - For kind "tableReady" (staff-triggered): you may say the table is ready; do not invent a table number if tableName is missing.
        - For other kinds: do not say the table is ready.
        - Do not include raw guest notes.
        - Occasion wording may use only occasion, hasDietaryFlag, and hasAccessibilityFlag.
        - Never say "your birthday", "VIP", "regular", "always", "never", "cake", "discount", "decorations", "prepared something special", or "we will make it special".
        - Write in \(packet.language.rawValue) with a \(packet.tone.rawValue) tone.
        - shortMessageBody must be at most \(GuestMessageDraftValidator.maximumShortMessageLength) characters.

        Forbidden:
        - Claiming the message was already sent
        - Cancelling, seating, or confirming on behalf of the restaurant without matching kind
        - Exposing hidden or blocked fields

        Allowlisted packet JSON:
        \(packetJSON)

        Write the JSON draft now:
        """
    }

    // MARK: - Private

    private static func serializePacket(_ packet: GuestMessageDraftPacket) -> String {
        let payload = PromptPacket(
            version: packet.version,
            kind: packet.kind.rawValue,
            restaurantName: packet.restaurantName,
            restaurantPhone: packet.restaurantPhone,
            restaurantAddress: packet.restaurantAddress,
            reservationManageURL: packet.reservationManageURL,
            guestFirstName: packet.guestFirstName,
            reservationDateDisplay: packet.reservationDateDisplay,
            reservationTimeDisplay: packet.reservationTimeDisplay,
            partySize: packet.partySize,
            tableName: packet.tableName,
            isLargeParty: packet.isLargeParty,
            hasSpecialOccasionFlag: packet.hasSpecialOccasionFlag,
            occasion: packet.occasion.rawValue,
            hasBirthdayFlag: packet.hasBirthdayFlag,
            hasAnniversaryFlag: packet.hasAnniversaryFlag,
            hasCelebrationFlag: packet.hasCelebrationFlag,
            hasDietaryFlag: packet.hasDietaryFlag,
            hasAccessibilityFlag: packet.hasAccessibilityFlag,
            hasSeatingPreferenceFlag: packet.hasSeatingPreferenceFlag,
            hasAllergyOrAccessibilityFlag: packet.hasAllergyOrAccessibilityFlag,
            needsReview: packet.needsReview,
            tone: packet.tone.rawValue,
            language: packet.language.rawValue,
            policyHints: packet.policyHints
        )

        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private struct PromptPacket: Encodable {
        let version: String
        let kind: String
        let restaurantName: String
        let restaurantPhone: String?
        let restaurantAddress: String?
        let reservationManageURL: String?
        let guestFirstName: String?
        let reservationDateDisplay: String
        let reservationTimeDisplay: String
        let partySize: Int
        let tableName: String?
        let isLargeParty: Bool
        let hasSpecialOccasionFlag: Bool
        let occasion: String
        let hasBirthdayFlag: Bool
        let hasAnniversaryFlag: Bool
        let hasCelebrationFlag: Bool
        let hasDietaryFlag: Bool
        let hasAccessibilityFlag: Bool
        let hasSeatingPreferenceFlag: Bool
        let hasAllergyOrAccessibilityFlag: Bool
        let needsReview: Bool
        let tone: String
        let language: String
        let policyHints: [String]
    }
}
