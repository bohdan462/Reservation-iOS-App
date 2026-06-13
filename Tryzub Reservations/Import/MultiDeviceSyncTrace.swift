//
//  MultiDeviceSyncTrace.swift
//  Tryzub Reservations
//
//  DEBUG-only focused traces proving the multi-device manual-reservation visibility
//  path end to end:
//
//    manual create                -> [MANUAL_CREATE_TRACE]
//    visible refresh decision     -> [VISIBLE_LIVE_REFRESH_TRACE]
//    active-window sync result    -> [ACTIVE_WINDOW_SYNC_TRACE]
//    active-window date breakdown -> [ACTIVE_WINDOW_DATE_BREAKDOWN_TRACE]
//    active-window per-row        -> [ACTIVE_WINDOW_ROW_TRACE]
//    repository date write        -> [REPOSITORY_DATE_TRACE]
//    host filter per-row          -> [HOST_FILTER_TRACE]
//    host snapshot preserve       -> [HOST_SNAPSHOT_PRESERVE_TRACE]
//    manual duplicate policy      -> [MANUAL_DUPLICATE_POLICY_TRACE]
//    host/bookings render         -> [HOST_RENDER_TRACE]
//    guest lookup match           -> [GUEST_LOOKUP_TRACE]
//
//  These traces never change behavior; they only narrate it. Compiled out of release.
//

import Foundation
import OSLog

/// Which visible surface requested the live auto-refresh.
enum VisibleLiveRefreshSource: String {
    case host
    case bookings
}

