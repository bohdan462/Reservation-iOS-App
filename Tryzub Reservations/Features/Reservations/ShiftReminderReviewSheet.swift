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
                        VStack(alignment: .leading, spacing: 6) {
                            summaryLine
                            Text("Review before sending. Nothing is sent automatically.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Replies are not tracked here. Guests are directed to call or email \(ReservationEmailWorkflow.guestContactEmail).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    Section {
                        ForEach(reservations) { reservation in
                            row(for: reservation)
                        }
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
        Text("\(daySummaryLabel) · \(summary.eligible) eligible · \(summary.emailReady) email · \(summary.smsReady) text")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var daySummaryLabel: String {
        let calendar = Calendar.current
        if let date = ReservationFormatters.reservationDateKey.date(from: dateKey) {
            if calendar.isDateInToday(date) {
                return "Today"
            }
            return Self.shortDateFormatter.string(from: date)
        }
        return dateKey
    }

    @ViewBuilder
    private func row(for reservation: ReservationRecord) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reservation.guestName)
                        .font(.subheadline.weight(.semibold))
                    Text("\(reservation.displayTime) · \(reservation.partySize) guest\(reservation.partySize == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    contactChips(for: reservation)
                }
                Spacer()
                if let result = results[reservation.remoteID] {
                    Text(result)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if reservation.reminderEmailSentAt?.nilIfBlank != nil {
                    Text("sent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                if reservation.hasUsableConfirmationEmail {
                    Button("Email") {
                        presentReview(for: reservation, channel: .email)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if GuestTextMessagePresenter.hasDialablePhone(reservation.phone) {
                    Button("Text") {
                        presentReview(for: reservation, channel: .sms)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Button("Skip") {
                    results[reservation.remoteID] = "skipped"
                    trace(reservation, channel: "email", result: "skipped")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private func contactChips(for reservation: ReservationRecord) -> some View {
        HStack(spacing: 5) {
            if reservation.hasUsableConfirmationEmail {
                chip("Email")
            }
            if GuestTextMessagePresenter.hasDialablePhone(reservation.phone) {
                chip("Text")
            }
        }
    }

    private func chip(_ label: String) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
    }

    private func presentReview(for reservation: ReservationRecord, channel: ShiftReminderChannel) {
        let textBody = ManualTextMessageService.reminderBody(reservation: reservation)
        let emailPreview = "This is a reminder for your reservation at \(ReservationEmailWorkflow.restaurantName) today."
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
            linkExpiresAt: nil,
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

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d"
        return formatter
    }()
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
                        Label("AI draft — review before sending.", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reservation.guestName)
                            .font(.subheadline.weight(.semibold))
                        Text("\(reservation.displayTime) · party of \(reservation.partySize)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Nothing is sent automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                if channel == .email {
                    Section("Subject") {
                        TextField("Subject", text: $editedSubject)
                            .onChange(of: editedSubject) { _, _ in markEdited() }
                    }
                }

                Section {
                    TextEditor(text: $editedBody)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: channel == .email ? 108 : 88)
                        .onChange(of: editedBody) { _, _ in markEdited() }
                } header: {
                    Text(channel == .email ? "Email message" : "Text message")
                } footer: {
                    if channel == .email {
                        Text("Composer uses the styled Tryzub email.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Review reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(channel == .email ? "Open Email" : "Open Text") {
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
                GuestCommunicationTrace.messageReviewPolish(
                    reservationID: reservation.remoteID,
                    type: channel == .email ? "reminder" : "textReminder",
                    fields: channel == .email ? "subject,email" : "text"
                )
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
