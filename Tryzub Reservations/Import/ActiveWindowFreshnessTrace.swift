//
//  ActiveWindowFreshnessTrace.swift
//  Tryzub Reservations
//
//  DEBUG-only focused trace proving that the active-window auto-refresh and the
//  startup delta share one freshness clock, and that idle automatic refresh skips
//  within the TTL after a successful sync.
//

import Foundation
import OSLog

enum ActiveWindowFreshnessTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "ActiveWindowFreshness"
    )

    /// Emitted whenever an active-window sync succeeds (startup delta, automatic, or
    /// manual). Anchors the freshness clock that auto-refresh later reads.
    static func markSuccess(
        source: String,
        scope: String,
        cursorSaved: Bool,
        autoFreshUntil: Date
    ) {
        guard isEnabled else { return }
        let until = autoFreshUntil.formatted(date: .omitted, time: .standard)
        logger.debug(
            "[ACTIVE_WINDOW_FRESHNESS_TRACE] event=mark_success source=\(source, privacy: .public) scope=\(scope, privacy: .public) cursorSaved=\(cursorSaved ? "true" : "false", privacy: .public) autoFreshUntil=\(until, privacy: .public)"
        )
    }

    /// Emitted by the automatic refresh path with the decision and the elapsed/ttl it used.
    static func autoCheck(
        source: String,
        decision: String,
        reason: String,
        elapsed: TimeInterval?,
        ttl: TimeInterval
    ) {
        guard isEnabled else { return }
        let elapsedText = elapsed.map { "\(Int($0))s" } ?? "-"
        logger.debug(
            "[ACTIVE_WINDOW_FRESHNESS_TRACE] event=auto_check source=\(source, privacy: .public) decision=\(decision, privacy: .public) reason=\(reason, privacy: .public) elapsed=\(elapsedText, privacy: .public) ttl=\(Int(ttl), privacy: .public)s"
        )
    }
}
