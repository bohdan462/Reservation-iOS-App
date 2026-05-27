//
//  HiddenReservationsStore.swift
//  Tryzub Reservations
//

import Combine
import Foundation

// MARK: - Local Hidden Reservations

@MainActor
final class HiddenReservationsStore: ObservableObject {
    private static let storageKey = "tryzub.hiddenReservationRemoteIDs"

    @Published private(set) var hiddenRemoteIDs: Set<Int>

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let storedIDs = userDefaults.array(forKey: Self.storageKey) as? [Int] ?? []
        hiddenRemoteIDs = Set(storedIDs)
    }

    private let userDefaults: UserDefaults

    func isHidden(_ reservation: ReservationRecord) -> Bool {
        hiddenRemoteIDs.contains(reservation.remoteID)
    }

    func hide(remoteID: Int) {
        hiddenRemoteIDs.insert(remoteID)
        persist()
    }

    func restore(remoteID: Int) {
        hiddenRemoteIDs.remove(remoteID)
        persist()
    }

    private func persist() {
        userDefaults.set(hiddenRemoteIDs.sorted(), forKey: Self.storageKey)
    }
}