enum MultiDeviceSyncTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "MultiDeviceSync"
    )

    // MARK: - Visible-live refresh

    /// Decision made by the visible Host/Bookings auto-refresh.
    static func visibleLiveRefresh(
        source: VisibleLiveRefreshSource,
        decision: String,
        reason: String
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[VISIBLE_LIVE_REFRESH_TRACE] source=\(source.rawValue, privacy: .public) decision=\(decision, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    // MARK: - Active-window sync

    /// Result of an active-window GET (delta or full).
    static func activeWindowSync(
        reason: String,
        decoded: Int,
        firstIDs: [Int],
        from: String,
        to: String,
        cursor: String?
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[ACTIVE_WINDOW_SYNC_TRACE] reason=\(reason, privacy: .public) decoded=\(decoded, privacy: .public) firstIDs=\(firstIDs.prefix(10).map(String.init).joined(separator: ","), privacy: .public) from=\(from, privacy: .public) to=\(to, privacy: .public) cursor=\(cursor ?? "none", privacy: .public)"
        )
    }

    /// After decoding a full/delta active-window API response: total count broken down per date.
    static func activeWindowDateBreakdown(
        reason: String,
        total: Int,
        dates: [String: Int]
    ) {
        guard isEnabled else { return }
        let breakdown = dates.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
        logger.debug(
            "[ACTIVE_WINDOW_DATE_BREAKDOWN_TRACE] reason=\(reason, privacy: .public) total=\(total, privacy: .public) dates=\(breakdown, privacy: .public)"
        )
    }

    /// Per-row compact trace after decoding (no PII). Proves whether a specific
    /// reservation ID was present in the API response before any upsert.
    static func activeWindowRow(
        id: Int,
        date: String,
        time: String,
        status: String,
        hidden: Bool,
        supersededBy: Int?,
        sourceType: String?,
        createdAt: String,
        apiUpdatedAt: String?
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[ACTIVE_WINDOW_ROW_TRACE] id=\(id, privacy: .public) date=\(date, privacy: .public) time=\(String(time.prefix(5)), privacy: .public) status=\(status, privacy: .public) hidden=\(hidden, privacy: .public) supersededBy=\(supersededBy.map(String.init) ?? "none", privacy: .public) sourceType=\(sourceType ?? "nil", privacy: .public) createdAt=\(createdAt, privacy: .public) apiUpdatedAt=\(apiUpdatedAt ?? "nil", privacy: .public)"
        )
    }

    // MARK: - Repository

    /// Per-date summary of what was written/skipped/removed in a date-window upsert.
    static func repositoryDateTrace(
        scope: String,
        date: String,
        serverIDs: [Int],
        upsertedIDs: [Int],
        skippedIDs: [Int],
        removedIDs: [Int],
        afterIDs: [Int]
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[REPOSITORY_DATE_TRACE] scope=\(scope, privacy: .public) date=\(date, privacy: .public) serverIDs=\(serverIDs.map(String.init).joined(separator: ","), privacy: .public) upsertedIDs=\(upsertedIDs.map(String.init).joined(separator: ","), privacy: .public) skippedIDs=\(skippedIDs.map(String.init).joined(separator: ","), privacy: .public) removedIDs=\(removedIDs.map(String.init).joined(separator: ","), privacy: .public) afterIDs=\(afterIDs.map(String.init).joined(separator: ","), privacy: .public)"
        )
    }

    // MARK: - Host filter

    /// Per-row decision for why a reservation was included or excluded from the
    /// selected-date Host board list. Emitted from selectedDateReservations.
    static func hostFilterTrace(
        selectedDate: String,
        id: Int,
        recordDate: String,
        time: String,
        status: String,
        hidden: Bool,
        superseded: Bool,
        included: Bool,
        reason: String
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[HOST_FILTER_TRACE] selectedDate=\(selectedDate, privacy: .public) id=\(id, privacy: .public) recordDate=\(recordDate, privacy: .public) time=\(String(time.prefix(5)), privacy: .public) status=\(status, privacy: .public) hidden=\(hidden, privacy: .public) superseded=\(superseded, privacy: .public) included=\(included, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    // MARK: - Snapshot preservation

    /// Emitted when the Host snapshot build task decides whether to publish an incoming
    /// snapshot or preserve the last stable one. `preserve=true` means the incoming
    /// 0-reservation snapshot was suppressed.
    static func hostSnapshotPreserve(
        date: String,
        incomingCount: Int,
        lastStableCount: Int,
        preserve: Bool,
        reason: String
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[HOST_SNAPSHOT_PRESERVE_TRACE] date=\(date, privacy: .public) incomingCount=\(incomingCount, privacy: .public) lastStableCount=\(lastStableCount, privacy: .public) preserve=\(preserve, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    // MARK: - Manual create

    /// Emitted right after a manual reservation is created server-first and upserted locally.
    static func manualCreateSuccess(
        remoteID: Int,
        date: String,
        time: String,
        apiUpdatedAt: String?
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[MANUAL_CREATE_TRACE] success remoteID=\(remoteID, privacy: .public) date=\(date, privacy: .public) time=\(time, privacy: .public) apiUpdatedAt=\(apiUpdatedAt ?? "nil", privacy: .public)"
        )
    }

    // MARK: - Duplicate policy

    /// Emitted for any row whose source type is manual (sourceType=manual_call_in or
    /// created by staff). Proves whether the backend or policy marked it hidden.
    static func manualDuplicatePolicy(
        id: Int,
        sourceType: String,
        identityMatchedExisting: Bool,
        sameDateTimeParty: Bool,
        superseded: Bool,
        hiddenByPolicy: Bool,
        reason: String
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[MANUAL_DUPLICATE_POLICY_TRACE] id=\(id, privacy: .public) sourceType=\(sourceType, privacy: .public) identityMatchedExisting=\(identityMatchedExisting, privacy: .public) sameDateTimeParty=\(sameDateTimeParty, privacy: .public) superseded=\(superseded, privacy: .public) hiddenByPolicy=\(hiddenByPolicy, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    // MARK: - Host render

    /// Emitted when the Host board snapshot rebuilds for a selected date.
    static func hostRender(
        selectedDate: String,
        reservations: Int,
        visibleIDs: [Int]
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[HOST_RENDER_TRACE] selectedDate=\(selectedDate, privacy: .public) reservations=\(reservations, privacy: .public) visibleIDs=\(visibleIDs.prefix(20).map(String.init).joined(separator: ","), privacy: .public)"
        )
    }

    // MARK: - Guest lookup

    /// Emitted when guest lookup resolves matches.
    static func guestLookup(
        query: String,
        matched: Int,
        firstIDs: [String]
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[GUEST_LOOKUP_TRACE] query=\(query, privacy: .private) matched=\(matched, privacy: .public) firstIDs=\(firstIDs.prefix(10).joined(separator: ","), privacy: .public)"
        )
    }
}
