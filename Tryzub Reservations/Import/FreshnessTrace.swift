//
//  FreshnessTrace.swift
//  Tryzub Reservations
//

import Foundation
import OSLog

enum FreshnessTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "Freshness"
    )

    static func log(
        key: String,
        date: String,
        action: String,
        reason: String? = nil,
        caller: String? = nil,
        age: TimeInterval? = nil
    ) {
        guard isEnabled else { return }
        var body = "key=\(key) date=\(date) action=\(action)"
        if let reason, !reason.isEmpty {
            body += " reason=\(reason)"
        }
        if let caller, !caller.isEmpty {
            body += " caller=\(caller)"
        }
        if let age {
            body += " age=\(Int(age))s"
        }
        logger.debug("[FRESHNESS_TRACE] \(body, privacy: .public)")
    }
}
