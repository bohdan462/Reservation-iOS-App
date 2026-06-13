//
//  ManualPhoneSuggestTrace.swift
//  Tryzub Reservations
//
//  DEBUG proof traces for manual reservation phone guest suggestions.
//  Never logs full phone numbers — digit count and match reason only.
//

import Foundation
import OSLog

enum ManualPhoneSuggestTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "ManualPhoneSuggest"
    )

    static let threshold = 4

    static func lookup(
        digits: Int,
        matches: Int,
        source: String = "cache",
        mode: String? = nil,
        reason: String? = nil
    ) {
        guard isEnabled else { return }
        if digits < threshold {
            logger.debug(
                "[MANUAL_PHONE_SUGGEST_TRACE] digits=\(digits, privacy: .public) matches=0 reason=below_threshold"
            )
            return
        }
        if matches == 0 {
            logger.debug(
                "[MANUAL_PHONE_SUGGEST_TRACE] digits=\(digits, privacy: .public) matches=0 threshold=\(threshold, privacy: .public) source=\(source, privacy: .public) reason=\(reason ?? "no_normalized_match", privacy: .public)"
            )
            return
        }
        logger.debug(
            "[MANUAL_PHONE_SUGGEST_TRACE] digits=\(digits, privacy: .public) matches=\(matches, privacy: .public) threshold=\(threshold, privacy: .public) source=\(source, privacy: .public) mode=\(mode ?? "unknown", privacy: .public)"
        )
    }

    static func selectedGuest(name: String, reason: String) {
        guard isEnabled else { return }
        logger.debug(
            "[MANUAL_PHONE_SUGGEST_TRACE] selectedGuest=\"\(name, privacy: .public)\" reason=\(reason, privacy: .public)"
        )
    }
}
