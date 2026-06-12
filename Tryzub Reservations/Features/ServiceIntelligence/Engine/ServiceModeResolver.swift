//
//  ServiceModeResolver.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 1 foundation.
//
//  Pure, deterministic, unit-testable resolution of the current ServiceMode.
//  No model, no I/O, no SwiftData — just time + business hours + a status
//  histogram. This is the single source of truth for "what part of the day is it",
//  and it is what stops live operational facts from leaking into an after-close
//  surface where they are useless.
//

import Foundation

/// Day-level reservation status histogram, derived from `ReservationStatus`.
struct ServiceDayStatusSummary: Equatable {
    /// Reservations still in expected/unresolved work states (.new/.needsReview/.confirmed).
    let activeOpenWork: Int
    /// Reservations currently marked `.seated` (never marked complete).
    let seatedCount: Int
    let completedCount: Int
    let cancelledCount: Int
    let noShowCount: Int

    var totalReservations: Int {
        activeOpenWork + seatedCount + completedCount + cancelledCount + noShowCount
    }

    /// Items that, after close, still need a staff status update.
    var cleanupCount: Int {
        activeOpenWork + seatedCount
    }

    static let zero = ServiceDayStatusSummary(
        activeOpenWork: 0, seatedCount: 0, completedCount: 0, cancelledCount: 0, noShowCount: 0
    )
}

enum ServiceModeResolver {

    struct Input {
        let now: Date
        let selectedDate: Date
        /// Selected-day open time resolved into an absolute `Date` (nil if unknown/closed).
        let openTime: Date?
        /// Selected-day close time resolved into an absolute `Date` (nil if unknown).
        let closeTime: Date?
        let status: ServiceDayStatusSummary
        var calendar: Calendar = .current
    }

    struct Result: Equatable {
        let mode: ServiceMode
        let cleanupItemCount: Int
    }

    static func resolve(_ input: Input) -> Result {
        let selectedDay = input.calendar.startOfDay(for: input.selectedDate)
        let today = input.calendar.startOfDay(for: input.now)

        if selectedDay > today {
            return Result(mode: .futurePlanning, cleanupItemCount: 0)
        }
        if selectedDay < today {
            return Result(mode: .pastRecap, cleanupItemCount: 0)
        }

        // Selected day is today.
        let cleanup = input.status.cleanupCount

        let afterCloseRegion = input.closeTime.map { input.now > $0 } ?? false
        if afterCloseRegion {
            return Result(
                mode: cleanup > 0 ? .afterCloseNeedsCleanup : .afterCloseFinished,
                cleanupItemCount: cleanup
            )
        }

        // Before open AND no service activity yet → before service.
        let beforeOpen = input.openTime.map { input.now < $0 } ?? false
        let noActivityYet = input.status.seatedCount == 0 && input.status.completedCount == 0
        if beforeOpen && noActivityYet {
            return Result(mode: .beforeService, cleanupItemCount: 0)
        }

        return Result(mode: .duringService, cleanupItemCount: cleanup)
    }

    /// Builds a status histogram from raw `ReservationStatus` values for the day.
    static func summarize(statuses: [ReservationStatus]) -> ServiceDayStatusSummary {
        var open = 0, seated = 0, completed = 0, cancelled = 0, noShow = 0
        for status in statuses {
            switch status {
            case .new, .needsReview, .confirmed:
                open += 1
            case .seated:
                seated += 1
            case .completed:
                completed += 1
            case .cancelled:
                cancelled += 1
            case .noShow:
                noShow += 1
            }
        }
        return ServiceDayStatusSummary(
            activeOpenWork: open,
            seatedCount: seated,
            completedCount: completed,
            cancelledCount: cancelled,
            noShowCount: noShow
        )
    }
}
