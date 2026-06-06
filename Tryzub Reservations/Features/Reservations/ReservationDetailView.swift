//
//  ReservationDetailView.swift
//  Tryzub Reservations
//

import MessageUI
import SwiftUI
import SwiftData
import UIKit

// MARK: - Detail Presentation

struct ReservationDetailPresentation {
    struct Header {
        let guestName: String
        let status: ReservationStatus
        let dateText: String
        let timeText: String
        let partyText: String
        let tableText: String
        let sourceText: String
    }

    struct Row: Identifiable {
        let title: String
        let value: String
        var allowsWrap = false

        var id: String {
            "\(title)-\(value)"
        }
    }

    let header: Header
    let guestRows: [Row]
    let reservationRows: [Row]
    let notesRows: [Row]
    let emailStatus: String
    let actionPolicy: ReservationHostActionPolicy

    static func make(
        reservation: ReservationRecord,
        capabilities: AppCapabilities
    ) -> ReservationDetailPresentation {
        let emailStatus = Self.emailStateText(for: reservation)
        var reservationRows: [Row] = [
            Row(title: "Status", value: reservation.statusValue.displayName),
            Row(title: "Date", value: reservation.displayDate),
            Row(title: "Time", value: reservation.displayTime),
            Row(title: "Party", value: "\(reservation.partySize)"),
            Row(title: "Table", value: reservation.tableDisplay),
            Row(title: "Source", value: reservation.sourceDisplayName),
            Row(title: "Email", value: emailStatus),
            Row(title: "Submitted", value: submittedValue(for: reservation))
        ]

        if let timingText = reservation.operationalTimingState().insightText {
            reservationRows.insert(Row(title: "Timing", value: timingText, allowsWrap: true), at: 1)
        }

        if let confirmedAt = reservation.confirmedAt?.nilIfBlank {
            reservationRows.append(Row(title: "Confirmed", value: serverTimestamp(confirmedAt)))
        }

        var notesRows: [Row] = []
        if let guestNotes = reservation.guestNotes?.nilIfBlank {
            notesRows.append(Row(title: "Guest", value: guestNotes, allowsWrap: true))
        }
        if let staffNotes = reservation.staffNotes?.nilIfBlank {
            notesRows.append(Row(title: "Staff", value: staffNotes, allowsWrap: true))
        }

        return ReservationDetailPresentation(
            header: Header(
                guestName: reservation.guestName,
                status: reservation.statusValue,
                dateText: reservation.displayDate,
                timeText: reservation.displayTime,
                partyText: "\(reservation.partySize) \(reservation.partySize == 1 ? "guest" : "guests")",
                tableText: reservation.tableDisplay,
                sourceText: reservation.sourceDisplayName
            ),
            guestRows: [
                Row(title: "Phone", value: reservation.formattedPhone),
                Row(title: "Email", value: reservation.email.nilIfBlank ?? "No email")
            ],
            reservationRows: reservationRows,
            notesRows: notesRows,
            emailStatus: emailStatus,
            actionPolicy: ReservationHostActionPolicy(
                reservation: reservation,
                capabilities: capabilities,
                surface: .detail
            )
        )
    }

    private static func emailStateText(for reservation: ReservationRecord) -> String {
        if reservation.hasConfirmationEmailRecord {
            return "Email sent (server)"
        }

        if reservation.hasManualConfirmationEmailRecord {
            return "Manual email sent"
        }

        if reservation.hasUsableConfirmationEmail {
            return "Email not sent"
        }

        return "No email"
    }

    private static func serverTimestamp(_ value: String) -> String {
        if let date = ReservationFormatters.serverDateTime.date(from: value) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return value
    }

    private static func submittedValue(for reservation: ReservationRecord) -> String {
        let stamp = serverTimestamp(reservation.createdAt)
        if let ago = reservation.submittedAgoText {
            return "\(stamp) · \(ago)"
        }
        return stamp
    }
}

// MARK: - Manual Confirmation Draft

struct ManualEmailDraftService {
    // Builds copy staff can paste into Gmail/Mail. Does not call POST /confirm.
    static func confirmationSubject(reservation: ReservationRecord) -> String {
        "Your reservation at \(ReservationEmailWorkflow.restaurantName) — \(emailDateLine(for: reservation)) at \(emailTimeLine(for: reservation))"
    }

