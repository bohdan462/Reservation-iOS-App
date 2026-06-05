//
//  AppUserRole.swift
//  Tryzub Reservations
//

import Foundation

// MARK: - App User Roles

enum AppUserRole: String, CaseIterable, Identifiable {
    case staff
    case manager
    case developer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .staff:
            return "Staff"
        case .manager:
            return "Manager"
        case .developer:
            return "Developer"
        }
    }
}

// MARK: - Staff Capabilities

// Intent: Keeps restaurant-facing actions gated by role without changing backend contracts.
struct AppCapabilities {
    let canConfirmReservations: Bool
    let canSeatReservations: Bool
    let canCancelReservations: Bool
    let canCreateManualReservations: Bool
    let canViewFailedImports: Bool
    let canEditReservationDetails: Bool
    let canViewDeveloperDiagnostics: Bool
    let canGenerateGuestManageLinks: Bool
    let canViewHiddenReservations: Bool
    let canHardDeleteReservations: Bool
    let canViewAnalytics: Bool
    let canManageRestaurantSettings: Bool

    static func capabilities(for role: AppUserRole) -> AppCapabilities {
        switch role {
        case .staff:
            return AppCapabilities(
                canConfirmReservations: false,
                canSeatReservations: true,
                canCancelReservations: false,
                canCreateManualReservations: false,
                canViewFailedImports: false,
                canEditReservationDetails: true,
                canViewDeveloperDiagnostics: false,
                canGenerateGuestManageLinks: false,
                canViewHiddenReservations: false,
                canHardDeleteReservations: false,
                canViewAnalytics: false,
                canManageRestaurantSettings: false
            )
        case .manager:
            return AppCapabilities(
                canConfirmReservations: true,
                canSeatReservations: true,
                canCancelReservations: true,
                canCreateManualReservations: true,
                canViewFailedImports: true,
                canEditReservationDetails: true,
                canViewDeveloperDiagnostics: false,
                canGenerateGuestManageLinks: true,
                canViewHiddenReservations: true,
                canHardDeleteReservations: false,
                canViewAnalytics: true,
                canManageRestaurantSettings: true
            )
        case .developer:
            return AppCapabilities(
                canConfirmReservations: true,
                canSeatReservations: true,
                canCancelReservations: true,
                canCreateManualReservations: true,
                canViewFailedImports: true,
                canEditReservationDetails: true,
                canViewDeveloperDiagnostics: true,
                canGenerateGuestManageLinks: true,
                canViewHiddenReservations: true,
                canHardDeleteReservations: true,
                canViewAnalytics: true,
                canManageRestaurantSettings: true
            )
        }
    }
}
