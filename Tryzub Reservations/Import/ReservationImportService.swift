//
//  ReservationImportService.swift
//  Tryzub Reservations
//
//  Created by Bohdan Tkachenko on 5/13/26.
//

import Foundation

@MainActor
protocol ReservationSyncServiceProtocol {
    func syncAllReservations(reason: ReservationAPIRequestReason) async throws
    func syncToday(reason: ReservationAPIRequestReason) async throws
    func syncScheduleWindow(from: String, to: String, reason: ReservationAPIRequestReason) async throws
    func syncReviewQueues(reason: ReservationAPIRequestReason) async throws
    func saveReservation(_ reservation: ReservationDTO) throws
}

@MainActor
final class ReservationSyncService: ReservationSyncServiceProtocol {
    private let client: any ReservationsAPIClientProtocol
    private let repository: any ReservationRepositoryProtocol

    init(
        client: any ReservationsAPIClientProtocol,
        repository: any ReservationRepositoryProtocol
    ) {
        self.client = client
        self.repository = repository
    }

    func syncAllReservations(reason: ReservationAPIRequestReason) async throws {
        let reservations = try await client.fetchAllReservations(
            perPage: 100,
            date: nil,
            from: nil,
            to: nil,
            status: nil,
            search: nil,
            reason: reason
        )
        try repository.upsert(reservations)
    }

    func syncToday(reason: ReservationAPIRequestReason) async throws {
        let response = try await client.fetchReservations(
            page: 1,
            perPage: 50,
            date: Date.reservationDateString(),
            from: nil,
            to: nil,
            status: nil,
            search: nil,
            retryCount: 0,
            reason: reason
        )

        try repository.upsert(response.data)
    }

    func syncScheduleWindow(from: String, to: String, reason: ReservationAPIRequestReason) async throws {
        let reservations = try await client.fetchAllReservations(
            perPage: 100,
            date: nil,
            from: from,
            to: to,
            status: nil,
            search: nil,
            reason: reason
        )
        try repository.upsert(reservations)
    }

    func syncReviewQueues(reason: ReservationAPIRequestReason) async throws {
        let needsReview = try await client.fetchReservations(
            page: 1,
            perPage: 50,
            date: nil,
            from: nil,
            to: nil,
            status: .needsReview,
            search: nil,
            retryCount: 0,
            reason: reason
        ).data

        let newReservations = try await client.fetchReservations(
            page: 1,
            perPage: 50,
            date: nil,
            from: nil,
            to: nil,
            status: .new,
            search: nil,
            retryCount: 0,
            reason: reason
        ).data

        try repository.upsert(needsReview + newReservations)
    }

    func saveReservation(_ reservation: ReservationDTO) throws {
        try repository.upsert(reservation)
    }
}
