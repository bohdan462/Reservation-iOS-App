//
//  HostQuickActionModels.swift
//  Tryzub Reservations
//
//  Per-reservation action cluster types used by HostReservationActionClusterBuilder
//  and HostBoardActionRouter.
//

import Foundation

// MARK: - HostReservationSignal

/// A deterministic per-reservation signal used to drive cluster severity,
/// title copy, and quick-action selection. No AI involvement.
enum HostReservationSignal: String, Hashable, CaseIterable {
    case guestNote
    case birthday
    case anniversary
    case celebration
    case dietary
    case accessibility
    case noTable
    case largeParty
    case confirmationMissing
    case reminderMissing
    case lateAttention
    case tableReadyRelevant
    case seatedTooLong
    case tableMismatch
    case returningGuest
}

// MARK: - HostQuickAction

/// A single tappable quick action shown on a Host reservation cluster.
enum HostQuickAction: Equatable {
    case viewGuestNote(remoteID: Int)
    case draftConfirmation(remoteID: Int)
    case draftReminder(remoteID: Int)
    case draftTableReady(remoteID: Int)
    case assignTable(remoteID: Int)
    case markSeated(remoteID: Int)
    case openReservation(remoteID: Int)

    var remoteID: Int {
        switch self {
        case .viewGuestNote(let id),
             .draftConfirmation(let id),
             .draftReminder(let id),
             .draftTableReady(let id),
             .assignTable(let id),
             .markSeated(let id),
             .openReservation(let id):
            return id
        }
    }

    var traceName: String {
        switch self {
        case .viewGuestNote:        return "view_guest_note"
        case .draftConfirmation:    return "draft_confirmation"
        case .draftReminder:        return "draft_reminder"
        case .draftTableReady:      return "draft_table_ready"
        case .assignTable:          return "assign_table"
        case .markSeated:           return "mark_seated"
        case .openReservation:      return "open_reservation"
        }
    }
}

// MARK: - HostReservationActionCluster

/// A card-level grouping that combines one reservation with its deterministic
/// signals, severity, display copy, and up to one primary + three secondary quick actions.
struct HostReservationActionCluster: Identifiable {
    let id: String
    let reservationRemoteID: Int
    let reservationLocalID: UUID
    let guestDisplayName: String
    let reservationTimeText: String
    let partySize: Int
    let tableName: String?
    let severity: HostSeverity
    let title: String
    let summary: String
    let signals: [HostReservationSignal]
    let primaryAction: HostQuickAction
    let secondaryActions: [HostQuickAction]
}
