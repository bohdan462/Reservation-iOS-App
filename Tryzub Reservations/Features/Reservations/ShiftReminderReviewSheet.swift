//
//  ShiftReminderReviewSheet.swift
//  Tryzub Reservations
//
//  Shared beginning-of-shift reminder review for Host Board and Bookings.
//

import MessageUI
import SwiftData
import SwiftUI

// MARK: - Eligibility

enum ShiftReminderEligibility {
    struct Summary: Equatable {
        let eligible: Int
        let emailReady: Int
        let smsReady: Int
        let noContact: Int
        let alreadyReminded: Int
    }

    static func eligibleReservations(
        from reservations: [ReservationRecord],
        dateKey: String,
        isHidden: (ReservationRecord) -> Bool
    ) -> [ReservationRecord] {
        reservations
            .filter { reservation in
                reservation.reservationDate == dateKey
                    && !isHidden(reservation)
                    && reservation.statusValue != .completed
                    && reservation.statusValue != .cancelled
                    && reservation.statusValue != .noShow
                    && (reservation.hasUsableConfirmationEmail || GuestTextMessagePresenter.hasDialablePhone(reservation.phone))
            }
            .sorted { lhs, rhs in
                lhs.reservationTime == rhs.reservationTime
                    ? lhs.guestName.localizedCaseInsensitiveCompare(rhs.guestName) == .orderedAscending
                    : lhs.reservationTime < rhs.reservationTime
            }
    }

    static func summary(for reservations: [ReservationRecord]) -> Summary {
        var emailReady = 0
        var smsReady = 0
        var noContact = 0
        var alreadyReminded = 0

        for reservation in reservations {
            let hasEmail = reservation.hasUsableConfirmationEmail
            let hasSMS = GuestTextMessagePresenter.hasDialablePhone(reservation.phone)
            if hasEmail { emailReady += 1 }
            if hasSMS { smsReady += 1 }
            if !hasEmail && !hasSMS { noContact += 1 }
            if reservation.reminderEmailSentAt?.nilIfBlank != nil {
                alreadyReminded += 1
            }
        }

        return Summary(
            eligible: reservations.count,
            emailReady: emailReady,
            smsReady: smsReady,
            noContact: noContact,
            alreadyReminded: alreadyReminded
        )
    }
}

// MARK: - Sheet

struct ShiftReminderReviewSheet: View {
    let dateKey: String
    let reservations: [ReservationRecord]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController

    @State private var mailDraft: GuestConfirmationMailPresenter.Draft?
    @State private var textDraft: GuestTextMessageDraft?
    @State private var activeEmailReservation: ReservationRecord?
    @State private var activeSMSReservation: ReservationRecord?
    @State private var results: [Int: String] = [:]
    @State private var reviewContext: ShiftReminderReviewContext?
    @State private var manageLinks: [Int: ReservationGuestManageLinkDTO] = [:]

    private var summary: ShiftReminderEligibility.Summary {
        ShiftReminderEligibility.summary(for: reservations)
    }

