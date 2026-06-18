//
//  FloorPlanViewState.swift
//  Tryzub Reservations
//

import Foundation

enum FloorPlanMode: String, Equatable {
    case liveService
    case planning

    var badgeTitle: String {
        switch self {
        case .liveService:
            return "Live today"
        case .planning:
            return "Planning"
        }
    }
}

enum FloorPlanTableState: Equatable {
    case empty
    case assignedUpcoming
    case seated
    case completedHistorical
    case conflict
    case inactive
}

struct FloorPlanTableBlock: Identifiable, Equatable {
    let table: RestaurantTableDTO
    let state: FloorPlanTableState
    let assignments: [FloorPlanTableReservationAssignment]
    let displayReservation: FloorPlanTableReservationAssignment?

    var id: String { table.tableKey }
    var reservation: ManagedReservationDTO? { displayReservation?.reservation }
    var assignment: TableAssignmentDTO? { displayReservation?.assignment }
    var assignedCount: Int { assignments.count }
}

struct FloorPlanTableReservationAssignment: Identifiable, Equatable {
    let reservation: ManagedReservationDTO
    let assignment: TableAssignmentDTO

    var id: Int { reservation.id }
}

struct FloorPlanAssignedReservation: Identifiable, Equatable {
    let reservation: ManagedReservationDTO
    let assignment: TableAssignmentDTO

    var id: Int { reservation.id }

    var tableLabel: String {
        let trimmed = assignment.tableLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        return assignment.tableKeys.joined(separator: " + ")
    }
}

struct FloorPlanConflictViewState: Equatable {
    let conflicts: [TableAssignmentConflictDTO]
    let message: String
}

struct FloorPlanViewState: Equatable {
    static let empty = FloorPlanViewState(
        selectedDate: Date().reservationDateString(),
        isToday: true,
        mode: .liveService,
        tableBlocks: [],
        unassignedReservations: [],
        assignedReservations: [],
        assignmentsByTableKey: [:],
        reservationsByID: [:],
        gridWidth: 12,
        gridHeight: 8,
        lastCheckedLine: "Not loaded yet",
        tables: []
    )

    let selectedDate: String
    let isToday: Bool
    let mode: FloorPlanMode
    let tableBlocks: [FloorPlanTableBlock]
    let unassignedReservations: [ManagedReservationDTO]
    let assignedReservations: [FloorPlanAssignedReservation]
    let assignmentsByTableKey: [String: [FloorPlanTableReservationAssignment]]
    let reservationsByID: [Int: ManagedReservationDTO]
    let gridWidth: Int
    let gridHeight: Int
    let lastCheckedLine: String
    let tables: [RestaurantTableDTO]

    var unassignedCount: Int { unassignedReservations.count }
    var hasTables: Bool { !tables.isEmpty }
}

