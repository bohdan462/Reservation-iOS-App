//
//  BookingLoadSupport.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 4 (Booking Load Suggestions).
//
//  Small pure helpers to resolve BookingLoadAnalyzer inputs (seats, bounds, blocked
//  times) consistently from Host Board and the Global hub. No network.
//

import Foundation

enum BookingLoadSupport {

    /// Planned reservable seats, preferring the real backend floor-plan table inventory,
    /// then the local host table config. Returns nil when there is no table plan at all
    /// (the analyzer then falls back to reservation/guest counts only).
    static func plannedReservableSeats(floorTables: [RestaurantTableDTO], localCapacity: Int) -> Int? {
        let floorSeats = floorTables
            .filter { $0.isActive }
            .reduce(0) { $0 + max(0, $1.maxCapacity) }
        if floorSeats > 0 { return floorSeats }
        if localCapacity > 0 { return localCapacity }
        return nil
    }

    /// Resolves planned seats and `hasBackendLayout` from a typed `TableCapacitySummary`.
    /// Returns `(seats: Int?, isBackendLayout: Bool)`.
    /// - If the summary has backend data, returns `(summary.totalSeats, true)`.
    /// - Falls back to `localCapacity` (host table config) if no backend layout.
    static func plannedSeats(
        from summary: TableCapacitySummary,
        localCapacity: Int
    ) -> (seats: Int?, isBackendLayout: Bool) {
        if summary.hasBackendLayout && summary.totalSeats > 0 {
            return (summary.totalSeats, true)
        }
        if localCapacity > 0 {
            return (localCapacity, false)
        }
        return (nil, false)
    }

    static func minutesOfDay(from date: Date?, calendar: Calendar = .current) -> Int? {
        guard let date else { return nil }
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = comps.hour, let minute = comps.minute else { return nil }
        return hour * 60 + minute
    }

    static func blockedMinutes(from blockedSlots: [RestaurantBlockedSlotDTO]) -> Set<Int> {
        Set(blockedSlots.compactMap { BookingLoadAnalyzer.minutesOfDay(from: $0.slotTime) })
    }
}
