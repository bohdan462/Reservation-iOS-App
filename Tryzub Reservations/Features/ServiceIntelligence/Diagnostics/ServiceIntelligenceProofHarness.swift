//
//  ServiceIntelligenceProofHarness.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 1 foundation.
//
//  DEBUG-only deterministic self-check for ServiceModeResolver + engine. No model,
//  no I/O. Proves the after-close bug fix (no live facts when nothing is active) and
//  the core mode transitions on device/sim via [SERVICE_INTELLIGENCE_TEST] logs.
//  This is the stand-in for unit tests until a formal XCTest target is added.
//

import Foundation

#if DEBUG
enum ServiceIntelligenceProofHarness {

    nonisolated(unsafe) private static var hasRun = false

    static func runOnceIfNeeded() {
        guard !hasRun else { return }
        hasRun = true
        run()
    }

    static func run() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        let today = cal.date(from: DateComponents(year: 2026, month: 6, day: 12))!
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(byAdding: DateComponents(hour: hour, minute: minute), to: today)!
        }
        let open = at(16)   // 4 PM
        let close = at(22)  // 10 PM

        // Scenario A — after close, nothing active → afterCloseFinished, no live facts.
        expect(
            scenario: "A_after_close_finished",
            input: .init(
                now: at(23),
                selectedDate: today,
                openTime: open,
                closeTime: close,
                status: .init(activeOpenWork: 0, seatedCount: 0, completedCount: 8, cancelledCount: 1, noShowCount: 0),
                calendar: cal
            ),
            expectedMode: .afterCloseFinished
        )

        // Scenario B — after close, incomplete statuses → afterCloseNeedsCleanup.
        expect(
            scenario: "B_after_close_cleanup",
            input: .init(
                now: at(23),
                selectedDate: today,
                openTime: open,
                closeTime: close,
                status: .init(activeOpenWork: 1, seatedCount: 1, completedCount: 6, cancelledCount: 0, noShowCount: 0),
                calendar: cal
            ),
            expectedMode: .afterCloseNeedsCleanup
        )

        // Scenario C — during service, active work → duringService.
        expect(
            scenario: "C_during_service",
            input: .init(
                now: at(18, 30),
                selectedDate: today,
                openTime: open,
                closeTime: close,
                status: .init(activeOpenWork: 3, seatedCount: 2, completedCount: 1, cancelledCount: 0, noShowCount: 0),
                calendar: cal
            ),
            expectedMode: .duringService
        )

        // Before service — before open, nothing seated.
        expect(
            scenario: "before_service",
            input: .init(
                now: at(14),
                selectedDate: today,
                openTime: open,
                closeTime: close,
                status: .init(activeOpenWork: 5, seatedCount: 0, completedCount: 0, cancelledCount: 0, noShowCount: 0),
                calendar: cal
            ),
            expectedMode: .beforeService
        )

        // Future planning — selected day after today.
        expect(
            scenario: "future_planning",
            input: .init(
                now: at(18),
                selectedDate: cal.date(byAdding: .day, value: 3, to: today)!,
                openTime: nil,
                closeTime: nil,
                status: .init(activeOpenWork: 2, seatedCount: 0, completedCount: 0, cancelledCount: 0, noShowCount: 0),
                calendar: cal
            ),
            expectedMode: .futurePlanning
        )

        // Past recap — selected day before today.
        expect(
            scenario: "past_recap",
            input: .init(
                now: at(18),
                selectedDate: cal.date(byAdding: .day, value: -2, to: today)!,
                openTime: nil,
                closeTime: nil,
                status: .init(activeOpenWork: 0, seatedCount: 0, completedCount: 4, cancelledCount: 0, noShowCount: 0),
                calendar: cal
            ),
            expectedMode: .pastRecap
        )
    }

    private static func expect(
        scenario: String,
        input: ServiceModeResolver.Input,
        expectedMode: ServiceMode
    ) {
        let result = ServiceModeResolver.resolve(input)
        let ok = result.mode == expectedMode

        // Also assert the bug fix: a recap/after-close-finished briefing must carry NO live actions.
        let briefing = ServiceIntelligenceEngine.makeBriefing(
            .init(
                mode: result.mode,
                status: input.status,
                totalGuests: input.status.totalReservations * 3,
                upcomingCount: input.status.activeOpenWork,
                busiestTimeLabel: "6 PM",
                liveActions: [],
                selectedDateLabel: nil
            )
        )
        let noLiveLeak = result.mode.allowsLiveOperationalFacts || (briefing.checkNow.isEmpty && briefing.comingUp.isEmpty)

        ServiceIntelligenceTrace.test(
            scenario: scenario,
            result: (ok && noLiveLeak) ? "pass" : "FAIL",
            detail: "mode=\(result.mode.traceLabel) expected=\(expectedMode.traceLabel) cleanup=\(result.cleanupItemCount) headline=\"\(briefing.headline)\""
        )
    }
}
#endif
