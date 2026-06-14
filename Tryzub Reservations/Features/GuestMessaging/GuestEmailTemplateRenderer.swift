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
        let input = base(
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
        let actionPrompt = actionPromptHTML(for: input.kind)
        let actionButtons = actionButtonsHTML(manageURL: input.manageLinkURL)
        let footer = footerHTML
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
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color:#f3efe6;padding:18px 12px;">
        <tr>
        <td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background:#ffffff;border-radius:12px;overflow:hidden;border:1px solid #e4ddd1;">
        <tr>
        <td style="background:#1f3d2b;padding:22px 26px;text-align:center;">
        <p style="margin:0;color:#d8c9a8;font-size:11px;letter-spacing:0.14em;text-transform:uppercase;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;">\(restaurantName)</p>
        <h1 style="margin:9px 0 0;color:#ffffff;font-size:23px;line-height:1.2;font-weight:650;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;">\(headerTitle)</h1>
        </td>
        </tr>
        <tr>
        <td style="padding:24px 26px 20px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#222222;font-size:15px;line-height:1.5;">
        <p style="margin:0 0 12px;">Dear \(firstName),</p>
        \(intro)
        \(reservationCard)
        \(actionPrompt)
        \(actionButtons)
        \(footer)
        </td>
        </tr>
        <tr>
        <td style="padding:14px 26px 22px;border-top:1px solid #ece8e1;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:11px;line-height:1.45;color:#8a8378;text-align:center;">
        <p style="margin:0;"><a href="\(policiesURL)" style="color:#1f6b3a;text-decoration:underline;">Reservation policies</a></p>
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
            lines.append("Review Reservation:")
            lines.append(url)
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

    private static func actionPromptHTML(for kind: GuestEmailTemplateKind) -> String {
        guard kind == .reminder else { return "" }
        return """
        <p style="margin:0 0 10px;font-size:14px;line-height:1.45;color:#5c574f;text-align:center;">Plans change — no problem.</p>
        """
    }

    private static func actionButtonsHTML(manageURL: String?) -> String {
        let bookURL = htmlAttributeEscape(ReservationEmailWorkflow.bookTableURL.absoluteString)
        let manageButton: String
        if let url = manageURL?.nilIfBlank {
            let linkURL = htmlAttributeEscape(url)
            manageButton = """
            <td align="center" style="padding:0 4px 8px;">
            <a href="\(linkURL)" style="display:inline-block;min-width:150px;padding:12px 18px;background-color:#1f6b3a;color:#ffffff;text-decoration:none;border-radius:999px;font-size:14px;font-weight:700;">Review Reservation</a>
            </td>
            """
        } else {
            manageButton = ""
        }

        return """
        <table role="presentation" cellspacing="0" cellpadding="0" align="center" style="margin:0 auto 18px;">
        <tr>
        \(manageButton)
        <td align="center" style="padding:0 4px 8px;">
        <a href="\(bookURL)" style="display:inline-block;min-width:150px;padding:11px 16px;border:1px solid #1f6b3a;color:#1f6b3a;text-decoration:none;border-radius:999px;font-size:13px;font-weight:700;">Request Different Time</a>
        </td>
        </tr>
        </table>
        """
    }

    private static var footerHTML: String {
        let contactEmail = htmlEscape(ReservationEmailWorkflow.guestContactEmail)
        let websiteURL = htmlAttributeEscape(ReservationEmailWorkflow.websiteURL.absoluteString)
        return """
        <p style="margin:4px 0 0;font-size:11px;line-height:1.45;color:#8a8378;text-align:center;">This is an automated reservation message. Please do not reply to this email.</p>
        <p style="margin:6px 0 0;font-size:11px;line-height:1.45;color:#766f65;text-align:center;">For questions, email <a href="mailto:\(contactEmail)" style="color:#1f6b3a;text-decoration:none;">\(contactEmail)</a>. For same-day changes during business hours, please call us.</p>
        <p style="margin:6px 0 0;font-size:11px;line-height:1.45;color:#8a8378;text-align:center;">
        \(htmlEscape(ReservationEmailWorkflow.restaurantAddressLine)) · \(htmlEscape(ReservationEmailWorkflow.restaurantPhone)) · <a href="\(websiteURL)" style="color:#1f6b3a;text-decoration:none;">tryzubchicago.com</a>
        </p>
        """
    }

    private static func reservationCardHTML(dateLine: String, timeLine: String, partySize: Int) -> String {
        """
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f8f5ef;border:1px solid #ece4d7;border-radius:10px;margin:0 0 18px;">
        <tr>
        <td style="padding:15px 16px 6px;">
        <p style="margin:0 0 8px;font-size:11px;color:#7a7368;letter-spacing:0.1em;text-transform:uppercase;">Your reservation</p>
        <p style="margin:0;font-size:18px;line-height:1.25;font-weight:700;color:#1f1f1f;">\(dateLine)</p>
        <p style="margin:5px 0 0;font-size:18px;line-height:1.25;font-weight:700;color:#1f1f1f;">\(timeLine)</p>
        <p style="margin:6px 0 0;font-size:14px;line-height:1.25;font-weight:650;color:#1f1f1f;">Party of \(partySize)</p>
        </td>
        </tr>
        </table>
        """
    }

    private static func introHTML(for input: GuestEmailRenderInput) -> String {
        if let custom = input.customPlainMessage?.nilIfBlank {
            return plainParagraphsHTML(sanitizedCustomMessage(custom))
        }
        switch input.kind {
        case .confirmation:
            return """
            <p style="margin:0 0 16px;">Your reservation at <strong>\(htmlEscape(ReservationEmailWorkflow.restaurantName))</strong> is confirmed. We look forward to welcoming you.</p>
            """
        case .reminder:
            return """
            <p style="margin:0 0 16px;">This is a reminder for your reservation at <strong>\(htmlEscape(ReservationEmailWorkflow.restaurantName))</strong> today.</p>
            """
        case .manualQuestion, .custom:
            return """
            <p style="margin:0 0 16px;">We wanted to follow up about your reservation at <strong>\(htmlEscape(ReservationEmailWorkflow.restaurantName))</strong>.</p>
            """
        }
    }

    private static func introPlain(for input: GuestEmailRenderInput) -> String {
        if let custom = input.customPlainMessage?.nilIfBlank {
            return sanitizedCustomMessage(custom)
        }
        switch input.kind {
        case .confirmation:
            return "Your reservation at \(ReservationEmailWorkflow.restaurantName) is confirmed. We look forward to welcoming you."
        case .reminder:
            return "This is a reminder for your reservation at \(ReservationEmailWorkflow.restaurantName) today."
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
                return "<p style=\"margin:0 0 14px;\">\(htmlEscape(trimmed))</p>"
            }
            .filter { !$0.isEmpty }
            .joined()
    }

    private static func sanitizedCustomMessage(_ text: String) -> String {
        var lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        while let first = lines.first, first.isEmpty {
            lines.removeFirst()
        }

        if let first = lines.first, isGreetingLine(first) {
            lines.removeFirst()
            while let next = lines.first, next.isEmpty {
                lines.removeFirst()
            }
        }

        var cleaned: [String] = []
        var skipNextURL = false
        for line in lines {
            let lower = line.lowercased()
            if lower == "view or manage your reservation:" {
                skipNextURL = true
                continue
            }
            if line.hasPrefix("http://") || line.hasPrefix("https://") || skipNextURL {
                skipNextURL = false
                continue
            }
            if line == ReservationEmailWorkflow.restaurantAddressLine || line == ReservationEmailWorkflow.restaurantPhone {
                continue
            }
            cleaned.append(line)
        }

        return cleaned.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isGreetingLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return (lower.hasPrefix("dear ") || lower.hasPrefix("hi ") || lower == "hi," || lower.hasPrefix("hello "))
            && (line.hasSuffix(",") || line.hasSuffix("."))
    }

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
        GuestCommunicationTrace.emailRenderPolish(
            reservationID: input.reservationID,
            type: input.kind,
            duplicatedGreeting: false,
            rawRescheduleURL: false
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
