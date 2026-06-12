//
//  SwiftDataTrace.swift
//  Tryzub Reservations
//
//  DEBUG-only SwiftData and UI pressure measurement traces.
//
//  Trace formats:
//    [SWIFTDATA_TRACE] operation=upsert rows=N changed=N duration=Xms
//    [SWIFTDATA_TRACE] operation=save changed=N duration=Xms
//    [VIEWSTATE_TRACE] surface=... reason=... duration=Xms
//    [UI_PRESSURE_TRACE] phase=... duration=Xms
//

import Foundation
import OSLog

enum SwiftDataTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "SwiftDataTrace"
    )

    // MARK: - SwiftData Operations

    /// Log after a batch upsert completes.
    static func upsert(rows: Int, changed: Int, durationMs: Double) {
        guard isEnabled else { return }
        logger.debug(
            "[SWIFTDATA_TRACE] operation=upsert rows=\(rows, privacy: .public) changed=\(changed, privacy: .public) duration=\(String(format: "%.1f", durationMs), privacy: .public)ms"
        )
    }

    /// Log after a SwiftData save completes.
    static func save(changed: Int, durationMs: Double) {
        guard isEnabled else { return }
        logger.debug(
            "[SWIFTDATA_TRACE] operation=save changed=\(changed, privacy: .public) duration=\(String(format: "%.1f", durationMs), privacy: .public)ms"
        )
    }

    /// Log a SwiftData operation timing using a start clock.
    static func operationCompleted(
        operation: String,
        rows: Int,
        changed: Int,
        started: ContinuousClock.Instant
    ) {
        guard isEnabled else { return }
        let durationMs = started.duration(to: .now).pressureTraceTimeInterval * 1000
        logger.debug(
            "[SWIFTDATA_TRACE] operation=\(operation, privacy: .public) rows=\(rows, privacy: .public) changed=\(changed, privacy: .public) duration=\(String(format: "%.1f", durationMs), privacy: .public)ms"
        )
    }

    // MARK: - ViewState Pressure

    /// Log a view state rebuild triggered by SwiftData or external change.
    static func viewStateRebuild(surface: String, reason: String, durationMs: Double) {
        guard isEnabled else { return }
        logger.debug(
            "[VIEWSTATE_TRACE] surface=\(surface, privacy: .public) reason=\(reason, privacy: .public) duration=\(String(format: "%.1f", durationMs), privacy: .public)ms"
        )
    }

    // MARK: - Convenience timing helper

    /// Returns the current instant for use as a start measurement point.
    static func now() -> ContinuousClock.Instant {
        ContinuousClock.now
    }

    /// Returns elapsed milliseconds since a start instant.
    static func elapsedMs(since start: ContinuousClock.Instant) -> Double {
        start.duration(to: .now).pressureTraceTimeInterval * 1000
    }
}

// MARK: - UIPressureTrace extension

extension UIPressureTrace {
    /// Convenience that also accepts a pre-captured start instant.
    static func phase(_ name: String, since start: ContinuousClock.Instant, extra: String? = nil) {
        let durationMs = start.duration(to: .now).pressureTraceTimeInterval
        var extraStr = ""
        if let extra { extraStr = " \(extra)" }
        UIPressureTrace.phase(name, duration: durationMs, extra: extraStr.isEmpty ? nil : extraStr)
    }
}