enum FloorPlanViewStateBuilder {
    static func build(
        response: FloorPlanResponseDTO,
        selectedDate: String,
        lastCheckedAt: Date?
    ) -> FloorPlanViewState {
        let todayKey = Date().reservationDateString()
        let isToday = selectedDate == todayKey
        let mode: FloorPlanMode = isToday ? .liveService : .planning

        let reservationsByID = Dictionary(
            uniqueKeysWithValues: response.reservations.map { ($0.id, $0) }
        )

        let assignmentsByReservationID = Dictionary(
            uniqueKeysWithValues: response.assignments.map { ($0.reservationId, $0) }
        )

        var assignmentsByTableKey: [String: [FloorPlanTableReservationAssignment]] = [:]
        for assignment in response.assignments {
            guard let reservation = reservationsByID[assignment.reservationId] else { continue }
            let tableAssignment = FloorPlanTableReservationAssignment(
                reservation: reservation,
                assignment: assignment
            )
            var seenTableKeys = Set<String>()
            for tableKey in assignment.tableKeys {
                guard seenTableKeys.insert(tableKey).inserted else { continue }
                assignmentsByTableKey[tableKey, default: []].append(tableAssignment)
            }
        }

        let activeTables = response.tables
            .filter(\.isActive)
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                }
                return lhs.sortOrder < rhs.sortOrder
            }

        let tableBlocks = activeTables.map { table in
            let assignments = (assignmentsByTableKey[table.tableKey] ?? [])
                .sorted { lhs, rhs in
                    reservationSort(lhs: lhs.reservation, rhs: rhs.reservation)
                }
            let displayReservation = FloorPlanDisplayReservationResolver.resolve(
                assignments: assignments,
                selectedDate: selectedDate,
                now: Date()
            )
            let state = tableState(for: displayReservation?.reservation)
            return FloorPlanTableBlock(
                table: table,
                state: state,
                assignments: assignments,
                displayReservation: displayReservation
            )
        }

        let unassignedReservations = response.reservations
            .filter { reservation in
                guard isFloorPlanAssignable(reservation.status) else { return false }
                let assignment = assignmentsByReservationID[reservation.id]
                return assignment == nil || assignment?.tableKeys.isEmpty == true
            }
            .sorted(by: reservationSort)

        let assignedReservations = response.assignments.compactMap { assignment -> FloorPlanAssignedReservation? in
            guard !assignment.tableKeys.isEmpty,
                  let reservation = reservationsByID[assignment.reservationId],
                  isFloorPlanAssignable(reservation.status) else {
                return nil
            }
            return FloorPlanAssignedReservation(
                reservation: reservation,
                assignment: assignment
            )
        }
        .sorted { lhs, rhs in
            reservationSort(lhs: lhs.reservation, rhs: rhs.reservation)
        }

        let gridBounds = gridBounds(for: activeTables)

        return FloorPlanViewState(
            selectedDate: selectedDate,
            isToday: isToday,
            mode: mode,
            tableBlocks: tableBlocks,
            unassignedReservations: unassignedReservations,
            assignedReservations: assignedReservations,
            assignmentsByTableKey: assignmentsByTableKey,
            reservationsByID: reservationsByID,
            gridWidth: gridBounds.width,
            gridHeight: gridBounds.height,
            lastCheckedLine: lastCheckedLine(lastCheckedAt: lastCheckedAt, serverTime: response.serverTime),
            tables: activeTables
        )
    }

    static func isFloorPlanAssignable(_ status: ReservationStatus) -> Bool {
        switch status {
        case .new, .needsReview, .confirmed, .seated:
            return true
        case .completed, .cancelled, .noShow:
            return false
        }
    }

    static func tableState(for reservation: ManagedReservationDTO?) -> FloorPlanTableState {
        guard let reservation else { return .empty }
        switch reservation.status {
        case .seated:
            return .seated
        case .confirmed, .new, .needsReview:
            return .assignedUpcoming
        case .completed, .cancelled, .noShow:
            return .completedHistorical
        }
    }

    private static func gridBounds(for tables: [RestaurantTableDTO]) -> (width: Int, height: Int) {
        guard !tables.isEmpty else { return (12, 8) }
        let width = tables.map { $0.x + max($0.widthUnits, 1) }.max() ?? 12
        let height = tables.map { $0.y + max($0.heightUnits, 1) }.max() ?? 8
        return (max(width + 1, 8), max(height + 1, 6))
    }

    private static func reservationSort(lhs: ManagedReservationDTO, rhs: ManagedReservationDTO) -> Bool {
        if lhs.reservationTime == rhs.reservationTime {
            return lhs.guestName.localizedCaseInsensitiveCompare(rhs.guestName) == .orderedAscending
        }
        return lhs.reservationTime < rhs.reservationTime
    }

    private static func lastCheckedLine(lastCheckedAt: Date?, serverTime: String?) -> String {
        if let lastCheckedAt {
            return "Last checked \(ReservationFormatters.shortTime.string(from: lastCheckedAt))"
        }
        if let serverTime,
           let parsed = ReservationFormatters.serverDateTime.date(from: serverTime)
            ?? ReservationFormatters.serverDateMinute.date(from: serverTime) {
            return "Server time \(ReservationFormatters.shortTime.string(from: parsed))"
        }
        return "Not loaded yet"
    }
}

enum FloorPlanPresentation {
    static func displayTime(_ raw: String) -> String {
        if let date = ReservationFormatters.apiTime.date(from: raw) {
            return ReservationFormatters.shortTime.string(from: date)
        }
        if raw.count >= 5 {
            let hhmm = String(raw.prefix(5))
            if let date = ReservationFormatters.serverDateMinute.date(from: "1970-01-01 \(hhmm)") {
                return ReservationFormatters.shortTime.string(from: date)
            }
            return hhmm
        }
        return raw
    }

    static func displayDate(_ raw: String) -> String {
        guard let date = ReservationFormatters.reservationDateKey.date(from: raw) else {
            return raw
        }
        return ReservationFormatters.mediumDate.string(from: date)
    }

    static func capacityRange(min: Int, max: Int) -> String {
        if min == max {
            return "\(min)"
        }
        return "\(min)–\(max)"
    }

    static func tableDetailLine(
        table: RestaurantTableDTO,
        reservation: ManagedReservationDTO?
    ) -> String {
        let capacity = "Fits \(capacityRange(min: table.minCapacity, max: table.maxCapacity)) guests"
        guard let reservation else {
            return "\(table.label)\n\(capacity)"
        }
        let guest = reservation.guestName.trimmingCharacters(in: .whitespacesAndNewlines)
        let time = displayTime(reservation.reservationTime)
        return "\(table.label)\n\(capacity)\nAssigned to \(guest) · \(time)"
    }

