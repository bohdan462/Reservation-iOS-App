//
//  FloorSourceTrace.swift
//  Tryzub Reservations
//
//  DEBUG proof traces for canonical floor-table source resolution.
//  Dedupes identical (date, source, reason, cachedTables) within a short window.
//

import Foundation
import OSLog

@MainActor
enum FloorSourceTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "FloorSource"
    )

    private static var lastSignature: String?
    private static var lastLoggedAt: Date?
    private static let dedupeInterval: TimeInterval = 3

    static func log(
        date: String,
        source: HostFloorTableSource,
        reason: String,
        cachedTables: Int
    ) {
        guard isEnabled else { return }

        let signature = "\(date)|\(source.traceLabel)|\(reason)|\(cachedTables)"
        let now = Date()
        if signature == lastSignature,
           let lastLoggedAt,
           now.timeIntervalSince(lastLoggedAt) < dedupeInterval {
            return
        }
        lastSignature = signature
        lastLoggedAt = now

        logger.debug(
            "[FLOOR_SOURCE_TRACE] date=\(date, privacy: .public) source=\(source.traceLabel, privacy: .public) reason=\(reason, privacy: .public) cachedTables=\(cachedTables, privacy: .public)"
        )
    }
}
