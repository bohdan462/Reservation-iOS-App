//
//  DateLoadTrace.swift
//  Tryzub Reservations
//
//  DEBUG-only date-scoped network load tracing.
//

import Foundation
import OSLog

enum DateLoadTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "DateLoad"
    )

    static func scheduled(date: String, type: String, delayMs: Int) {
        guard isEnabled else { return }
        emit("scheduled date=\(date) type=\(type) delay=\(delayMs)ms")
    }

    static func cancelled(date: String, reason: String) {
        guard isEnabled else { return }
        emit("cancelled date=\(date) reason=\(reason)")
    }

    static func ignoredResponse(date: String, reason: String) {
        guard isEnabled else { return }
        emit("ignored_response date=\(date) reason=\(reason)")
    }

    static func completed(date: String, type: String, durationMs: Int) {
        guard isEnabled else { return }
        emit("completed date=\(date) type=\(type) duration=\(durationMs)ms")
    }

    private static func emit(_ body: String) {
        logger.debug("[DATE_LOAD_TRACE] \(body, privacy: .public)")
    }
}
