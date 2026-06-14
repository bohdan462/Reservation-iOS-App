//
//  GuestEmailTemplateRenderer.swift
//  Tryzub Reservations
//
//  Shared styled HTML for guest-facing reservation emails.
//  Privacy: only guest name, date, time, party size, restaurant contact, and approved links.
//

import Foundation

// MARK: - Kind

enum GuestEmailTemplateKind: String, Equatable {
    case confirmation
    case reminder
    case manualQuestion
    case custom

    var headerTitle: String {
        switch self {
        case .confirmation:
            return "Reservation Confirmed"
        case .reminder:
            return "Reservation Reminder"
        case .manualQuestion, .custom:
            return "Message from Tryzub Ukrainian Kitchen"
        }
    }

    var defaultSubject: String {
        switch self {
        case .confirmation:
            return "Your Tryzub reservation is confirmed"
        case .reminder:
            return "Reminder: your Tryzub reservation today"
        case .manualQuestion, .custom:
            return "Message from \(ReservationEmailWorkflow.restaurantName)"
        }
    }

    /// Backend `manual-email-log` supports only confirmation and reminder.
    var backendLogEmailType: ReservationManualEmailLogEmailType? {
        switch self {
        case .confirmation:
            return .confirmation
        case .reminder:
            return .reminder
        case .manualQuestion, .custom:
            return nil
        }
    }
}

// MARK: - Input

struct GuestEmailRenderInput: Equatable {
    let kind: GuestEmailTemplateKind
    let reservationID: Int
    let guestFirstName: String
    let dateLine: String
    let timeLine: String
    let partySize: Int
    let manageLinkURL: String?
    let linkExpiresAt: String?
    /// Staff-approved plain text for manual/custom intros. Never guest or staff notes.
    let customPlainMessage: String?
    let subjectOverride: String?

    static func confirmation(
        reservation: ReservationRecord,
        manageLink: ReservationGuestManageLinkDTO
    ) -> GuestEmailRenderInput {
        base(reservation: reservation, kind: .confirmation, manageLinkURL: manageLink.url, linkExpiresAt: manageLink.expiresAt)
    }

    static func reminder(
        reservation: ReservationRecord,
        manageLinkURL: String?,
        linkExpiresAt: String? = nil
    ) -> GuestEmailRenderInput {
        base(reservation: reservation, kind: .reminder, manageLinkURL: manageLinkURL, linkExpiresAt: linkExpiresAt)
    }

    static func manual(
        reservation: ReservationRecord,
        customPlainMessage: String,
        manageLinkURL: String? = nil,
        subjectOverride: String? = nil
    ) -> GuestEmailRenderInput {
        var input = base(
            reservation: reservation,
            kind: .manualQuestion,
            manageLinkURL: manageLinkURL,
            linkExpiresAt: nil
        )
        return GuestEmailRenderInput(
            kind: input.kind,
            reservationID: input.reservationID,
            guestFirstName: input.guestFirstName,
            dateLine: input.dateLine,
            timeLine: input.timeLine,
            partySize: input.partySize,
            manageLinkURL: manageLinkURL,
            linkExpiresAt: nil,
            customPlainMessage: customPlainMessage,
            subjectOverride: subjectOverride
        )
    }

    private static func base(
        reservation: ReservationRecord,
        kind: GuestEmailTemplateKind,
        manageLinkURL: String?,
        linkExpiresAt: String?
    ) -> GuestEmailRenderInput {
        GuestEmailRenderInput(
            kind: kind,
            reservationID: reservation.remoteID,
            guestFirstName: GuestEmailTemplateRenderer.guestFirstName(from: reservation.guestName),
            dateLine: ManualEmailDraftService.emailDateLine(for: reservation),
            timeLine: ManualEmailDraftService.emailTimeLine(for: reservation),
            partySize: reservation.partySize,
            manageLinkURL: manageLinkURL,
            linkExpiresAt: linkExpiresAt,
            customPlainMessage: nil,
            subjectOverride: nil
        )
    }
}

