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
    var wordingProfileProvider: () -> LocalWordingModelProfile

    init(
        useLocalModelProvider: @escaping () -> Bool = { false },
        wordingProfileProvider: @escaping () -> LocalWordingModelProfile = { .template }
    ) {
        self.useLocalModelProvider = useLocalModelProvider
        self.wordingProfileProvider = wordingProfileProvider
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
        guard !isDrafting else {
            return GuestMessageDraftTemplateWriter.draft(
                from: GuestMessageDraftPacketBuilder.build(
                    kind: kind,
                    reservation: reservation,
                    manageURL: manageURL
                )
            )
        }

        isDrafting = true
        lastErrorMessage = nil
        defer { isDrafting = false }

        let selectedProfile = wordingProfileProvider()
        let effectiveProfile: LocalWordingModelProfile = selectedProfile == .template && useLocalModelProvider()
            ? .smallFastLocal
            : selectedProfile
        let draftService = GuestMessageDraftServiceFactory.make(profile: effectiveProfile)
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
        approved: ApprovedGuestMessageDraft,
        manageURL: String?
    ) -> GuestConfirmationMailPresenter.Draft? {
        let email = reservation.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            lastErrorMessage = StaffMessage.noGuestEmail
            return nil
        }

        let input = GuestEmailRenderInput(
            kind: approved.kind.emailTemplateKind,
            reservationID: reservation.remoteID,
            guestFirstName: GuestEmailTemplateRenderer.guestFirstName(from: reservation.guestName),
            dateLine: ManualEmailDraftService.emailDateLine(for: reservation),
            timeLine: ManualEmailDraftService.emailTimeLine(for: reservation),
            partySize: reservation.partySize,
            manageLinkURL: manageURL,
            linkExpiresAt: nil,
            customPlainMessage: approved.wasEdited || approved.kind.emailTemplateKind == .manualQuestion
                ? approved.emailBody
                : nil,
            subjectOverride: approved.emailSubject
        )

        return GuestConfirmationMailPresenter.styledDraft(
            reservation: reservation,
            input: input
        )
    }

    func makeTextComposerDraft(
        reservation: ReservationRecord,
        approved: ApprovedGuestMessageDraft
    ) -> GuestTextMessageDraft? {
        guard let textDraft = GuestTextMessagePresenter.draft(
            phone: reservation.phone,
            body: approved.shortMessageBody
        ) else {
            lastErrorMessage = StaffMessage.noDialablePhone
            return nil
        }
        return textDraft
    }

    func emailPasteboardText(from approved: ApprovedGuestMessageDraft) -> String {
        "Subject: \(approved.emailSubject)\n\n\(approved.emailBody)"
    }

    func textPasteboardText(from approved: ApprovedGuestMessageDraft) -> String {
        approved.shortMessageBody
    }

    func copyEmailDraft(_ approved: ApprovedGuestMessageDraft) {
        UIPasteboard.general.string = emailPasteboardText(from: approved)
    }

    func copyTextDraft(_ approved: ApprovedGuestMessageDraft) {
        UIPasteboard.general.string = textPasteboardText(from: approved)
    }
}
