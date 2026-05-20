//
//  ReservationRepository.swift
//  Tryzub Reservations
//

import Foundation
import SwiftData

@MainActor
protocol ReservationRepositoryProtocol {
    func latestLocalSyncDate() throws -> Date?
    func upsert(_ reservation: ReservationDTO) throws
    func upsert(_ reservations: [ReservationDTO]) throws
}

@MainActor
final class ReservationRepository: ReservationRepositoryProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func latestLocalSyncDate() throws -> Date? {
        var descriptor = FetchDescriptor<ReservationRecord>(
            sortBy: [SortDescriptor(\ReservationRecord.lastSyncedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.lastSyncedAt
    }

    func upsert(_ reservation: ReservationDTO) throws {
        try upsert([reservation])
    }

    func upsert(_ reservations: [ReservationDTO]) throws {
        let existingRecords = try context.fetch(FetchDescriptor<ReservationRecord>())
        var existingByRemoteID: [Int: ReservationRecord] = [:]
        for record in existingRecords {
            existingByRemoteID[record.remoteID] = record
        }

        for dto in reservations {
            if let existing = existingByRemoteID[dto.id] {
                existing.update(from: dto)
            } else {
                context.insert(ReservationRecord(from: dto))
            }
        }

        try context.save()
    }
}