// MARK: - Renderer

enum GuestEmailTemplateRenderer {
    static func subject(for input: GuestEmailRenderInput) -> String {
        input.subjectOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? input.kind.defaultSubject
    }

    static func renderHTML(_ input: GuestEmailRenderInput) -> String {
        trace(input)

        let firstName = htmlEscape(input.guestFirstName)
        let dateLine = htmlEscape(input.dateLine)
        let timeLine = htmlEscape(input.timeLine)
        let intro = introHTML(for: input)
        let reservationCard = reservationCardHTML(dateLine: dateLine, timeLine: timeLine, partySize: input.partySize)
        let primaryButton = primaryButtonHTML(manageURL: input.manageLinkURL)
        let primaryHelper = primaryHelperHTML
        let rescheduleSection = rescheduleSectionHTML
        let noReplySection = noReplySectionHTML
        let addressSection = addressSectionHTML
        let expiresHTML = formattedExpiresHTML(input.linkExpiresAt)
        let policiesURL = htmlAttributeEscape(ReservationEmailWorkflow.reservationPoliciesURL.absoluteString)
        let headerTitle = htmlEscape(input.kind.headerTitle)
        let restaurantName = htmlEscape(ReservationEmailWorkflow.restaurantName)

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        </head>
        <body style="margin:0;padding:0;background-color:#f3efe6;font-family:Georgia,'Times New Roman',serif;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color:#f3efe6;padding:28px 14px;">
        <tr>
        <td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:580px;background:#ffffff;border-radius:14px;overflow:hidden;border:1px solid #e4ddd1;">
        <tr>
        <td style="background:#1f3d2b;padding:30px 34px;text-align:center;">
        <p style="margin:0;color:#d8c9a8;font-size:12px;letter-spacing:0.16em;text-transform:uppercase;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;">\(restaurantName)</p>
        <h1 style="margin:14px 0 0;color:#ffffff;font-size:26px;line-height:1.25;font-weight:600;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;">\(headerTitle)</h1>
        </td>
        </tr>
        <tr>
        <td style="padding:34px 34px 10px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#222222;font-size:16px;line-height:1.65;">
        <p style="margin:0 0 18px;">Dear \(firstName),</p>
        \(intro)
        \(reservationCard)
        \(primaryButton)
        \(primaryHelper)
        \(rescheduleSection)
        \(expiresHTML)
        \(addressSection)
        \(noReplySection)
        </td>
        </tr>
        <tr>
        <td style="padding:18px 34px 30px;border-top:1px solid #ece8e1;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:12px;line-height:1.6;color:#8a8378;text-align:center;">
        <p style="margin:0;">By dining with us you agree to our <a href="\(policiesURL)" style="color:#1f6b3a;text-decoration:underline;">reservation policies</a>.</p>
        </td>
        </tr>
        </table>
        </td>
        </tr>
        </table>
        </body>
        </html>
        """
    }

    static func renderPlain(_ input: GuestEmailRenderInput) -> String {
        let intro = introPlain(for: input)
        var lines = [
            "Dear \(input.guestFirstName),",
            "",
            intro,
            "",
            input.dateLine,
            input.timeLine,
            "Party of \(input.partySize)"
        ]

        if let url = input.manageLinkURL?.nilIfBlank {
            lines.append("")
            lines.append("View Reservation:")
            lines.append(url)
            if let expires = formattedExpiresLine(input.linkExpiresAt) {
                lines.append(expires)
            }
        }

        lines.append("")
        lines.append("Plans change — no problem.")
        lines.append(ReservationEmailWorkflow.bookTableURL.absoluteString)
        lines.append("For questions, email \(ReservationEmailWorkflow.guestContactEmail) or call us.")
        lines.append("")
        lines.append(ReservationEmailWorkflow.restaurantAddressLine)
        lines.append(ReservationEmailWorkflow.restaurantPhone)
        lines.append(ReservationEmailWorkflow.websiteURL.absoluteString)
        lines.append("")
        lines.append("This is an automated reservation message. Please do not reply to this email.")

        return lines.joined(separator: "\n")
    }

    static func logSnapshot(_ input: GuestEmailRenderInput) -> String {
        var snapshot = renderPlain(input)
        if let url = input.manageLinkURL {
            snapshot = snapshot.replacingOccurrences(of: url, with: "[guest-manage-link]")
        }
        return String(snapshot.prefix(1800))
    }

    // MARK: - Private HTML blocks

    private static var primaryHelperHTML: String {
        """
        <p style="margin:0 0 28px;font-size:14px;line-height:1.6;color:#666666;text-align:center;">Use your private link to view reservation details or cancel.</p>
        """
    }

    private static var rescheduleSectionHTML: String {
        let bookURL = htmlAttributeEscape(ReservationEmailWorkflow.bookTableURL.absoluteString)
        return """
        <p style="margin:0 0 12px;font-size:15px;line-height:1.65;color:#444444;text-align:center;">Plans change — no problem.</p>
        <p style="margin:0 0 10px;text-align:center;">
        <a href="\(bookURL)" style="display:inline-block;padding:10px 18px;border:1px solid #1f6b3a;color:#1f6b3a;text-decoration:none;border-radius:999px;font-size:14px;font-weight:600;">Request Different Time</a>
        </p>
        <p style="margin:0 0 28px;font-size:13px;line-height:1.55;color:#777777;text-align:center;">If you request a new time online, please mention your existing reservation in the notes.</p>
        """
    }

    private static var noReplySectionHTML: String {
        let contactEmail = htmlEscape(ReservationEmailWorkflow.guestContactEmail)
        return """
        <p style="margin:28px 0 0;font-size:12px;line-height:1.6;color:#8a8378;text-align:center;">This is an automated reservation message. Please do not reply to this email.</p>
        <p style="margin:8px 0 0;font-size:13px;line-height:1.6;color:#666666;text-align:center;">For questions, email <a href="mailto:\(contactEmail)" style="color:#1f6b3a;text-decoration:none;">\(contactEmail)</a>. For same-day changes during business hours, please call us.</p>
        """
    }

    private static var addressSectionHTML: String {
        let websiteURL = htmlAttributeEscape(ReservationEmailWorkflow.websiteURL.absoluteString)
        return """
        <p style="margin:0 0 24px;font-size:14px;line-height:1.7;color:#5c574f;text-align:center;">
        \(htmlEscape(ReservationEmailWorkflow.restaurantAddressLine))<br>
        \(htmlEscape(ReservationEmailWorkflow.restaurantPhone)) · <a href="\(websiteURL)" style="color:#1f6b3a;text-decoration:none;">tryzubchicago.com</a>
        </p>
        """
    }

    private static func primaryButtonHTML(manageURL: String?) -> String {
        guard let url = manageURL?.nilIfBlank else { return "" }
        let linkURL = htmlAttributeEscape(url)
        return """
        <p style="margin:0 0 18px;text-align:center;">
        <a href="\(linkURL)" style="display:inline-block;padding:15px 28px;background-color:#1f6b3a;color:#ffffff;text-decoration:none;border-radius:999px;font-size:16px;font-weight:700;letter-spacing:0.01em;">View Reservation</a>
        </p>
        """
    }

    private static func reservationCardHTML(dateLine: String, timeLine: String, partySize: Int) -> String {
        """
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f8f5ef;border:1px solid #ece4d7;border-radius:12px;margin:0 0 28px;">
        <tr>
        <td style="padding:22px 22px 8px;">
        <p style="margin:0 0 14px;font-size:12px;color:#7a7368;letter-spacing:0.12em;text-transform:uppercase;">Your reservation</p>
        <p style="margin:0;font-size:20px;line-height:1.35;font-weight:700;color:#1f1f1f;">\(dateLine)</p>
        <p style="margin:8px 0 0;font-size:20px;line-height:1.35;font-weight:700;color:#1f1f1f;">\(timeLine)</p>
        </td>
        </tr>
        <tr>
        <td style="padding:0 22px 20px;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
        <tr><td style="padding:6px 0;color:#5c574f;font-size:14px;">Party size</td><td style="padding:6px 0;color:#1f1f1f;font-size:15px;font-weight:600;text-align:right;">\(partySize)</td></tr>
        </table>
        </td>
        </tr>
        </table>
        """
    }

    private static func introHTML(for input: GuestEmailRenderInput) -> String {
        if let custom = input.customPlainMessage?.nilIfBlank {
            return plainParagraphsHTML(custom)
        }
        switch input.kind {
        case .confirmation:
            return """
            <p style="margin:0 0 26px;">Thank you for choosing <strong>\(htmlEscape(ReservationEmailWorkflow.restaurantName))</strong>. We look forward to welcoming you to Ukrainian Village.</p>
            """
        case .reminder:
            return """
            <p style="margin:0 0 26px;">This is a reminder for your reservation at <strong>\(htmlEscape(ReservationEmailWorkflow.restaurantName))</strong> today at \(htmlEscape(input.timeLine)) for \(input.partySize) guest\(input.partySize == 1 ? "" : "s").</p>
            """
        case .manualQuestion, .custom:
            return """
            <p style="margin:0 0 26px;">We wanted to follow up about your reservation at <strong>\(htmlEscape(ReservationEmailWorkflow.restaurantName))</strong>.</p>
            """
        }
    }

    private static func introPlain(for input: GuestEmailRenderInput) -> String {
        if let custom = input.customPlainMessage?.nilIfBlank {
            return custom
        }
        switch input.kind {
        case .confirmation:
            return "Thank you for choosing \(ReservationEmailWorkflow.restaurantName). We look forward to welcoming you to Ukrainian Village."
        case .reminder:
            return "This is a reminder for your reservation at \(ReservationEmailWorkflow.restaurantName) today at \(input.timeLine) for \(input.partySize) guest\(input.partySize == 1 ? "" : "s")."
        case .manualQuestion, .custom:
            return "We wanted to follow up about your reservation at \(ReservationEmailWorkflow.restaurantName)."
        }
    }

    private static func plainParagraphsHTML(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { paragraph in
                let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "" }
                return "<p style=\"margin:0 0 18px;\">\(htmlEscape(trimmed))</p>"
            }
            .filter { !$0.isEmpty }
            .joined()
    }

    private static func formattedExpiresLine(_ value: String?) -> String? {
        guard let value = value?.nilIfBlank else { return nil }
        if let date = ReservationFormatters.serverDateTime.date(from: value) {
            return "This private link expires \(emailLongDateFormatter.string(from: date)) at \(emailLongTimeFormatter.string(from: date))."
        }
        return "This private link expires \(value)."
    }

    private static func formattedExpiresHTML(_ value: String?) -> String {
        guard let line = formattedExpiresLine(value) else { return "" }
        return "<p style=\"margin:0 0 24px;font-size:13px;line-height:1.6;color:#8a8378;text-align:center;\">\(htmlEscape(line))</p>"
    }

    private static let emailLongDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter
    }()

    private static let emailLongTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static func guestFirstName(from guestName: String) -> String {
        guestName.split(separator: " ").first.map(String.init) ?? guestName
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func htmlAttributeEscape(_ value: String) -> String {
        htmlEscape(value)
    }

    private static func trace(_ input: GuestEmailRenderInput) {
        GuestCommunicationTrace.emailTemplate(
            type: input.kind,
            reservationID: input.reservationID,
            privateLink: input.manageLinkURL != nil,
            rescheduleLink: true
        )
        GuestCommunicationTrace.emailPrivacy(
            reservationID: input.reservationID,
            type: input.kind,
            leakedInternalFields: false
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
