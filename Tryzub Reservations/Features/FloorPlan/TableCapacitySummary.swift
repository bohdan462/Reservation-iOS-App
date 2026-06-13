//
//  TableCapacitySummary.swift
//  Tryzub Reservations
//
//  Exposes a clean, typed capacity summary with explicit floor source.
//  Service Intelligence and BookingLoadAnalyzer consume this — they never guess
//  from free-form text or silently substitute local advisory tables.
//
//  Trace examples:
//    [TABLE_CAPACITY_TRACE] source=backend tables=17 seats=88
//    [TABLE_CAPACITY_TRACE] source=pendingBackend tables=0 seats=0
//    [TABLE_CAPACITY_TRACE] source=legacyFallback tables=17 seats=96 advisory=true
//

import Foundation
import OSLog

// MARK: - Model

struct TableCapacitySummary {
    let source: HostFloorTableSource
    /// Number of active tables in the resolved layout.
    let tableCount: Int
    /// Sum of maxCapacity across ALL active tables.
    let totalSeats: Int
    /// Same as totalSeats — kept for clarity (active tables only).
    let activeSeats: Int
    /// Per-section seat totals. Key = section name; value = summed maxCapacity.
    let sections: [String: Int]
    /// Largest maxCapacity among all active tables.
    let largestTableCapacity: Int
    /// True only when `source == .backend` with non-zero active inventory.
    let hasBackendLayout: Bool

    // MARK: - Convenience

    static func empty(source: HostFloorTableSource) -> TableCapacitySummary {
        TableCapacitySummary(
            source: source,
            tableCount: 0,
            totalSeats: 0,
            activeSeats: 0,
            sections: [:],
            largestTableCapacity: 0,
            hasBackendLayout: false
        )
    }

    // MARK: - Builders

    static func build(from tables: [RestaurantTableDTO], source: HostFloorTableSource = .backend) -> TableCapacitySummary {
        let active = tables.filter(\.isActive)
        guard !active.isEmpty else {
            return .empty(source: source == .backend ? .notConfigured : source)
        }
        let totalSeats = active.reduce(0) { $0 + max(0, $1.maxCapacity) }
        let largest = active.map(\.maxCapacity).max() ?? 0
        var sectionMap: [String: Int] = [:]
        for table in active {
            let rawSection = table.section?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let key = rawSection.isEmpty ? "Main" : rawSection
            sectionMap[key, default: 0] += max(0, table.maxCapacity)
        }
        return TableCapacitySummary(
            source: source,
            tableCount: active.count,
            totalSeats: totalSeats,
            activeSeats: totalSeats,
            sections: sectionMap,
            largestTableCapacity: largest,
            hasBackendLayout: source == .backend
        )
    }

    static func build(from configs: [RestaurantTableConfig], source: HostFloorTableSource) -> TableCapacitySummary {
        guard source == .legacyFallback else {
            return .empty(source: source)
        }
        let active = configs.filter(\.isActive)
        guard !active.isEmpty else {
            return .empty(source: .legacyFallback)
        }
        let totalSeats = active.reduce(0) { $0 + max(0, $1.capacity) }
        let largest = active.map(\.capacity).max() ?? 0
        var sectionMap: [String: Int] = [:]
        for table in active {
            let rawSection = table.section.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = rawSection.isEmpty ? "Main" : rawSection
            sectionMap[key, default: 0] += max(0, table.capacity)
        }
        return TableCapacitySummary(
            source: .legacyFallback,
            tableCount: active.count,
            totalSeats: totalSeats,
            activeSeats: totalSeats,
            sections: sectionMap,
            largestTableCapacity: largest,
            hasBackendLayout: false
        )
    }
}

// MARK: - Trace

private let capacityLogger = Logger(
    subsystem: "Bohdan-Solovey.Tryzub-Reservations",
    category: "TableCapacity"
)

enum TableCapacityTrace {
    static func summary(_ summary: TableCapacitySummary) {
        #if DEBUG
        let source = summary.source.traceLabel
        if summary.source == .legacyFallback {
            capacityLogger.debug(
                "[TABLE_CAPACITY_TRACE] source=\(source, privacy: .public) tables=\(summary.tableCount, privacy: .public) seats=\(summary.totalSeats, privacy: .public) advisory=true"
            )
        } else {
            capacityLogger.debug(
                "[TABLE_CAPACITY_TRACE] source=\(source, privacy: .public) tables=\(summary.tableCount, privacy: .public) seats=\(summary.totalSeats, privacy: .public)"
            )
        }
        #endif
    }
}
