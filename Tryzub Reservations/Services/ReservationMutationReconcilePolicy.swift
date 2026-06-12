//
//  ReservationMutationReconcilePolicy.swift
//  Tryzub Reservations
//
//  Normalizes backend mutation results into staff-safe outcomes.
//
//  Rules:
//  - 404 after a stale action means the row may already be gone or changed on the server.
//    Do not show "not deleted" or "could not update" when server truth is "already gone."
//  - 409 tryzub_reservation_conflict → refresh affected reservation or active window.
//  - 409 tryzub_invalid_status_transition → use allowed_transitions from server response.
//  - 409 tryzub_table_assignment_conflict → keep floor/table conflict UI.
//  - Timeout/unknown mutation → reconcile by ID before claiming failure.
//
//  Staff-safe copy constants are defined on MutationOutcome so callers show
//  consistent wording without coupling to specific error types.
//

import Foundation
import OSLog

// MARK: - Outcome

enum MutationOutcome {
    /// Server accepted the mutation; upsert the returned DTO.
    case success(ReservationDTO)
    /// 404 — server truth is the row is gone. Caller should remove from local cache.
    case alreadyGone(reservationID: Int)
    /// 409 conflict (stale data) — server still has the row but it changed. Caller
    /// should refresh it and show changed-copy to staff.
    case alreadyChanged(reservationID: Int, refreshedDTO: ReservationDTO?)
    /// 409 invalid status transition — server rejected because status cannot move
    /// from current to requested. allowedTransitions may contain valid next statuses.
    case invalidTransition(reservationID: Int, allowedTransitions: [String])
    /// 409 table assignment conflict — caller should show the FloorPlan conflict UI.
    case tableConflict([TableAssignmentConflictDTO])
    /// Network timeout or unknown error: the mutation may or may not have reached
    /// the server. Caller must reconcile by ID before presenting any failure.
    case uncertainNeedsReconcile(reservationID: Int, underlyingError: Error)
    /// All other failures; message is staff-safe (no stack trace).
    case failedStaffSafe(reservationID: Int, message: String)

    // MARK: - Staff-safe copy

    static let copyAlreadyGone =
        "This reservation is already gone on the server. Saved data was refreshed."
    static let copyAlreadyChanged =
        "This reservation was already changed on another device. Saved data was refreshed."
    static let copyCouldNotUpdate =
        "Could not update this reservation. Saved data was refreshed."

    var staffMessage: String {
        switch self {
        case .success:
            return ""
        case .alreadyGone:
            return MutationOutcome.copyAlreadyGone
        case .alreadyChanged:
            return MutationOutcome.copyAlreadyChanged
        case .invalidTransition:
            return "This reservation cannot move to that status right now."
        case .tableConflict:
            return "This table is already assigned. Please choose a different table."
        case .uncertainNeedsReconcile:
            return MutationOutcome.copyCouldNotUpdate
        case .failedStaffSafe(_, let message):
            return message.isEmpty ? MutationOutcome.copyCouldNotUpdate : message
        }
    }

    var requiresActiveWindowRefresh: Bool {
        switch self {
        case .alreadyGone, .alreadyChanged:
            return true
        default:
            return false
        }
    }

    var requiresReservationRefresh: Bool {
        switch self {
        case .alreadyChanged, .uncertainNeedsReconcile:
            return true
        default:
            return false
        }
    }
}

// MARK: - Policy

