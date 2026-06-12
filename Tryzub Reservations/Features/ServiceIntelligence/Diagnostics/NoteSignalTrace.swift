//
//  NoteSignalTrace.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 6 (Note intelligence).
//
//  DEBUG-only structured traces for the NoteSignalAnalyzer.
//  Signal counts and type tokens only — no raw note text, no PII.
//

import Foundation
import OSLog

enum NoteSignalTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "NoteSignal"
    )

    /// Emitted once per analysis run — total signals found.
    static func analyzed(reservationID: String, signals: Int, fallback: Bool) {
        guard isEnabled else { return }
        logger.debug(
            "[SERVICE_NOTE_ANALYZER_TRACE] reservation=\(reservationID, privacy: .public) signals=\(signals, privacy: .public) fallback=\(fallback ? "true" : "false", privacy: .public)"
        )
    }

    /// Emitted for each signal found.
    static func signal(
        reservationID: String,
        type: String,
        confidence: String,
        source: String,
        requiresReview: Bool
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[SERVICE_NOTE_ANALYZER_TRACE] reservation=\(reservationID, privacy: .public) type=\(type, privacy: .public) confidence=\(confidence, privacy: .public) source=\(source, privacy: .public) requiresReview=\(requiresReview ? "true" : "false", privacy: .public)"
        )
    }
}
