//
//  ReservationImportService.swift
//  Tryzub Reservations
//
//  Created by Bohdan Tkachenko on 5/13/26.
//

import Foundation

// MARK: - Sync Service Contract

@MainActor
protocol ReservationSyncServiceProtocol {
    func syncAllReservations(reason: ReservationAPIRequestReason) async throws
    func syncTodayFull(reason: ReservationAPIRequestReason) async throws -> ReservationSyncResult
    func syncTodayChanges(since: String, reason: ReservationAPIRequestReason) async throws -> ReservationSyncResult
    func syncActiveWindowFull(from: String, to: String, reason: ReservationAPIRequestReason) async throws -> ReservationSyncResult
    func syncActiveWindowChanges(from: String, to: String, since: String, reason: ReservationAPIRequestReason) async throws -> ReservationSyncResult
    func syncScheduleWindowFull(from: String, to: String, reason: ReservationAPIRequestReason) async throws -> ReservationSyncResult
    func syncToday(reason: ReservationAPIRequestReason) async throws
    func syncScheduleWindow(from: String, to: String, reason: ReservationAPIRequestReason) async throws
    func syncReviewQueues(reason: ReservationAPIRequestReason) async throws
    func saveReservation(_ reservation: ReservationDTO) throws
}

struct ReservationSyncResult: Equatable {
    let rowCount: Int
    let serverTime: String?
    /// Rows actually written to SwiftData; nil when not measured.
    let rowsWritten: Int?

    init(rowCount: Int, serverTime: String?, rowsWritten: Int? = nil) {
        self.rowCount = rowCount
        self.serverTime = serverTime
        self.rowsWritten = rowsWritten
    }
}

@MainActor
final class ReservationSyncService: ReservationSyncServiceProtocol {
    // MARK: - Dependencies

    private let client: any ReservationsAPIClientProtocol
    private let repository: any ReservationRepositoryProtocol
    private let syncServiceInstanceID = StartupTrace.makeInstanceID()
    private let controllerTraceID: String?

    init(
        client: any ReservationsAPIClientProtocol,
        repository: any ReservationRepositoryProtocol,
        controllerTraceID: String? = nil
    ) {
        self.client = client
        self.repository = repository
        self.controllerTraceID = controllerTraceID
        StartupTrace.syncServiceCreated(id: syncServiceInstanceID, controllerID: controllerTraceID)
    }

    // MARK: - Full Cache Sync

    // Intent: Fetches every managed reservation page for diagnostics or broad cache refresh.
    // Network: GET /managed-reservations across all pages.
    // SwiftData: Upserts fetched server DTOs; cache only.
    func syncAllReservations(reason: ReservationAPIRequestReason) async throws {
        let reservations = try await client.fetchAllReservations(
            perPage: 100,
            date: nil,
            from: nil,
            to: nil,
            status: nil,
            search: nil,
            includeHidden: false,
            reason: reason
        )
        try repository.upsert(reservations)
    }

    // MARK: - Today Sync

    // Legacy/private path: refreshes today's date scope only.
    // Normal Home/List/Review refresh uses the shared active-window full/delta flow below.
    // Network: GET /managed-reservations?date=today.
    // SwiftData: Replaces this date scope with fetched server DTOs.
    @discardableResult
    func syncTodayFull(reason: ReservationAPIRequestReason) async throws -> ReservationSyncResult {
        let today = Date.reservationDateString()
        let response = try await client.fetchReservations(
            page: 1,
            perPage: 50,
            date: today,
            from: nil,
            to: nil,
            status: nil,
            search: nil,
            includeHidden: false,
            updatedSince: nil,
            retryCount: 0,
            reason: reason
        )

        try repository.replaceDateScope(date: today, with: response.data, includeHidden: false)
        return ReservationSyncResult(rowCount: response.data.count, serverTime: response.serverTime)
    }

    // Legacy/private path: applies server changes for today's date only.
    // Normal auto-refresh uses active-window delta with from/to/updated_since.
    // Network: GET /managed-reservations?date=today&updated_since=...
    func syncTodayChanges(since: String, reason: ReservationAPIRequestReason) async throws -> ReservationSyncResult {
        let today = Date.reservationDateString()
        let response = try await client.fetchReservations(
            page: 1,
            perPage: 50,
            date: today,
            from: nil,
            to: nil,
            status: nil,
            search: nil,
            includeHidden: false,
            updatedSince: since,
            retryCount: 0,
            reason: reason
        )

        // Delta responses are partial.
        // Upsert returned rows only.
        // Never replace/delete a local scope from an updated_since response.
        if !response.data.isEmpty {
            try repository.upsert(response.data)
        }

        return ReservationSyncResult(rowCount: response.data.count, serverTime: response.serverTime)
    }

