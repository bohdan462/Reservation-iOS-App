//
//  FormTrace.swift
//  Tryzub Reservations
//

import Foundation
import OSLog

enum FormTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "Form"
    )

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
        logger.debug("[FORM_TRACE] \(body, privacy: .public)")
    }
}
