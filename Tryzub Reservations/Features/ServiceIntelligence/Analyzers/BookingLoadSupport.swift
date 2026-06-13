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

    /// Planned reservable seats from explicit floor source. Never silently substitutes
    /// local advisory capacity while backend floor is pending or unavailable.
    static func plannedReservableSeats(
        floorTables: [RestaurantTableDTO],
        source: HostFloorTableSource,
        localCapacity: Int
    ) -> Int? {
        switch source {
        case .backend:
            let floorSeats = floorTables
                .filter(\.isActive)
                .reduce(0) { $0 + max(0, $1.maxCapacity) }
            return floorSeats > 0 ? floorSeats : nil
        case .legacyFallback:
            return localCapacity > 0 ? localCapacity : nil
        case .pendingBackend, .notConfigured, .unavailable:
            return nil
        }
    }

    /// Resolves planned seats and backend-layout flag from a typed `TableCapacitySummary`.
    static func plannedSeats(
        from summary: TableCapacitySummary,
        localCapacity: Int
    ) -> (seats: Int?, isBackendLayout: Bool) {
        switch summary.source {
        case .backend:
            return (summary.totalSeats > 0 ? summary.totalSeats : nil, true)
        case .legacyFallback:
            let seats = summary.totalSeats > 0 ? summary.totalSeats : (localCapacity > 0 ? localCapacity : nil)
            return (seats, false)
        case .pendingBackend, .notConfigured, .unavailable:
            return (nil, false)
        }
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