    func syncToday(reason: ReservationAPIRequestReason) async throws {
        _ = try await syncTodayFull(reason: reason)
    }

    // MARK: - Active Operational Window Sync

    // Intent: Refreshes the shared cache window used by Home, Schedule, and Review.
    // Network: GET /managed-reservations?from=...&to=... across pages.
    // SwiftData: Replaces only this active window with fetched server DTOs.
    @discardableResult
    func syncActiveWindowFull(from: String, to: String, reason: ReservationAPIRequestReason) async throws -> ReservationSyncResult {
        let syncResponse = try await fetchAllReservationPages(
            perPage: 100,
            date: nil,
            from: from,
            to: to,
            status: nil,
            search: nil,
            includeHidden: false,
            updatedSince: nil,
            reason: reason
        )
        ReservationSyncDiagnostics.cacheUpsertStarted(
            scope: "window=\(from)...\(to)",
            rowCount: syncResponse.reservations.count
        )
        let stats = try await repository.replaceDateWindowYielding(
            from: from,
            to: to,
            with: syncResponse.reservations,
            includeHidden: false
        )
        ReservationSyncDiagnostics.cacheUpsertFinished(
            scope: "window=\(from)...\(to)",
            written: stats.written,
            skipped: stats.skipped,
            removed: stats.removed
        )
        return ReservationSyncResult(
            rowCount: syncResponse.reservations.count,
            serverTime: resolvedSyncCursor(
                serverTime: syncResponse.serverTime,
                reservations: syncResponse.reservations
            )
        )
    }

    /// Background history enrichment: upsert-only, never replaces or deletes local rows.
    @discardableResult
    func prefetchHistoryWindow(
        from: String,
        to: String,
        reason: ReservationAPIRequestReason
    ) async throws -> ReservationSyncResult {
        let syncResponse = try await fetchAllReservationPages(
            perPage: 100,
            date: nil,
            from: from,
            to: to,
            status: nil,
            search: nil,
            includeHidden: false,
            updatedSince: nil,
            reason: reason
        )
        let stats = try await repository.upsertYielding(syncResponse.reservations)
        ReservationSyncDiagnostics.cacheUpsertFinished(
            scope: "history=\(from)...\(to)",
            written: stats.written,
            skipped: stats.skipped,
            removed: 0
        )
        return ReservationSyncResult(
            rowCount: syncResponse.reservations.count,
            serverTime: syncResponse.serverTime,
            rowsWritten: stats.written
        )
    }

    // Intent: Quietly applies server-side reservation changes within the active window since the backend cursor.
    // Network: GET /managed-reservations?from=...&to=...&updated_since=...
    func syncActiveWindowChanges(from: String, to: String, since: String, reason: ReservationAPIRequestReason) async throws -> ReservationSyncResult {
        let networkStarted = ContinuousClock.now
        let syncResponse = try await fetchAllReservationPages(
            perPage: 100,
            date: nil,
            from: from,
            to: to,
            status: nil,
            search: nil,
            includeHidden: false,
            updatedSince: since,
            reason: reason
        )
        UIPressureTrace.phase(
            "startup_delta_network",
            duration: networkStarted.duration(to: .now).pressureTraceTimeInterval,
            extra: "reason=\(reason.rawValue) total=\(syncResponse.reservations.count)"
        )

        UIPressureTrace.phase(
            "decode",
            duration: 0,
            extra: "total=\(syncResponse.reservations.count) decoded=\(syncResponse.reservations.count)"
        )

        // Delta responses are partial.
        // Upsert returned rows only.
        // Never replace/delete a local scope from an updated_since response.
        if !syncResponse.reservations.isEmpty {
            try UIPressureTrace.measure(
                phase: "repository_upsert",
                extra: "rows=\(syncResponse.reservations.count)"
            ) {
                try repository.upsert(syncResponse.reservations)
            }
        } else {
            UIPressureTrace.phase("repository_upsert", duration: 0, extra: "rows=0 skipped=true")
        }

        return ReservationSyncResult(
            rowCount: syncResponse.reservations.count,
            serverTime: resolvedSyncCursor(
                serverTime: syncResponse.serverTime,
                reservations: syncResponse.reservations
            )
        )
    }

