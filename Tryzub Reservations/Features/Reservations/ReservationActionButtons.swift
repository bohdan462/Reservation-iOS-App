//
//  ReservationActionButtons.swift
//  Tryzub Reservations
//

import SwiftUI

// MARK: - Staff Host Actions

// Business intent enum for staff actions.
// Confirm only is PATCH status=confirmed; Confirm + Email uses POST /confirm when enabled.
enum ReservationHostAction: String, Identifiable {
    case confirmOnly
    case confirmAndSendEmail
    case seat
    case assignTable
    case complete
    case cancel
    case noShow

    var id: String { rawValue }

    // MARK: - Action Labels

    var shortTitle: String {
        switch self {
        case .confirmOnly:
            return "Confirm"
        case .confirmAndSendEmail:
            return "Confirm + Email"
        case .seat:
            return "Seat"
        case .assignTable:
            return "Assign Table"
        case .complete:
            return "Complete"
        case .cancel:
            return "Cancel"
        case .noShow:
            return "No Show"
        }
    }

    var rowTitle: String {
        switch self {
        case .assignTable:
            return "Table"
        case .confirmOnly:
            return "Confirm"
        case .confirmAndSendEmail:
            return "Email"
        case .seat, .complete, .cancel, .noShow:
            return shortTitle
        }
    }

    var fullTitle: String {
        switch self {
        case .confirmOnly:
            return "Confirm Only"
        case .confirmAndSendEmail:
            return "Confirm + Email"
        case .seat:
            return "Seat Party"
        case .assignTable:
            return "Assign Table"
        case .complete:
            return "Complete"
        case .cancel:
            return "Cancel Reservation"
        case .noShow:
            return "Mark No Show"
        }
    }

    var systemImage: String {
        switch self {
        case .confirmOnly:
            return "checkmark.circle"
        case .confirmAndSendEmail:
            return "envelope.badge"
        case .seat:
            return "person.2"
        case .assignTable:
            return "table.furniture"
        case .complete:
            return "checkmark.seal"
        case .cancel:
            return "xmark.circle"
        case .noShow:
            return "person.crop.circle.badge.xmark"
        }
    }

    var tint: Color {
        switch self {
        case .confirmOnly, .confirmAndSendEmail, .seat, .assignTable, .complete:
            return Color(.label)
        case .cancel, .noShow:
            return Color(.secondaryLabel)
        }
    }

    var role: ButtonRole? {
        switch self {
        case .cancel, .noShow:
            return .destructive
        case .confirmOnly, .confirmAndSendEmail, .seat, .assignTable, .complete:
            return nil
        }
    }

    func displayRowTitle(for reservation: ReservationRecord, compact: Bool) -> String {
        switch self {
        case .seat:
            if let table = reservation.assignedTableName {
                return "Seat at \(table)"
            }
            return compact ? rowTitle : shortTitle
        default:
            return compact ? rowTitle : shortTitle
        }
    }

    func displayPendingTitle(for reservation: ReservationRecord) -> String {
        switch self {
        case .seat:
            if let table = reservation.assignedTableName {
                return "Seat at \(table)?"
            }
            return "Seat now?"
        case .confirmOnly:
            return "Confirm?"
        case .confirmAndSendEmail:
            return "Email?"
        case .complete:
            return "Complete?"
        case .cancel:
            return "Cancel?"
        case .noShow:
            return "No show?"
        case .assignTable:
            return rowTitle
        }
    }

    static var isBackendConfirmEmailEnabled: Bool {
        ReservationEmailWorkflow.isBackendConfirmEmailEnabled
    }

    var isInteractionEnabled: Bool {
        switch self {
        case .confirmAndSendEmail:
            return Self.isBackendConfirmEmailEnabled
        default:
            return true
        }
    }

    var disabledLabel: String? {
        guard self == .confirmAndSendEmail, !isInteractionEnabled else { return nil }
        return "Confirm + Email (backend disabled)"
    }

    // MARK: - Status Patch Mapping

    // Only direct status updates live here. Confirm + Email uses POST /confirm elsewhere.
    var statusPatch: ReservationStatus? {
        switch self {
        case .confirmOnly:
            return .confirmed
        case .seat:
            return .seated
        case .complete:
            return .completed
        case .cancel:
            return .cancelled
        case .noShow:
            return .noShow
        case .confirmAndSendEmail, .assignTable:
            return nil
        }
    }

    // MARK: - Action Availability

