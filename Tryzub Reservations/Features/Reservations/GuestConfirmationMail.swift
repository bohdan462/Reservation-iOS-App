//
//  GuestConfirmationMail.swift
//  Tryzub Reservations
//

import MessageUI
import SwiftUI
import UIKit

enum GuestConfirmationMailPresenter {
    struct Draft: Identifiable, Equatable {
        let recipients: [String]
        let subject: String
        let htmlBody: String
        let plainBody: String

        var id: String {
            recipients.joined(separator: ",") + "|" + subject
        }
    }

    static func canSendMail() -> Bool {
        MFMailComposeViewController.canSendMail()
    }

    static func draft(
        reservation: ReservationRecord,
        manageLink: ReservationGuestManageLinkDTO
    ) -> Draft? {
        let email = reservation.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return nil }

        return Draft(
            recipients: [email],
            subject: ManualEmailDraftService.confirmationSubject(reservation: reservation),
            htmlBody: ManualEmailDraftService.confirmationHTMLBody(
                reservation: reservation,
                manageLink: manageLink
            ),
            plainBody: ManualEmailDraftService.confirmationPlainBody(
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
        composer.setMessageBody(draft.htmlBody, isHTML: true)
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void

        init(onFinish: @escaping (MFMailComposeResult) -> Void) {
            self.onFinish = onFinish
        }

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
