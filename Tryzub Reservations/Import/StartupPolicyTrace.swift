//
//  StartupPolicyTrace.swift
//  Tryzub Reservations
//
//  DEBUG-only startup policy tracing.
//

import Foundation
import OSLog

enum StartupRefreshPolicy: String, Equatable {
    case coldFull = "full"
    case skip = "skip"
    case delta = "delta"
    case full = "full_recovery"
}

enum StartupPolicyTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "StartupPolicy"
    )

    static func policy(
        cacheHit: Bool,
        activeWindowFresh: Bool,
        hasServerCursor: Bool,
        policy: StartupRefreshPolicy,
        reason: String,
        setupLoadedFromCache: Bool? = nil,
        remoteSetupStarted: Bool? = nil
    ) {
        guard isEnabled else { return }
        var parts = [
            "cacheHit=\(cacheHit)",
            "activeWindowFresh=\(activeWindowFresh)",
            "hasCursor=\(hasServerCursor)",
            "policy=\(policy.rawValue)",
            "reason=\(reason)",
        ]
        if let setupLoadedFromCache {
            parts.append("setupLoadedFromCache=\(setupLoadedFromCache)")
        }
        if let remoteSetupStarted {
            parts.append("remoteSetupStarted=\(remoteSetupStarted)")
        }
        emit(parts.joined(separator: " "))
    }

    static func noncriticalDeferred(work: String, delaySeconds: Int) {
        guard isEnabled else { return }
        emit("noncritical deferred \(work) delay=\(delaySeconds)s")
    }

    static func remoteSetupStarted(fromCache: Bool) {
        guard isEnabled else { return }
        emit("remoteSetupStarted setupLoadedFromCache=\(fromCache)")
    }

    static func persisted(
        scope: String,
        cursorSaved: Bool,
        lastSuccessSaved: Bool
    ) {
        guard isEnabled else { return }
        emit(
            "persisted scope=\(scope) cursorSaved=\(cursorSaved) lastSuccessSaved=\(lastSuccessSaved)"
        )
    }

    static func guestIntelligenceScheduled(date: String, selected: Bool, delaySeconds: Int) {
        guard isEnabled else { return }
        emit(
            "guest_intelligence scheduled date=\(date) selected=\(selected) delay=\(delaySeconds)s"
        )
    }

    static func guestIntelligenceCancelled(date: String, reason: String) {
        guard isEnabled else { return }
        emit("guest_intelligence cancelled date=\(date) reason=\(reason)")
    }

    private static func emit(_ body: String) {
        logger.debug("[STARTUP_POLICY] \(body, privacy: .public)")
    }
}