    static func assignmentCountHint(for count: Int) -> String? {
        count > 1 ? "+\(count - 1) more" : nil
    }

    static func assignmentCountAccessibilityHint(for count: Int) -> String? {
        count > 1 ? "\(count) assigned reservations" : nil
    }

    static func combinedCapacity(for tables: [RestaurantTableDTO]) -> String {
        guard !tables.isEmpty else { return "-" }
        let minTotal = tables.reduce(0) { $0 + $1.minCapacity }
        let maxTotal = tables.reduce(0) { $0 + $1.maxCapacity }
        return capacityRange(min: minTotal, max: maxTotal)
    }

    static func selectedTablesLabel(_ tables: [RestaurantTableDTO]) -> String {
        tables.map(\.label).joined(separator: " + ")
    }

    static func tableStatusLabel(for block: FloorPlanTableBlock) -> String {
        guard let reservation = block.reservation else {
            return "Open"
        }

        switch reservation.status {
        case .seated:
            return "Occupied"
        case .confirmed, .new, .needsReview:
            return "Assigned at \(displayTime(reservation.reservationTime))"
        case .completed, .cancelled, .noShow:
            return "Historical"
        }
    }

    static func compactTableStatusLabel(for block: FloorPlanTableBlock) -> String {
        guard let reservation = block.reservation else {
            return "Open"
        }

        switch reservation.status {
        case .seated:
            return "Seated"
        case .confirmed, .new, .needsReview:
            return displayTime(reservation.reservationTime)
        case .completed, .cancelled, .noShow:
            return "Done"
        }
    }
}

enum FloorPlanDisplayReservationResolver {
    static func resolve(
        assignments: [FloorPlanTableReservationAssignment],
        selectedDate: String,
        now: Date = Date()
    ) -> FloorPlanTableReservationAssignment? {
        assignments.min { lhs, rhs in
            sortKey(for: lhs.reservation, selectedDate: selectedDate, now: now)
                < sortKey(for: rhs.reservation, selectedDate: selectedDate, now: now)
        }
    }

    private static func sortKey(
        for reservation: ManagedReservationDTO,
        selectedDate: String,
        now: Date
    ) -> ReservationDisplaySortKey {
        let reservationDate = reservationDate(for: reservation, selectedDate: selectedDate)
        let timeInterval = reservationDate.map { $0.timeIntervalSince(now) }
        let distance = abs(timeInterval ?? .greatestFiniteMagnitude)
        let currentWindow: TimeInterval = 90 * 60

        switch reservation.status {
        case .seated:
            return ReservationDisplaySortKey(priority: 0, distance: distance, time: reservation.reservationTime, guestName: reservation.guestName)
        case .confirmed, .new, .needsReview:
            if let timeInterval, abs(timeInterval) <= currentWindow {
                return ReservationDisplaySortKey(priority: 1, distance: distance, time: reservation.reservationTime, guestName: reservation.guestName)
            }
            if let timeInterval, timeInterval >= 0 {
                return ReservationDisplaySortKey(priority: 2, distance: timeInterval, time: reservation.reservationTime, guestName: reservation.guestName)
            }
            return ReservationDisplaySortKey(priority: 3, distance: distance, time: reservation.reservationTime, guestName: reservation.guestName)
        case .completed, .cancelled, .noShow:
            return ReservationDisplaySortKey(priority: 4, distance: distance, time: reservation.reservationTime, guestName: reservation.guestName)
        }
    }

    private static func reservationDate(
        for reservation: ManagedReservationDTO,
        selectedDate: String
    ) -> Date? {
        let date = reservation.reservationDate.isEmpty ? selectedDate : reservation.reservationDate
        if let parsed = ReservationFormatters.serverDateTime.date(from: "\(date) \(reservation.reservationTime)") {
            return parsed
        }
        let time = String(reservation.reservationTime.prefix(5))
        return ReservationFormatters.serverDateMinute.date(from: "\(date) \(time)")
    }
}

private struct ReservationDisplaySortKey: Comparable {
    let priority: Int
    let distance: TimeInterval
    let time: String
    let guestName: String

    static func < (lhs: ReservationDisplaySortKey, rhs: ReservationDisplaySortKey) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        if lhs.distance != rhs.distance {
            return lhs.distance < rhs.distance
        }
        if lhs.time != rhs.time {
            return lhs.time < rhs.time
        }
        return lhs.guestName.localizedCaseInsensitiveCompare(rhs.guestName) == .orderedAscending
    }
}
