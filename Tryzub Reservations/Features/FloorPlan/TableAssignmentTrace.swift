//
//  TableAssignmentTrace.swift
//  Tryzub Reservations
//
//  Traces for the two table-assignment code paths.
//
//  Legacy path (PATCH table_name):
//    Does NOT enforce backend table conflict rules.
//    Callers should migrate to the canonical path when a floor layout exists.
//    [TABLE_ASSIGNMENT_TRACE] path=legacy_table_name_patch ...
//
//  Canonical path (PATCH /managed-reservations/{id}/tables):
//    Backend Floor Plan assignment. Enforces conflict rules.
//    [TABLE_ASSIGNMENT_TRACE] path=floor_plan_backend ...
//

import Foundation
import OSLog

enum TableAssignmentTrace {

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "TableAssignment"
    )

    /// Legacy PATCH table_name path. Does NOT enforce backend table conflict rules.
    static func legacyPatch(reservationID: Int, tableName: String) {
        #if DEBUG
        logger.debug(
            "[TABLE_ASSIGNMENT_TRACE] path=legacy_table_name_patch reservation=\(reservationID, privacy: .public) tableName=\(tableName, privacy: .public)"
        )
        #endif
    }

    /// Canonical PATCH /managed-reservations/{id}/tables path.
    /// Enforces backend table conflict rules.
    static func canonicalFloorPlan(reservationID: Int, tableKeys: [String]) {
        #if DEBUG
        let keysStr = tableKeys.joined(separator: ",")
        logger.debug(
            "[TABLE_ASSIGNMENT_TRACE] path=floor_plan_backend reservation=\(reservationID, privacy: .public) tableKeys=\(keysStr, privacy: .public)"
        )
        #endif
    }

    /// Logged before falling back to the legacy path.
    /// - Parameters:
    ///   - reason: `no_backend_layout` or `key_not_found`
    ///   - detail: Extra context (e.g. the unresolved label), or nil.
    static func fallback(reservationID: Int, reason: String, detail: String?) {
        #if DEBUG
        let extra = detail.map { " detail=\($0)" } ?? ""
        logger.debug(
            "[TABLE_ASSIGNMENT_TRACE] fallback_reason=\(reason, privacy: .public) reservation=\(reservationID, privacy: .public)\(extra, privacy: .public)"
        )
        #endif
    }
}
