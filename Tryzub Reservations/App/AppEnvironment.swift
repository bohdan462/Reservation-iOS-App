//
//  AppEnvironment.swift
//  Tryzub Reservations
//

import Foundation

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
