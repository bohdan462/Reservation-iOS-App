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
                detailContent()
                    .padding(.horizontal, proxy.size.width >= 760 ? 20 : 16)
                    .padding(.vertical, 16)
                    .padding(.bottom, 92)
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle(reservation.guestName)
        .navigationBarTitleDisplayMode(.inline)
        .popover(item: $tableAssignmentReservation, arrowEdge: .top) { reservation in
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
    private func detailContent() -> some View {
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

            ReservationHeroCard(
                reservation: reservation,
                capabilities: controller.capabilities,
                isBusy: isSavingQuickAction || controller.isActionInProgress(for: reservation),
                onAction: handleAction,
                onEdit: { showEditScreen = true },
                onHideWrongEntry: reservation.canSoftHideAsWrongEntry && !reservation.isHidden
                    ? { isShowingHideWrongEntryConfirmation = true }
                    : nil,
                onRestoreHidden: reservation.isHidden
                    ? { Task { await restoreHiddenReservation() } }
                    : nil
            )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    guestInsightsLink(report: insightReport)
                    Spacer(minLength: 0)
                }

                guestInsightsLink(report: insightReport)
            }
        }
    }

    private func guestInsightsLink(report: GuestInsightReport) -> some View {
        NavigationLink {
            GuestInsightsView(
                selectedReservation: reservation,
                allReservations: allCachedReservations
            )
        } label: {
            GuestInsightsPreviewCard(report: report)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 520, alignment: .leading)
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
    let onHideWrongEntry: (() -> Void)?
    let onRestoreHidden: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    timeBlock

                    Rectangle()
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: 1)

                    mainBlock
                        .layoutPriority(2)

                    Spacer(minLength: 8)

                    actionBlock
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        timeBlock
                        mainBlock
                    }
                    actionBlock
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var timeBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reservation.displayTime)
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Text(reservation.displayDate)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ReservationStatusBadge(status: reservation.statusValue)
        }
        .frame(width: 112, alignment: .leading)
    }

    private var mainBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(reservation.guestName)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            quickFacts

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    contactBlock
                    notesBlock
                    serviceBlock
                }

                VStack(alignment: .leading, spacing: 10) {
                    contactBlock
                    notesBlock
                    serviceBlock
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickFacts: some View {
        FlowLayout(spacing: 7) {
            DetailPill(label: "\(reservation.partySize) \(reservation.partySize == 1 ? "guest" : "guests")", systemImage: "person.2", tint: .secondary)
            DetailPill(label: reservation.tableDisplay, systemImage: "table.furniture", tint: .secondary)
            DetailPill(label: reservation.sourceDisplayName, systemImage: "tray.and.arrow.down", tint: .secondary)
        }
    }

    private var contactBlock: some View {
        DetailDataPanel(title: "Contact", systemImage: "phone") {
            DetailDataRow(title: "Phone", value: reservation.formattedPhone)
            DetailDataRow(title: "Email", value: reservation.email.nilIfBlank ?? "No email")
        }
    }

    private var notesBlock: some View {
        DetailDataPanel(title: "Notes", systemImage: "note.text") {
            if reservation.guestNotes?.nilIfBlank == nil,
               reservation.staffNotes?.nilIfBlank == nil {
                DetailPlainLine("No notes")
            } else {
                if let guestNotes = reservation.guestNotes?.nilIfBlank {
                    DetailDataRow(title: "Guest", value: guestNotes, allowsWrap: true)
                }
                if let staffNotes = reservation.staffNotes?.nilIfBlank {
                    DetailDataRow(title: "Staff", value: staffNotes, allowsWrap: true)
                }
            }
        }
    }

    private var serviceBlock: some View {
        DetailDataPanel(title: "Service", systemImage: "fork.knife") {
            DetailDataRow(title: "Status", value: reservation.statusValue.displayName)
            DetailDataRow(title: "Source", value: reservation.sourceDisplayName)
            if let timingText = reservation.operationalTimingState().insightText {
                DetailDataRow(title: "Timing", value: timingText, allowsWrap: true)
            }
            DetailDataRow(title: "Email", value: emailStateText)
            DetailDataRow(title: "Created", value: serverTimestamp(reservation.createdAt))
            if let confirmedAt = reservation.confirmedAt?.nilIfBlank {
                DetailDataRow(title: "Confirmed", value: serverTimestamp(confirmedAt))
            }
        }
    }

    private var actionBlock: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ReservationActionButtons(
                reservation: reservation,
                capabilities: capabilities,
                compact: false,
                includeSecondary: false,
                isBusy: isBusy,
                onAction: onAction
            )

            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.78))
                    .frame(minWidth: 86, minHeight: 34)
            }
            .buttonStyle(.plain)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
            .disabled(!capabilities.canEditReservationDetails)

            if showsMoreMenu {
                Menu {
                    ForEach(secondaryActions) { action in
                        Button(role: action.role) {
                            onAction(action)
                        } label: {
                            Label(action.fullTitle, systemImage: action.systemImage)
                        }
                    }

                    if !secondaryActions.isEmpty,
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.78))
                        .frame(minWidth: 86, minHeight: 34)
                }
                .buttonStyle(.plain)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }
                .disabled(isBusy)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var emailStateText: String {
        if reservation.hasConfirmationEmailRecord {
            return "Email sent"
        }

        if reservation.hasUsableConfirmationEmail {
            return "Email not sent"
        }

        return "No email"
    }

    private func serverTimestamp(_ value: String) -> String {
        if let date = ReservationFormatters.serverDateTime.date(from: value) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return value
    }

    private var primaryAction: ReservationHostAction? {
        ReservationHostAction.availableActions(
            for: reservation,
            capabilities: capabilities,
            includeSecondary: false
        ).first
    }

    private var secondaryActions: [ReservationHostAction] {
        ReservationHostAction.availableActions(
            for: reservation,
            capabilities: capabilities,
            includeSecondary: true
        )
        .filter { action in
            if action == primaryAction {
                return false
            }
            if primaryAction == .confirmOnly, action == .confirmAndSendEmail {
                return false
            }
            return true
        }
    }

    private var showsMoreMenu: Bool {
        !secondaryActions.isEmpty || onHideWrongEntry != nil || onRestoreHidden != nil
    }
}

// MARK: - Shared Detail Components

private struct DetailDataPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            content
        }
        .padding(12)
        .frame(minWidth: 210, maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
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
                .frame(width: 64, alignment: .leading)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.84))
                .lineLimit(allowsWrap ? 2 : 1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
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
