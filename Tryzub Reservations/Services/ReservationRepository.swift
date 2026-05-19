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
        for dto in reservations {
            if let existing = try existingReservation(remoteID: dto.id) {
                existing.update(from: dto)
            } else {
                context.insert(ReservationRecord(from: dto))
            }
        }

        try context.save()
    }

    private func existingReservation(remoteID: Int) throws -> ReservationRecord? {
        let descriptor = FetchDescriptor<ReservationRecord>(
            predicate: #Predicate<ReservationRecord> { $0.remoteID == remoteID }
        )
        return try context.fetch(descriptor).first
    }
}
