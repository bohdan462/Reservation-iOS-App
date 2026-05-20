//
//  ReservationImportService.swift
//  Tryzub Reservations
//
//  Created by Bohdan Tkachenko on 5/13/26.
//

import Foundation

@MainActor
protocol ReservationSyncServiceProtocol {
    func syncAllReservations() async throws
    func syncToday() async throws
    func syncUpcoming() async throws
    func syncNeedsReview() async throws
    func syncReviewQueues() async throws
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

    func syncAllReservations() async throws {
        let reservations = try await client.fetchAllReservations(
            perPage: 100,
            date: nil,
            from: nil,
            to: nil,
            status: nil,
            search: nil
        )
        try repository.upsert(reservations)
    }

    func syncToday() async throws {
        let response = try await client.fetchReservations(
            page: 1,
            perPage: 50,
            date: Date.reservationDateString(),
            from: nil,
            to: nil,
            status: nil,
            search: nil,
            retryCount: 0
        )

        try repository.upsert(response.data)
    }

    func syncUpcoming() async throws {
        let reservations = try await client.fetchAllReservations(
            perPage: 100,
            date: nil,
            from: Date.reservationDateString(),
            to: nil,
            status: nil,
            search: nil
        )
        try repository.upsert(reservations)
    }

    func syncNeedsReview() async throws {
        let reservations = try await client.fetchAllReservations(
            perPage: 100,
            date: nil,
            from: nil,
            to: nil,
            status: .needsReview,
            search: nil
        )
        try repository.upsert(reservations)
    }

    func syncReviewQueues() async throws {
        let needsReview = try await client.fetchAllReservations(
            perPage: 100,
            date: nil,
            from: nil,
            to: nil,
            status: .needsReview,
            search: nil
        )

        let newReservations = try await client.fetchAllReservations(
            perPage: 100,
            date: nil,
            from: nil,
            to: nil,
            status: .new,
            search: nil
        )

        try repository.upsert(needsReview + newReservations)
    }

    func saveReservation(_ reservation: ReservationDTO) throws {
        try repository.upsert(reservation)
    }
}

typealias ReservationImportService = ReservationSyncService
