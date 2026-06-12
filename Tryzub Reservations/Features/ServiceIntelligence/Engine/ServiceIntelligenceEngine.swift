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

        ServiceIntelligenceTrace.serviceMode(mode: input.mode, cleanupNeeded: input.status.cleanupCount)
        ServiceIntelligenceTrace.briefing(
            mode: input.mode,
            reservations: input.status.totalReservations,
            active: input.status.activeOpenWork,
            seated: input.status.seatedCount,
            incomplete: input.status.cleanupCount,
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
            headline = input.upcomingCount > 0
                ? "Service hasn't started. \(input.upcomingCount) \(reservationWord(input.upcomingCount)) coming up."
                : "Service hasn't started yet."
            summary = comingUp.isEmpty ? "" : "Get setup and tables ready before guests arrive."
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
            headline: "Service is over, but \(input.status.cleanupCount) \(reservationWord(input.status.cleanupCount)) need a status update.",
            summary: "Check if they were seated or should be marked complete.",
            checkNow: [],
            comingUp: [],
            reviewLater: [],
            afterClose: afterClose,
            todaySummary: recapLines(input, finished: false),
            unresolvedCount: input.status.cleanupCount,
            source: input.resolvedSource
        )
    }

    // MARK: - Recap (finished / past)

    private static func recapBriefing(_ input: Input) -> ServiceBriefing {
        ServiceBriefing(
            mode: input.mode,
            headline: input.mode == .pastRecap ? "Recap" : "Service is wrapped.",
            summary: "Nothing is left to check.",
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
        let comingUp = input.liveActions.filter { $0.type == .assignTable || $0.type == .prepareSetup || $0.type == .verifyGuestCount }
        return ServiceBriefing(
            mode: input.mode,
            headline: headline,
            summary: comingUp.isEmpty ? "" : "Set tables and setup for the larger parties before service.",
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

        if s.totalReservations > 0 {
            lines.append("Today had \(s.totalReservations) \(reservationWord(s.totalReservations)) and \(input.totalGuests) \(guestWord(input.totalGuests)).")
        }

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
        if finished {
            lines.append("Nothing is left to check.")
        }
        return lines
    }

    private static func reservationWord(_ count: Int) -> String {
        count == 1 ? "reservation" : "reservations"
    }

    private static func guestWord(_ count: Int) -> String {
        count == 1 ? "guest" : "guests"
    }
}
