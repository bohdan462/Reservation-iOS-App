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
    func createGuestManageLink(id: Int) async throws -> ReservationGuestManageLinkDTO
    func logManualEmail(reservationID: Int, request: ReservationManualEmailLogRequest) async throws -> ReservationManualEmailLogDTO
    func hardDeleteReservation(id: Int) async throws
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

    // MARK: - Guest Self-Service Link

    // Intent: Generates a link staff can paste into a manual Gmail/Mail confirmation.
    // Network: POST /managed-reservations/{id}/guest-manage-link.
    // Email: Does not call backend email sending or mark email as sent.
    func createGuestManageLink(id: Int) async throws -> ReservationGuestManageLinkDTO {
        try await client.createGuestManageLink(id: id, reason: .guestManageLink)
    }

    // MARK: - Manual Email Activity Log

    // Intent: Records what staff did in Mail/Gmail; it does not send email.
    // Network: POST /managed-reservations/{id}/manual-email-log.
    // SwiftData: None unless the controller reconciles the reservation afterward.
    func logManualEmail(
        reservationID: Int,
        request: ReservationManualEmailLogRequest
    ) async throws -> ReservationManualEmailLogDTO {
        try await client.logManualEmail(
            reservationID: reservationID,
            request: request,
            reason: .manualEmailLog
        )
    }

    // MARK: - Developer Hard Delete

    // Intent: Admin/developer cleanup of test reservations only.
    // Network: DELETE /managed-reservations/{id}?force=1.
    // SwiftData: Deletes the local cached row only after server success.
    func hardDeleteReservation(id: Int) async throws {
        _ = try await client.hardDeleteReservation(id: id, reason: .hardDelete)
        try repository.deleteReservation(remoteID: id)
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
