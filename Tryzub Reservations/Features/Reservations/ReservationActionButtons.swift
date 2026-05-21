//
//  ReservationActionButtons.swift
//  Tryzub Reservations
//

import SwiftUI

enum ReservationHostAction: String, Identifiable {
    case confirm
    case seat
    case assignTable
    case complete
    case cancel
    case noShow

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .confirm:
            return "Confirm"
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
        case .confirm, .seat, .complete, .cancel, .noShow:
            return shortTitle
        }
    }

    var fullTitle: String {
        switch self {
        case .confirm:
            return "Confirm and Send Email"
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
        case .confirm:
            return "checkmark.circle"
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
        case .confirm, .seat, .assignTable, .complete:
            return Color(.label)
        case .cancel, .noShow:
            return Color(.secondaryLabel)
        }
    }

    var role: ButtonRole? {
        switch self {
        case .cancel, .noShow:
            return .destructive
        case .confirm, .seat, .assignTable, .complete:
            return nil
        }
    }

    var statusPatch: ReservationStatus? {
        switch self {
        case .seat:
            return .seated
        case .complete:
            return .completed
        case .cancel:
            return .cancelled
        case .noShow:
            return .noShow
        case .confirm, .assignTable:
            return nil
        }
    }

    static func availableActions(
        for reservation: ReservationRecord,
        capabilities: AppCapabilities,
        includeSecondary: Bool
    ) -> [ReservationHostAction] {
        let status = reservation.statusValue
        var actions: [ReservationHostAction] = []

        if capabilities.canConfirmReservations,
           status == .new || status == .needsReview {
            actions.append(.confirm)
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

    func dialogTitle(for reservation: ReservationRecord) -> String {
        switch self {
        case .confirm:
            return "Confirm reservation?"
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
        case .confirm:
            return "\(summary)\n\nThis will mark the reservation confirmed and send a confirmation email to \(reservation.email)."
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

struct ReservationActionButtons: View {
    let reservation: ReservationRecord
    let capabilities: AppCapabilities
    var compact = false
    var includeSecondary = true
    var isBusy = false
    let onAction: (ReservationHostAction) -> Void

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
                        .font(.body.weight(.bold))
                        .foregroundStyle(.primary.opacity(0.7))
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
                        .font(.subheadline.weight(.semibold))
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

    private func actionButton(_ action: ReservationHostAction, compact: Bool, isPrimary: Bool) -> some View {
        Button {
            handleTap(action)
        } label: {
            if compact {
                Text(title(for: action, compact: true))
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            } else {
                Label(title(for: action, compact: false), systemImage: action.systemImage)
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
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
            pendingInlineAction == action ? Color.primary : Color(.systemGray6),
            in: RoundedRectangle(cornerRadius: compact ? 8 : 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 8 : 9, style: .continuous)
                .stroke(pendingInlineAction == action ? Color.primary.opacity(0.7) : Color.primary.opacity(isPrimary ? 0.42 : 0.24), lineWidth: 1)
        )
        .disabled(isBusy)
        .accessibilityLabel(accessibilityLabel(for: action))
    }

    private func title(for action: ReservationHostAction, compact: Bool) -> String {
        if pendingInlineAction == action {
            switch action {
            case .confirm:
                return hasConfirmationEmailTimestamp ? "Confirm?" : "Send email?"
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

    private var hasConfirmationEmailTimestamp: Bool {
        reservation.confirmationEmailSentAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func handleTap(_ action: ReservationHostAction) {
        guard action.needsInlineConfirmation else {
            pendingInlineAction = nil
            onAction(action)
            return
        }

        if pendingInlineAction == action {
            pendingInlineAction = nil
            onAction(action)
        } else {
            pendingInlineAction = action
        }
    }

    private func accessibilityLabel(for action: ReservationHostAction) -> String {
        switch action {
        case .confirm:
            return pendingInlineAction == action
                ? "Confirm reservation for \(reservation.guestName)"
                : "Prepare to confirm reservation for \(reservation.guestName)"
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

private extension ReservationHostAction {
    var needsInlineConfirmation: Bool {
        switch self {
        case .confirm, .seat, .complete:
            return true
        case .assignTable, .cancel, .noShow:
            return false
        }
    }
}

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
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section("Reservation") {
                    HStack {
                        Text(reservation.displayTime)
                            .font(.headline.monospacedDigit())
                        Text(reservation.guestName)
                            .lineLimit(1)
                        Spacer()
                        Text("\(reservation.partySize)")
                            .font(.headline.monospacedDigit())
                    }
                }

                Section("Table") {
                    TextField("Table number or name", text: $tableName)
                        .textInputAutocapitalization(.characters)
                }
            }
            .navigationTitle("Assign Table")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await save()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

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
