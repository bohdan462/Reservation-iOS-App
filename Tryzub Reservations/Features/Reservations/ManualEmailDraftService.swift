//
//  ManualEmailDraftService.swift
//  Tryzub Reservations
//
//  Staff-reviewed guest email drafts. Uses shared styled HTML templates.
//  Does not call POST /confirm.
//

import Foundation

struct ManualEmailDraftService {
    static func confirmationSubject(reservation: ReservationRecord) -> String {
        GuestEmailTemplateRenderer.subject(
            for: .confirmation(reservation: reservation, manageLink: placeholderManageLink(for: reservation))
        )
    }

    static func confirmationHTMLBody(
        reservation: ReservationRecord,
        manageLink: ReservationGuestManageLinkDTO
    ) -> String {
        GuestEmailTemplateRenderer.renderHTML(
            .confirmation(reservation: reservation, manageLink: manageLink)
        )
    }

    static func confirmationPlainBody(
        reservation: ReservationRecord,
        manageLink: ReservationGuestManageLinkDTO
    ) -> String {
        GuestEmailTemplateRenderer.renderPlain(
            .confirmation(reservation: reservation, manageLink: manageLink)
        )
    }

    static func reminderHTMLBody(
        reservation: ReservationRecord,
        manageLinkURL: String?,
        linkExpiresAt: String? = nil
    ) -> String {
        GuestEmailTemplateRenderer.renderHTML(
            .reminder(
                reservation: reservation,
                manageLinkURL: manageLinkURL,
                linkExpiresAt: linkExpiresAt
            )
        )
    }

    static func reminderPlainBody(
        reservation: ReservationRecord,
        manageLinkURL: String?,
        linkExpiresAt: String? = nil
    ) -> String {
        GuestEmailTemplateRenderer.renderPlain(
            .reminder(
                reservation: reservation,
                manageLinkURL: manageLinkURL,
                linkExpiresAt: linkExpiresAt
            )
        )
    }

    static func confirmationDraft(
        reservation: ReservationRecord,
        manageLink: ReservationGuestManageLinkDTO
    ) -> String {
        let input = GuestEmailRenderInput.confirmation(reservation: reservation, manageLink: manageLink)
        return """
        Subject: \(GuestEmailTemplateRenderer.subject(for: input))

        \(GuestEmailTemplateRenderer.renderPlain(input))
        """
    }

    static func confirmationLogSnapshot(
        reservation: ReservationRecord,
        manageLink: ReservationGuestManageLinkDTO
    ) -> String {
        GuestEmailTemplateRenderer.logSnapshot(
            .confirmation(reservation: reservation, manageLink: manageLink)
        )
    }

    static func emailDateLine(for reservation: ReservationRecord) -> String {
        emailDateLine(for: reservation.reservationDate, displayFallback: reservation.displayDate)
    }

    static func emailTimeLine(for reservation: ReservationRecord) -> String {
        emailTimeLine(for: reservation.reservationTime, displayFallback: reservation.displayTime)
    }

    static func emailDateLine(for dateKey: String, displayFallback: String) -> String {
        guard let date = ReservationFormatters.reservationDateKey.date(from: dateKey) else {
            return displayFallback
        }
        return emailLongDateFormatter.string(from: date)
    }

    static func emailTimeLine(for timeKey: String, displayFallback: String) -> String {
        guard let date = ReservationFormatters.apiTime.date(from: timeKey) else {
            return displayFallback
        }
        return emailLongTimeFormatter.string(from: date)
    }

    private static func placeholderManageLink(for reservation: ReservationRecord) -> ReservationGuestManageLinkDTO {
        ReservationGuestManageLinkDTO(url: "", expiresAt: nil)
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
}
