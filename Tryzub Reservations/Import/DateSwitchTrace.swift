//
//  DateSwitchTrace.swift
//  Tryzub Reservations
//
//  Focused instrumentation for Host date-chip switching and the availability
//  bundle lifecycle. Used to localize the "System gesture gate timed out" /
//  "unsafeForcedSync called from Swift Concurrent context" warnings that appear
//  around restaurant_day_availability loading.
//
//  Trace formats:
//    [DATE_SWITCH_TRACE] from=... to=... phase=begin
//    [DATE_SWITCH_TRACE] date=... phase=availability_start
//    [DATE_SWITCH_TRACE] date=... phase=availability_publish duration=...ms
//    [CONCURRENCY_TRACE] context=availability_completion modelContextUsed=true|false
//

import Foundation
import OSLog

enum DateSwitchTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "DateSwitch"
    )

    static func begin(from: String?, to: String) {
        guard isEnabled else { return }
        logger.debug("[DATE_SWITCH_TRACE] from=\(from ?? "none", privacy: .public) to=\(to, privacy: .public) phase=begin")
    }

    static func availabilityStart(date: String) {
        guard isEnabled else { return }
        logger.debug("[DATE_SWITCH_TRACE] date=\(date, privacy: .public) phase=availability_start")
    }

    static func availabilityPublish(date: String, durationMs: Int) {
        guard isEnabled else { return }
        logger.debug("[DATE_SWITCH_TRACE] date=\(date, privacy: .public) phase=availability_publish duration=\(durationMs, privacy: .public)ms")
    }

    static func concurrency(context: String, modelContextUsed: Bool) {
        guard isEnabled else { return }
        logger.debug("[CONCURRENCY_TRACE] context=\(context, privacy: .public) modelContextUsed=\(modelContextUsed ? "true" : "false", privacy: .public)")
    }

    /// Phase-tagged concurrency breadcrumb. `detail` is a space-joined set of
    /// already-sanitized key=value pairs (e.g. "modelContextUsed=false mainActor=true").
    static func concurrencyPhase(context: String, phase: String, detail: String) {
        guard isEnabled else { return }
        logger.debug("[CONCURRENCY_TRACE] context=\(context, privacy: .public) phase=\(phase, privacy: .public) \(detail, privacy: .public)")
    }
}
