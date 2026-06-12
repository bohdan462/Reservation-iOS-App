//
//  TableCapacitySummary.swift
//  Tryzub Reservations
//
//  Exposes a clean, typed capacity summary built from the backend floor layout.
//  Service Intelligence and BookingLoadAnalyzer consume this — they never guess
//  from free-form text when a real layout is available.
//
//  Source priority:
//    1. Backend floor tables (FloorPlanStore.layoutTables / viewState.tables)
//    2. If no backend layout, hasBackendLayout = false and all numeric fields are zero.
//
//  Trace:
//    [TABLE_CAPACITY_TRACE] source=backend tables=17 seats=88
//    [TABLE_CAPACITY_TRACE] source=none — no backend layout available
//

import Foundation
import OSLog

// MARK: - Model

struct TableCapacitySummary {
    /// Number of active tables in the backend layout.
    let tableCount: Int
    /// Sum of maxCapacity across ALL active tables.
    let totalSeats: Int
    /// Same as totalSeats — kept for clarity (active tables only).
    let activeSeats: Int
    /// Per-section seat totals. Key = section name; value = summed maxCapacity.
    let sections: [String: Int]
    /// Largest maxCapacity among all active tables.
    let largestTableCapacity: Int
    /// True when built from a real backend floor layout.
    let hasBackendLayout: Bool

    // MARK: - Convenience

    static let empty = TableCapacitySummary(
        tableCount: 0,
        totalSeats: 0,
        activeSeats: 0,
        sections: [:],
        largestTableCapacity: 0,
        hasBackendLayout: false
    )

    // MARK: - Builder

    static func build(from tables: [RestaurantTableDTO]) -> TableCapacitySummary {
        let active = tables.filter(\.isActive)
        guard !active.isEmpty else {
            return .empty
        }
        let totalSeats = active.reduce(0) { $0 + max(0, $1.maxCapacity) }
        let largest = active.map(\.maxCapacity).max() ?? 0
        var sectionMap: [String: Int] = [:]
        for t in active {
            let rawSection = t.section?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let key = rawSection.isEmpty ? "Main" : rawSection
            sectionMap[key, default: 0] += max(0, t.maxCapacity)
        }
        return TableCapacitySummary(
            tableCount: active.count,
            totalSeats: totalSeats,
            activeSeats: totalSeats,
            sections: sectionMap,
            largestTableCapacity: largest,
            hasBackendLayout: true
        )
    }
}

// MARK: - Trace

private let capacityLogger = Logger(
    subsystem: "Bohdan-Solovey.Tryzub-Reservations",
    category: "TableCapacity"
)

enum TableCapacityTrace {
    static func summary(_ s: TableCapacitySummary) {
        #if DEBUG
        if s.hasBackendLayout {
            capacityLogger.debug(
                "[TABLE_CAPACITY_TRACE] source=backend tables=\(s.tableCount, privacy: .public) seats=\(s.totalSeats, privacy: .public)"
            )
        } else {
            capacityLogger.debug("[TABLE_CAPACITY_TRACE] source=none")
        }
        #endif
    }
}