    // Intent: Decides which staff actions are visible for the current status/capabilities.
    // Network: None; callers route the selected action to the controller.
    static func availableActions(
        for reservation: ReservationRecord,
        capabilities: AppCapabilities,
        includeSecondary: Bool,
        now: Date = Date()
    ) -> [ReservationHostAction] {
        let status = reservation.statusValue
        var actions: [ReservationHostAction] = []

        let showPastDueComplete = reservation.isPastDueCompleteEligible(now: now)
            && reservation.canMarkPastDueComplete
            && capabilities.canSeatReservations

        if showPastDueComplete {
            actions.append(.complete)
        } else {
            if capabilities.canConfirmReservations,
               status == .new || status == .needsReview {
                actions.append(.confirmOnly)
                if includeSecondary,
                   Self.isBackendConfirmEmailEnabled,
                   reservation.hasUsableConfirmationEmail {
                    actions.append(.confirmAndSendEmail)
                }
            }

            if capabilities.canSeatReservations,
               status == .confirmed {
                actions.append(.seat)

                if includeSecondary,
                   !reservation.hasTableAssignment,
                   capabilities.canEditReservationDetails {
                    actions.append(.assignTable)
                }
            }
        }

        if includeSecondary,
           capabilities.canConfirmReservations,
           status == .confirmed,
           !reservation.hasConfirmationEmailRecord,
           Self.isBackendConfirmEmailEnabled,
           reservation.hasUsableConfirmationEmail {
            actions.append(.confirmAndSendEmail)
        }

        if capabilities.canSeatReservations,
           status == .seated {
            actions.append(.complete)
        }

        if includeSecondary,
           capabilities.canEditReservationDetails,
           !actions.contains(.assignTable),
           status != .completed,
           status != .cancelled,
           status != .noShow {
            actions.append(.assignTable)
        }

        if includeSecondary,
           capabilities.canCancelReservations,
           status != .completed,
           status != .cancelled,
           status != .noShow {
            actions.append(.cancel)
        }

        if includeSecondary,
           capabilities.canCancelReservations,
           status == .confirmed || status == .seated {
            actions.append(.noShow)
        }

        return actions
    }

    // MARK: - Confirmation Copy

    func dialogTitle(for reservation: ReservationRecord) -> String {
        switch self {
        case .confirmOnly:
            return "Confirm reservation?"
        case .confirmAndSendEmail:
            return Self.isBackendConfirmEmailEnabled ? "Send backend confirmation email?" : "Manual email draft?"
        case .seat:
            return "Seat this party?"
        case .assignTable:
            return "Assign table?"
        case .complete:
            return "Complete this visit?"
        case .cancel:
            return "Cancel reservation?"
        case .noShow:
            return "Mark as no show?"
        }
    }

    func dialogMessage(for reservation: ReservationRecord) -> String {
        let summary = "\(reservation.guestName), \(reservation.displayDate) at \(reservation.displayTime), party of \(reservation.partySize)."

        switch self {
        case .confirmOnly:
            let helper = reservation.email.nilIfBlank == nil
                ? "\n\nNo guest email on this reservation."
                : ""
            let manualFlow = Self.isBackendConfirmEmailEnabled
                ? "Choose Confirm only to update the reservation without email, or Confirm + Send Email to ask the server to send the confirmation email."
                : "Choose Confirm only to update status. Use Detail → More → Send confirmation draft for the manual Gmail/Mail flow."
            return "\(manualFlow)\(helper)"
        case .confirmAndSendEmail:
            if Self.isBackendConfirmEmailEnabled {
                return "\(summary)\n\nThis will mark the reservation confirmed and ask the server to send a confirmation email to \(reservation.email)."
            }
            return "Backend confirmation email is disabled for the pilot. Use Detail → More → Send confirmation draft instead."
        case .seat:
            return "\(summary)\n\nThis only updates staff status. No email will be sent."
        case .assignTable:
            return "\(summary)\n\nEnter the table name or number staff should use."
        case .complete:
            return "\(summary)\n\nUse this after the party has finished service."
        case .cancel:
            return "\(summary)\n\nThis cancels the reservation. No email will be sent yet."
        case .noShow:
            return "\(summary)\n\nUse this only when the guest did not arrive."
        }
    }
}

// MARK: - Action Policy

enum ReservationActionSurface {
    case row
    case detail
}

struct ReservationHostActionPolicy {
    let reservation: ReservationRecord
    let capabilities: AppCapabilities
    var surface: ReservationActionSurface = .row

    var primaryRowAction: ReservationHostAction? {
        rowActions.first
    }

    var rowActions: [ReservationHostAction] {
        excludingPendingConfirmationFromRows(
            ReservationHostAction.availableActions(
                for: reservation,
                capabilities: capabilities,
                includeSecondary: false
            )
        )
    }

