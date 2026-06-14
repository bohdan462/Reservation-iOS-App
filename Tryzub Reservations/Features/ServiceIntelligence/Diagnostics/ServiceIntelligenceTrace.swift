//
//  ServiceIntelligenceTrace.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 1 foundation.
//
//  DEBUG-only structured traces for the deterministic service-intelligence layer.
//  No raw guest contact data or raw private notes — counts, modes, and stable tokens.
//

import Foundation
import OSLog

enum ServiceIntelligenceTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "ServiceIntelligence"
    )

    static func briefing(
        mode: ServiceMode,
        reservations: Int,
        pendingArrivals: Int,
        activeService: Int,
        seated: Int,
        cleanupNeeded: Int,
        actions: Int
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[SERVICE_INTELLIGENCE_TRACE] mode=\(mode.traceLabel, privacy: .public) reservations=\(reservations, privacy: .public) pendingArrivals=\(pendingArrivals, privacy: .public) activeService=\(activeService, privacy: .public) seated=\(seated, privacy: .public) cleanupNeeded=\(cleanupNeeded, privacy: .public) actions=\(actions, privacy: .public)"
        )
    }

    static func serviceMode(
        mode: ServiceMode,
        pendingArrivals: Int,
        activeService: Int,
        cleanupNeeded: Int
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[HOST_SERVICE_MODE_TRACE] mode=\(mode.traceLabel, privacy: .public) afterClose=\(mode.isAfterClose ? "true" : "false", privacy: .public) pendingArrivals=\(pendingArrivals, privacy: .public) activeService=\(activeService, privacy: .public) cleanupNeeded=\(cleanupNeeded, privacy: .public)"
        )
    }

    static func action(type: StaffActionType, reservationID: String?, priority: ActionPriority, source: String) {
        guard isEnabled else { return }
        logger.debug(
            "[SERVICE_ACTION_TRACE] action=\(type.rawValue, privacy: .public) reservation=\(reservationID ?? "-", privacy: .public) priority=\(priority.rawValue, privacy: .public) source=\(source, privacy: .public)"
        )
    }

    static func alertRoute(signal: String, routedTo: String, reason: String) {
        guard isEnabled else { return }
        logger.debug(
            "[SERVICE_ALERT_ROUTE_TRACE] signal=\(signal, privacy: .public) routedTo=\(routedTo, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    /// Phase 2: proves the Host Board Service Briefing evaluated from cache only,
    /// with no new server dependency, plus the evaluation duration.
    static func evaluate(
        source: String,
        selectedDate: String,
        mode: ServiceMode,
        reservations: Int,
        actions: Int,
        durationMs: Int
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[SERVICE_INTELLIGENCE_TRACE] source=\(source, privacy: .public) selectedDate=\(selectedDate, privacy: .public) mode=\(mode.traceLabel, privacy: .public) reservations=\(reservations, privacy: .public) actions=\(actions, privacy: .public)"
        )
        logger.debug("[SERVICE_INTELLIGENCE_TRACE] no_network=true")
        logger.debug("[SERVICE_INTELLIGENCE_TRACE] phase=evaluate durationMs=\(durationMs, privacy: .public)")
    }

    /// Phase 2: emitted when the Host card renders the new deterministic briefing.
    static func hostCard(display: String, mode: ServiceMode) {
        guard isEnabled else { return }
        logger.debug(
            "[HOST_CARD_TRACE] display=\(display, privacy: .public) mode=\(mode.traceLabel, privacy: .public)"
        )
    }

    /// Phase 3: emitted when the global Service Intelligence hub (More → Business)
    /// renders. Proves the combined hub built from cache only (no_network) and which
    /// optional sections were available without forcing a fetch.
    static func globalView(
        mode: ServiceMode,
        actions: Int,
        analyticsCached: Bool,
        upcomingCount: Int
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[SERVICE_GLOBAL_TRACE] surface=global mode=\(mode.traceLabel, privacy: .public) actions=\(actions, privacy: .public) analyticsCached=\(analyticsCached ? "true" : "false", privacy: .public) upcoming=\(upcomingCount, privacy: .public) no_network=true"
        )
    }

    /// Backend-fed phase: full context trace proving which data sources were used.
    /// Emitted once per `rebuild()` call — proves cache-only vs backend-enriched.
    static func context(
        dateKey: String,
        reservations: Int,
        guestSummaryStatus: String,
        businessSummaryStatus: String,
        profilePacks: Int,
        source: String
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[SERVICE_CONTEXT_TRACE] date=\(dateKey, privacy: .public) reservations=\(reservations, privacy: .public) guestSummary=\(guestSummaryStatus, privacy: .public) businessSummary=\(businessSummaryStatus, privacy: .public) profilePacks=\(profilePacks, privacy: .public) source=\(source, privacy: .public)"
        )
    }

    /// Backend-fed phase: emitted when a background load is scheduled or completes.
    static func backendFeed(type: String, status: String, durationMs: Int? = nil) {
        guard isEnabled else { return }
        if let ms = durationMs {
            logger.debug(
                "[SERVICE_BACKEND_FEED_TRACE] type=\(type, privacy: .public) status=\(status, privacy: .public) duration=\(ms, privacy: .public)ms"
            )
        } else {
            logger.debug(
                "[SERVICE_BACKEND_FEED_TRACE] type=\(type, privacy: .public) status=\(status, privacy: .public)"
            )
        }
    }

    /// Phase 6: number of reservations with actionable note signals in the global hub.
    static func noteSignals(count: Int) {
        guard isEnabled else { return }
        logger.debug(
            "[SERVICE_GLOBAL_TRACE] section=note_signals count=\(count, privacy: .public)"
        )
    }

    /// Phase 4: number of busy booking windows surfaced in the global hub section.
    static func bookingSection(count: Int) {
        guard isEnabled else { return }
        logger.debug(
            "[SERVICE_GLOBAL_TRACE] section=booking_suggestions count=\(count, privacy: .public)"
        )
    }

    static func test(scenario: String, result: String, detail: String? = nil) {
        guard isEnabled else { return }
        if let detail, !detail.isEmpty {
            logger.debug("[SERVICE_INTELLIGENCE_TEST] scenario=\(scenario, privacy: .public) result=\(result, privacy: .public) \(detail, privacy: .public)")
        } else {
            logger.debug("[SERVICE_INTELLIGENCE_TEST] scenario=\(scenario, privacy: .public) result=\(result, privacy: .public)")
        }
    }
}
