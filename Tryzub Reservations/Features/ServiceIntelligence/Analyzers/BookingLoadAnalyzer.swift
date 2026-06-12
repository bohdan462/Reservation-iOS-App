//
//  BookingLoadAnalyzer.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 4 (Booking Load Suggestions).
//
//  PURE + DETERMINISTIC. No network, no model. Groups a single day's KNOWN reservations
//  into time windows, compares the known guest count against planned reservable seats /
//  thresholds, and (when a window is too full) suggests the next better nearby time.
//
//  This never closes a slot, blocks a time, or mutates anything. It only describes load
//  and produces suggestions for staff to confirm later.
//

import Foundation

enum BookingLoadAnalyzer {

    struct Input {
        let date: String
        /// Reservations already filtered to `date` (hidden excluded by the caller).
        let reservations: [ReservationRecord]
        /// Service window in minutes-of-day, if known (used to bound alternate times).
        let openMinutes: Int?
        let closeMinutes: Int?
        /// Sum of active table seats, when a real table plan is available.
        let plannedReservableSeats: Int?
        /// True when `plannedReservableSeats` came from the backend floor layout
        /// (i.e. real table data). False when from local config or unavailable.
        var hasBackendLayout: Bool = false
        /// Minutes-of-day already blocked/closed — never suggested as alternates. Any
        /// blocked time inside a window disqualifies that window as an alternate.
        let blockedSlotMinutes: Set<Int>
        var thresholds: BookingLoadThresholds = .default
    }

    static func analyze(_ input: Input) -> BookingLoadReport {
        let hasTablePlan = (input.plannedReservableSeats ?? 0) > 0
        let thresholds = input.thresholds
        let window = max(5, thresholds.windowMinutes)

        // 1. Group known reservations into fixed windows.
        var grouped: [Int: [ReservationRecord]] = [:]
        for reservation in input.reservations where countsTowardLoad(reservation) {
            guard let minutes = minutesOfDay(from: reservation.reservationTime) else { continue }
            let bucket = (minutes / window) * window
            grouped[bucket, default: []].append(reservation)
        }

        guard !grouped.isEmpty else {
            return .empty(date: input.date, hasTablePlan: hasTablePlan, hasBackendLayout: input.hasBackendLayout, plannedReservableSeats: input.plannedReservableSeats)
        }

        // 2. Build a window summary for each bucket.
        let windows: [BookingLoadWindow] = grouped
            .map { bucket, items in makeWindow(start: bucket, items: items, input: input, thresholds: thresholds) }
            .sorted { $0.startMinutes < $1.startMinutes }

        let busyWindows = windows.filter { $0.isBusy }

        // 3. For each busy window, choose the next better nearby time.
        let suggestions: [BookingLoadSuggestion] = busyWindows.map { busy in
            let alternate = alternateWindow(after: busy, in: windows, input: input, thresholds: thresholds)
            return BookingLoadSuggestion(
                window: busy,
                alternateLabel: alternate?.label,
                alternateStartMinutes: alternate?.startMinutes,
                alternateSlotValue: alternate?.slotValue
            )
        }

        emitTraces(date: input.date, suggestions: suggestions, windows: windows)

        return BookingLoadReport(
            date: input.date,
            hasTablePlan: hasTablePlan,
            hasBackendLayout: input.hasBackendLayout,
            plannedReservableSeats: input.plannedReservableSeats,
            windows: windows,
            busyWindows: busyWindows,
            suggestions: suggestions
        )
    }

    // MARK: - Window construction

    private static func makeWindow(
        start: Int,
        items: [ReservationRecord],
        input: Input,
        thresholds: BookingLoadThresholds
    ) -> BookingLoadWindow {
        let reservationCount = items.count
        let knownGuestCount = items.reduce(0) { $0 + max(0, $1.partySize) }
        let largePartyCount = items.filter { $0.partySize >= thresholds.largePartyThreshold }.count
        let assignedTableCount = items.filter { $0.hasTableAssignment }.count
        let noTableCount = reservationCount - assignedTableCount

        var reasons: [String] = []
        if reservationCount >= thresholds.busyReservationCount {
            reasons.append("\(reservationCount) reservations at the same time")
        }
        if knownGuestCount >= thresholds.busyKnownGuestCount {
            reasons.append("\(knownGuestCount) known guests at the same time")
        }
        var seatTriggered = false
        if let seats = input.plannedReservableSeats, seats > 0 {
            let ratio = Double(knownGuestCount) / Double(seats)
            if ratio >= thresholds.seatUtilizationBusyRatio {
                seatTriggered = true
                reasons.append("known guests fill most of the tables")
            }
        }
        if largePartyCount >= thresholds.multipleLargePartyCount {
            reasons.append("\(largePartyCount) large parties close together")
        }

        let severity: BookingLoadSeverity
        if reasons.isEmpty {
            severity = .normal
        } else if knownGuestCount >= thresholds.busyKnownGuestCount || seatTriggered {
            severity = .veryBusy
        } else {
            severity = .busy
        }

        return BookingLoadWindow(
            startMinutes: start,
            label: clockLabel(fromMinutes: start),
            slotValue: slotValue(fromMinutes: start),
            reservationCount: reservationCount,
            knownGuestCount: knownGuestCount,
            largePartyCount: largePartyCount,
            noTableCount: noTableCount,
            assignedTableCount: assignedTableCount,
            severity: severity,
            busyReasons: reasons
        )
    }

