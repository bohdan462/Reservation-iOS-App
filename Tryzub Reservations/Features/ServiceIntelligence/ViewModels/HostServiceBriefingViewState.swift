//
//  HostServiceBriefingViewState.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 2.
//
//  Cached-only ViewState for the Host Board Service Briefing card. The builder
//  reads ONLY already-in-memory data (selected date, ticking now, day reservations,
//  the deterministic HostDecisionSnapshot, and cached open/close times). It never
//  triggers a network request. It is measured and traced so we can prove on device
//  that the new layer added no server dependency.
//

import Foundation

struct HostServiceBriefingViewState: Equatable {
    let mode: ServiceMode
    let headline: String
    let summary: String
    let primaryActions: [StaffActionIntent]
    let secondaryActions: [StaffActionIntent]
    let todaySummary: [String]
    let unresolvedCount: Int
    let source: BriefingSource
    let isLoadingModelText: Bool

    /// Label for the primary action group, in simple staff language.
    var primaryGroupTitle: String? {
        guard !primaryActions.isEmpty else { return nil }
        switch mode {
        case .afterCloseNeedsCleanup:
            return "Cleanup needed"
        case .duringService, .beforeService:
            return "Check now"
        case .futurePlanning:
            return "Plan ahead"
        case .afterCloseFinished, .pastRecap:
            return nil
        }
    }

    var secondaryGroupTitle: String? {
        guard !secondaryActions.isEmpty else { return nil }
        return "Coming up"
    }

    /// Whether the summary line adds new information beyond headline + first action.
    var showsSummary: Bool {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed == headline { return false }
        if primaryActions.contains(where: { $0.title == trimmed }) { return false }
        return true
    }
}

enum HostServiceBriefingViewStateBuilder {

    struct Input {
        let now: Date
        let selectedDate: Date
        let reservations: [ReservationRecord]
        let snapshot: HostDecisionSnapshot
        let openTime: Date?
        let closeTime: Date?
        var calendar: Calendar = .current
        var selectedDateLabel: String?
    }

    /// Pure, cached-only build. Emits performance + no-network traces.
    static func build(_ input: Input) -> HostServiceBriefingViewState {
        let start = ContinuousClock.now

        let statuses = input.reservations.map { $0.statusValue }
        let status = ServiceModeResolver.summarize(statuses: statuses)

        let modeResult = ServiceModeResolver.resolve(
            ServiceModeResolver.Input(
                now: input.now,
                selectedDate: input.selectedDate,
                openTime: input.openTime,
                closeTime: input.closeTime,
                status: status,
                calendar: input.calendar
            )
        )

        // Guests = expected/served guests (exclude cancelled + no-show party sizes).
        let totalGuests = input.reservations.reduce(into: 0) { sum, reservation in
            switch reservation.statusValue {
            case .cancelled, .noShow:
                break
            case .new, .needsReview, .confirmed, .seated, .completed:
                sum += max(0, reservation.partySize)
            }
        }

        let upcomingCount = input.reservations.filter {
            switch $0.statusValue {
            case .new, .needsReview, .confirmed: return true
            default: return false
            }
        }.count

        // For future-date planning, snapshot actions belong to a different date's evaluation
        // and must not appear in the planning card. Only today/live service uses the snapshot.
        let snapshotActions = modeResult.mode == .futurePlanning ? [] : input.snapshot.suggestedActions
        let liveActions = HostActionMapper.map(snapshotActions)
        let busiestLabel = busiestTimeLabel(from: input.snapshot.slotPressures)

        let briefing = ServiceIntelligenceEngine.makeBriefing(
            ServiceIntelligenceEngine.Input(
                mode: modeResult.mode,
                status: status,
                totalGuests: totalGuests,
                upcomingCount: upcomingCount,
                busiestTimeLabel: busiestLabel,
                liveActions: liveActions,
                selectedDateLabel: input.selectedDateLabel
            )
        )

        let primary = briefing.checkNow + briefing.afterClose
        let secondary = briefing.comingUp + briefing.reviewLater
        let missingTables = input.reservations.filter { reservation in
            switch reservation.statusValue {
            case .new, .needsReview, .confirmed:
                return !reservation.hasTableAssignment
            default:
                return false
            }
        }.count
        let displayHeadline = headline(
            briefing: briefing,
            input: input,
            status: status,
            totalGuests: totalGuests
        )
        let displaySummary = summary(
            briefing: briefing,
            mode: modeResult.mode,
            missingTables: missingTables
        )

        let durationMs = Int((start.duration(to: .now)).pressureTraceTimeInterval * 1000)
        ServiceIntelligenceTrace.evaluate(
            source: "cached",
            selectedDate: input.selectedDate.reservationDateString(),
            mode: modeResult.mode,
            reservations: status.totalReservations,
            actions: briefing.totalActionCount,
            durationMs: durationMs
        )

        return HostServiceBriefingViewState(
            mode: modeResult.mode,
            headline: displayHeadline,
            summary: displaySummary,
            primaryActions: primary,
            secondaryActions: secondary,
            todaySummary: briefing.todaySummary,
            unresolvedCount: briefing.unresolvedCount,
            source: briefing.source,
            isLoadingModelText: false
        )
    }

    /// Picks the busiest slot deterministically and renders it as simple staff time.
    static func busiestTimeLabel(from slotPressures: [HostSlotPressure]) -> String? {
        guard let busiest = slotPressures.max(by: { lhs, rhs in
            if lhs.guestCount != rhs.guestCount { return lhs.guestCount < rhs.guestCount }
            return lhs.reservationCount < rhs.reservationCount
        }), busiest.guestCount > 0 || busiest.reservationCount > 0 else {
            return nil
        }
        return clockHourLabel(from: busiest.slotTime)
    }

    private static func clockHourLabel(from slotTime: String) -> String? {
        let trimmed = slotTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let hourPart = trimmed.split(separator: ":").first.map(String.init) ?? trimmed
        guard let hour = Int(hourPart) else { return nil }
        switch hour {
        case 0: return "12 AM"
        case 12: return "12 PM"
        case 13...23: return "\(hour - 12) PM"
        case 1...11: return "\(hour) AM"
        default: return nil
        }
    }

    private static func headline(
        briefing: ServiceBriefing,
        input: Input,
        status: ServiceDayStatusSummary,
        totalGuests: Int
    ) -> String {
        guard briefing.mode == .beforeService, status.activeOpenWork > 0 else {
            return briefing.headline
        }
        let startText = input.openTime.map { ReservationFormatters.shortTime.string(from: $0) }
        let serviceStart = startText.map { "Service starts at \($0)" } ?? "Service starts"
        let guestText = totalGuests > 0 ? " and \(totalGuests) \(totalGuests == 1 ? "guest" : "guests")" : ""
        return "\(serviceStart) with \(status.activeOpenWork) \(status.activeOpenWork == 1 ? "reservation" : "reservations")\(guestText)."
    }

    private static func summary(
        briefing: ServiceBriefing,
        mode: ServiceMode,
        missingTables: Int
    ) -> String {
        guard mode == .beforeService, missingTables > 0 else {
            return briefing.summary
        }
        return "\(missingTables) \(missingTables == 1 ? "reservation still needs" : "reservations still need") tables."
    }
}
