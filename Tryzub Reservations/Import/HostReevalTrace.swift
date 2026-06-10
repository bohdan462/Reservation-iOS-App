//
//  HostReevalTrace.swift
//  Tryzub Reservations
//

import Foundation
import OSLog

enum HostReevalTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "HostReeval"
    )

    static func log(
        trigger: String,
        debounced: Bool? = nil,
        immediate: Bool? = nil
    ) {
        guard isEnabled else { return }
        var body = "trigger=\(trigger)"
        if let debounced {
            body += " debounced=\(debounced)"
        }
        if let immediate {
            body += " immediate=\(immediate)"
        }
        logger.debug("[HOST_REEVAL_TRACE] \(body, privacy: .public)")
    }
}
