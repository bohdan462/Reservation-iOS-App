//
//  GuestIntelTrace.swift
//  Tryzub Reservations
//
//  DEBUG-only guest intelligence fetch and merge tracing.
//

import Foundation
import OSLog

enum GuestIntelTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "GuestIntel"
    )

    private static let lock = NSLock()
    private nonisolated(unsafe) static var lastMergedKeys: [String: String] = [:]
    private nonisolated(unsafe) static var lastDetailKeys: [String: String] = [:]

    private static func stateKey(surface: String, reservationID: Int) -> String {
        "\(surface)-\(reservationID)"
    }

    static func dateSummaryStart(date: String) {
        guard isEnabled else { return }
        emit("date=\(date) start date_summary")
    }

    static func dateSummaryCompleted(
        date: String,
        count: Int,
        durationMs: Int? = nil,
        cacheHit: Bool = false
    ) {
        guard isEnabled else { return }
        let duration = durationMs.map { " duration=\($0)ms" } ?? ""
        emit("date=\(date) completed count=\(count)\(duration) cacheHit=\(cacheHit)")
    }

    static func profileStart(reservationID: Int, cacheHit: Bool) {
        guard isEnabled else { return }
        emit("reservation=\(reservationID) profile cacheHit=\(cacheHit) start")
    }

    static func profileCompleted(
        reservationID: Int,
        durationMs: Int? = nil,
        cacheHit: Bool = false
    ) {
        guard isEnabled else { return }
        let duration = durationMs.map { " duration=\($0)ms" } ?? ""
        emit("reservation=\(reservationID) profile completed\(duration) cacheHit=\(cacheHit)")
    }

    static func profileSkipped(reservationID: Int, reason: String) {
        guard isEnabled else { return }
        emit("reservation=\(reservationID) profile skipped reason=\(reason)")
    }

    @discardableResult
    static func mergedIfChanged(
        surface: String,
        reservationID: Int,
        dedupeKey: String,
        source: String,
        localPrior: Int,
        backendSeenBefore: Bool,
        durationMs: Int? = nil
    ) -> Bool {
        guard isEnabled else { return false }

        let key = stateKey(surface: surface, reservationID: reservationID)
        lock.lock()
        let deduped = lastMergedKeys[key] == dedupeKey
        if !deduped {
            lastMergedKeys[key] = dedupeKey
        }
        lock.unlock()

        guard !deduped else { return false }

        let duration = durationMs.map { " duration=\($0)ms" } ?? ""
        emit(
            "surface=\(surface) reservation=\(reservationID) merged source=\(source) localPrior=\(localPrior) backend_seen_before=\(backendSeenBefore)\(duration) deduped=false"
        )
        return true
    }

    @discardableResult
    static func detailIfChanged(
        surface: String,
        reservationID: Int,
        dedupeKey: String,
        shown: Bool,
        source: String,
        sinceOpenMs: Int? = nil
    ) -> Bool {
        guard isEnabled else { return false }

        let key = stateKey(surface: surface, reservationID: reservationID)
        lock.lock()
        let deduped = lastDetailKeys[key] == dedupeKey
        if !deduped {
            lastDetailKeys[key] = dedupeKey
        }
        lock.unlock()

        guard !deduped else { return false }

        let sinceOpen = sinceOpenMs.map { " sinceOpen=\($0)ms" } ?? ""
        emit(
            "surface=\(surface) detail reservation=\(reservationID) shown=\(shown) source=\(source)\(sinceOpen) deduped=false"
        )
        return true
    }

    static func dateSummaryCached(date: String, selectedMismatch: Bool) {
        guard isEnabled else { return }
        emit("date=\(date) cached selectedMismatch=\(selectedMismatch)")
    }

    private static func emit(_ body: String) {
        logger.debug("[GUEST_INTEL_TRACE] \(body, privacy: .public)")
    }
}