/// Maps raw API errors and responses to typed MutationOutcomes.
/// This policy does not perform network calls — callers decide whether to reconcile.
enum ReservationMutationReconcilePolicy {

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "MutationReconcile"
    )

    // MARK: - Main classifier

    /// Classify a thrown mutation error into a MutationOutcome.
    /// Pass `reservationID` from the cached row being mutated.
    static func classify(
        error: Error,
        action: String,
        reservationID: Int
    ) -> MutationOutcome {
        // Cancellations are never staff-facing failures.
        if error.isCancellationLike {
            return .failedStaffSafe(reservationID: reservationID, message: "")
        }

        // Uncertain network — mutation may have reached server.
        if error.mayHaveReachedReservationServer {
            emit(action: action, id: reservationID, outcome: "uncertain_needs_reconcile")
            return .uncertainNeedsReconcile(
                reservationID: reservationID,
                underlyingError: error
            )
        }

        guard let apiError = error as? ReservationAPIError else {
            emit(action: action, id: reservationID, outcome: "failed_staff_safe")
            return .failedStaffSafe(
                reservationID: reservationID,
                message: MutationOutcome.copyCouldNotUpdate
            )
        }

        switch apiError {
        case .serverError(let statusCode, _) where statusCode == 404:
            emit(action: action, id: reservationID, outcome: "already_gone", refresh: "active_window")
            return .alreadyGone(reservationID: reservationID)

        case .wordpressError(let code, _, let statusCode, _) where statusCode == 404
                || code == "tryzub_reservation_not_found":
            emit(action: action, id: reservationID, outcome: "already_gone", refresh: "active_window")
            return .alreadyGone(reservationID: reservationID)

        case .wordpressError(let code, let message, let statusCode, _)
                where statusCode == 409 || code.contains("conflict") || code.contains("invalid_status"):
            return classify409(
                code: code,
                message: message,
                action: action,
                reservationID: reservationID
            )

        case .serverError(let statusCode, _) where statusCode == 409:
            emit(action: action, id: reservationID, outcome: "already_changed", refresh: "reservation")
            return .alreadyChanged(reservationID: reservationID, refreshedDTO: nil)

        default:
            emit(action: action, id: reservationID, outcome: "failed_staff_safe")
            return .failedStaffSafe(
                reservationID: reservationID,
                message: apiError.errorDescription ?? MutationOutcome.copyCouldNotUpdate
            )
        }
    }

    /// Classify a successful DTO result (convenience for callers returning .success).
    static func success(_ dto: ReservationDTO, action: String) -> MutationOutcome {
        emit(action: action, id: dto.id, outcome: "success")
        return .success(dto)
    }

    /// Emits the table-conflict reconcile trace for the Floor Plan / table assignment path,
    /// which decodes its own conflict DTOs (FloorPlanError) rather than ReservationAPIError.
    static func traceTableConflict(reservationID: Int, source: String) {
        emit(action: "table_assignment", id: reservationID, outcome: "table_conflict", refresh: source)
    }

    // MARK: - 409 sub-classifier

    private static func classify409(
        code: String,
        message: String,
        action: String,
        reservationID: Int
    ) -> MutationOutcome {
        switch code {
        case "tryzub_table_assignment_conflict":
            emit(action: action, id: reservationID, outcome: "table_conflict")
            // The caller is expected to have already decoded the conflict DTOs
            // from the 409 response. Return empty array here; FloorPlanStore handles
            // its own conflict decoding from the raw response.
            return .tableConflict([])

        case "tryzub_invalid_status_transition":
            emit(action: action, id: reservationID, outcome: "invalid_transition")
            // Backend may include allowed_transitions in the message; keep it simple
            // for now — the UI will re-fetch the row to show current state.
            return .invalidTransition(reservationID: reservationID, allowedTransitions: [])

        default:
            // Generic 409 — treat as stale/changed.
            emit(action: action, id: reservationID, outcome: "already_changed", refresh: "reservation")
            return .alreadyChanged(reservationID: reservationID, refreshedDTO: nil)
        }
    }

    // MARK: - Trace

    private static func emit(
        action: String,
        id: Int,
        outcome: String,
        refresh: String? = nil
    ) {
        #if DEBUG
        var line = "[MUTATION_RECONCILE] action=\(action) id=\(id) outcome=\(outcome)"
        if let refresh {
            line += " refresh=\(refresh)"
        }
        logger.debug("\(line, privacy: .public)")
        #endif
    }
}

// MARK: - Reconcile helpers on MutationService

extension ReservationMutationReconcilePolicy {

    /// Wraps a throwing mutation closure into a MutationOutcome.
    /// On success, returns `.success(dto)`.
    /// On error, classifies and returns the appropriate outcome.
    static func attempt(
        action: String,
        reservationID: Int,
        _ work: () async throws -> ReservationDTO
    ) async -> MutationOutcome {
        do {
            let dto = try await work()
            return success(dto, action: action)
        } catch {
            return classify(error: error, action: action, reservationID: reservationID)
        }
    }
}
