//
//  FloorPlanService.swift
//  Tryzub Reservations
//

import Foundation

protocol FloorPlanServiceProtocol: Sendable {
    func getRestaurantTables() async throws -> [RestaurantTableDTO]
    func putRestaurantTables(_ tables: [RestaurantTableDTO]) async throws -> [RestaurantTableDTO]
    func getFloorPlan(date: String) async throws -> FloorPlanResponseDTO
    func patchReservationTables(
        reservationID: Int,
        tableKeys: [String]
    ) async throws -> FloorPlanPatchResponseDTO
}

final class FloorPlanService: FloorPlanServiceProtocol {
    private let client: any ReservationsAPIClientProtocol

    init(client: any ReservationsAPIClientProtocol) {
        self.client = client
    }

    func getRestaurantTables() async throws -> [RestaurantTableDTO] {
        do {
            return try await client.fetchRestaurantTables(reason: .restaurantTables)
        } catch {
            throw mapError(error)
        }
    }

    func putRestaurantTables(_ tables: [RestaurantTableDTO]) async throws -> [RestaurantTableDTO] {
        do {
            return try await client.putRestaurantTables(tables, reason: .restaurantTablesPut)
        } catch {
            throw mapError(error)
        }
    }

    func getFloorPlan(date: String) async throws -> FloorPlanResponseDTO {
        do {
            return try await client.fetchFloorPlan(date: date, reason: .floorPlan)
        } catch {
            throw mapError(error)
        }
    }

    func patchReservationTables(
        reservationID: Int,
        tableKeys: [String]
    ) async throws -> FloorPlanPatchResponseDTO {
        do {
            return try await client.patchReservationTables(
                reservationID: reservationID,
                request: PatchReservationTablesRequest(tableKeys: tableKeys),
                reason: .reservationTablesPatch
            )
        } catch {
            throw mapError(error)
        }
    }

    private func mapError(_ error: Error) -> FloorPlanError {
        if let error = error as? FloorPlanError {
            return error
        }
        if let apiError = error as? ReservationAPIError {
            switch apiError {
            case .wordpressError(_, let message, _, _):
                return .serverMessage(message)
            case .serverError(_, let diagnostics):
                if let snippet = diagnostics?.responseBodySnippet?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !snippet.isEmpty {
                    return .serverMessage(snippet)
                }
                return .serverMessage(apiError.errorDescription ?? "The reservation API returned an error.")
            case .networkFailure(let urlError):
                return .network(urlError)
            case .decodingFailure(let decodingError, _):
                return .decoding(decodingError)
            default:
                return .network(apiError)
            }
        }
        return .network(error)
    }
}
