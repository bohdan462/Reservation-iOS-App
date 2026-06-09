//
//  GuestCommunicationCoordinator.swift
//  Tryzub Reservations
//
//  Communication facade for Reservation Detail. Prepares drafts and pasteboard
//  content only — never sends mail/text or mutates reservations.
//

import Foundation
import UIKit

@MainActor
final class GuestCommunicationCoordinator: ObservableObject {

    enum StaffMessage {
        static let noGuestEmail = "Add a guest email in Edit before sending."
        static let noDialablePhone = "Add a dialable guest phone before sending a text."
        static let mailUnavailableCopied = "Mail isn’t set up on this device. Email draft copied."
        static let messagesUnavailableCopied = "Messages isn’t available. Text draft copied."
    }

    @Published private(set) var isDrafting = false
    @Published private(set) var lastErrorMessage: String?

    var useLocalModelProvider: () -> Bool

    init(useLocalModelProvider: @escaping () -> Bool = { false }) {
        self.useLocalModelProvider = useLocalModelProvider
    }

    static func templateOnly() -> GuestCommunicationCoordinator {
        GuestCommunicationCoordinator(useLocalModelProvider: { false })
    }

    func clearStaffError() {
        lastErrorMessage = nil
    }

    func noteStaffError(_ message: String) {
        lastErrorMessage = message
    }

    func draftGuestMessage(
        kind: GuestMessageDraftKind,
        reservation: ReservationRecord,
        manageURL: String?
    ) async -> GuestMessageDraft {
        isDrafting = true
        lastErrorMessage = nil
        defer { isDrafting = false }

        let draftService = GuestMessageDraftServiceFactory.make(
            useLocalModel: useLocalModelProvider()
        )
        let draft = await draftService.draft(
            kind: kind,
            reservation: reservation,
            restaurantProfile: .workflowDefault,
            manageURL: manageURL
        )
        lastErrorMessage = draftService.lastErrorMessage
        return draft
    }

    func makeEmailComposerDraft(
        reservation: ReservationRecord,
        draft: GuestMessageDraft
    ) -> GuestConfirmationMailPresenter.Draft? {
        guard let mailDraft = GuestConfirmationMailPresenter.manualDraft(
            reservation: reservation,
            subject: draft.emailSubject,
            body: draft.emailBody
        ) else {
            lastErrorMessage = StaffMessage.noGuestEmail
            return nil
        }
        return mailDraft
    }

    func makeTextComposerDraft(
        reservation: ReservationRecord,
        draft: GuestMessageDraft
    ) -> GuestTextMessageDraft? {
        guard let textDraft = GuestTextMessagePresenter.draft(
            phone: reservation.phone,
            body: draft.shortMessageBody
        ) else {
            lastErrorMessage = StaffMessage.noDialablePhone
            return nil
        }
        return textDraft
    }

    func emailPasteboardText(from draft: GuestMessageDraft) -> String {
        "Subject: \(draft.emailSubject)\n\n\(draft.emailBody)"
    }

    func textPasteboardText(from draft: GuestMessageDraft) -> String {
        draft.shortMessageBody
    }

    func copyEmailDraft(_ draft: GuestMessageDraft) {
        UIPasteboard.general.string = emailPasteboardText(from: draft)
    }

    func copyTextDraft(_ draft: GuestMessageDraft) {
        UIPasteboard.general.string = textPasteboardText(from: draft)
    }
}
