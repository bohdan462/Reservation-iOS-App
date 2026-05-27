//
//  HiddenReservationsStore.swift
//  Tryzub Reservations
//

import Combine

// MARK: - Hidden Reservation Filter

@MainActor
final class HiddenReservationsStore: ObservableObject {
    func isHidden(_ reservation: ReservationRecord) -> Bool {
        reservation.isHidden
    }
}
