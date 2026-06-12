//
//  BookingLoadModels.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 4 (Booking Load Suggestions).
//
//  Deterministic, decision-support output describing when too many KNOWN reservations
//  are scheduled around the same time. This is NOT capacity control and NOT POS: it
//  never closes a booking time. It only surfaces a suggestion for staff to confirm.
//
//  Walk-ins are never counted. All math is "known reservations only".
//

import Foundation

/// Configurable thresholds for what counts as a busy booking window. Constants for now;
/// can later be sourced from settings. Tuned conservatively so a quiet night stays quiet.
struct BookingLoadThresholds: Equatable {
    /// Window width that reservations are grouped into.
    var windowMinutes: Int = 30
    /// 4+ known reservations in one window is busy.
    var busyReservationCount: Int = 4
    /// 18+ known guests in one window is busy.
    var busyKnownGuestCount: Int = 18
    /// Known guests using 75% of planned reservable seats is busy (the "70–80%" rule).
    var seatUtilizationBusyRatio: Double = 0.75
    /// Two or more large parties in one window is busy.
    var multipleLargePartyCount: Int = 2
    /// Party size that counts as a "large party".
    var largePartyThreshold: Int = 7

    static let `default` = BookingLoadThresholds()
}

enum BookingLoadSeverity: String, Codable, Equatable {
    case normal
    case busy
    case veryBusy

    var traceToken: String {
        switch self {
        case .normal: return "normal"
        case .busy: return "high"
        case .veryBusy: return "high"
        }
    }
}

/// One grouped time window (e.g. the 30 minutes starting 6:00 PM) with known-only load.
struct BookingLoadWindow: Equatable, Identifiable {
    let startMinutes: Int          // minutes-of-day (e.g. 18:00 -> 1080)
    let label: String              // staff language, e.g. "6:00 PM"
    let slotValue: String          // "HH:mm" for backend/blocked-slot targeting
    let reservationCount: Int
    let knownGuestCount: Int
    let largePartyCount: Int
    let noTableCount: Int
    let assignedTableCount: Int
    let severity: BookingLoadSeverity
    /// Human-readable reasons this window tripped a threshold (busy windows only).
    let busyReasons: [String]

    var id: Int { startMinutes }
    var isBusy: Bool { severity != .normal }
}

/// A busy window plus the next better nearby time, if one exists.
struct BookingLoadSuggestion: Equatable, Identifiable {
    let window: BookingLoadWindow
    let alternateLabel: String?
    let alternateStartMinutes: Int?
    let alternateSlotValue: String?

    var id: Int { window.startMinutes }
    var hasAlternate: Bool { alternateLabel != nil }
}

/// Whole-day deterministic booking-load result.
struct BookingLoadReport: Equatable {
    let date: String
    /// True when we had real table/seat capacity to compare against (backend or local).
    let hasTablePlan: Bool
    /// True when capacity came from the canonical backend floor layout.
    let hasBackendLayout: Bool
    /// Planned reservable seats used as the capacity denominator, when available.
    let plannedReservableSeats: Int?
    let windows: [BookingLoadWindow]
    let busyWindows: [BookingLoadWindow]
    let suggestions: [BookingLoadSuggestion]

    var hasSuggestions: Bool { !suggestions.isEmpty }

    /// One-line capacity context shown below booking suggestions.
    /// Tells staff exactly what data the load estimate is based on.
    var knownOnlyNote: String {
        if let seats = plannedReservableSeats {
            let source = hasBackendLayout ? "backend tables" : "local config"
            return "\(seats) seats (\(source)) — known reservations only, walk-ins not counted."
        }
        return "Known reservations only — walk-ins not counted. No table plan configured."
    }

    /// Short capacity label for inline display (e.g. next to a window label).
    var capacitySourceLabel: String? {
        guard let seats = plannedReservableSeats else { return nil }
        return hasBackendLayout ? "\(seats) seats" : "\(seats) seats (local)"
    }

    static func empty(date: String, hasTablePlan: Bool, hasBackendLayout: Bool = false, plannedReservableSeats: Int?) -> BookingLoadReport {
        BookingLoadReport(
            date: date,
            hasTablePlan: hasTablePlan,
            hasBackendLayout: hasBackendLayout,
            plannedReservableSeats: plannedReservableSeats,
            windows: [],
            busyWindows: [],
            suggestions: []
        )
    }
}
