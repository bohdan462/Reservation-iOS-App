//
//  BookingLoadTrace.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 4 (Booking Load Suggestions).
//
//  DEBUG-only structured traces. Counts and slot times only — no guest contact data.
//

import Foundation
import OSLog

enum BookingLoadTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "BookingLoad"
    )

    /// A busy window that produced a close-slot suggestion.
    static func busyWindow(
        date: String,
        slot: String,
        reservations: Int,
        guests: Int,
        threshold: String,
        suggestedAction: String,
        alternate: String?
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[BOOKING_LOAD_TRACE] date=\(date, privacy: .public) slot=\(slot, privacy: .public) reservations=\(reservations, privacy: .public) guests=\(guests, privacy: .public) knownOnly=true threshold=\(threshold, privacy: .public) suggestedAction=\(suggestedAction, privacy: .public) alternate=\(alternate ?? "-", privacy: .public)"
        )
    }

    /// A window picked as the next better alternate time.
    static func alternateWindow(date: String, slot: String, reservations: Int, guests: Int) {
        guard isEnabled else { return }
        logger.debug(
            "[BOOKING_LOAD_TRACE] date=\(date, privacy: .public) slot=\(slot, privacy: .public) reservations=\(reservations, privacy: .public) guests=\(guests, privacy: .public) suggestedAsAlternate=true"
        )
    }

    /// Emitted for each generated booking-load staff action (always canAutoComplete=false).
    static func action(type: StaffActionType, slot: String, priority: ActionPriority, canAutoComplete: Bool) {
        guard isEnabled else { return }
        logger.debug(
            "[SERVICE_ACTION_TRACE] type=\(type.rawValue, privacy: .public) slot=\(slot, privacy: .public) priority=\(priority.rawValue, privacy: .public) canAutoComplete=\(canAutoComplete ? "true" : "false", privacy: .public)"
        )
    }
}
