//
//  GuestConfirmationMail.swift
//  Tryzub Reservations
//

import MessageUI
import SwiftUI
import UIKit

enum GuestConfirmationMailPresenter {
    struct Draft: Identifiable, Equatable {
        let reservationID: Int
        let recipients: [String]
        let subject: String
        let htmlBody: String
        let plainBody: String
        let logBodySnapshot: String
        var prefersPlainText = false

        var id: String {
            "\(reservationID)|" + recipients.joined(separator: ",") + "|" + subject
        }
    }

    @MainActor
    static func canSendMail() -> Bool {
        MFMailComposeViewController.canSendMail()
    }

    /// Staff-reviewed styled draft. Does not call POST /confirm or record sent status.
    static func manualDraft(
        reservation: ReservationRecord,
        subject: String,
        body: String
    ) -> Draft? {
        let email = reservation.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return nil }

        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSubject.isEmpty, !trimmedBody.isEmpty else { return nil }

        let input = GuestEmailRenderInput.manual(
            reservation: reservation,
            customPlainMessage: trimmedBody,
            subjectOverride: trimmedSubject
        )

        return Draft(
            reservationID: reservation.remoteID,
            recipients: [email],
            subject: trimmedSubject,
            htmlBody: GuestEmailTemplateRenderer.renderHTML(input),
            plainBody: GuestEmailTemplateRenderer.renderPlain(input),
            logBodySnapshot: GuestEmailTemplateRenderer.logSnapshot(input)
        )
    }

    static func styledDraft(
        reservation: ReservationRecord,
        input: GuestEmailRenderInput
    ) -> Draft? {
        let email = reservation.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return nil }

        return Draft(
            reservationID: reservation.remoteID,
            recipients: [email],
            subject: GuestEmailTemplateRenderer.subject(for: input),
            htmlBody: GuestEmailTemplateRenderer.renderHTML(input),
            plainBody: GuestEmailTemplateRenderer.renderPlain(input),
            logBodySnapshot: GuestEmailTemplateRenderer.logSnapshot(input)
        )
    }

    static func draft(
        reservation: ReservationRecord,
        manageLink: ReservationGuestManageLinkDTO
    ) -> Draft? {
        let email = reservation.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return nil }

        return Draft(
            reservationID: reservation.remoteID,
            recipients: [email],
            subject: GuestEmailTemplateRenderer.subject(
                for: .confirmation(reservation: reservation, manageLink: manageLink)
            ),
            htmlBody: ManualEmailDraftService.confirmationHTMLBody(
                reservation: reservation,
                manageLink: manageLink
            ),
            plainBody: ManualEmailDraftService.confirmationPlainBody(
                reservation: reservation,
                manageLink: manageLink
            ),
            logBodySnapshot: ManualEmailDraftService.confirmationLogSnapshot(
                reservation: reservation,
                manageLink: manageLink
            )
        )
    }

    @MainActor
    @discardableResult
    static func openMailtoFallback(draft: Draft) -> Bool {
        guard let recipient = draft.recipients.first,
              let url = mailtoURL(recipient: recipient, subject: draft.subject, body: draft.plainBody) else {
            return false
        }

        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return true
    }

    private static func mailtoURL(recipient: String, subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}

struct GuestConfirmationMailComposer: UIViewControllerRepresentable {
    let draft: GuestConfirmationMailPresenter.Draft
    let onFinish: (MFMailComposeResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients(draft.recipients)
        composer.setSubject(draft.subject)
        if draft.prefersPlainText {
            composer.setMessageBody(draft.plainBody, isHTML: false)
        } else {
            composer.setMessageBody(draft.htmlBody, isHTML: true)
        }
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void

        init(onFinish: @escaping (MFMailComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        @MainActor
        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
            onFinish(result)
        }
    }
}
