//
//  GuestProfileTrace.swift
//  Tryzub Reservations
//
//  DEBUG-only guest profile pack fetch tracing.
//

import Foundation
import OSLog

enum GuestProfileTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "GuestProfile"
    )

    static func profilePackDecoded(
        reservationID: Int,
        previewRows: Int,
        managementNotes: Int,
        noteSignalBuckets: Int,
        hasHostPacket: Bool,
        durationMs: Int,
        cacheHit: Bool
    ) {
        guard isEnabled else { return }
        emit(
            "reservation=\(reservationID) decoded profilePack=true previewRows=\(previewRows) managementNotes=\(managementNotes) noteSignalBuckets=\(noteSignalBuckets) hostPacket=\(hasHostPacket) duration=\(durationMs)ms cacheHit=\(cacheHit)"
        )
    }

    static func profileSection(
        reservationID: Int,
        source: String,
        section: String,
        rows: Int
    ) {
        guard isEnabled else { return }
        emit("reservation=\(reservationID) source=\(source) section=\(section) rows=\(rows)")
    }

    private static func emit(_ body: String) {
        logger.debug("[GUEST_PROFILE_TRACE] \(body, privacy: .public)")
    }
}
