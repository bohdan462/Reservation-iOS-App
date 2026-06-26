//
//  TableAssignmentCoordinator.swift
//  Tryzub Reservations
//
//  Single facade for table assignment from every surface (Host Board, Reservation Detail,
//  Schedule list, etc.).
//
//  Decision rule:
//    1. If a backend floor layout exists and the entered label resolves to a known tableKey
//       → use PATCH /managed-reservations/{id}/tables (canonical, conflict-protected).
//    2. If no backend layout exists → fall back to PATCH /managed-reservations/{id}
//       with tableName (legacy, no conflict checks). Trace always says why.
//    3. If a backend layout exists but the label cannot resolve, do not write a raw
//       table string.
//
//  Traces:
//    [TABLE_ASSIGNMENT_TRACE] path=floor_plan_backend  reservation=... table=...
//    [TABLE_ASSIGNMENT_TRACE] path=legacy_table_name_patch  reservation=... tableName=...
//    [TABLE_ASSIGNMENT_TRACE] fallback_reason=no_backend_layout  reservation=...
//    [TABLE_ASSIGNMENT_TRACE] fallback_reason=key_not_found  tableName=... reservation=...
//

import Foundation
import SwiftData

@MainActor
enum TableAssignmentCoordinator {

    // MARK: - Assign

    /// Assign a table (by display label or free-form text) to a reservation.
    ///
    /// Uses the canonical `/managed-reservations/{id}/tables` endpoint when the app
    /// has a backend floor layout and the label resolves to a known `tableKey`.
    /// Falls back to the legacy `tableName` PATCH only when no backend layout exists.
    ///
    /// Assignment is always **manual** — no automatic assignment happens here.
    static func assign(
        reservationID: Int,
        tableName: String,
        floorPlanStore: FloorPlanStore,
        controller: ReservationsController,
        context: ModelContext
    ) async {
        let normalizedTableName = tableName.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedTableName.isEmpty {
            await clear(
                reservationID: reservationID,
                floorPlanStore: floorPlanStore,
                controller: controller,
                context: context
            )
            return
        }

        if floorPlanStore.hasBackendLayout {
            if let tableKey = floorPlanStore.tableKey(forLabel: normalizedTableName) {
                TableAssignmentTrace.canonicalFloorPlan(
                    reservationID: reservationID,
                    tableKeys: [tableKey]
                )
                await floorPlanStore.assign(
                    reservationID: reservationID,
                    tableKeys: [tableKey],
                    controller: controller,
                    context: context
                )
                return
            } else {
                // Layout exists but label didn't map to a known key.
                // Fall through to legacy with a trace.
                TableAssignmentTrace.fallback(
                    reservationID: reservationID,
                    reason: "key_not_found",
                    detail: normalizedTableName
                )
                return
            }
        } else {
            TableAssignmentTrace.fallback(
                reservationID: reservationID,
                reason: "no_backend_layout",
                detail: nil
            )
        }

        // Legacy path - no conflict checks.
        TableAssignmentTrace.legacyPatch(reservationID: reservationID, tableName: normalizedTableName)
        _ = try? await controller.updateReservation(
            id: reservationID,
            request: ReservationUpdateRequest(tableName: normalizedTableName),
            context: context
        )
    }

    // MARK: - Clear

    /// Remove a table assignment from a reservation.
    static func clear(
        reservationID: Int,
        floorPlanStore: FloorPlanStore,
        controller: ReservationsController,
        context: ModelContext
    ) async {
        if floorPlanStore.hasBackendLayout {
            await floorPlanStore.clearAssignment(
                reservationID: reservationID,
                controller: controller,
                context: context
            )
        } else {
            TableAssignmentTrace.legacyPatch(reservationID: reservationID, tableName: "")
            _ = try? await controller.updateReservation(
                id: reservationID,
                request: ReservationUpdateRequest(tableName: ""),
                context: context
            )
        }
    }
}
