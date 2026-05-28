//
//  ReservationActionButtons.swift
//  Tryzub Reservations
//

import SwiftUI

// MARK: - Staff Host Actions

// Business intent enum for staff actions.
// Confirm only is PATCH status=confirmed; Confirm + Email calls the backend email endpoint.
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
        includeSecondary: Bool
    ) -> [ReservationHostAction] {
        let status = reservation.statusValue
        var actions: [ReservationHostAction] = []

        if capabilities.canConfirmReservations,
           status == .new || status == .needsReview {
            actions.append(.confirmOnly)
            if includeSecondary, reservation.hasUsableConfirmationEmail {
                actions.append(.confirmAndSendEmail)
            }
        }

        if capabilities.canSeatReservations,
           status == .confirmed {
            if !reservation.hasTableAssignment,
               capabilities.canEditReservationDetails {
                actions.append(.assignTable)
                if includeSecondary {
                    actions.append(.seat)
                }
            } else {
                actions.append(.seat)
            }
        }

        if includeSecondary,
           capabilities.canConfirmReservations,
           status == .confirmed,
           !reservation.hasConfirmationEmailRecord,
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

    static func contextMenuActions(
        for reservation: ReservationRecord,
        capabilities: AppCapabilities
    ) -> [ReservationHostAction] {
        availableActions(
            for: reservation,
            capabilities: capabilities,
            includeSecondary: true
        )
    }

    // MARK: - Confirmation Copy

    func dialogTitle(for reservation: ReservationRecord) -> String {
        switch self {
        case .confirmOnly:
            return "Confirm reservation?"
        case .confirmAndSendEmail:
            return "Send confirmation email?"
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
            return "Choose Confirm only to update the reservation without email, or Confirm + Email to ask the backend to send the confirmation email.\(helper)"
        case .confirmAndSendEmail:
            return "\(summary)\n\nThis will mark the reservation confirmed and ask the server to send a confirmation email to \(reservation.email)."
        case .seat:
            return "\(summary)\n\nThis only updates staff status. No email will be sent."
        case .assignTable:
            return "\(summary)\n\nEnter the table name or number staff should use."
        case .complete:
            return "\(summary)\n\nUse this after the party has finished service."
        case .cancel:
            return "\(summary)\n\nThis cancels the managed reservation. No email will be sent yet."
        case .noShow:
            return "\(summary)\n\nUse this only when the guest did not arrive."
        }
    }
}

// MARK: - Action Buttons View

struct ReservationActionButtons: View {
    let reservation: ReservationRecord
    let capabilities: AppCapabilities
    var compact = false
    var includeSecondary = true
    var isBusy = false
    let onAction: (ReservationHostAction) -> Void

    // Two-tap safety state for quick service actions in compact rows.
    @State private var pendingInlineAction: ReservationHostAction?

    private var actions: [ReservationHostAction] {
        ReservationHostAction.availableActions(
            for: reservation,
            capabilities: capabilities,
            includeSecondary: includeSecondary
        )
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
                        Button(role: action.role) {
                            onAction(action)
                        } label: {
                            Label(action.fullTitle, systemImage: action.systemImage)
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
        HStack(spacing: 8) {
            if let primaryAction = actions.first {
                actionButton(primaryAction, compact: false, isPrimary: true)
            }

            if actions.count > 1 {
                Menu {
                    ForEach(actions.dropFirst()) { action in
                            Button(role: action.role) {
                                onAction(action)
                            } label: {
                                Label(action.fullTitle, systemImage: action.systemImage)
                            }
                        }
                } label: {
                    Label("More", systemImage: "ellipsis")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary.opacity(0.74))
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .disabled(isBusy)
            }
        }
    }

    // MARK: - Button Rendering

    private func actionButton(_ action: ReservationHostAction, compact: Bool, isPrimary: Bool) -> some View {
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
        .disabled(isBusy)
        .accessibilityLabel(accessibilityLabel(for: action))
    }

    // MARK: - Inline Confirmation

    private func title(for action: ReservationHostAction, compact: Bool) -> String {
        if pendingInlineAction == action {
            switch action {
            case .confirmOnly:
                return "Confirm?"
            case .confirmAndSendEmail:
                return "Email?"
            case .seat:
                return "Seat now?"
            case .complete:
                return "Complete?"
            case .cancel:
                return "Cancel?"
            case .noShow:
                return "No show?"
            case .assignTable:
                return action.rowTitle
            }
        }

        return compact ? action.rowTitle : action.shortTitle
    }

    // Intent: Requires a second tap for actions that can change service state quickly.
    private func handleTap(_ action: ReservationHostAction) {
        guard action.needsInlineConfirmation else {
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

// MARK: - Inline Confirmation Rules

private extension ReservationHostAction {
    var needsInlineConfirmation: Bool {
        switch self {
        case .seat, .complete:
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

// MARK: - Table Assignment Popover

struct TableAssignmentSheet: View {
    let reservation: ReservationRecord
    let onSave: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
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
        VStack(alignment: .leading, spacing: 12) {
            header

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            TextField("Table", text: $tableName)
                .font(.title3.weight(.semibold))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 7)], spacing: 7) {
                ForEach(tableSuggestions, id: \.self) { suggestion in
                    Button {
                        tableName = suggestion
                        ReservationHaptics.selection()
                    } label: {
                        ReservationChoiceChip(
                            title: suggestion,
                            isSelected: tableName.trimmed.caseInsensitiveCompare(suggestion) == .orderedSame,
                            minWidth: 50,
                            minHeight: 32,
                            fillsWidth: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                if reservation.hasTableAssignment || !tableName.trimmed.isEmpty {
                    Button {
                        tableName = ""
                        ReservationHaptics.selection()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.72))
                .buttonStyle(.plain)

                Button {
                    Task {
                        await save()
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color(.systemBackground))
                    } else {
                        Text("Save")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.systemBackground))
                .frame(minWidth: 72, minHeight: 34)
                .background(ReservationUIStyle.selectedControlColor, in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
        }
        .padding(14)
        .frame(width: 360, alignment: .topLeading)
        .background(Color(.systemGroupedBackground))
        .presentationCompactAdaptation(.popover)
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
        ["A1", "A2", "A3", "B1", "B2", "B3", "Bar", "Patio"]
    }

    // Intent: Staff assigns a table through the caller's PATCH handler.
    private func save() async {
        isSaving = true
        errorMessage = nil

        defer {
            isSaving = false
        }

        do {
            try await onSave(tableName.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
