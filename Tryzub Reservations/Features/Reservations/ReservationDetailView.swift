//
//  ReservationDetailView.swift
//  Tryzub Reservations
//

import SwiftUI
import SwiftData

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

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                detailContent(isWide: proxy.size.width >= 760)
                    .padding(.horizontal, proxy.size.width >= 760 ? 20 : 16)
                    .padding(.vertical, 16)
                    .padding(.bottom, 92)
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle(reservation.guestName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showEditScreen = true
                    } label: {
                        Label("Edit Details", systemImage: "pencil")
                    }
                    .disabled(!controller.capabilities.canEditReservationDetails)

                    if reservation.canSoftHideAsWrongEntry && !reservation.isHidden {
                        Button(role: .destructive) {
                            isShowingHideWrongEntryConfirmation = true
                        } label: {
                            Label("Hide wrong entry", systemImage: "archivebox")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
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

                    if reservation.hasUsableConfirmationEmail {
                        Button("Confirm + Email") {
                            Task {
                                await perform(.confirmAndSendEmail)
                            }
                        }
                    } else {
                        Button("Confirm + Email") {}
                            .disabled(true)
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
    }

    // MARK: - Detail Layout

    @ViewBuilder
    private func detailContent(isWide: Bool) -> some View {
        // Read-only hospitality analysis from the local SwiftData cache.
        let insightReport = GuestInsightsController().analyze(
            selected: reservation,
            allReservations: allCachedReservations
        )

        VStack(alignment: .leading, spacing: 14) {
            if let message = errorMessage ?? controller.errorMessage {
                DetailWarningCard(
                    title: "Action did not finish",
                    message: message,
                    symbolName: "exclamationmark.triangle",
                    tint: .red
                )
            }

            if reservation.statusValue == .needsReview {
                DetailWarningCard(
                    title: "Needs review",
                    message: "Check this reservation before confirming.",
                    symbolName: "exclamationmark.triangle",
                    tint: .orange
                )
            }

            if isWide {
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 14) {
                        ReservationHeroCard(
                            reservation: reservation,
                            capabilities: controller.capabilities,
                            isBusy: isSavingQuickAction || controller.isActionInProgress(for: reservation),
                            onAction: handleAction,
                            onEdit: { showEditScreen = true }
                        )
                        ReservationNotesCard(reservation: reservation) {
                            showEditScreen = true
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(spacing: 14) {
                        ReservationContactCard(reservation: reservation)
                        NavigationLink {
                            GuestInsightsView(
                                selectedReservation: reservation,
                                allReservations: allCachedReservations
                            )
                        } label: {
                            GuestInsightsPreviewCard(report: insightReport)
                        }
                        .buttonStyle(.plain)
                        ReservationEmailHistoryCard(
                            reservation: reservation,
                            latestEmailStatus: controller.latestEmailStatusByReservationID[reservation.remoteID]
                        )
                        ReservationFactsCard(reservation: reservation)
                        ReservationOperationalCard(reservation: reservation)
                    }
                    .frame(maxWidth: 420, alignment: .topLeading)
                }
            } else {
                ReservationHeroCard(
                    reservation: reservation,
                    capabilities: controller.capabilities,
                    isBusy: isSavingQuickAction || controller.isActionInProgress(for: reservation),
                    onAction: handleAction,
                    onEdit: { showEditScreen = true }
                )
                ReservationContactCard(reservation: reservation)
                NavigationLink {
                    GuestInsightsView(
                        selectedReservation: reservation,
                        allReservations: allCachedReservations
                    )
                } label: {
                    GuestInsightsPreviewCard(report: insightReport)
                }
                .buttonStyle(.plain)
                ReservationEmailHistoryCard(
                    reservation: reservation,
                    latestEmailStatus: controller.latestEmailStatusByReservationID[reservation.remoteID]
                )
                ReservationFactsCard(reservation: reservation)
                ReservationNotesCard(reservation: reservation) {
                    showEditScreen = true
                }
                ReservationOperationalCard(reservation: reservation)
            }
        }
    }

    // MARK: - Staff Action Routing

    // View sends staff intent only; controller owns network and cache writes.
    private func handleAction(_ action: ReservationHostAction) {
        if action == .assignTable {
            tableAssignmentReservation = reservation
        } else if action == .seat, !reservation.hasTableAssignment {
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
    private func perform(_ action: ReservationHostAction, allowSeatWithoutTable: Bool = false) async {
        if action == .seat, !allowSeatWithoutTable, !reservation.hasTableAssignment {
            pendingAction = nil
            tableAssignmentReservation = reservation
            return
        }

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

// MARK: - Reservation Hero Postcard

private struct ReservationHeroCard: View {
    let reservation: ReservationRecord
    let capabilities: AppCapabilities
    let isBusy: Bool
    let onAction: (ReservationHostAction) -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reservation")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(reservation.displayTime)
                        .font(.system(size: 32, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(reservation.displayDate)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .layoutPriority(2)

                Spacer()

                ReservationStatusBadge(status: reservation.statusValue)
            }

            ReservationDashedLine()
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 6) {
                Text(reservation.guestName)
                    .font(.title3.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 8) {
                    DetailPill(label: "\(reservation.partySize)", systemImage: "person.2", tint: .secondary)
                    DetailPill(label: reservation.tableDisplay, systemImage: "table.furniture", tint: .secondary)
                    if reservation.hasConfirmationEmailRecord {
                        DetailPill(label: "Email recorded", systemImage: "envelope.badge", tint: .secondary)
                    }
                }
                .lineLimit(1)
            }

            if let staffNotes = reservation.staffNotes?.nilIfBlank {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Staff notes", systemImage: "note.text")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text(staffNotes)
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            ReservationActionButtons(
                reservation: reservation,
                capabilities: capabilities,
                compact: false,
                includeSecondary: true,
                isBusy: isBusy,
                onAction: onAction
            )

            Button {
                onEdit()
            } label: {
                Label("Edit Details", systemImage: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.82))
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.plain)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
            .disabled(!capabilities.canEditReservationDetails)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .overlay(postcardNotches)
    }

    private var postcardNotches: some View {
        HStack {
            Circle()
                .fill(Color(.systemGroupedBackground))
                .frame(width: 16, height: 16)
                .offset(x: -8)

            Spacer()

            Circle()
                .fill(Color(.systemGroupedBackground))
                .frame(width: 16, height: 16)
                .offset(x: 8)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Contact / Facts / Notes Cards

private struct ReservationContactCard: View {
    let reservation: ReservationRecord

    private var phoneURL: URL? {
        let digits = reservation.phone.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel://\(digits)")
    }

    private var emailURL: URL? {
        guard let email = reservation.email.nilIfBlank else {
            return nil
        }
        return URL(string: "mailto:\(email)")
    }

    var body: some View {
        DetailCard(title: "Contact", systemImage: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 12) {
                if let phoneURL {
                    Link(destination: phoneURL) {
                        DetailContactLine(title: "Phone", value: reservation.formattedPhone, systemImage: "phone")
                    }
                    .buttonStyle(.plain)
                } else {
                    DetailContactLine(title: "Phone", value: reservation.formattedPhone, systemImage: "phone")
                }

                if let emailURL {
                    Link(destination: emailURL) {
                        DetailContactLine(title: "Email", value: reservation.email, systemImage: "envelope")
                    }
                    .buttonStyle(.plain)
                } else {
                    DetailContactLine(title: "Email", value: reservation.email.nilIfBlank ?? "No email", systemImage: "envelope")
                }
            }
        }
    }
}

private struct ReservationFactsCard: View {
    let reservation: ReservationRecord

    var body: some View {
        DetailCard(title: "Reservation", systemImage: "calendar") {
            VStack(spacing: 10) {
                DetailInfoRow(title: "Date", value: reservation.displayDate)
                DetailInfoRow(title: "Time", value: reservation.displayTime, monospaced: true)
                DetailInfoRow(title: "Party", value: "\(reservation.partySize) guests", monospaced: true)
                DetailInfoRow(title: "Table", value: reservation.tableDisplay)
                DetailInfoRow(title: "Status", value: reservation.statusValue.displayName)
            }
        }
    }
}

private struct ReservationEmailHistoryCard: View {
    let reservation: ReservationRecord
    let latestEmailStatus: ReservationEmailStatus?

    private var sentText: String? {
        guard reservation.confirmationEmailSentAt?.nilIfBlank != nil else {
            return nil
        }

        return DetailDateFormatting.server(reservation.confirmationEmailSentAt)
    }

    private var statusTitle: String {
        if sentText != nil {
            return "Confirmation email recorded"
        }

        if reservation.statusValue == .confirmed, reservation.email.nilIfBlank == nil {
            return "No guest email"
        }

        if reservation.statusValue == .confirmed {
            return "Email not recorded"
        }

        return "Not confirmed yet"
    }

    private var statusMessage: String {
        if let sentText {
            // Copy says "recorded" because this timestamp is backend state, not inbox proof.
            return "Backend recorded the confirmation email at \(sentText)."
        }

        if reservation.statusValue == .confirmed, reservation.email.nilIfBlank == nil {
            return "Reservation is confirmed, but no confirmation email can be sent."
        }

        if reservation.statusValue == .confirmed {
            return "This reservation is confirmed, but the app has no sent-email timestamp. Follow up manually if needed."
        }

        return "Use Confirm to update this reservation."
    }

    private var latestActionMessage: String? {
        switch latestEmailStatus {
        case .sent?:
            return "Latest action: confirmation email was recorded as sent."
        case .alreadySent?:
            return "Latest action: confirmation email was already recorded as sent."
        case .skipped?:
            return "Latest action: no confirmation email sent because there is no guest email."
        case .failed?:
            return "Latest action: email failed; follow up manually."
        case .unknown?:
            return "Latest action: email status was not recognized."
        case nil:
            return nil
        }
    }

    var body: some View {
        DetailCard(title: "Confirmation Email", systemImage: "envelope.badge") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: sentText == nil ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Text(statusTitle)
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 0)
                }

                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let latestActionMessage {
                    Text(latestActionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct ReservationNotesCard: View {
    let reservation: ReservationRecord
    let onEdit: () -> Void

    var body: some View {
        DetailCard(title: "Notes", systemImage: "note.text") {
            VStack(alignment: .leading, spacing: 14) {
                DetailNoteBlock(title: "Staff", value: reservation.staffNotes)
                DetailNoteBlock(title: "Guest", value: reservation.guestNotes)

                Button {
                    onEdit()
                } label: {
                    Label("Edit Notes", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.82))
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.plain)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }
            }
        }
    }
}

private struct ReservationOperationalCard: View {
    let reservation: ReservationRecord
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 9) {
                Divider()
                DetailInfoRow(title: "Remote ID", value: "#\(reservation.remoteID)", monospaced: true)
                DetailInfoRow(title: "Source", value: reservation.sourceDisplayName)
                DetailInfoRow(title: "Source ID", value: reservation.sourceSubmissionID > 0 ? "#\(reservation.sourceSubmissionID)" : "-", monospaced: true)
                DetailInfoRow(title: "Superseded By", value: reservation.supersededById.map { "#\($0)" } ?? "-", monospaced: true)
                DetailInfoRow(title: "Hidden", value: reservation.isHidden ? "Yes" : "No")
                DetailInfoRow(title: "Hidden Reason", value: reservation.hiddenReason?.nilIfBlank ?? "-")
                DetailInfoRow(title: "Created", value: DetailDateFormatting.server(reservation.createdAt))
                DetailInfoRow(title: "Updated", value: DetailDateFormatting.server(reservation.apiUpdatedAt))
                DetailInfoRow(title: "Confirmed", value: DetailDateFormatting.server(reservation.confirmedAt))
                DetailInfoRow(title: "Email", value: DetailDateFormatting.server(reservation.confirmationEmailSentAt))
                DetailInfoRow(title: "Reminder", value: DetailDateFormatting.server(reservation.reminderEmailSentAt))
                DetailInfoRow(title: "Last Synced", value: DetailDateFormatting.local(reservation.lastSyncedAt))
            }
            .padding(.top, 8)
        } label: {
            Label("Developer / Sync Info", systemImage: "server.rack")
                .font(.headline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - Shared Detail Components

private struct DetailWarningCard: View {
    let title: String
    let message: String
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color(.systemGray5), in: Circle())

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

private struct DetailCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.medium))
                .foregroundStyle(.secondary)

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct DetailContactLine: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct DetailInfoRow: View {
    let title: String
    let value: String
    var monospaced = false
    var valueTint: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(monospaced ? .subheadline.monospacedDigit() : .subheadline)
                .foregroundStyle(valueTint)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct DetailNoteBlock: View {
    let title: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Text(value?.nilIfBlank ?? "-")
                .font(.subheadline)
                .foregroundStyle(value?.nilIfBlank == nil ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
    }
}

// MARK: - Detail Date Formatting

private enum DetailDateFormatting {
    static func server(_ dateString: String?) -> String {
        guard let dateString = dateString?.nilIfBlank else {
            return "-"
        }

        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd HH:mm:ss"

        guard let date = parser.date(from: dateString) else {
            return dateString
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func local(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
