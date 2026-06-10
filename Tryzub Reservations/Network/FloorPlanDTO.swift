//
//  FloorPlanDTO.swift
//  Tryzub Reservations
//

import Foundation

// MARK: - Floor Plan Response

/// Backend floor-plan payload for one service date.
/// Decoder uses `.convertFromSnakeCase` on `ReservationsAPIClient`.
struct FloorPlanResponseDTO: Decodable, Equatable {
    let success: Bool
    let date: String
    let serverTime: String?
    let tables: [RestaurantTableDTO]
    let assignments: [TableAssignmentDTO]
    let reservations: [ManagedReservationDTO]
}

typealias ManagedReservationDTO = ReservationDTO

// MARK: - Tables

struct RestaurantTableDTO: Codable, Identifiable, Equatable {
    let id: Int
    let restaurantKey: String
    let tableKey: String
    let label: String
    let x: Int
    let y: Int
    let widthUnits: Int
    let heightUnits: Int
    let minCapacity: Int
    let maxCapacity: Int
    let section: String?
    let sortOrder: Int
    let isActive: Bool
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case restaurantKey
        case tableKey
        case label
        case x
        case y
        case widthUnits
        case heightUnits
        case minCapacity
        case maxCapacity
        case section
        case sortOrder
        case isActive
        case createdAt
        case updatedAt
    }
}

struct RestaurantTablesResponseDTO: Decodable, Equatable {
    let success: Bool
    let data: [RestaurantTableDTO]
    let upsertMode: String?
    let contractNote: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        upsertMode = try container.decodeIfPresent(String.self, forKey: .upsertMode)
        contractNote = try container.decodeIfPresent(String.self, forKey: .contractNote)

        if let rows = try container.decodeIfPresent([RestaurantTableDTO].self, forKey: .data) {
            data = rows
        } else if let legacyRows = try container.decodeIfPresent([RestaurantTableDTO].self, forKey: .tables) {
            data = legacyRows
        } else {
            data = []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case success
        case data
        case tables
        case upsertMode
        case contractNote
    }
}

struct RestaurantTableUpsertDTO: Encodable, Equatable {
    let restaurantKey: String
    let tableKey: String
    let label: String
    let x: Int
    let y: Int
    let widthUnits: Int
    let heightUnits: Int
    let minCapacity: Int
    let maxCapacity: Int
    let sortOrder: Int
    let isActive: Bool
    let id: Int?
    let section: String?

    init(from table: RestaurantTableDTO) {
        id = table.id > 0 ? table.id : nil
        restaurantKey = table.restaurantKey
        tableKey = table.tableKey
        label = table.label
        x = table.x
        y = table.y
        widthUnits = table.widthUnits
        heightUnits = table.heightUnits
        minCapacity = table.minCapacity
        maxCapacity = table.maxCapacity
        sortOrder = table.sortOrder
        isActive = table.isActive
        section = table.section
    }

    enum CodingKeys: String, CodingKey {
        case id
        case restaurantKey
        case tableKey
        case label
        case x
        case y
        case widthUnits
        case heightUnits
        case minCapacity
        case maxCapacity
        case section
        case sortOrder
        case isActive
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(restaurantKey, forKey: .restaurantKey)
        try container.encode(tableKey, forKey: .tableKey)
        try container.encode(label, forKey: .label)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(widthUnits, forKey: .widthUnits)
        try container.encode(heightUnits, forKey: .heightUnits)
        try container.encode(minCapacity, forKey: .minCapacity)
        try container.encode(maxCapacity, forKey: .maxCapacity)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(section, forKey: .section)
    }
}

struct RestaurantTablesPutRequestDTO: Encodable, Equatable {
    let tables: [RestaurantTableUpsertDTO]

    init(tables: [RestaurantTableDTO]) {
        self.tables = tables.map(RestaurantTableUpsertDTO.init)
    }
}

// MARK: - Assignments

struct TableAssignmentDTO: Codable, Equatable {
    let reservationId: Int
    let reservationDate: String
    let tableKeys: [String]
    let tableLabel: String?
    let assignedAt: String?
    let updatedAt: String?
}

struct PatchReservationTablesRequest: Encodable, Equatable {
    let tableKeys: [String]
}

struct FloorPlanPatchDataDTO: Decodable, Equatable {
    let reservation: ManagedReservationDTO?
    let assignment: TableAssignmentDTO?
}

struct FloorPlanPatchResponseDTO: Decodable, Equatable {
    let success: Bool
    let data: FloorPlanPatchDataDTO?
    let message: String?

    var reservation: ManagedReservationDTO? {
        data?.reservation ?? directReservation
    }

    var assignment: TableAssignmentDTO? {
        data?.assignment ?? directAssignment
    }

    private let directReservation: ManagedReservationDTO?
    private let directAssignment: TableAssignmentDTO?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        message = try container.decodeIfPresent(String.self, forKey: .message)

        if let wrapped = try container.decodeIfPresent(FloorPlanPatchDataDTO.self, forKey: .data) {
            data = wrapped
            directReservation = nil
            directAssignment = nil
        } else {
            data = nil
            directReservation = try container.decodeIfPresent(ManagedReservationDTO.self, forKey: .reservation)
            directAssignment = try container.decodeIfPresent(TableAssignmentDTO.self, forKey: .assignment)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case success
        case data
        case message
        case reservation
        case assignment
    }
}

// MARK: - Conflicts

struct TableAssignmentConflictDTO: Decodable, Equatable, Identifiable {
    let reservationId: Int
    let guestName: String?
    let reservationTime: String?
    let tableKey: String
    let tableLabel: String?
    let status: String?
    let reason: String?

    var id: String {
        "\(reservationId)-\(tableKey)-\(reason ?? "conflict")"
    }
}

struct TableAssignmentConflictResponseDTO: Decodable, Equatable {
    let success: Bool?
    let code: String?
    let message: String?
    let conflicts: [TableAssignmentConflictDTO]

    private struct WordPressConflictData: Decodable, Equatable {
        let status: Int?
        let conflicts: [TableAssignmentConflictDTO]?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message)

        let topLevel = try container.decodeIfPresent([TableAssignmentConflictDTO].self, forKey: .conflicts) ?? []
        if !topLevel.isEmpty {
            conflicts = topLevel
            return
        }

        if let nested = try container.decodeIfPresent(WordPressConflictData.self, forKey: .data),
           let nestedConflicts = nested.conflicts,
           !nestedConflicts.isEmpty {
            conflicts = nestedConflicts
            return
        }

        conflicts = []
    }

    private enum CodingKeys: String, CodingKey {
        case success
        case code
        case message
        case conflicts
        case data
    }
}