    // MARK: - Schedule Window Sync

    // Legacy/private path: refreshes a caller-provided schedule window.
    // Normal Schedule upcoming uses the shared active-window cache.
    // Network: GET /managed-reservations?from=...&to=... across pages.
    // SwiftData: Replaces only the requested date window with fetched server DTOs.
    @discardableResult
    func syncScheduleWindowFull(from: String, to: String, reason: ReservationAPIRequestReason) async throws -> ReservationSyncResult {
        let syncResponse = try await fetchAllReservationPages(
            perPage: 100,
            date: nil,
            from: from,
            to: to,
            status: nil,
            search: nil,
            includeHidden: false,
            updatedSince: nil,
            reason: reason
        )
        try repository.replaceDateWindow(from: from, to: to, with: syncResponse.reservations, includeHidden: false)
        return ReservationSyncResult(rowCount: syncResponse.reservations.count, serverTime: syncResponse.serverTime)
    }

    func syncScheduleWindow(from: String, to: String, reason: ReservationAPIRequestReason) async throws {
        _ = try await syncScheduleWindowFull(from: from, to: to, reason: reason)
    }

    // MARK: - Pending Review Sync

    // Legacy/private path: refreshes the staff pending queue from new and needs_review rows.
    // Normal Bookings Needs Review filtering uses the shared active-window cache.
    // Network: GET /managed-reservations?status=needs_review and status=new.
    // SwiftData: Upserts fetched server DTOs without deleting records missing from this status snapshot.
    func syncReviewQueues(reason: ReservationAPIRequestReason) async throws {
        let needsReview = try await client.fetchReservations(
            page: 1,
            perPage: 50,
            date: nil,
            from: nil,
            to: nil,
            status: .needsReview,
            search: nil,
            includeHidden: false,
            updatedSince: nil,
            retryCount: 0,
            reason: reason
        ).data

        let newReservations = try await client.fetchReservations(
            page: 1,
            perPage: 50,
            date: nil,
            from: nil,
            to: nil,
            status: .new,
            search: nil,
            includeHidden: false,
            updatedSince: nil,
            retryCount: 0,
            reason: reason
        ).data

        try repository.replaceReviewQueue(with: needsReview + newReservations)
    }

    // MARK: - Local Cache Upsert

    // Intent: Upserts one server DTO already returned by another operation.
    // Network: None; this is cache-only.
    func saveReservation(_ reservation: ReservationDTO) throws {
        try repository.upsert(reservation)
    }

    private func fetchAllReservationPages(
        perPage: Int,
        date: String?,
        from: String?,
        to: String?,
        status: ReservationStatus?,
        search: String?,
        includeHidden: Bool,
        updatedSince: String?,
        reason: ReservationAPIRequestReason
    ) async throws -> (reservations: [ReservationDTO], serverTime: String?) {
        let cappedPerPage = min(max(perPage, 1), 100)
        var currentPage = 1
        var allReservations: [ReservationDTO] = []
        var totalPages = 1
        var latestServerTime: String?

        repeat {
            try Task.checkCancellation()

            let response = try await client.fetchReservations(
                page: currentPage,
                perPage: cappedPerPage,
                date: date,
                from: from,
                to: to,
                status: status,
                search: search,
                includeHidden: includeHidden,
                updatedSince: updatedSince,
                retryCount: 0,
                reason: reason
            )

            allReservations.append(contentsOf: response.data)
            if let serverTime = response.serverTime?.trimmingCharacters(in: .whitespacesAndNewlines),
               !serverTime.isEmpty {
                latestServerTime = serverTime
            }
            totalPages = max(response.totalPages, 1)
            currentPage += 1

            if currentPage <= totalPages {
                await Task.yield()
            }
        } while currentPage <= totalPages

        return (allReservations, latestServerTime)
    }

    private func resolvedSyncCursor(
        serverTime: String?,
        reservations: [ReservationDTO]
    ) -> String? {
        if let serverTime = serverTime?.trimmingCharacters(in: .whitespacesAndNewlines),
           !serverTime.isEmpty {
            return serverTime
        }

        let latestUpdatedAt = reservations
            .compactMap { $0.updatedAt?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .max()
        return latestUpdatedAt?.isEmpty == false ? latestUpdatedAt : nil
    }
}
