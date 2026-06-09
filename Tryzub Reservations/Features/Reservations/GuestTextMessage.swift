//
//  GuestTextMessage.swift
//  Tryzub Reservations
//
//  Pre-filled iMessage/SMS drafts for staff to send manually.
//

import MessageUI
import SwiftUI
import UIKit

enum GuestTextMessageKind: String, Equatable {
    case confirmation
    case tableDue
}

struct GuestTextMessageDraft: Identifiable, Equatable {
    let recipients: [String]
    let body: String

    var id: String {
        recipients.joined(separator: ",") + "|" + body
    }
}

enum ManualTextMessageService {
    static func confirmationBody(
        guestName: String,
        dateLine: String,
        timeLine: String,
        partySize: Int,
        tableName: String? = nil
    ) -> String {
        let firstName = guestFirstName(from: guestName)
        var message = "Hi \(firstName), your reservation at \(ReservationEmailWorkflow.restaurantName) is confirmed for \(dateLine) at \(timeLine) for party of \(partySize)."
        if let tableName = tableName?.trimmedNonEmpty {
            message += " Table \(tableName)."
        }
        message += " To cancel or change, contact us at \(ReservationEmailWorkflow.restaurantPhone)."
        return message
    }

    static func confirmationBody(
        guestName: String,
        reservationDate: Date,
        reservationTime: Date,
        partySize: Int,
        tableName: String? = nil
    ) -> String {
        confirmationBody(
            guestName: guestName,
            dateLine: longDateLine(reservationDate),
            timeLine: longTimeLine(reservationTime),
            partySize: partySize,
            tableName: tableName
        )
    }

    static func confirmationBody(reservation: ReservationRecord) -> String {
        confirmationBody(
            guestName: reservation.guestName,
            dateLine: ManualEmailDraftService.emailDateLine(for: reservation),
            timeLine: ManualEmailDraftService.emailTimeLine(for: reservation),
            partySize: reservation.partySize,
            tableName: reservation.tableName
        )
    }

    static func tableDueBody(
        guestName: String,
        tableName: String? = nil
    ) -> String {
        let firstName = guestFirstName(from: guestName)
        if let tableName = tableName?.trimmedNonEmpty {
            return "Hi \(firstName), your table (\(tableName)) at \(ReservationEmailWorkflow.restaurantName) is ready. Please check in with the host. Questions? \(ReservationEmailWorkflow.restaurantPhone)"
        }
        return "Hi \(firstName), your table at \(ReservationEmailWorkflow.restaurantName) is ready. Please check in with the host. Questions? \(ReservationEmailWorkflow.restaurantPhone)"
    }

    static func tableDueBody(reservation: ReservationRecord) -> String {
        tableDueBody(guestName: reservation.guestName, tableName: reservation.tableName)
    }

    static func body(for kind: GuestTextMessageKind, reservation: ReservationRecord) -> String {
        switch kind {
        case .confirmation:
            return confirmationBody(reservation: reservation)
        case .tableDue:
            return tableDueBody(reservation: reservation)
        }
    }

    private static func guestFirstName(from guestName: String) -> String {
        let trimmed = guestName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(separator: " ").first else { return "there" }
        return String(first)
    }

    private static let longDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()

    private static let longTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static func longDateLine(_ date: Date) -> String {
        longDateFormatter.string(from: date)
    }

    private static func longTimeLine(_ time: Date) -> String {
        longTimeFormatter.string(from: time)
    }
}

enum GuestTextMessagePresenter {
    static func canSendText() -> Bool {
        MFMessageComposeViewController.canSendText()
    }

    static func hasDialablePhone(_ phone: String) -> Bool {
        dialableRecipient(from: phone) != nil
    }

    static func draft(phone: String, body: String) -> GuestTextMessageDraft? {
        guard let recipient = dialableRecipient(from: phone) else { return nil }
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return nil }
        return GuestTextMessageDraft(recipients: [recipient], body: trimmedBody)
    }

    @MainActor
    @discardableResult
    static func openSMSFallback(draft: GuestTextMessageDraft) -> Bool {
        guard let recipient = draft.recipients.first,
              let url = smsURL(recipient: recipient, body: draft.body) else {
            return false
        }

        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return true
    }

    static func dialableRecipient(from phone: String) -> String? {
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 10 else { return nil }

        if digits.count == 10 {
            return digits
        }

        if digits.count == 11, digits.first == "1" {
            return String(digits)
        }

        let lastTen = String(digits.suffix(10))
        return lastTen.count == 10 ? lastTen : nil
    }

    private static func smsURL(recipient: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "sms"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}

struct GuestTextMessageComposer: UIViewControllerRepresentable {
    let draft: GuestTextMessageDraft
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = context.coordinator
        composer.recipients = draft.recipients
        composer.body = draft.body
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true)
            onFinish()
        }
    }
}

struct GuestTextMessageActionButtons: View {
    let phone: String
    let confirmationBody: String
    let tableDueBody: String
    var isCompact = false

    @State private var activeDraft: GuestTextMessageDraft?

    var body: some View {
        if GuestTextMessagePresenter.hasDialablePhone(phone) {
            ViewThatFits {
                HStack(spacing: 10) {
                    messageButton(
                        title: "Text Confirmation",
                        systemImage: "message.fill",
                        body: confirmationBody
                    )
                    messageButton(
                        title: "Text Table Ready",
                        systemImage: "bell.badge.fill",
                        body: tableDueBody
                    )
                }

                VStack(spacing: 8) {
                    messageButton(
                        title: "Text Confirmation",
                        systemImage: "message.fill",
                        body: confirmationBody,
                        fillsWidth: true
                    )
                    messageButton(
                        title: "Text Table Ready",
                        systemImage: "bell.badge.fill",
                        body: tableDueBody,
                        fillsWidth: true
                    )
                }
            }
            .sheet(item: $activeDraft) { draft in
                GuestTextMessageComposer(draft: draft) {
                    activeDraft = nil
                }
            }
        }
    }

    @ViewBuilder
    private func messageButton(
        title: String,
        systemImage: String,
        body: String,
        fillsWidth: Bool = false
    ) -> some View {
        Button {
            openMessage(body: body)
        } label: {
            Label(title, systemImage: systemImage)
                .font(isCompact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .buttonStyle(.bordered)
        .controlSize(isCompact ? .small : .regular)
    }

    private func openMessage(body: String) {
        guard let draft = GuestTextMessagePresenter.draft(phone: phone, body: body) else { return }

        if GuestTextMessagePresenter.canSendText() {
            activeDraft = draft
            ReservationHaptics.selection()
        } else if GuestTextMessagePresenter.openSMSFallback(draft: draft) {
            ReservationHaptics.selection()
        } else {
            UIPasteboard.general.string = draft.body
            ReservationHaptics.warning()
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
