//
//  HostBoardOrchestrationFacade.swift
//  Tryzub Reservations
//

import Foundation

@MainActor
enum HostBoardOrchestrationFacade {
    static func prepareAvailability(
        controller: ReservationsController,
        date: String,
        isVisible: Bool,
        shouldDefer: Bool
    ) {
        guard isVisible else {
            controller.cancelAvailabilitySummary(date: date)
            return
        }
        guard !shouldDefer else { return }
        ReservationAvailabilityFacade.prepare(
            controller: controller,
            date: date,
            reason: .hostBoardVisible
        )
    }

    static func scheduleGuestIntelligence(
        store: GuestIntelligenceStore,
        dateKey: String,
        isVisible: Bool,
        shouldDefer: Bool
    ) {
        guard isVisible else {
            store.cancelScheduledLoad()
            return
        }
        guard !shouldDefer else { return }
        store.scheduleLoad(dateKey: dateKey)
    }
}