    var body: some View {
        NavigationStack {
            List {
                if reservations.isEmpty {
                    ContentUnavailableView(
                        "No reminders to review",
                        systemImage: "bell.slash",
                        description: Text("No active reservations with email or phone are eligible for this date.")
                    )
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Replies are not tracked in this app. Guests are directed to call during business hours or email \(ReservationEmailWorkflow.guestContactEmail).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            summaryLine
                        }
                        .padding(.vertical, 4)
                    }

                    Section {
                        ForEach(reservations) { reservation in
                            row(for: reservation)
                        }
                    } header: {
                        Text("Review before sending")
                    }
                }
            }
            .navigationTitle("Shift reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        completeSheet()
                    }
                }
            }
            .onAppear {
                WorkflowCleanupTrace.log(
                    "SHIFT_REMINDER_TRACE",
                    fields: [
                        "phase": "open",
                        "date": dateKey,
                        "eligible": "\(summary.eligible)",
                        "emailReady": "\(summary.emailReady)",
                        "smsReady": "\(summary.smsReady)",
                        "excluded": "\(summary.noContact)",
                        "alreadyReminded": "\(summary.alreadyReminded)"
                    ]
                )
            }
            .sheet(item: $reviewContext) { context in
                ShiftReminderMessageReviewSheet(
                    reservation: context.reservation,
                    channel: context.channel,
                    subject: context.subject,
                    emailBodyPreview: context.emailBodyPreview,
                    textBody: context.textBody,
                    showsBetaWarning: context.showsBetaWarning,
                    onApprove: { approved in
                        reviewContext = nil
                        sendApproved(approved, for: context.reservation, channel: context.channel)
                    },
                    onDismiss: {
                        reviewContext = nil
                    }
                )
            }
            .sheet(item: $mailDraft) { draft in
                GuestConfirmationMailComposer(draft: draft) { result in
                    handleMailResult(result, draft: draft)
                }
            }
            .sheet(item: $textDraft) { draft in
                GuestTextMessageComposer(draft: draft) { result in
                    handleSMSResult(result, draft: draft)
                }
            }
        }
    }

    private var summaryLine: Text {
        Text("Eligible \(summary.eligible) · Email \(summary.emailReady) · Text \(summary.smsReady) · No contact \(summary.noContact) · Already reminded \(summary.alreadyReminded)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func row(for reservation: ReservationRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reservation.guestName)
                        .font(.headline.weight(.semibold))
                    Text("\(reservation.displayTime) · \(reservation.partySize) guest\(reservation.partySize == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(contactLabel(for: reservation))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if let result = results[reservation.remoteID] {
                    Text(result)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if reservation.reminderEmailSentAt?.nilIfBlank != nil {
                    Text("reminded")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                if reservation.hasUsableConfirmationEmail {
                    Button("Email") {
                        presentReview(for: reservation, channel: .email)
                    }
                    .buttonStyle(.bordered)
                }
                if GuestTextMessagePresenter.hasDialablePhone(reservation.phone) {
                    Button("Text reminder") {
                        presentReview(for: reservation, channel: .sms)
                    }
                    .buttonStyle(.bordered)
                }
                Button("Skip") {
                    results[reservation.remoteID] = "skipped"
                    trace(reservation, channel: "email", result: "skipped")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func contactLabel(for reservation: ReservationRecord) -> String {
        var parts: [String] = []
        if reservation.hasUsableConfirmationEmail { parts.append("Email") }
        if GuestTextMessagePresenter.hasDialablePhone(reservation.phone) { parts.append("Text") }
        if parts.isEmpty { return "No contact" }
        return parts.joined(separator: " · ")
    }

    private func presentReview(for reservation: ReservationRecord, channel: ShiftReminderChannel) {
        let textBody = ManualTextMessageService.reminderBody(reservation: reservation)
        let emailPreview = ManualEmailDraftService.reminderPlainBody(
            reservation: reservation,
            manageLinkURL: manageLinks[reservation.remoteID]?.url
        )
        let subject = GuestEmailTemplateKind.reminder.defaultSubject

        GuestCommunicationTrace.messageReview(
            reservationID: reservation.remoteID,
            type: channel == .email ? "reminder" : "textReminder",
            phase: "presented",
            aiDraft: false,
            edited: false
        )

        reviewContext = ShiftReminderReviewContext(
            reservation: reservation,
            channel: channel,
            subject: subject,
            emailBodyPreview: emailPreview,
            textBody: textBody,
            showsBetaWarning: false
        )
    }

    private func sendApproved(
        _ approved: ShiftReminderApprovedMessage,
        for reservation: ReservationRecord,
        channel: ShiftReminderChannel
    ) {
        GuestCommunicationTrace.messageReview(
            reservationID: reservation.remoteID,
            type: channel == .email ? "reminder" : "textReminder",
            phase: "approved_for_composer",
            aiDraft: false,
            edited: approved.wasEdited
        )

        switch channel {
        case .email:
            Task {
                await openApprovedEmail(for: reservation, approved: approved)
            }
        case .sms:
            openApprovedSMS(for: reservation, approved: approved)
        }
    }

    private func openApprovedEmail(
        for reservation: ReservationRecord,
        approved: ShiftReminderApprovedMessage
    ) async {
        var manageLink = manageLinks[reservation.remoteID]
        if manageLink == nil {
            do {
                let link = try await controller.generateGuestManageLink(
                    reservation: reservation,
                    announceNotice: false
                )
                manageLinks[reservation.remoteID] = link
                manageLink = link
            } catch {
                results[reservation.remoteID] = "failed"
                trace(reservation, channel: "email", result: "failed")
                return
            }
        }

        let input = GuestEmailRenderInput(
            kind: .reminder,
            reservationID: reservation.remoteID,
            guestFirstName: GuestEmailTemplateRenderer.guestFirstName(from: reservation.guestName),
            dateLine: ManualEmailDraftService.emailDateLine(for: reservation),
            timeLine: ManualEmailDraftService.emailTimeLine(for: reservation),
            partySize: reservation.partySize,
            manageLinkURL: manageLink?.url,
            linkExpiresAt: manageLink?.expiresAt,
            customPlainMessage: approved.wasEdited ? approved.body : nil,
            subjectOverride: approved.subject
        )

        guard let draft = GuestConfirmationMailPresenter.styledDraft(
            reservation: reservation,
            input: input
        ) else {
            results[reservation.remoteID] = "failed"
            trace(reservation, channel: "email", result: "failed")
            return
        }

        activeEmailReservation = reservation
        if GuestConfirmationMailPresenter.canSendMail() {
            mailDraft = draft
            trace(reservation, channel: "email", result: "presented")
        } else if GuestConfirmationMailPresenter.openMailtoFallback(draft: draft) {
            results[reservation.remoteID] = "presented"
            trace(reservation, channel: "email", result: "presented")
        } else {
            UIPasteboard.general.string = draft.plainBody
            results[reservation.remoteID] = "failed"
            trace(reservation, channel: "email", result: "failed")
        }
    }

    private func openApprovedSMS(
        for reservation: ReservationRecord,
        approved: ShiftReminderApprovedMessage
    ) {
        guard let draft = GuestTextMessagePresenter.draft(
            phone: reservation.phone,
            body: approved.body
        ) else {
            results[reservation.remoteID] = "failed"
            trace(reservation, channel: "sms", result: "failed")
            return
        }

        if GuestTextMessagePresenter.canSendText() {
            activeSMSReservation = reservation
            textDraft = draft
            results[reservation.remoteID] = "presented"
            trace(reservation, channel: "sms", result: "presented")
        } else if GuestTextMessagePresenter.openSMSFallback(draft: draft) {
            results[reservation.remoteID] = "presented"
            trace(reservation, channel: "sms", result: "presented")
        } else {
            UIPasteboard.general.string = draft.body
            results[reservation.remoteID] = "failed"
            trace(reservation, channel: "sms", result: "failed")
        }
    }

    private func handleMailResult(_ result: MFMailComposeResult, draft: GuestConfirmationMailPresenter.Draft) {
        guard let reservation = activeEmailReservation else {
            mailDraft = nil
            return
        }
        switch result {
        case .sent:
            Task {
                do {
                    _ = try await controller.recordManualReminderSent(
                        reservation: reservation,
                        toEmail: draft.recipients.first,
                        subject: draft.subject,
                        bodySnapshot: draft.logBodySnapshot,
                        context: modelContext
                    )
                    results[reservation.remoteID] = "sent"
                    trace(reservation, channel: "email", result: "sent")
                } catch {
                    results[reservation.remoteID] = "failed"
                    trace(reservation, channel: "email", result: "failed")
                }
                mailDraft = nil
                activeEmailReservation = nil
            }
        case .cancelled, .saved:
            results[reservation.remoteID] = "cancelled"
            trace(reservation, channel: "email", result: "cancelled")
            mailDraft = nil
            activeEmailReservation = nil
        case .failed:
            results[reservation.remoteID] = "failed"
            trace(reservation, channel: "email", result: "failed")
            mailDraft = nil
            activeEmailReservation = nil
        @unknown default:
            results[reservation.remoteID] = "failed"
            trace(reservation, channel: "email", result: "failed")
            mailDraft = nil
            activeEmailReservation = nil
        }
    }

    private func handleSMSResult(_ result: MessageComposeResult, draft: GuestTextMessageDraft) {
        guard let reservation = activeSMSReservation else {
            textDraft = nil
            return
        }
        switch result {
        case .sent:
            results[reservation.remoteID] = "sent"
            trace(reservation, channel: "sms", result: "staff_confirmed_sent")
        case .cancelled:
            results[reservation.remoteID] = "cancelled"
            trace(reservation, channel: "sms", result: "cancelled")
        case .failed:
            results[reservation.remoteID] = "failed"
            trace(reservation, channel: "sms", result: "failed")
        @unknown default:
            results[reservation.remoteID] = "failed"
            trace(reservation, channel: "sms", result: "failed")
        }
        textDraft = nil
        activeSMSReservation = nil
    }

    private func completeSheet() {
        let emailSent = results.values.filter { $0 == "sent" }.count
        let smsSent = results.values.filter { $0 == "sent" }.count
        let skipped = results.values.filter { $0 == "skipped" }.count
        let failed = results.values.filter { $0 == "failed" }.count
        WorkflowCleanupTrace.log(
            "SHIFT_REMINDER_TRACE",
            fields: [
                "phase": "completed",
                "emailSent": "\(emailSent)",
                "smsSent": "\(smsSent)",
                "skipped": "\(skipped)",
                "failed": "\(failed)"
            ]
        )
        dismiss()
    }

    private func trace(_ reservation: ReservationRecord, channel: String, result: String) {
        WorkflowCleanupTrace.log(
            "SHIFT_REMINDER_TRACE",
            fields: [
                "reservation": "\(reservation.remoteID)",
                "channel": channel,
                "result": result
            ]
        )
    }
}

// MARK: - Review sub-sheet

private enum ShiftReminderChannel: Equatable {
    case email
    case sms
}

private struct ShiftReminderReviewContext: Identifiable {
    let reservation: ReservationRecord
    let channel: ShiftReminderChannel
    let subject: String
    let emailBodyPreview: String
    let textBody: String
    let showsBetaWarning: Bool

    var id: String {
        "\(reservation.remoteID)-\(channel)"
    }
}

struct ShiftReminderApprovedMessage: Equatable {
    let subject: String
    let body: String
    let wasEdited: Bool
}

private struct ShiftReminderMessageReviewSheet: View {
    let reservation: ReservationRecord
    let channel: ShiftReminderChannel
    let subject: String
    let emailBodyPreview: String
    let textBody: String
    let showsBetaWarning: Bool
    let onApprove: (ShiftReminderApprovedMessage) -> Void
    let onDismiss: () -> Void

    @State private var editedSubject: String = ""
    @State private var editedBody: String = ""
    @State private var didEdit = false

    var body: some View {
        NavigationStack {
            Form {
                if showsBetaWarning {
                    Section {
                        Text("AI draft is beta. Review and edit before sending.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text(reservation.guestName)
                    Text("\(reservation.displayTime) · party of \(reservation.partySize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if channel == .email {
                    Section("Email subject") {
                        TextField("Subject", text: $editedSubject)
                            .onChange(of: editedSubject) { _, _ in markEdited() }
                    }
                }

                Section(channel == .email ? "Email preview" : "Text reminder") {
                    TextEditor(text: $editedBody)
                        .frame(minHeight: 160)
                        .onChange(of: editedBody) { _, _ in markEdited() }
                }
            }
            .navigationTitle(channel == .email ? "Review email" : "Review text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open composer") {
                        onApprove(
                            ShiftReminderApprovedMessage(
                                subject: editedSubject,
                                body: editedBody,
                                wasEdited: didEdit
                            )
                        )
                    }
                    .disabled(editedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                editedSubject = subject
                editedBody = channel == .email ? emailBodyPreview : textBody
            }
        }
    }

    private func markEdited() {
        didEdit = true
        GuestCommunicationTrace.messageReview(
            reservationID: reservation.remoteID,
            type: channel == .email ? "reminder" : "textReminder",
            phase: "edited",
            edited: true
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