    var contextMenuActions: [ReservationHostAction] {
        excludingPendingConfirmationFromRows(allActions)
    }

    var detailPrimaryAction: ReservationHostAction? {
        rowActions.first
    }

    var detailSecondaryActions: [ReservationHostAction] {
        allActions.filter { action in
            if action == detailPrimaryAction {
                return false
            }
            if detailPrimaryAction == .confirmOnly, action == .confirmAndSendEmail {
                return false
            }
            return true
        }
    }

    var visibleActions: [ReservationHostAction] {
        switch surface {
        case .row:
            return rowActions
        case .detail:
            return allActions
        }
    }

    func requiresDialog(_ action: ReservationHostAction) -> Bool {
        switch action {
        case .confirmOnly, .confirmAndSendEmail, .cancel, .noShow:
            return true
        case .seat, .complete, .assignTable:
            return false
        }
    }

    private var allActions: [ReservationHostAction] {
        ReservationHostAction.availableActions(
            for: reservation,
            capabilities: capabilities,
            includeSecondary: true
        )
    }

    private func excludingPendingConfirmationFromRows(_ actions: [ReservationHostAction]) -> [ReservationHostAction] {
        guard surface == .row else { return actions }

        switch reservation.statusValue {
        case .new, .needsReview:
            return actions.filter { $0 != .confirmOnly && $0 != .confirmAndSendEmail }
        default:
            return actions
        }
    }
}

// MARK: - Action Buttons View

struct ReservationActionButtons: View {
    let reservation: ReservationRecord
    let capabilities: AppCapabilities
    var compact = false
    var includeSecondary = true
    var primaryFillsWidth = false
    var actionSurface: ReservationActionSurface?
    var isBusy = false
    let onAction: (ReservationHostAction) -> Void
    var onSeatRequiresTableChoice: (() -> Void)? = nil

    // Two-tap safety state for quick service actions in compact rows.
    @State private var pendingInlineAction: ReservationHostAction?

    private var policy: ReservationHostActionPolicy {
        ReservationHostActionPolicy(
            reservation: reservation,
            capabilities: capabilities,
            surface: actionSurface ?? (includeSecondary ? .detail : .row)
        )
    }

    private var actions: [ReservationHostAction] {
        if policy.surface == .detail, !includeSecondary, let primary = policy.detailPrimaryAction {
            return [primary]
        }
        return policy.visibleActions
    }

    var body: some View {
        Group {
            if !actions.isEmpty {
                if compact {
                    compactActions
                } else {
                    fullActions
                }
            }
        }
        .task(id: pendingInlineAction) {
            guard let action = pendingInlineAction else { return }
            try? await Task.sleep(for: .seconds(3))
            if pendingInlineAction == action {
                pendingInlineAction = nil
            }
        }
    }

    // MARK: - Compact / Full Layouts

