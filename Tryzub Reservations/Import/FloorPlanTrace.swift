//
//  FloorPlanTrace.swift
//  Tryzub Reservations
//

import Foundation
import OSLog

enum FloorPlanTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "FloorPlan"
    )

    static func event(name: String, extra: String? = nil) {
        guard isEnabled else { return }
        var body = "event=\(name)"
        if let extra, !extra.isEmpty {
            body += " \(extra)"
        }
        logger.debug("[FLOOR_PLAN_TRACE] \(body, privacy: .public)")
    }

    // MARK: - Layout-specific helpers

    static func layoutImportDefaults(count: Int) {
        event(name: "import_defaults", extra: "tables=\(count)")
    }

    static func layoutSaveStarted(count: Int) {
        event(name: "save_started", extra: "tables=\(count)")
    }

    static func layoutSaveCompleted(count: Int) {
        event(name: "save_completed", extra: "tables=\(count)")
    }
}

/// Convenience alias for layout-specific call sites.
typealias FloorLayoutTrace = FloorPlanTrace
