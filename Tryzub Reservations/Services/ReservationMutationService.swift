//
//  ReservationMutationService.swift
//  Tryzub Reservations
//

import Foundation

// MARK: - Mutation Service Contract

@MainActor
protocol ReservationMutationServiceProtocol {
    func updateReservation(id: Int, request: ReservationUpdateRequest) async throws -> ReservationDTO
    func createReservation(_ request: ReservationCreateRequest) async throws -> ReservationDTO
    func confirmReservation(id: Int) async throws -> ReservationConfirmResponse
    func reconcileReservation(id: Int) async throws -> ReservationDTO
}

@MainActor
final class ReservationMutationService: ReservationMutationServiceProtocol {
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

    // MARK: - Reservation Updates

    // Intent: Server-first edit for table, notes, date/time, party size, or status.
    // Network: PATCH /managed-reservations/{id}.
    // SwiftData: Upserts the returned server DTO.
    func updateReservation(id: Int, request: ReservationUpdateRequest) async throws -> ReservationDTO {
        let reservation = try await client.updateReservation(
            id: id,
            request: request,
            reason: .mutationPatch
        )
        try repository.upsert(reservation)
        return reservation
    }

    // MARK: - Manual Reservation Creation

    // Intent: Staff creates a call-in/manual reservation on the server.
    // Network: POST /managed-reservations.
    // SwiftData: Upserts the returned server DTO.
    func createReservation(_ request: ReservationCreateRequest) async throws -> ReservationDTO {
        let reservation = try await client.createReservation(request, reason: .mutationCreate)
        try repository.upsert(reservation)
        return reservation
    }

    // MARK: - Confirm With Email

    // Intent: Confirms reservation and asks backend to send/record confirmation email.
    // Network: POST /managed-reservations/{id}/confirm.
    // Rename note: This method should mention email in a later cleanup.
    func confirmReservation(id: Int) async throws -> ReservationConfirmResponse {
        let response = try await client.confirmReservation(id: id, reason: .mutationConfirm)
        try repository.upsert(response.data)
        return response
    }

    // MARK: - Reconcile Uncertain Mutation

    // Intent: Reads server truth after a PATCH/POST may have reached WordPress.
    // Network: GET /managed-reservations/{id}.
    // SwiftData: Upserts the fetched server DTO.
    func reconcileReservation(id: Int) async throws -> ReservationDTO {
        let reservation = try await client.fetchReservation(
            id: id,
            retryCount: 0,
            reason: .reconcileByID
        )
        try repository.upsert(reservation)
        return reservation
    }
}
