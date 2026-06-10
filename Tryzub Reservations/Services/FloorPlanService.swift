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
        } catch let error as FloorPlanError {
            throw error
        } catch {
            throw FloorPlanError.network(error)
        }
    }

    func putRestaurantTables(_ tables: [RestaurantTableDTO]) async throws -> [RestaurantTableDTO] {
        do {
            return try await client.putRestaurantTables(tables, reason: .restaurantTablesPut)
        } catch let error as FloorPlanError {
            throw error
        } catch {
            throw FloorPlanError.network(error)
        }
    }

    func getFloorPlan(date: String) async throws -> FloorPlanResponseDTO {
        do {
            return try await client.fetchFloorPlan(date: date, reason: .floorPlan)
        } catch let error as FloorPlanError {
            throw error
        } catch {
            throw FloorPlanError.network(error)
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
        } catch let error as FloorPlanError {
            throw error
        } catch {
            throw FloorPlanError.network(error)
        }
    }
}
