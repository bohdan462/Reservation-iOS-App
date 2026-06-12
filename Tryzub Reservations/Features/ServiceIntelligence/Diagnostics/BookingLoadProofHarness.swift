//
//  BookingLoadProofHarness.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 4 (Booking Load Suggestions).
//
//  DEBUG-only deterministic self-check for BookingLoadAnalyzer. No model, no I/O.
//  Emits [SERVICE_INTELLIGENCE_TEST] (pass/FAIL) plus the analyzer's own
//  [BOOKING_LOAD_TRACE] lines so the acceptance scenarios are verifiable on device/sim
//  without a live floor of reservations.
//

import Foundation

#if DEBUG
enum BookingLoadProofHarness {

    nonisolated(unsafe) private static var hasRun = false

    static func runOnceIfNeeded() {
        guard !hasRun else { return }
        hasRun = true
        run()
    }

    static func run() {
        let date = "2026-06-12"
        let open = 16 * 60   // 4 PM
        let close = 22 * 60  // 10 PM

        // Scenario A — 5 reservations around 6 PM, ~22 known guests → busy + alternate.
        let aReservations = [
            res(1, "18:00", 4), res(2, "18:05", 5), res(3, "18:10", 4),
            res(4, "18:15", 5), res(5, "18:20", 4)
        ] + [res(6, "18:45", 2)] // a quieter nearby window for the alternate
        let aReport = analyze(date: date, reservations: aReservations, open: open, close: close, seats: 60)
        let aBusy = aReport.busyWindows.contains { $0.slotValue == "18:00" }
        let aHasAlternate = aReport.suggestions.first { $0.window.slotValue == "18:00" }?.hasAlternate ?? false
        report("A_busy_18_with_alternate", pass: aBusy && aHasAlternate, detail: "busy=\(aReport.busyWindows.count) suggestions=\(aReport.suggestions.count)")

        // Scenario B — only 1–2 per window → nothing busy.
        let bReservations = [res(1, "17:00", 2), res(2, "18:00", 2), res(3, "19:00", 3), res(4, "20:00", 2)]
        let bReport = analyze(date: date, reservations: bReservations, open: open, close: close, seats: 60)
        report("B_quiet_no_suggestions", pass: !bReport.hasSuggestions, detail: "suggestions=\(bReport.suggestions.count)")

        // Scenario D — no table plan: still busy by counts, hasTablePlan=false.
        let dReport = analyze(date: date, reservations: aReservations, open: open, close: close, seats: nil)
        let dKnownOnly = dReport.knownOnlyNote.contains("Based on known reservations only")
        report("D_no_table_plan", pass: dReport.hasSuggestions && !dReport.hasTablePlan && dKnownOnly, detail: "hasTablePlan=\(dReport.hasTablePlan)")

        // Scenario (seat ratio) — 18+ guests across one window using 75% of seats.
        let seatReport = analyze(date: date, reservations: [res(1, "19:00", 6), res(2, "19:10", 6), res(3, "19:20", 6)], open: open, close: close, seats: 24)
        report("seat_ratio_busy", pass: seatReport.busyWindows.contains { $0.slotValue == "19:00" }, detail: "veryBusy=\(seatReport.busyWindows.first?.severity.rawValue ?? "-")")
    }

    // MARK: - Helpers

    private static func res(_ id: Int, _ time: String, _ party: Int) -> ReservationRecord {
        ReservationRecord(
            fixtureRemoteID: id,
            reservationDate: "2026-06-12",
            reservationTime: time,
            partySize: party,
            status: .confirmed
        )
    }

    private static func analyze(
        date: String,
        reservations: [ReservationRecord],
        open: Int,
        close: Int,
        seats: Int?
    ) -> BookingLoadReport {
        BookingLoadAnalyzer.analyze(
            BookingLoadAnalyzer.Input(
                date: date,
                reservations: reservations,
                openMinutes: open,
                closeMinutes: close,
                plannedReservableSeats: seats,
                blockedSlotMinutes: []
            )
        )
    }

    private static func report(_ scenario: String, pass: Bool, detail: String) {
        ServiceIntelligenceTrace.test(
            scenario: "booking_\(scenario)",
            result: pass ? "pass" : "FAIL",
            detail: detail
        )
    }
}
#endif
