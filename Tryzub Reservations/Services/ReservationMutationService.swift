//
//  ReservationMutationService.swift
//  Tryzub Reservations
//

import Foundation

@MainActor
protocol ReservationMutationServiceProtocol {
    func updateReservation(id: Int, request: ReservationUpdateRequest) async throws -> ReservationDTO
    func createReservation(_ request: ReservationCreateRequest) async throws -> ReservationDTO
    func confirmReservation(id: Int) async throws -> ReservationConfirmResponse
    func reconcileReservation(id: Int) async throws -> ReservationDTO
}

@MainActor
final class ReservationMutationService: ReservationMutationServiceProtocol {
    private let client: any ReservationsAPIClientProtocol
    private let repository: any ReservationRepositoryProtocol

    init(
        client: any ReservationsAPIClientProtocol,
        repository: any ReservationRepositoryProtocol
    ) {
        self.client = client
        self.repository = repository
    }

    func updateReservation(id: Int, request: ReservationUpdateRequest) async throws -> ReservationDTO {
        do {
            let reservation = try await client.updateReservation(
                id: id,
                request: request,
                reason: .mutationPatch
            )
            try repository.upsert(reservation)
            return reservation
        } catch {
            if error.mayHaveReachedReservationServer {
                _ = try? await reconcileReservation(id: id)
            }
            throw error
        }
    }

    func createReservation(_ request: ReservationCreateRequest) async throws -> ReservationDTO {
        let reservation = try await client.createReservation(request, reason: .mutationCreate)
        try repository.upsert(reservation)
        return reservation
    }

    func confirmReservation(id: Int) async throws -> ReservationConfirmResponse {
        do {
            let response = try await client.confirmReservation(id: id, reason: .mutationConfirm)
            try repository.upsert(response.data)
            return response
        } catch {
            if error.mayHaveReachedReservationServer {
                _ = try? await reconcileReservation(id: id)
            }
            throw error
        }
    }

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
