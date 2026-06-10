//
//  FloorPlanError.swift
//  Tryzub Reservations
//

import Foundation

enum FloorPlanError: Error, Equatable {
    case assignmentConflict([TableAssignmentConflictDTO])
    case network(Error)
    case decoding(Error)
    case serverMessage(String)

    static func == (lhs: FloorPlanError, rhs: FloorPlanError) -> Bool {
        switch (lhs, rhs) {
        case let (.assignmentConflict(left), .assignmentConflict(right)):
            return left == right
        case let (.serverMessage(left), .serverMessage(right)):
            return left == right
        case (.network, .network), (.decoding, .decoding):
            return true
        default:
            return false
        }
    }
}

extension FloorPlanError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .assignmentConflict:
            return "This table assignment conflicts with another reservation."
        case let .network(error):
            return error.localizedDescription
        case let .decoding(error):
            return error.localizedDescription
        case let .serverMessage(message):
            return message
        }
    }
}

enum FloorPlanConflictCopy {
    static func staffMessage(
        for conflict: TableAssignmentConflictDTO,
        tables: [RestaurantTableDTO]
    ) -> String {
        let tableLabel = conflict.tableLabel
            ?? tables.first(where: { $0.tableKey == conflict.tableKey })?.label
            ?? conflict.tableKey
        let guest = conflict.guestName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? "Another guest"

        switch conflict.reason {
        case "table_already_seated":
            return "Table \(tableLabel) is already occupied by \(guest). Complete or move that reservation before assigning this table."
        case "same_time_assignment":
            let timeSuffix = conflict.reservationTime
                .map { FloorPlanPresentation.displayTime($0) }
                .map { " at \($0)" } ?? ""
            return "Table \(tableLabel) is already assigned to \(guest)\(timeSuffix)."
        default:
            return "This table assignment conflicts with another reservation. Refresh the floor plan and try again."
        }
    }

    static func summary(for conflicts: [TableAssignmentConflictDTO], tables: [RestaurantTableDTO]) -> String {
        guard let first = conflicts.first else {
            return "This table assignment conflicts with another reservation. Refresh the floor plan and try again."
        }
        return staffMessage(for: first, tables: tables)
    }

}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
