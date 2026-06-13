//
//  MultiDeviceSyncTrace.swift
//  Tryzub Reservations
//
//  DEBUG-only focused traces proving the multi-device manual-reservation visibility
//  path end to end:
//
//    manual create  -> [MANUAL_CREATE_TRACE]
//    visible refresh decision -> [VISIBLE_LIVE_REFRESH_TRACE]
//    active-window sync result -> [ACTIVE_WINDOW_SYNC_TRACE]
//    host/bookings render -> [HOST_RENDER_TRACE]
//    guest lookup match -> [GUEST_LOOKUP_TRACE]
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

    /// Decision made by the visible Host/Bookings auto-refresh: a cursor-backed delta,
    /// a full sync, or a skip. Fresh-cache TTL may skip a full sync but must never
    /// suppress a delta check while a surface is visible and the app is active.
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

    /// Result of an active-window GET (delta or full): how many rows decoded and the
    /// leading IDs, plus the window and the cursor used (`none` for a full sync).
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

    /// Emitted right after a manual reservation is created server-first and the returned
    /// DTO is upserted locally. Anchors the ID/date/time/version other devices must pick up.
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

    /// Emitted when the Host/Bookings board rebuilds for a selected date. Proves whether
    /// a reservation that synced into SwiftData actually reaches the rendered list.
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

    /// Emitted when guest lookup resolves matches, proving a newly synced guest/reservation
    /// is reachable from search without a broad history fetch.
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
