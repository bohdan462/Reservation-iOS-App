//
//  AppEnvironment.swift
//  Tryzub Reservations
//

import Foundation

// MARK: - App Dependencies

// Shared environment injected into the reservation shell.
// API client is shared; repositories/services are created per operation with current ModelContext.
struct AppEnvironment {
    let apiClient: any ReservationsAPIClientProtocol
    let role: AppUserRole
    let capabilities: AppCapabilities

    init(
        apiClient: any ReservationsAPIClientProtocol,
        role: AppUserRole
    ) {
        self.apiClient = apiClient
        self.role = role
        self.capabilities = AppCapabilities.capabilities(for: role)
    }
}