    static func confirmationPlainBody(
        reservation: ReservationRecord,
        manageLink: ReservationGuestManageLinkDTO
    ) -> String {
        let firstName = guestFirstName(for: reservation)
        let expiresText = formattedExpiresLine(manageLink.expiresAt).map { "\n\($0)" } ?? ""
        let tableLine = reservation.tableName?.nilIfBlank.map { "Table: \($0)\n" } ?? ""
        let guestNotesLine = reservation.guestNotes?.nilIfBlank.map { "Notes: \($0)\n" } ?? ""

        return """
        Dear \(firstName),

        Thank you for choosing \(ReservationEmailWorkflow.restaurantName). Your reservation is confirmed.

        \(emailDateLine(for: reservation))
        \(emailTimeLine(for: reservation))
        Party of \(reservation.partySize)
        \(tableLine)\(guestNotesLine)
        View or manage your reservation online:
        \(manageLink.url)\(expiresText)

        \(ReservationEmailWorkflow.restaurantAddressLine)
        \(ReservationEmailWorkflow.restaurantPhone)
        \(ReservationEmailWorkflow.websiteURL.absoluteString)

        Reservation policies: \(ReservationEmailWorkflow.reservationPoliciesURL.absoluteString)

        We look forward to welcoming you.
        \(ReservationEmailWorkflow.restaurantName)
        """
    }

