//
//  FacadeTrace.swift
//  Tryzub Reservations
//

import Foundation
import OSLog

enum FacadeTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "Facade"
    )

    static func build(
        surface: String,
        duration: TimeInterval,
        extra: String? = nil
    ) {
        guard isEnabled else { return }
        let ms = String(format: "%.0f", duration * 1000)
        var body = "surface=\(surface) event=build_view_state duration=\(ms)ms"
        if let extra, !extra.isEmpty {
            body += " \(extra)"
        }
        logger.debug("[FACADE_TRACE] \(body, privacy: .public)")
    }

    static func event(
        surface: String,
        name: String,
        extra: String? = nil
    ) {
        guard isEnabled else { return }
        var body = "surface=\(surface) event=\(name)"
        if let extra, !extra.isEmpty {
            body += " \(extra)"
        }
        logger.debug("[FACADE_TRACE] \(body, privacy: .public)")
    }
}