    private var compactActions: some View {
        HStack(spacing: 6) {
            if let primaryAction = actions.first {
                actionButton(primaryAction, compact: true, isPrimary: true)
            }

            if includeSecondary, actions.count > 1 {
                Menu {
                    ForEach(actions.dropFirst()) { action in
                        if let disabledLabel = action.disabledLabel {
                            Button(disabledLabel) {}
                                .disabled(true)
                        } else {
                            Button(role: action.role) {
                                onAction(action)
                            } label: {
                                Label(action.fullTitle, systemImage: action.systemImage)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary.opacity(0.64))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
        .layoutPriority(1)
    }

    private var fullActions: some View {
        Group {
            if primaryFillsWidth, let primaryAction = actions.first {
                VStack(spacing: 10) {
                    actionButton(primaryAction, compact: false, isPrimary: true)

                    if actions.count > 1 {
                        detailSecondaryMenu
                    }
                }
            } else {
                HStack(spacing: 8) {
                    if let primaryAction = actions.first {
                        actionButton(primaryAction, compact: false, isPrimary: true)
                    }

                    if actions.count > 1 {
                        detailSecondaryMenu
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailSecondaryMenu: some View {
        let menu = Menu {
            ForEach(actions.dropFirst()) { action in
                if let disabledLabel = action.disabledLabel {
                    Button(disabledLabel) {}
                        .disabled(true)
                } else {
                    Button(role: action.role) {
                        onAction(action)
                    } label: {
                        Label(action.fullTitle, systemImage: action.systemImage)
                    }
                }
            }
        } label: {
            if primaryFillsWidth {
                Label("More", systemImage: "ellipsis")
                    .frame(maxWidth: .infinity)
            } else {
                Label("More", systemImage: "ellipsis")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
        }
        .disabled(isBusy)

        if primaryFillsWidth {
            menu
                .buttonStyle(.bordered)
                .controlSize(.large)
        } else {
            menu
                .buttonStyle(.plain)
                .foregroundStyle(.primary.opacity(0.74))
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    // MARK: - Button Rendering

    private func actionButton(_ action: ReservationHostAction, compact: Bool, isPrimary: Bool) -> some View {
        Group {
            if primaryFillsWidth, !compact {
                let label = Label(title(for: action, compact: false), systemImage: action.systemImage)
                    .frame(maxWidth: .infinity)

                Group {
                    if pendingInlineAction == action {
                        Button(action: { handleTap(action) }) { label }
                            .buttonStyle(.bordered)
                    } else {
                        Button(action: { handleTap(action) }) { label }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.large)
                .disabled(isBusy || !action.isInteractionEnabled)
                .opacity(action.isInteractionEnabled ? 1 : 0.45)
                .accessibilityLabel(accessibilityLabel(for: action))
            } else {
                Button {
                    handleTap(action)
                } label: {
                    if compact {
                        Text(title(for: action, compact: true))
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    } else {
                        Label(title(for: action, compact: false), systemImage: action.systemImage)
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(pendingInlineAction == action ? Color(.systemBackground) : .primary)
                .background(
                    pendingInlineAction == action ? Color.primary.opacity(0.82) : Color(.systemGray6),
                    in: RoundedRectangle(cornerRadius: compact ? 8 : 9, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? 8 : 9, style: .continuous)
                        .stroke(pendingInlineAction == action ? Color.primary.opacity(0.55) : Color.primary.opacity(isPrimary ? 0.22 : 0.14), lineWidth: 1)
                )
                .disabled(isBusy || !action.isInteractionEnabled)
                .opacity(action.isInteractionEnabled ? 1 : 0.45)
                .accessibilityLabel(accessibilityLabel(for: action))
            }
        }
    }

    // MARK: - Inline Confirmation

    private func title(for action: ReservationHostAction, compact: Bool) -> String {
        if pendingInlineAction == action {
            return action.displayPendingTitle(for: reservation)
        }

        return action.displayRowTitle(for: reservation, compact: compact)
    }

    // Intent: Requires a second tap for actions that can change service state quickly.
    private func handleTap(_ action: ReservationHostAction) {
        if action == .seat, !reservation.hasTableAssignment {
            pendingInlineAction = nil
            ReservationHaptics.lightImpact()
            onSeatRequiresTableChoice?()
            return
        }

        guard action.needsInlineConfirmation(for: reservation) else {
            pendingInlineAction = nil
            ReservationHaptics.lightImpact()
            onAction(action)
            return
        }

        if pendingInlineAction == action {
            pendingInlineAction = nil
            ReservationHaptics.success()
            onAction(action)
        } else {
            ReservationHaptics.lightImpact()
            pendingInlineAction = action
        }
    }

    private func accessibilityLabel(for action: ReservationHostAction) -> String {
        switch action {
        case .confirmOnly:
            return pendingInlineAction == action
                ? "Confirm reservation for \(reservation.guestName)"
                : "Prepare to confirm reservation for \(reservation.guestName)"
        case .confirmAndSendEmail:
            return pendingInlineAction == action
                ? "Send confirmation email for \(reservation.guestName)"
                : "Prepare to send confirmation email for \(reservation.guestName)"
        case .seat:
            if let table = reservation.assignedTableName {
                return pendingInlineAction == action
                    ? "Seat party at \(table)"
                    : "Prepare to seat party at \(table)"
            }
            return pendingInlineAction == action
                ? "Seat party of \(reservation.partySize)"
                : "Prepare to seat party of \(reservation.partySize)"
        case .assignTable:
            return "Assign table for \(reservation.guestName)"
        case .complete:
            return pendingInlineAction == action ? "Complete visit" : "Prepare to complete visit"
        case .cancel:
            return "Cancel reservation for \(reservation.guestName)"
        case .noShow:
            return "Mark no show for \(reservation.guestName)"
        }
    }
}

// MARK: - Confirm Dialog Helpers

enum ReservationConfirmDialog {
    @ViewBuilder
    static func backendEmailButton(
        hasUsableEmail: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if ReservationEmailWorkflow.isBackendConfirmEmailEnabled {
            if hasUsableEmail {
                Button("Confirm + Email", action: action)
            } else {
                Button("Confirm + Email") {}
                    .disabled(true)
            }
        } else {
            Button("Confirm + Email (backend disabled)") {}
                .disabled(true)
        }
    }
}

// MARK: - Inline Confirmation Rules

private extension ReservationHostAction {
    func needsInlineConfirmation(for reservation: ReservationRecord, now: Date = Date()) -> Bool {
        switch self {
        case .complete:
            if reservation.isPastDueCompleteEligible(now: now), reservation.canMarkPastDueComplete {
                return false
            }
            return true
        case .seat:
            return true
        case .confirmOnly, .confirmAndSendEmail, .assignTable, .cancel, .noShow:
            return false
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfBlank: String? {
        trimmed.isEmpty ? nil : trimmed
    }
}

extension Array where Element: Hashable {
    func uniquedPreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - Table Assignment Popover

enum ReservationTableOptionsStore {
    static let storageKey = "tryzub.localTableNames"
    static let defaultRawValue = "A1\nA2\nA3\nB1\nB2\nB3\nBar\nPatio"

    static func options(from rawValue: String) -> [String] {
        rawValue
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniquedPreservingOrder()
    }
}

struct TableAssignmentSheet: View {
    let reservation: ReservationRecord
    let onSave: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var controller: ReservationsController
    @AppStorage(ReservationTableOptionsStore.storageKey) private var tableOptionsRawValue = ReservationTableOptionsStore.defaultRawValue
    @State private var tableName: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        reservation: ReservationRecord,
        onSave: @escaping (String) async throws -> Void
    ) {
        self.reservation = reservation
        self.onSave = onSave
        _tableName = State(initialValue: reservation.tableName ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(TryzubColors.danger)
                            .lineLimit(2)
                    }

                    if controller.isNetworkDegraded {
                        Label("Offline — showing saved reservations. Edits require internet.", systemImage: "wifi.slash")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TryzubColors.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    TextField("Table", text: $tableName)
                        .font(.title3.weight(.semibold))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(TryzubColors.secondaryCardBackground, in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                                .stroke(TryzubColors.border, lineWidth: 1)
                        }

                    LazyVGrid(
                        columns: ReservationSlotGridStyle.fourColumns,
                        spacing: ReservationSlotGridStyle.rowSpacing
                    ) {
                        ForEach(tableSuggestions, id: \.self) { suggestion in
                            Button {
                                tableName = suggestion
                                ReservationHaptics.selection()
                            } label: {
                                ReservationChoiceChip(
                                    title: suggestion,
                                    isSelected: tableName.trimmed.caseInsensitiveCompare(suggestion) == .orderedSame,
                                    minWidth: 56,
                                    minHeight: 36,
                                    fillsWidth: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if reservation.hasTableAssignment || !tableName.trimmed.isEmpty {
                        Button {
                            tableName = ""
                            ReservationHaptics.selection()
                        } label: {
                            Label("Clear table", systemImage: "xmark.circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TryzubColors.mutedText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(TryzubColors.screenBackground)
            .navigationTitle("Assign Table")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(TryzubColors.mutedText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving || controller.isNetworkDegraded)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(reservation.displayTime)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(reservation.guestName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(reservation.partySize) \(reservation.partySize == 1 ? "guest" : "guests")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            ReservationStatusBadge(status: reservation.statusValue)
        }
    }

    private var tableSuggestions: [String] {
        ReservationTableOptionsStore.options(from: tableOptionsRawValue)
    }

    // Intent: Staff assigns a table through the caller's PATCH handler.
    private func save() async {
        guard !controller.isNetworkDegraded else {
            errorMessage = "Offline — edits require internet."
            return
        }

        isSaving = true
        errorMessage = nil

        defer {
            isSaving = false
        }

        do {
            try await onSave(tableName.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch {
            errorMessage = "Could not assign table. Please try again."
        }
    }
}

// MARK: - Seat / Table Workflow

extension View {
    func reservationSeatTableChoice(
        seatPromptReservation: Binding<ReservationRecord?>,
        onAssignTable: @escaping (ReservationRecord) -> Void,
        onSeatWithoutTable: @escaping (ReservationRecord) -> Void
    ) -> some View {
        confirmationDialog(
            seatPromptReservation.wrappedValue.map { "Seat \($0.guestName)?" } ?? "Seat party?",
            isPresented: Binding(
                get: { seatPromptReservation.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        seatPromptReservation.wrappedValue = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let reservation = seatPromptReservation.wrappedValue {
                Button("Assign Table") {
                    onAssignTable(reservation)
                    seatPromptReservation.wrappedValue = nil
                }
                Button("Seat Without Table") {
                    onSeatWithoutTable(reservation)
                    seatPromptReservation.wrappedValue = nil
                }
            }
            Button("Cancel", role: .cancel) {
                seatPromptReservation.wrappedValue = nil
            }
        } message: {
            Text("Assign a table before seating, or seat the party without a table.")
        }
    }
}
