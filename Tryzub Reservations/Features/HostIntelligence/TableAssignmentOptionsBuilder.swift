//
//  TableAssignmentOptionsBuilder.swift
//  Tryzub Reservations
//
//  Derives Assign Table chip names from structured inventory with legacy fallback.
//

import Foundation

enum TableAssignmentOptionsBuilder {

    static func assignmentTableNames(
        configuredTables: [RestaurantTableConfig],
        legacyNames: [String]
    ) -> [String] {
        let active = configuredTables.filter(\.isActive)
        guard !active.isEmpty else {
            return deduplicatedNames(legacyNames)
        }

        let sorted = active.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            let sectionCompare = lhs.section.localizedCaseInsensitiveCompare(rhs.section)
            if sectionCompare != .orderedSame {
                return sectionCompare == .orderedAscending
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return deduplicatedNames(sorted.map(\.name))
    }

    private static func deduplicatedNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = HostTableIntelligenceSupport.normalizeTableName(trimmed)
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }

        return result
    }
}

extension HostTableConfigStore {

    func assignmentTableNames(legacyFallback: [String]) -> [String] {
        TableAssignmentOptionsBuilder.assignmentTableNames(
            configuredTables: tables,
            legacyNames: legacyFallback
        )
    }
}
