//
//  GuestInsightLocalPool.swift
//  Tryzub Reservations
//

import Foundation

// MARK: - Bounded Local Guest History

enum GuestInsightLocalPool {
    private static let defaultMaxRecords = 800

    /// Supplements the active reservation window with identity-matched rows from the same pool.
    static func boundedPool(
        selected: ReservationRecord,
        windowRecords: [ReservationRecord],
        maxRecords: Int = defaultMaxRecords
    ) -> [ReservationRecord] {
        let visible = windowRecords.filter { !$0.isHidden }
        guard visible.count > maxRecords else { return visible }

        let resolver = GuestIdentityResolver()
        let selectedIdentity = resolver.identity(for: selected)
        var candidates = visible.filter { record in
            record.remoteID == selected.remoteID
                || resolver.match(record, against: selectedIdentity, selectedID: selected.remoteID) != nil
        }

        if candidates.count > maxRecords {
            candidates.sort { lhs, rhs in
                if lhs.reservationDate == rhs.reservationDate {
                    if lhs.reservationTime == rhs.reservationTime {
                        return lhs.remoteID > rhs.remoteID
                    }
                    return lhs.reservationTime > rhs.reservationTime
                }
                return lhs.reservationDate > rhs.reservationDate
            }
            candidates = Array(candidates.prefix(maxRecords))
        }

        return candidates
    }
}
