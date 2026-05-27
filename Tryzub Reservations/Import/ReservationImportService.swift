//
//  ReservationImportService.swift
//  Tryzub Reservations
//
//  Created by Bohdan Tkachenko on 5/13/26.
//

import Foundation

// MARK: - Sync Service Contract

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
    // MARK: - Dependencies

    private let client: any ReservationsAPIClientProtocol
    private let repository: any ReservationRepositoryProtocol

    init(
        client: any ReservationsAPIClientProtocol,
        repository: any ReservationRepositoryProtocol
    ) {
        self.client = client
        self.repository = repository
    }

    // MARK: - Full Cache Sync

    // Intent: Fetches every managed reservation page for diagnostics or broad cache refresh.
    // Network: GET /managed-reservations across all pages.
    // SwiftData: Upserts fetched server DTOs; cache only.
    func syncAllReservations(reason: ReservationAPIRequestReason) async throws {
        let reservations = try await client.fetchAllReservations(
            perPage: 100,
            date: nil,
            from: nil,
            to: nil,
            status: nil,
            search: nil,
            includeHidden: false,
            reason: reason
        )
        try repository.upsert(reservations)
    }

    // MARK: - Today Sync

    // Intent: Refreshes today's host-board reservation cache.
    // Network: GET /managed-reservations?date=today.
    // SwiftData: Replaces this date scope with fetched server DTOs.
    func syncToday(reason: ReservationAPIRequestReason) async throws {
        let today = Date.reservationDateString()
        let response = try await client.fetchReservations(
            page: 1,
            perPage: 50,
            date: today,
            from: nil,
            to: nil,
            status: nil,
            search: nil,
            includeHidden: false,
            retryCount: 0,
            reason: reason
        )

        try repository.replaceDateScope(date: today, with: response.data, includeHidden: false)
    }

    // MARK: - Schedule Window Sync

    // Intent: Refreshes the upcoming schedule window used by Schedule.
    // Network: GET /managed-reservations?from=...&to=... across pages.
    // SwiftData: Replaces only the requested date window with fetched server DTOs.
    func syncScheduleWindow(from: String, to: String, reason: ReservationAPIRequestReason) async throws {
        let reservations = try await client.fetchAllReservations(
            perPage: 100,
            date: nil,
            from: from,
            to: to,
            status: nil,
            search: nil,
            includeHidden: false,
            reason: reason
        )
        try repository.replaceDateWindow(from: from, to: to, with: reservations, includeHidden: false)
    }

    // MARK: - Pending Review Sync

    // Intent: Refreshes the staff pending queue from new and needs_review rows.
    // Network: GET /managed-reservations?status=needs_review and status=new.
    // SwiftData: Upserts fetched server DTOs without deleting records missing from this status snapshot.
    func syncReviewQueues(reason: ReservationAPIRequestReason) async throws {
        let needsReview = try await client.fetchReservations(
            page: 1,
            perPage: 50,
            date: nil,
            from: nil,
            to: nil,
            status: .needsReview,
            search: nil,
            includeHidden: false,
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
            includeHidden: false,
            retryCount: 0,
            reason: reason
        ).data

        try repository.replaceReviewQueue(with: needsReview + newReservations)
    }

    // MARK: - Local Cache Upsert

    // Intent: Upserts one server DTO already returned by another operation.
    // Network: None; this is cache-only.
    func saveReservation(_ reservation: ReservationDTO) throws {
        try repository.upsert(reservation)
    }
}
