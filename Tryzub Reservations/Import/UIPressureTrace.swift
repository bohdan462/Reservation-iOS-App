//
//  UIPressureTrace.swift
//  Tryzub Reservations
//
//  DEBUG-only main-thread / sync phase timing.
//

import Foundation
import OSLog

enum UIPressureTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "UIPressure"
    )

    static func phase(
        _ phase: String,
        duration: TimeInterval,
        extra: String? = nil
    ) {
        guard isEnabled else { return }
        let ms = String(format: "%.0f", duration * 1000)
        var body = "phase=\(phase) duration=\(ms)ms"
        if let extra, !extra.isEmpty {
            body += " \(extra)"
        }
        logger.debug("[UI_PRESSURE_TRACE] \(body, privacy: .public)")
    }

    static func measure<T>(
        phase: String,
        extra: String? = nil,
        operation: () throws -> T
    ) rethrows -> T {
        let started = ContinuousClock.now
        defer {
            let elapsed = started.duration(to: .now)
            Self.phase(phase, duration: elapsed.timeInterval, extra: extra)
        }
        return try operation()
    }

    static func measureAsync<T>(
        phase: String,
        extra: String? = nil,
        operation: () async throws -> T
    ) async rethrows -> T {
        let started = ContinuousClock.now
        defer {
            let elapsed = started.duration(to: .now)
            Self.phase(phase, duration: elapsed.timeInterval, extra: extra)
        }
        return try await operation()
    }
}

extension Duration {
    var pressureTraceTimeInterval: TimeInterval {
        let components = components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1e18
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        pressureTraceTimeInterval
    }
}
