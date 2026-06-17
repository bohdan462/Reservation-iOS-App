//
//  ServiceIntelligenceEngine.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 1 foundation.
//
//  Deterministic assembler of a `ServiceBriefing`. It groups staff actions into
//  Check now / Coming up / Review later / After close, and produces an honest
//  today-summary recap. Crucially, it respects `ServiceMode`: live actions are only
//  surfaced `duringService`; after close it produces cleanup or a wrapped-up recap.
//  The model is never consulted here — this is the always-available floor.
//

import Foundation

enum ServiceIntelligenceEngine {

    struct Input {
        let mode: ServiceMode
        let status: ServiceDayStatusSummary
        let totalGuests: Int
        let upcomingCount: Int
        /// Simple staff-language busiest-time label, e.g. "6 PM". Optional.
        let busiestTimeLabel: String?
        /// Live actions already mapped from the Host engine (used only during service).
        let liveActions: [StaffActionIntent]
        let selectedDateLabel: String?

        // MARK: Backend enrichment (all optional — nil = cache-only render)

        /// Guest summaries from backend for the service day. Used to upgrade `source`.
        let backendGuestSummaries: [GuestIntelligenceSummaryDTO]
        /// Business intelligence from backend. Provides richer busiest-time data in recaps.
        let backendBusinessSummary: BusinessIntelligenceSummaryDTO?
        /// Freshness metadata for source labelling and trace emission.
        let freshness: ServiceIntelligenceFreshness?

        init(
            mode: ServiceMode,
            status: ServiceDayStatusSummary,
            totalGuests: Int,
            upcomingCount: Int,
            busiestTimeLabel: String?,
            liveActions: [StaffActionIntent],
            selectedDateLabel: String?,
            backendGuestSummaries: [GuestIntelligenceSummaryDTO] = [],
            backendBusinessSummary: BusinessIntelligenceSummaryDTO? = nil,
            freshness: ServiceIntelligenceFreshness? = nil
        ) {
            self.mode = mode
            self.status = status
            self.totalGuests = totalGuests
            self.upcomingCount = upcomingCount
            self.busiestTimeLabel = busiestTimeLabel
            self.liveActions = liveActions
            self.selectedDateLabel = selectedDateLabel
            self.backendGuestSummaries = backendGuestSummaries
            self.backendBusinessSummary = backendBusinessSummary
            self.freshness = freshness
        }

        /// Source resolved from available backend data.
        var resolvedSource: BriefingSource {
            freshness?.briefingSource ?? .deterministic
        }
    }

    static func makeBriefing(_ input: Input) -> ServiceBriefing {
        let briefing: ServiceBriefing
        switch input.mode {
        case .duringService, .beforeService:
            briefing = liveBriefing(input)
        case .afterCloseNeedsCleanup:
            briefing = cleanupBriefing(input)
        case .afterCloseFinished, .pastRecap:
            briefing = recapBriefing(input)
        case .futurePlanning:
            briefing = planningBriefing(input)
        }

        let cleanupNeeded = input.status.cleanupCount(for: input.mode)
        ServiceIntelligenceTrace.serviceMode(
            mode: input.mode,
            pendingArrivals: input.status.pendingArrivals,
            activeService: input.status.activeService,
            cleanupNeeded: cleanupNeeded
        )
        ServiceIntelligenceTrace.briefing(
            mode: input.mode,
            reservations: input.status.totalReservations,
            pendingArrivals: input.status.pendingArrivals,
            activeService: input.status.activeService,
            seated: input.status.seatedCount,
            cleanupNeeded: cleanupNeeded,
            actions: briefing.totalActionCount
        )
        return briefing
    }

    // MARK: - Live (before / during service)

    private static func liveBriefing(_ input: Input) -> ServiceBriefing {
        let checkNow = input.liveActions.filter { $0.timing == .now }
            .sorted { $0.priority > $1.priority }
        let comingUp = input.liveActions.filter { $0.timing == .comingUp }
            .sorted { $0.priority > $1.priority }
        let reviewLater = input.liveActions.filter { $0.timing == .later || $0.timing == .anytime }
            .sorted { $0.priority > $1.priority }

        let headline: String
        let summary: String
        if input.mode == .beforeService {
            if input.upcomingCount > 0 {
                let firstPart = "Service starts"
                let guestPart = input.totalGuests > 0 ? " and \(input.totalGuests) \(guestWord(input.totalGuests))" : ""
                headline = "\(firstPart) with \(input.upcomingCount) \(reservationWord(input.upcomingCount))\(guestPart)."
            } else {
                headline = "Service is quiet. No reservations are active for this date."
            }
            summary = comingUp.isEmpty ? "" : "Get tables and notes ready before guests arrive."
        } else if checkNow.isEmpty && comingUp.isEmpty {
            headline = "Service is running. Nothing needs a check right now."
            summary = ""
        } else if !checkNow.isEmpty {
            headline = "\(checkNow.count) \(reservationWord(checkNow.count)) need a check."
            summary = checkNow.prefix(2).map(\.title).joined(separator: " ")
        } else {
            headline = "\(comingUp.count) \(reservationWord(comingUp.count)) coming up."
            summary = ""
        }

        return ServiceBriefing(
            mode: input.mode,
            headline: headline,
            summary: summary,
            checkNow: checkNow,
            comingUp: comingUp,
            reviewLater: reviewLater,
            afterClose: [],
            todaySummary: [],
            unresolvedCount: checkNow.count,
            source: input.resolvedSource
        )
    }

    // MARK: - After close (cleanup needed)

