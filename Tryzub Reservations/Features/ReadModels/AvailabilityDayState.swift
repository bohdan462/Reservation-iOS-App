//
//  AvailabilityDayState.swift
//  Tryzub Reservations
//

import Foundation

enum AvailabilityLoadReason: String, Equatable {
    case viewOpened
    case dateChanged
    case manualRefresh
    case hostBoardVisible
    case manualAddOpen = "manual_add_open"
}

struct AvailabilityDayState: Equatable {
    let date: String
    let availability: RestaurantDayAvailabilityDTO?
    let slots: ReservationSlotsResponseDTO?
    let blockedSlotValues: Set<String>
    let availabilityFreshness: ScreenFreshnessState
    let slotsFreshness: ScreenFreshnessState
    let blockedFreshness: ScreenFreshnessState
    let isLoading: Bool
    let errorMessage: String?
    let statusLine: String?

    var hasUsableSlots: Bool {
        availability != nil || slots != nil
    }

    var isClosed: Bool {
        if let availability, !availability.isOpen { return true }
        if let slots, !slots.isOpen { return true }
        return false
    }

    var hasFreshAvailabilityData: Bool {
        availability != nil && availabilityFreshness.isFresh
    }

    var hasFreshSlotsData: Bool {
        slots != nil && slotsFreshness.isFresh
    }

    var hasFreshAvailabilityBundle: Bool {
        hasFreshAvailabilityData && hasFreshSlotsData
    }
}
