//
//  AnalyticsTrace.swift
//  Tryzub Reservations
//
//  DEBUG-only tracing for Business Analytics loading.
//

import Foundation
import OSLog

enum AnalyticsTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "Analytics"
    )

    static func displayCached(range: AnalyticsRangeKey, fresh: Bool) {
        guard isEnabled else { return }
        emit("range=\(range.traceLabel) cacheHit=true fresh=\(fresh) action=display_cached")
    }

    static func scheduled(range: AnalyticsRangeKey, delayMilliseconds: Int) {
        guard isEnabled else { return }
        emit("range=\(range.traceLabel) scheduled delay=\(delayMilliseconds)ms")
    }

    static func cancelled(range: AnalyticsRangeKey, reason: String) {
        guard isEnabled else { return }
        emit("range=\(range.traceLabel) cancelled reason=\(reason)")
    }

    static func start(range: AnalyticsRangeKey, endpoint: String, enrichment: Bool = false) {
        guard isEnabled else { return }
        if enrichment {
            emit("range=\(range.traceLabel) start \(endpoint) enrichment=true")
        } else {
            emit("range=\(range.traceLabel) start \(endpoint)")
        }
    }

    static func end(range: AnalyticsRangeKey, endpoint: String) {
        guard isEnabled else { return }
        emit("range=\(range.traceLabel) end \(endpoint)")
    }

    static func fail(
        range: AnalyticsRangeKey,
        endpoint: String,
        timeout: Bool,
        keepReservationAnalytics: Bool
    ) {
        guard isEnabled else { return }
        emit(
            "range=\(range.traceLabel) fail \(endpoint) timeout=\(timeout) keepReservationAnalytics=\(keepReservationAnalytics)"
        )
    }

    static func ignoredResponse(range: AnalyticsRangeKey, reason: String) {
        guard isEnabled else { return }
        emit("range=\(range.traceLabel) ignored_response reason=\(reason)")
    }

    static func cacheMiss(range: AnalyticsRangeKey) {
        guard isEnabled else { return }
        emit("range=\(range.traceLabel) cacheHit=false fresh=false action=load")
    }

    private static func emit(_ body: String) {
        logger.debug("[ANALYTICS_TRACE] \(body, privacy: .public)")
    }
}