    // MARK: - Alternate time selection

    /// The next better nearby time after a busy window:
    /// - within service bounds,
    /// - not itself busy,
    /// - not blocked/closed,
    /// - and the quietest (fewest known guests) among the candidates.
    private static func alternateWindow(
        after busy: BookingLoadWindow,
        in windows: [BookingLoadWindow],
        input: Input,
        thresholds: BookingLoadThresholds
    ) -> AlternateCandidate? {
        let step = max(5, thresholds.windowMinutes)
        let loadByStart = Dictionary(uniqueKeysWithValues: windows.map { ($0.startMinutes, $0) })

        // Candidate starts: the existing non-busy windows after the busy one, plus
        // empty in-service windows after it (an empty window is the best alternate).
        var candidateStarts: [Int] = []

        // Empty windows up to close (or up to last known window + a few steps).
        let upperBound = input.closeMinutes ?? (windows.map(\.startMinutes).max().map { $0 + step * 4 } ?? busy.startMinutes)
        var cursor = busy.startMinutes + step
        while cursor <= upperBound {
            candidateStarts.append(cursor)
            cursor += step
        }

        var best: AlternateCandidate?
        for start in candidateStarts {
            if let open = input.openMinutes, start < open { continue }
            if let close = input.closeMinutes, start >= close { continue }
            if input.blockedSlotMinutes.contains(where: { $0 >= start && $0 < start + step }) { continue }

            let existing = loadByStart[start]
            if let existing, existing.isBusy { continue }

            let guests = existing?.knownGuestCount ?? 0
            // Skip windows that already carry a high known guest count.
            if guests >= thresholds.busyKnownGuestCount { continue }

            let candidate = AlternateCandidate(
                startMinutes: start,
                label: clockLabel(fromMinutes: start),
                slotValue: slotValue(fromMinutes: start),
                knownGuestCount: guests
            )
            if best == nil || candidate.knownGuestCount < best!.knownGuestCount {
                best = candidate
            }
            // An empty, immediately-following window is already ideal — stop early.
            if guests == 0 { break }
        }
        return best
    }

    private struct AlternateCandidate {
        let startMinutes: Int
        let label: String
        let slotValue: String
        let knownGuestCount: Int
    }

    // MARK: - Filtering

    /// Known reservations that occupy a future/current seat. Cancelled, no-show, and
    /// already-completed reservations do not count toward booking load.
    private static func countsTowardLoad(_ reservation: ReservationRecord) -> Bool {
        switch reservation.statusValue {
        case .new, .needsReview, .confirmed, .seated:
            return true
        case .completed, .cancelled, .noShow:
            return false
        }
    }

    // MARK: - Time helpers

    /// Parses "HH:mm" / "HH:mm:ss" into minutes-of-day. Returns nil for malformed input.
    static func minutesOfDay(from rawTime: String) -> Int? {
        let trimmed = rawTime.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    /// "HH:mm" for backend/blocked-slot targeting.
    static func slotValue(fromMinutes minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// Staff-language clock label, e.g. "6:00 PM" / "6:30 PM".
    static func clockLabel(fromMinutes minutes: Int) -> String {
        let hour24 = (minutes / 60) % 24
        let minute = minutes % 60
        let period = hour24 < 12 ? "AM" : "PM"
        var hour12 = hour24 % 12
        if hour12 == 0 { hour12 = 12 }
        return String(format: "%d:%02d %@", hour12, minute, period)
    }

    // MARK: - Traces

    private static func emitTraces(
        date: String,
        suggestions: [BookingLoadSuggestion],
        windows: [BookingLoadWindow]
    ) {
        guard BookingLoadTrace.isEnabled else { return }
        let byStart = Dictionary(uniqueKeysWithValues: windows.map { ($0.startMinutes, $0) })
        for suggestion in suggestions {
            let w = suggestion.window
            BookingLoadTrace.busyWindow(
                date: date,
                slot: w.slotValue,
                reservations: w.reservationCount,
                guests: w.knownGuestCount,
                threshold: w.severity.traceToken,
                suggestedAction: "close_slot",
                alternate: suggestion.alternateSlotValue
            )
            if let altSlot = suggestion.alternateSlotValue {
                let alt = suggestion.alternateStartMinutes.flatMap { byStart[$0] }
                BookingLoadTrace.alternateWindow(
                    date: date,
                    slot: altSlot,
                    reservations: alt?.reservationCount ?? 0,
                    guests: alt?.knownGuestCount ?? 0
                )
            }
        }
    }
}
