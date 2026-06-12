//
//  HostActionMapper.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 1 foundation.
//
//  Adapts the existing deterministic `HostSuggestedAction` output into the new
//  `StaffActionIntent` shape. This is a reuse bridge — the Host engine still owns
//  the operational logic; Service Intelligence just re-expresses it in staff
//  language and timing buckets. No facts are invented here.
//

import Foundation

enum HostActionMapper {

    static func map(_ actions: [HostSuggestedAction]) -> [StaffActionIntent] {
        actions.compactMap { map($0) }
    }

    static func map(_ action: HostSuggestedAction) -> StaffActionIntent? {
        guard action.kind != .noAction else { return nil }
        let priority = priority(for: action.severity)
        return StaffActionIntent(
            id: "svc-\(action.id)",
            type: type(for: action.kind),
            reservationID: action.relatedReservationIDs.first.map(String.init),
            title: action.title,
            detail: action.reason.isEmpty ? nil : action.reason,
            priority: priority,
            timing: timing(for: action.severity),
            sourceSignalIDs: action.relatedReservationIDs.map { "res-\($0)" }
        )
    }

    private static func type(for kind: HostActionKind) -> StaffActionType {
        switch kind {
        case .reviewReservation: return .checkReservationStatus
        case .assignTable, .holdTable, .releaseTable: return .assignTable
        case .seatReservation: return .markSeated
        case .completeReservation: return .markComplete
        case .confirmReservation: return .sendConfirmation
        case .suggestAlternateTime: return .checkReservationStatus
        case .closeSlot: return .checkReservationStatus
        case .alertServer: return .reviewGuestNote
        case .generateEmailDraft, .generateGuestManageLink: return .sendConfirmation
        case .markNoShow: return .checkReservationStatus
        case .reviewCancellationOpportunity: return .reviewNoTable
        case .noAction: return .nothingToDo
        }
    }

    private static func priority(for severity: HostSeverity) -> ActionPriority {
        switch severity {
        case .critical: return .critical
        case .warning: return .high
        case .watch: return .medium
        case .info: return .low
        }
    }

    private static func timing(for severity: HostSeverity) -> ActionTiming {
        switch severity {
        case .critical, .warning: return .now
        case .watch: return .comingUp
        case .info: return .later
        }
    }
}