    static func confirmationHTMLBody(
        reservation: ReservationRecord,
        manageLink: ReservationGuestManageLinkDTO
    ) -> String {
        let firstName = htmlEscape(guestFirstName(for: reservation))
        let dateLine = htmlEscape(emailDateLine(for: reservation))
        let timeLine = htmlEscape(emailTimeLine(for: reservation))
        let expiresHTML = formattedExpiresHTML(manageLink.expiresAt)
        let tableHTML = reservation.tableName?.nilIfBlank.map {
            "<tr><td style=\"padding:6px 0;color:#5c574f;font-size:14px;\">Table</td><td style=\"padding:6px 0;color:#1f1f1f;font-size:15px;font-weight:600;text-align:right;\">\(htmlEscape($0))</td></tr>"
        } ?? ""
        let guestNotesHTML = reservation.guestNotes?.nilIfBlank.map {
            "<tr><td style=\"padding:6px 0;color:#5c574f;font-size:14px;vertical-align:top;\">Notes</td><td style=\"padding:6px 0;color:#1f1f1f;font-size:15px;text-align:right;\">\(htmlEscape($0))</td></tr>"
        } ?? ""
        let linkURL = htmlAttributeEscape(manageLink.url)
        let policiesURL = htmlAttributeEscape(ReservationEmailWorkflow.reservationPoliciesURL.absoluteString)
        let websiteURL = htmlAttributeEscape(ReservationEmailWorkflow.websiteURL.absoluteString)

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
        <p style="margin:0;color:#d8c9a8;font-size:12px;letter-spacing:0.16em;text-transform:uppercase;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;">\(htmlEscape(ReservationEmailWorkflow.restaurantName))</p>
        <h1 style="margin:14px 0 0;color:#ffffff;font-size:26px;line-height:1.25;font-weight:600;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;">Reservation Confirmed</h1>
        </td>
        </tr>
        <tr>
        <td style="padding:34px 34px 10px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#222222;font-size:16px;line-height:1.65;">
        <p style="margin:0 0 18px;">Dear \(firstName),</p>
        <p style="margin:0 0 26px;">Thank you for choosing <strong>\(htmlEscape(ReservationEmailWorkflow.restaurantName))</strong>. We look forward to welcoming you to Ukrainian Village.</p>
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
        <tr><td style="padding:6px 0;color:#5c574f;font-size:14px;">Party size</td><td style="padding:6px 0;color:#1f1f1f;font-size:15px;font-weight:600;text-align:right;">\(reservation.partySize)</td></tr>
        \(tableHTML)
        \(guestNotesHTML)
        </table>
        </td>
        </tr>
        </table>
        <p style="margin:0 0 18px;text-align:center;">
        <a href="\(linkURL)" style="display:inline-block;padding:15px 28px;background-color:#1f6b3a;color:#ffffff;text-decoration:none;border-radius:999px;font-size:16px;font-weight:700;letter-spacing:0.01em;">View or Manage Reservation</a>
        </p>
        <p style="margin:0 0 28px;font-size:14px;line-height:1.6;color:#666666;text-align:center;">Use your private link to view reservation details, request changes, or cancel within the allowed time window.</p>
        \(expiresHTML)
        <p style="margin:0;font-size:14px;line-height:1.7;color:#5c574f;text-align:center;">
        \(htmlEscape(ReservationEmailWorkflow.restaurantAddressLine))<br>
        \(htmlEscape(ReservationEmailWorkflow.restaurantPhone)) · <a href="\(websiteURL)" style="color:#1f6b3a;text-decoration:none;">tryzubchicago.com</a>
        </p>
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

    static func confirmationDraft(
        reservation: ReservationRecord,
        manageLink: ReservationGuestManageLinkDTO
    ) -> String {
        """
        Subject: \(confirmationSubject(reservation: reservation))

        \(confirmationPlainBody(reservation: reservation, manageLink: manageLink))
        """
    }

    static func emailDateLine(for reservation: ReservationRecord) -> String {
        guard let date = ReservationFormatters.reservationDateKey.date(from: reservation.reservationDate) else {
            return reservation.displayDate
        }

        return emailLongDateFormatter.string(from: date)
    }

    static func emailTimeLine(for reservation: ReservationRecord) -> String {
        guard let date = ReservationFormatters.apiTime.date(from: reservation.reservationTime) else {
            return reservation.displayTime
        }

        return emailLongTimeFormatter.string(from: date)
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

    private static func guestFirstName(for reservation: ReservationRecord) -> String {
        reservation.guestName
            .split(separator: " ")
            .first
            .map(String.init) ?? reservation.guestName
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
}

// MARK: - Reservation Detail

struct ReservationDetailView: View {
    let reservation: ReservationRecord
    let environment: AppEnvironment

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    // Guest Insights reads cached reservations only; no network or mutation is involved.
    @Query(sort: [
        SortDescriptor(\ReservationRecord.reservationDate),
        SortDescriptor(\ReservationRecord.reservationTime)
    ])
    private var allCachedReservations: [ReservationRecord]

    // MARK: - Local UI State

    @State private var showEditScreen = false
    @State private var isSavingQuickAction = false
    @State private var errorMessage: String?
    @State private var pendingAction: ReservationHostAction?
    @State private var tableAssignmentReservation: ReservationRecord?
    @State private var isShowingHideWrongEntryConfirmation = false
    @State private var guestManageLink: ReservationGuestManageLinkDTO?
    @State private var guestManageLinkMessage: String?
    @State private var isGeneratingGuestManageLink = false
    @State private var guestConfirmationMailDraft: GuestConfirmationMailPresenter.Draft?
    @State private var guestInsightReport: GuestInsightReport?

    var body: some View {
        GeometryReader { proxy in
            let safeWidth = proxy.size.width.tryzubFiniteNonNegativeLayoutValue
            let isWide = safeWidth >= 760
            ScrollView {
                detailContent(isWide: isWide)
                    .padding(.horizontal, isWide ? 20 : 16)
                    .padding(.vertical, 16)
                    .padding(.bottom, 92)
                    .cappedContentWidth(isWide ? 1000 : nil)
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle(reservation.guestName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $tableAssignmentReservation) { reservation in
            TableAssignmentSheet(reservation: reservation) { tableName in
                // Table assignment is a server PATCH through the controller.
                _ = try await controller.updateReservation(
                    id: reservation.remoteID,
                    request: ReservationUpdateRequest(tableName: tableName),
                    context: modelContext
                )
            }
        }
        .sheet(item: $guestConfirmationMailDraft) { draft in
            GuestConfirmationMailComposer(draft: draft) { result in
                handleGuestConfirmationMailFinished(result)
            }
        }
        .navigationDestination(isPresented: $showEditScreen) {
            ReservationEditFormView(reservation: reservation) { request in
                // Detail edits are server PATCH operations through the controller.
                try await controller.updateReservation(
                    id: reservation.remoteID,
                    request: request,
                    context: modelContext
                )
            }
        }
        .confirmationDialog(
            pendingAction?.dialogTitle(for: reservation) ?? "Update Reservation?",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingAction {
                if pendingAction == .confirmOnly {
                    Button("Confirm only") {
                        Task {
                            await perform(.confirmOnly)
                        }
                    }

                    ReservationConfirmDialog.backendEmailButton(
                        hasUsableEmail: reservation.hasUsableConfirmationEmail
                    ) {
                        Task {
                            await perform(.confirmAndSendEmail)
                        }
                    }
                } else {
                    Button(pendingAction.fullTitle, role: pendingAction.role) {
                        Task {
                            await perform(pendingAction)
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            if let pendingAction {
                Text(pendingAction.dialogMessage(for: reservation))
            }
        }
        .confirmationDialog(
            "Hide wrong entry?",
            isPresented: $isShowingHideWrongEntryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Hide wrong entry", role: .destructive) {
                Task {
                    await hideWrongManualEntry()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This hides the server reservation from normal lists while keeping it in backend history.")
        }
        .task(id: guestInsightCacheKey) {
            // Cache-only hospitality analysis. Compute outside body so detail
            // rendering and row mutations do not repeatedly scan all records.
            guestInsightReport = GuestInsightsController().analyze(
                selected: reservation,
                allReservations: allCachedReservations
            )
        }
    }

    // MARK: - Detail Layout

    @ViewBuilder
    private func detailContent(isWide: Bool) -> some View {
        let presentation = ReservationDetailPresentation.make(
            reservation: reservation,
            capabilities: controller.capabilities
        )

        VStack(alignment: .leading, spacing: 14) {
            banners

            if isWide {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 14) {
                        DetailHeroCard(header: presentation.header)
                        actionBar
                        contactCard
                    }
                    .frame(width: 360)

                    VStack(spacing: 14) {
                        notesCard(presentation)
                        detailsCard(presentation)
                        ReservationServiceLoadCard(
                            reservation: reservation,
                            sameDayReservations: sameDayReservations
                        )
                        guestInsightsSection
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 14) {
                    DetailHeroCard(header: presentation.header)
                    actionBar
                    contactCard
                    notesCard(presentation)
                    detailsCard(presentation)
                    ReservationServiceLoadCard(
                        reservation: reservation,
                        sameDayReservations: sameDayReservations
                    )
                    guestInsightsSection
                }
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
        if let message = errorMessage ?? controller.errorMessage {
            DetailWarningCard(
                title: "Action did not finish",
                message: message,
                symbolName: "exclamationmark.triangle",
                tint: .red
            )
        }

        if let attention = attentionExplanation {
            DetailWarningCard(
                title: attention.title,
                message: attention.message,
                symbolName: attention.symbol,
                tint: attention.tint
            )
        }

        if let guestManageLinkMessage {
            DetailWarningCard(
                title: "Guest link ready",
                message: guestManageLinkMessage,
                symbolName: "link",
                tint: TryzubColors.info
            )
        }
    }

    private var actionBar: some View {
        DetailActionBar(
            reservation: reservation,
            capabilities: controller.capabilities,
            isBusy: isSavingQuickAction || controller.isActionInProgress(for: reservation),
            isNetworkDegraded: controller.isNetworkDegraded,
            isGeneratingGuestManageLink: isGeneratingGuestManageLink,
            hasGuestManageLink: guestManageLink != nil,
            onAction: handleAction,
            onEdit: { showEditScreen = true },
            onSendGuestConfirmationEmail: controller.capabilities.canGenerateGuestManageLinks
                ? { Task { await sendGuestConfirmationEmail() } }
                : nil,
            onGenerateGuestManageLink: controller.capabilities.canGenerateGuestManageLinks
                ? { Task { await generateGuestManageLink() } }
                : nil,
            onCopyGuestManageLink: guestManageLink != nil
                ? { copyGuestManageLink() }
                : nil,
            onCopyConfirmationDraft: guestManageLink != nil
                ? { copyGuestConfirmationDraft() }
                : nil,
            onHideWrongEntry: reservation.canSoftHideAsWrongEntry && !reservation.isHidden
                ? { isShowingHideWrongEntryConfirmation = true }
                : nil,
            onRestoreHidden: reservation.isHidden
                ? { Task { await restoreHiddenReservation() } }
                : nil
        )
    }

    private var contactCard: some View {
        DetailSectionCard(title: "Contact", systemImage: "phone.fill") {
            VStack(spacing: 10) {
                DetailContactRow(
                    title: "Phone",
                    value: reservation.formattedPhone,
                    url: reservation.callURL
                )
                Divider().opacity(0.4)
                DetailContactRow(
                    title: "Email",
                    value: reservation.hasUsableConfirmationEmail ? reservation.email : "No email",
                    url: reservation.mailtoURL
                )
            }
        }
    }

    private func notesCard(_ presentation: ReservationDetailPresentation) -> some View {
        DetailSectionCard(title: "Notes", systemImage: "note.text") {
            if presentation.notesRows.isEmpty {
                DetailPlainLine("No guest or staff notes")
            } else {
                VStack(spacing: 10) {
                    ForEach(presentation.notesRows) { row in
                        DetailDataRow(title: row.title, value: row.value, allowsWrap: row.allowsWrap)
                    }
                }
            }
        }
    }

    private func detailsCard(_ presentation: ReservationDetailPresentation) -> some View {
        DetailSectionCard(title: "Reservation details", systemImage: "fork.knife") {
            VStack(spacing: 10) {
                ForEach(presentation.reservationRows) { row in
                    DetailDataRow(title: row.title, value: row.value, allowsWrap: row.allowsWrap)
                }
            }
        }
    }

    private var sameDayReservations: [ReservationRecord] {
        allCachedReservations.filter {
            $0.reservationDate == reservation.reservationDate && !$0.isHidden
        }
    }

    // Human explanation of why this reservation needs attention right now.
    private var attentionExplanation: (title: String, message: String, symbol: String, tint: Color)? {
        let timing = reservation.operationalTimingState()

        if reservation.statusValue == .needsReview {
            return (
                "Needs review",
                "Check this reservation before confirming. Guest Notes and Staff Notes are shown separately below.",
                "exclamationmark.triangle",
                .orange
            )
        }

        if case .overdue = timing, let text = timing.insightText {
            return ("Running late", "\(text). The reservation time has passed and it is not seated yet.", "exclamationmark.triangle", .red)
        }

        if reservation.statusValue == .new, let ago = reservation.submittedAgoText {
            return ("Awaiting confirmation", "Submitted \(ago). Confirm to notify the guest and lock the table.", "clock.badge.exclamationmark", TryzubColors.info)
        }

        return nil
    }

    @ViewBuilder
    private var guestInsightsSection: some View {
        if let guestInsightReport {
            NavigationLink {
                GuestInsightsView(
                    selectedReservation: reservation,
                    allReservations: allCachedReservations
                )
            } label: {
                GuestInsightsPreviewCard(report: guestInsightReport)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            DetailSectionCard(title: "Guest insights", systemImage: "person.text.rectangle") {
                TryzubLoadingRow(title: "Loading guest insights...")
            }
        }
    }

    private var guestInsightCacheKey: ReservationDetailGuestInsightCacheKey {
        ReservationDetailGuestInsightCacheKey(
            selectedReservation: reservation,
            reservations: allCachedReservations
        )
    }

    // MARK: - Staff Action Routing

    // View sends staff intent only; controller owns network and cache writes.
    private func handleAction(_ action: ReservationHostAction) {
        if action == .assignTable {
            tableAssignmentReservation = reservation
        } else if action == .confirmOnly || action == .confirmAndSendEmail || action == .cancel || action == .noShow {
            pendingAction = action
        } else {
            Task {
                await perform(action)
            }
        }
    }

    // Intent: Converts detail actions into controller calls.
    // Confirm = PATCH status confirmed; Confirm + Email = POST /confirm.
    private func perform(_ action: ReservationHostAction) async {
        pendingAction = nil
        isSavingQuickAction = true
        errorMessage = nil

        defer {
            isSavingQuickAction = false
        }

        switch action {
        case .confirmOnly:
            await controller.updateStatus(reservation: reservation, status: .confirmed, context: modelContext)
            ReservationHaptics.success()
        case .confirmAndSendEmail:
            guard ReservationEmailWorkflow.isBackendConfirmEmailEnabled else { return }
            await controller.confirmReservation(reservation: reservation, context: modelContext)
            ReservationHaptics.success()
        case .seat:
            await controller.updateStatus(reservation: reservation, status: .seated, context: modelContext)
            ReservationHaptics.success()
        case .complete:
            await controller.updateStatus(reservation: reservation, status: .completed, context: modelContext)
            ReservationHaptics.success()
        case .cancel:
            await controller.updateStatus(reservation: reservation, status: .cancelled, context: modelContext)
            ReservationHaptics.warning()
        case .noShow:
            await controller.updateStatus(reservation: reservation, status: .noShow, context: modelContext)
            ReservationHaptics.warning()
        case .assignTable:
            tableAssignmentReservation = reservation
        }
    }

    // Intent: Hide a mistaken manual entry without hard-deleting server data.
    // Network: PATCH /managed-reservations/{id} is_hidden=true.
    private func hideWrongManualEntry() async {
        isSavingQuickAction = true
        errorMessage = nil

        defer {
            isSavingQuickAction = false
        }

        do {
            _ = try await controller.hideWrongEntry(
                reservation: reservation,
                context: modelContext
            )
            ReservationHaptics.warning()
        } catch {
            errorMessage = "Could not hide this entry. Please retry before relying on service lists."
            ReservationHaptics.warning()
        }
    }

    // Intent: Restores a hidden server row from detail.
    // Network: PATCH /managed-reservations/{id} is_hidden=false.
    private func restoreHiddenReservation() async {
        isSavingQuickAction = true
        errorMessage = nil

        defer {
            isSavingQuickAction = false
        }

        do {
            _ = try await controller.restoreHiddenReservation(
                reservation: reservation,
                context: modelContext
            )
            ReservationHaptics.success()
        } catch {
            errorMessage = "Could not restore this reservation. Please retry."
            ReservationHaptics.warning()
        }
    }

    // Intent: Prepares a self-service URL for manual confirmation email copy.
    // Network: POST /managed-reservations/{id}/guest-manage-link.
    // Email: Does not send email and does not mark confirmation email as sent.
    private func generateGuestManageLink() async {
        guard !isGeneratingGuestManageLink else { return }

        isGeneratingGuestManageLink = true
        errorMessage = nil
        guestManageLinkMessage = nil

        defer {
            isGeneratingGuestManageLink = false
        }

        do {
            let link = try await controller.generateGuestManageLink(reservation: reservation)
            guestManageLink = link
            UIPasteboard.general.string = link.url
            guestManageLinkMessage = "Guest link copied. You can also send a confirmation email from More."
            ReservationHaptics.success()
        } catch {
            errorMessage = "Could not generate a guest link. Please retry."
            ReservationHaptics.warning()
        }
    }

    private func sendGuestConfirmationEmail() async {
        guard !isGeneratingGuestManageLink else { return }

        let email = reservation.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            errorMessage = "Add a guest email in Edit before sending confirmation."
            ReservationHaptics.warning()
            return
        }

        isGeneratingGuestManageLink = true
        errorMessage = nil
        guestManageLinkMessage = nil

        defer {
            isGeneratingGuestManageLink = false
        }

        do {
            let link = try await controller.generateGuestManageLink(
                reservation: reservation,
                announceNotice: false
            )
            guestManageLink = link

            guard let draft = GuestConfirmationMailPresenter.draft(
                reservation: reservation,
                manageLink: link
            ) else {
                errorMessage = "Add a guest email in Edit before sending confirmation."
                ReservationHaptics.warning()
                return
            }

            if GuestConfirmationMailPresenter.canSendMail() {
                guestConfirmationMailDraft = draft
                ReservationHaptics.success()
            } else if GuestConfirmationMailPresenter.openMailtoFallback(draft: draft) {
                guestManageLinkMessage = "Opened Mail with a plain-text confirmation draft."
                ReservationHaptics.success()
            } else {
                UIPasteboard.general.string = ManualEmailDraftService.confirmationDraft(
                    reservation: reservation,
                    manageLink: link
                )
                guestManageLinkMessage = "Mail isn’t set up on this device. Confirmation draft copied."
                ReservationHaptics.success()
            }
        } catch {
            errorMessage = "Could not prepare the confirmation email. Please retry."
            ReservationHaptics.warning()
        }
    }

    private func copyGuestManageLink() {
        guard let url = guestManageLink?.url else { return }
        UIPasteboard.general.string = url
        guestManageLinkMessage = "Guest link copied. Paste it into your email if needed."
        ReservationHaptics.success()
    }

    private func copyGuestConfirmationDraft() {
        guard let guestManageLink else { return }
        UIPasteboard.general.string = ManualEmailDraftService.confirmationDraft(
            reservation: reservation,
            manageLink: guestManageLink
        )
        guestManageLinkMessage = "Plain confirmation draft copied."
        ReservationHaptics.success()
    }

    private func handleGuestConfirmationMailFinished(_ result: MFMailComposeResult) {
        guestConfirmationMailDraft = nil

        switch result {
        case .sent:
            Task {
                await finalizeManualConfirmationAfterSend()
            }
        case .cancelled, .saved, .failed:
            guestManageLinkMessage = "Confirmation email was not sent. Reservation was not confirmed."
        @unknown default:
            guestManageLinkMessage = "Confirmation email was not sent. Reservation was not confirmed."
        }
    }

    private func finalizeManualConfirmationAfterSend() async {
        do {
            _ = try await controller.recordManualConfirmationSent(
                reservation: reservation,
                context: modelContext
            )
            guestManageLinkMessage = "Confirmation email sent and reservation recorded."
            ReservationHaptics.success()
        } catch {
            errorMessage = "Email was sent, but the reservation could not be recorded on the server. Check details and retry if needed."
            ReservationHaptics.warning()
        }
    }
}

private struct ReservationDetailGuestInsightCacheKey: Hashable {
    let selectedID: Int
    let visibleCount: Int
    let maxLastSyncedAt: Date?
    let maxUpdatedAt: Date?

    init(selectedReservation: ReservationRecord, reservations: [ReservationRecord]) {
        selectedID = selectedReservation.remoteID
        let visible = reservations.filter { !$0.isHidden }
        visibleCount = visible.count
        maxLastSyncedAt = visible.map(\.lastSyncedAt).max()
        maxUpdatedAt = visible.compactMap(\.updatedAt).max()
    }
}

// MARK: - Service Load Card

private struct ReservationServiceLoadCard: View {
    let reservation: ReservationRecord
    let sameDayReservations: [ReservationRecord]

    private var slots: [ServiceTimelineSlot] {
        ServiceTimeline.slots(from: sameDayReservations)
    }

    private var highlightHour: Int? {
        Int(reservation.reservationTime.prefix(2))
    }

    private var summaryText: String {
        let expected = sameDayReservations.filter(\.isExpectedGuest)
        let guests = expected.reduce(0) { $0 + $1.partySize }
        let reservationWord = expected.count == 1 ? "reservation" : "reservations"
        return "\(expected.count) \(reservationWord) · \(guests) guests on \(reservation.displayDate)"
    }

    var body: some View {
        DetailSectionCard(title: "Service load", systemImage: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(TryzubColors.primaryControl)
                        .frame(width: 9, height: 9)
                    Text("This reservation's hour")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

                ServiceLoadChart(slots: slots, highlightHour: highlightHour, height: 130)

                Text(summaryText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

// MARK: - Guest Insights Entry

private struct GuestInsightsPreviewCard: View {
    let report: GuestInsightReport

    private var previousReservationText: String {
        let previousCount = max(report.summary.totalMatchedReservations - 1, 0)
        if previousCount == 0 {
            return "No previous reservations found"
        }
        return "\(previousCount) previous \(previousCount == 1 ? "reservation" : "reservations")"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "person.text.rectangle")
                .font(.headline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color(.systemGray6), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Guest Insights")
                        .font(.headline.weight(.medium))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Text(previousReservationText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                FlowLayout(spacing: 7) {
                    GuestRegularityBadge(level: report.regularityLevel)
                    if !report.staffMentionHistory.isEmpty {
                        DetailPill(label: "Staff notes", systemImage: "note.text", tint: .secondary)
                    }
                    if !report.possibleMatches.isEmpty {
                        DetailPill(label: "Possible match", systemImage: "person.2", tint: .secondary)
                    }
                }
                .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - Reservation Hero Card

private struct DetailHeroCard: View {
    let header: ReservationDetailPresentation.Header

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(header.timeText)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(header.dateText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                ReservationStatusBadge(status: header.status)
            }

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 10) {
                Text(header.guestName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                FlowLayout(spacing: 7) {
                    DetailPill(label: header.partyText, systemImage: "person.2", tint: .secondary)
                    DetailPill(label: header.tableText, systemImage: "table.furniture", tint: .secondary)
                    DetailPill(label: header.sourceText, systemImage: "tray.and.arrow.down", tint: .secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - Reservation Action Bar

private struct DetailActionBar: View {
    let reservation: ReservationRecord
    let capabilities: AppCapabilities
    let isBusy: Bool
    let isNetworkDegraded: Bool
    let isGeneratingGuestManageLink: Bool
    let hasGuestManageLink: Bool
    let onAction: (ReservationHostAction) -> Void
    let onEdit: () -> Void
    let onSendGuestConfirmationEmail: (() -> Void)?
    let onGenerateGuestManageLink: (() -> Void)?
    let onCopyGuestManageLink: (() -> Void)?
    let onCopyConfirmationDraft: (() -> Void)?
    let onHideWrongEntry: (() -> Void)?
    let onRestoreHidden: (() -> Void)?

    private var policy: ReservationHostActionPolicy {
        ReservationHostActionPolicy(
            reservation: reservation,
            capabilities: capabilities,
            surface: .detail
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            if isNetworkDegraded {
                Label("Offline — edits require internet.", systemImage: "wifi.slash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TryzubColors.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ReservationActionButtons(
                reservation: reservation,
                capabilities: capabilities,
                compact: false,
                includeSecondary: false,
                isBusy: isBusy || isNetworkDegraded,
                onAction: onAction
            )
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                secondaryButton(title: "Edit", systemImage: "pencil") {
                    onEdit()
                }
                .disabled(!capabilities.canEditReservationDetails || isNetworkDegraded)

                if showsMoreMenu {
                    moreMenu
                        .disabled(isNetworkDegraded)
                }
            }
        }
    }

    private func secondaryButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.82))
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
    }

    private var moreMenu: some View {
        Menu {
            ForEach(policy.detailSecondaryActions) { action in
                Button(role: action.role) {
                    onAction(action)
                } label: {
                    Label(action.fullTitle, systemImage: action.systemImage)
                }
            }

            if !policy.detailSecondaryActions.isEmpty,
               hasAdminActions {
                Divider()
            }

            if let onSendGuestConfirmationEmail {
                Button {
                    onSendGuestConfirmationEmail()
                } label: {
                    Label(
                        isGeneratingGuestManageLink ? "Preparing email" : "Send confirmation email",
                        systemImage: "envelope"
                    )
                }
                .disabled(isGeneratingGuestManageLink)
            }

            if let onGenerateGuestManageLink {
                Button {
                    onGenerateGuestManageLink()
                } label: {
                    Label(
                        isGeneratingGuestManageLink ? "Generating guest link" : "Manual guest link",
                        systemImage: "link.badge.plus"
                    )
                }
                .disabled(isGeneratingGuestManageLink)
            }

            if hasGuestManageLink, let onCopyGuestManageLink {
                Button {
                    onCopyGuestManageLink()
                } label: {
                    Label("Copy guest link", systemImage: "doc.on.doc")
                }
            }

            if hasGuestManageLink, let onCopyConfirmationDraft {
                Button {
                    onCopyConfirmationDraft()
                } label: {
                    Label("Copy plain draft", systemImage: "doc.plaintext")
                }
            }

            if (onSendGuestConfirmationEmail != nil || onGenerateGuestManageLink != nil || onCopyGuestManageLink != nil || onCopyConfirmationDraft != nil),
               onHideWrongEntry != nil || onRestoreHidden != nil {
                Divider()
            }

            if let onHideWrongEntry {
                Button(role: .destructive) {
                    onHideWrongEntry()
                } label: {
                    Label("Hide wrong entry", systemImage: "archivebox")
                }
            }

            if let onRestoreHidden {
                Button {
                    onRestoreHidden()
                } label: {
                    Label("Restore to lists", systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.82))
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .disabled(isBusy || isGeneratingGuestManageLink)
    }

    private var showsMoreMenu: Bool {
        !policy.detailSecondaryActions.isEmpty || hasAdminActions
    }

    private var hasAdminActions: Bool {
        onSendGuestConfirmationEmail != nil
            || onGenerateGuestManageLink != nil
            || onCopyGuestManageLink != nil
            || onCopyConfirmationDraft != nil
            || onHideWrongEntry != nil
            || onRestoreHidden != nil
    }
}

// MARK: - Shared Detail Components

private struct DetailSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(1)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct DetailDataRow: View {
    let title: String
    let value: String
    var allowsWrap = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.84))
                .lineLimit(allowsWrap ? 2 : 1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DetailContactRow: View {
    let title: String
    let value: String
    let url: URL?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)

            if let url {
                Link(destination: url) {
                    HStack(spacing: 5) {
                        Text(value)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: title == "Phone" ? "phone.fill" : "envelope.fill")
                            .font(.caption2)
                    }
                    .foregroundStyle(TryzubColors.info)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct DetailPlainLine: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DetailWarningCard: View {
    let title: String
    let message: String
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.medium))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct DetailPill: View {
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
    }
}

// MARK: - Detail String Helpers

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfBlank: String? {
        let trimmed = trimmed
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Reservation Detail") {
    NavigationStack {
        ReservationDetailView(
            reservation: ReservationPreviewData.sampleRecord,
            environment: AppEnvironment(apiClient: ReservationsAPIClient.preview, role: .developer)
        )
    }
    .modelContainer(ReservationPreviewData.previewContainer)
    .environmentObject(
        ReservationsController(
            environment: AppEnvironment(apiClient: ReservationsAPIClient.preview, role: .developer)
        )
    )
    .environmentObject(HiddenReservationsStore())
}
#endif
