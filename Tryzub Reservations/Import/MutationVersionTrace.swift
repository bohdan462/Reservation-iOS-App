//
//  MutationVersionTrace.swift
//  Tryzub Reservations
//
//  DEBUG-only row-version presence tracing for mutation calls.
//  Expected format: [MUTATION_VERSION_TRACE] action=... id=... expected_updated_at=present|missing
//

import Foundation
import OSLog

enum MutationVersionTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "MutationVersionTrace"
    )

    /// Log whether a row version was available when a mutation was issued.
    static func log(
        action: String,
        reservationID: Int,
        expectedUpdatedAt: String?
    ) {
        guard isEnabled else { return }
        let presence = expectedUpdatedAt != nil ? "present" : "missing"
        logger.debug(
            "[MUTATION_VERSION_TRACE] action=\(action, privacy: .public) id=\(reservationID, privacy: .public) expected_updated_at=\(presence, privacy: .public)"
        )
    }
}