    private static func cleanupBriefing(_ input: Input) -> ServiceBriefing {
        var afterClose: [StaffActionIntent] = []
        if input.status.activeOpenWork > 0 {
            afterClose.append(
                StaffActionIntent(
                    id: "svc-cleanup-status",
                    type: .checkReservationStatus,
                    reservationID: nil,
                    title: "\(input.status.activeOpenWork) \(reservationWord(input.status.activeOpenWork)) need a status update.",
                    detail: "Check if they were seated, completed, or did not show.",
                    priority: .high,
                    timing: .afterClose
                )
            )
        }
        if input.status.seatedCount > 0 {
            afterClose.append(
                StaffActionIntent(
                    id: "svc-cleanup-seated",
                    type: .markComplete,
                    reservationID: nil,
                    title: "\(input.status.seatedCount) \(reservationWord(input.status.seatedCount)) still marked seated.",
                    detail: "Mark complete if the table has turned.",
                    priority: .high,
                    timing: .afterClose
                )
            )
        }

        return ServiceBriefing(
            mode: input.mode,
            headline: "Service is wrapped, but \(input.status.afterCloseCleanupCount) \(reservationWord(input.status.afterCloseCleanupCount)) still need a final status.",
            summary: "Check if they were seated, completed, or did not show.",
            checkNow: [],
            comingUp: [],
            reviewLater: [],
            afterClose: afterClose,
            todaySummary: recapLines(input, finished: false),
            unresolvedCount: input.status.afterCloseCleanupCount,
            source: input.resolvedSource
        )
    }

    // MARK: - Recap (finished / past)

    private static func recapBriefing(_ input: Input) -> ServiceBriefing {
        ServiceBriefing(
            mode: input.mode,
            headline: recapHeadline(input),
            summary: recapSummary(input),
            checkNow: [],
            comingUp: [],
            reviewLater: [],
            afterClose: [],
            todaySummary: recapLines(input, finished: true),
            unresolvedCount: 0,
            source: input.resolvedSource
        )
    }

    // MARK: - Future planning

    private static func planningBriefing(_ input: Input) -> ServiceBriefing {
        let total = input.status.totalReservations
        let headline = total > 0
            ? "Planning: \(total) \(reservationWord(total)) booked\(input.selectedDateLabel.map { " for \($0)" } ?? "")."
            : "Planning\(input.selectedDateLabel.map { " for \($0)" } ?? "")."
        // Only surface prep/verification actions for upcoming dates — do not push table pre-assignment
        // for every unassigned reservation. Table assignment is optional before service.
        let comingUp = input.liveActions.filter { $0.type == .prepareSetup || $0.type == .verifyGuestCount }
        let summary: String
        if comingUp.isEmpty {
            summary = total > 0 ? "Check large parties and guest notes before service." : ""
        } else {
            summary = "Check large parties and guest notes before service."
        }
        return ServiceBriefing(
            mode: input.mode,
            headline: headline,
            summary: summary,
            checkNow: [],
            comingUp: comingUp,
            reviewLater: [],
            afterClose: [],
            todaySummary: [],
            unresolvedCount: 0,
            source: input.resolvedSource
        )
    }

    // MARK: - Recap line builder

    private static func recapLines(_ input: Input, finished: Bool) -> [String] {
        var lines: [String] = []
        let s = input.status

        // Prefer backend business peak-window label over local slot analysis when available.
        let backendPeak = input.backendBusinessSummary
            .flatMap { BusinessIntelligenceFormatting.peakWindowLabel(summary: $0) }
        let busiestLabel = backendPeak ?? input.busiestTimeLabel
        if let busiest = busiestLabel, !busiest.isEmpty {
            lines.append("Busiest time was around \(busiest).")
        }

        if s.cancelledCount > 0 {
            lines.append("\(s.cancelledCount) \(reservationWord(s.cancelledCount)) \(s.cancelledCount == 1 ? "was" : "were") canceled.")
        }
        if s.noShowCount > 0 {
            lines.append("\(s.noShowCount) \(s.noShowCount == 1 ? "guest was a no-show" : "guests were no-shows").")
        }
        return lines
    }

    private static func recapHeadline(_ input: Input) -> String {
        let total = input.status.totalReservations
        if total == 0 {
            return input.mode == .pastRecap
                ? "Service was quiet. No reservations were active for this date."
                : "Service is quiet. No reservations are active for this date."
        }
        let guestLine = input.totalGuests > 0 ? " and \(input.totalGuests) \(guestWord(input.totalGuests))" : ""
        return "Service is wrapped. \(total) \(reservationWord(total))\(guestLine) \(total == 1 ? "was" : "were") on the book."
    }

    private static func recapSummary(_ input: Input) -> String {
        let s = input.status
        if s.activeService > 0 {
            return "\(s.activeService) \(reservationWord(s.activeService)) still \(s.activeService == 1 ? "has" : "have") active guests."
        }
        if s.totalReservations == 0 {
            return ""
        }
        var parts: [String] = []
        if s.completedCount > 0 {
            parts.append("\(s.completedCount) completed")
        }
        if s.noShowCount > 0 {
            parts.append("\(s.noShowCount) no-show")
        }
        if s.cancelledCount > 0 {
            parts.append("\(s.cancelledCount) cancelled")
        }
        if parts.isEmpty {
            return "No active guests remain."
        }
        return "\(parts.joined(separator: " · ")). No active guests remain."
    }

    private static func reservationWord(_ count: Int) -> String {
        count == 1 ? "reservation" : "reservations"
    }

    private static func guestWord(_ count: Int) -> String {
        count == 1 ? "guest" : "guests"
    }
}
