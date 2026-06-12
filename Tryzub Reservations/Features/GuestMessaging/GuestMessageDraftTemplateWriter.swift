//
//  GuestMessageDraftTemplateWriter.swift
//  Tryzub Reservations
//

import Foundation

enum GuestMessageDraftTemplateWriter {

    static func draft(from packet: GuestMessageDraftPacket) -> GuestMessageDraft {
        switch packet.kind {
        case .confirmation:
            return confirmationDraft(from: packet)
        case .reminder:
            return reminderDraft(from: packet)
        case .clarificationRequest:
            return clarificationDraft(from: packet)
        case .largePartyConfirmation:
            return largePartyDraft(from: packet)
        case .tableReady:
            return tableReadyDraft(from: packet)
        }
    }

    // MARK: - Kinds

    private static func confirmationDraft(from packet: GuestMessageDraftPacket) -> GuestMessageDraft {
        let greeting = greetingLine(for: packet)
        let restaurant = packet.restaurantName
        let manage = manageURLLine(for: packet)

        let subject = "Reservation confirmation — \(restaurant)"
        let body = """
        \(greeting)

        Your reservation for party of \(packet.partySize) on \(packet.reservationDateDisplay) at \(packet.reservationTimeDisplay) is confirmed.\(tableLine(for: packet))
        \(manage)

        We look forward to welcoming you to \(restaurant).
        \(contactFooter(for: packet))
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        let sms = compactSMS(
            for: packet,
            core: "your \(restaurant) reservation for party of \(packet.partySize) on \(packet.reservationDateDisplay) at \(packet.reservationTimeDisplay) is confirmed."
        )

        return GuestMessageDraft(
            emailSubject: subject,
            emailBody: body,
            shortMessageBody: sms,
            safetyNote: nil,
            blockedReason: nil,
            source: .template
        )
    }

    private static func reminderDraft(from packet: GuestMessageDraftPacket) -> GuestMessageDraft {
        let greeting = greetingLine(for: packet)
        let restaurant = packet.restaurantName
        let subject = "Reminder — your reservation at \(restaurant)"
        let body = """
        \(greeting)

        This is a friendly reminder about your reservation for party of \(packet.partySize) on \(packet.reservationDateDisplay) at \(packet.reservationTimeDisplay).\(tableLine(for: packet))
        \(manageURLLine(for: packet))

        If your plans have changed, please contact us as soon as you can.
        \(contactFooter(for: packet))
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        let sms = compactSMS(
            for: packet,
            core: "friendly reminder: your \(restaurant) reservation is \(packet.reservationDateDisplay) at \(packet.reservationTimeDisplay) for party of \(packet.partySize)."
        )

        return GuestMessageDraft(
            emailSubject: subject,
            emailBody: body,
            shortMessageBody: sms,
            safetyNote: nil,
            blockedReason: nil,
            source: .template
        )
    }

    private static func clarificationDraft(from packet: GuestMessageDraftPacket) -> GuestMessageDraft {
        let greeting = greetingLine(for: packet)
        let restaurant = packet.restaurantName
        let subject = "Quick question about your reservation — \(restaurant)"
        let body = """
        \(greeting)

        We are preparing for your reservation on \(packet.reservationDateDisplay) at \(packet.reservationTimeDisplay) for party of \(packet.partySize).

        Could you please confirm your party size and arrival time, or let us know if any details have changed?
        \(contactFooter(for: packet))
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        let sms = compactSMS(
            for: packet,
            core: "could you confirm your party size and arrival time for your \(restaurant) reservation on \(packet.reservationDateDisplay) at \(packet.reservationTimeDisplay)?"
        )

        return GuestMessageDraft(
            emailSubject: subject,
            emailBody: body,
            shortMessageBody: sms,
            safetyNote: nil,
            blockedReason: nil,
            source: .template
        )
    }

    private static func largePartyDraft(from packet: GuestMessageDraftPacket) -> GuestMessageDraft {
        let greeting = greetingLine(for: packet)
        let restaurant = packet.restaurantName
        let subject = "Please confirm your large party — \(restaurant)"
        let body = """
        \(greeting)

        Thank you for your reservation request for party of \(packet.partySize) on \(packet.reservationDateDisplay) at \(packet.reservationTimeDisplay).

        Could you please confirm your final party size and arrival time so we can plan seating accordingly?
        \(contactFooter(for: packet))
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        let sms = compactSMS(
            for: packet,
            core: "please confirm party size and arrival time for your party of \(packet.partySize) at \(restaurant) on \(packet.reservationDateDisplay) at \(packet.reservationTimeDisplay)."
        )

        return GuestMessageDraft(
            emailSubject: subject,
            emailBody: body,
            shortMessageBody: sms,
            safetyNote: nil,
            blockedReason: nil,
            source: .template
        )
    }

    private static func tableReadyDraft(from packet: GuestMessageDraftPacket) -> GuestMessageDraft {
        let greeting = greetingLine(for: packet)
        let restaurant = packet.restaurantName
        let tablePart = packet.tableName.map { " Table \($0) is ready." } ?? " Your table is ready."
        let subject = "Your table is ready — \(restaurant)"
        let body = """
        \(greeting)

        \(tablePart.trimmingCharacters(in: .whitespacesAndNewlines)) Please check in with the host when you arrive.
        \(contactFooter(for: packet))
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        let tableSMS = packet.tableName.map { "table \($0) is ready" } ?? "your table is ready"
        let sms = compactSMS(
            for: packet,
            core: "\(tableSMS) at \(restaurant). Please check in with the host."
        )

        return GuestMessageDraft(
            emailSubject: subject,
            emailBody: body,
            shortMessageBody: sms,
            safetyNote: nil,
            blockedReason: nil,
            source: .template
        )
    }

    // MARK: - Helpers

    private static func greetingLine(for packet: GuestMessageDraftPacket) -> String {
        if let firstName = packet.guestFirstName {
            return "Hi \(firstName),"
        }
        return "Hi,"
    }

    private static func reservationDetailLine(for packet: GuestMessageDraftPacket) -> String {
        "\(packet.reservationDateDisplay) at \(packet.reservationTimeDisplay)"
    }

    private static func tableLine(for packet: GuestMessageDraftPacket) -> String {
        guard let table = packet.tableName else { return "" }
        return " Table: \(table)."
    }

    private static func manageURLLine(for packet: GuestMessageDraftPacket) -> String {
        guard let url = packet.reservationManageURL else { return "" }
        return "\n\nView or manage your reservation:\n\(url)"
    }

    private static func contactFooter(for packet: GuestMessageDraftPacket) -> String {
        var lines: [String] = []
        if let address = packet.restaurantAddress, !address.isEmpty {
            lines.append(address)
        }
        if let phone = packet.restaurantPhone, !phone.isEmpty {
            lines.append(phone)
        }
        return lines.joined(separator: "\n")
    }

    private static func compactSMS(for packet: GuestMessageDraftPacket, core: String) -> String {
        let prefix = packet.guestFirstName.map { "Hi \($0), " } ?? "Hi, "
        var message = prefix + core.prefix(1).uppercased() + core.dropFirst()
        if let phone = packet.restaurantPhone, !phone.isEmpty, message.count < 260 {
            message += " Questions? \(phone)"
        }
        return String(message.prefix(GuestMessageDraftValidator.maximumShortMessageLength))
    }
}
