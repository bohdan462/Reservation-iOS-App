//
//  ReservationActivityStore.swift
//  Tryzub Reservations
//
//  On-demand activity history cache. Never blocks first render.
//

import Foundation
import OSLog

enum ReservationActivityStoreTrace {
    #if DEBUG
    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "ReservationActivity"
    )
    #endif

    static func store(scope: String, id: String, decision: String, reason: String) {
        #if DEBUG
        logger.debug(
            "[ACTIVITY_STORE_TRACE] scope=\(scope, privacy: .public) id=\(id, privacy: .public) decision=\(decision, privacy: .public) reason=\(reason, privacy: .public)"
        )
        #endif
    }
}

enum ReservationActivityAPITrace {
    #if DEBUG
    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "ReservationActivity"
    )
    #endif

    static func start(endpoint: String, detail: String) {
        #if DEBUG
        logger.debug("[ACTIVITY_API_TRACE] endpoint=\(endpoint, privacy: .public) \(detail, privacy: .public) status=start")
        #endif
    }

    static func completed(endpoint: String, detail: String, count: Int, durationMs: Int) {
        #if DEBUG
        logger.debug(
            "[ACTIVITY_API_TRACE] endpoint=\(endpoint, privacy: .public) \(detail, privacy: .public) status=completed count=\(count, privacy: .public) durationMs=\(durationMs, privacy: .public)"
        )
        #endif
    }
}

enum ReservationActivityDetailTrace {
    #if DEBUG
    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "ReservationActivity"
    )
    #endif

    static func loaded(reservationID: Int, count: Int) {
        #if DEBUG
        logger.debug(
            "[ACTIVITY_DETAIL_TRACE] reservation=\(reservationID, privacy: .public) status=loaded count=\(count, privacy: .public)"
        )
        #endif
    }

    static func empty(reservationID: Int) {
        #if DEBUG
        logger.debug(
            "[ACTIVITY_DETAIL_TRACE] reservation=\(reservationID, privacy: .public) status=empty reason=no_backend_history"
        )
        #endif
    }
}

private struct ReservationActivityCacheEntry: Equatable {
    var items: [ReservationActivityItemViewState]
    var total: Int
    var page: Int
    var totalPages: Int
    var loadedAt: Date
    var isStale: Bool = false
}

private struct ActivityFeedCacheEntry: Equatable {
    var items: [ReservationActivityItemViewState]
    var summaryChips: [ReservationActivitySummaryChip]
    var total: Int
    var page: Int
    var totalPages: Int
    var loadedAt: Date
    var isStale: Bool = false
}

@MainActor
final class ReservationActivityStore: ObservableObject {
    @Published private(set) var reservationLoadStateByID: [Int: ActivityLoadState] = [:]
    @Published private(set) var feedLoadStateByDateKey: [String: ActivityLoadState] = [:]
    @Published private(set) var feedSummaryChipsByDateKey: [String: [ReservationActivitySummaryChip]] = [:]
    @Published private(set) var feedPaginationByDateKey: [String: (page: Int, totalPages: Int, total: Int)] = [:]

    private var reservationCache: [Int: ReservationActivityCacheEntry] = [:]
    private var feedCache: [String: ActivityFeedCacheEntry] = [:]
    private var inFlightReservationIDs: Set<Int> = []
    private var inFlightFeedDateKeys: Set<String> = []
    private var invalidationTask: Task<Void, Never>?

    private let apiClient: any ReservationsAPIClientProtocol
    private let cacheTTL: TimeInterval = 90

    init(apiClient: any ReservationsAPIClientProtocol) {
        self.apiClient = apiClient
        invalidationTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: ReservationActivityInvalidation.notification
            ) {
                self?.handleInvalidation(notification)
            }
        }
    }

    deinit {
        invalidationTask?.cancel()
    }

    // MARK: - Reservation scope

    func loadState(for reservationID: Int) -> ActivityLoadState {
        reservationLoadStateByID[reservationID] ?? .idle
    }

    func previewItems(for reservationID: Int, limit: Int = 5) -> [ReservationActivityItemViewState] {
        guard let cache = reservationCache[reservationID] else { return [] }
        return Array(cache.items.prefix(limit))
    }

    func allItems(for reservationID: Int) -> [ReservationActivityItemViewState] {
        reservationCache[reservationID]?.items ?? []
    }

    func reservationPagination(for reservationID: Int) -> (page: Int, totalPages: Int, total: Int)? {
        guard let cache = reservationCache[reservationID] else { return nil }
        return (cache.page, cache.totalPages, cache.total)
    }

    func loadReservationActivity(
        reservationID: Int,
        page: Int = 1,
        perPage: Int = 25,
        force: Bool = false
    ) async {
        if inFlightReservationIDs.contains(reservationID) {
            ReservationActivityStoreTrace.store(
                scope: "reservation",
                id: "\(reservationID)",
                decision: "join_in_flight",
                reason: "already_loading"
            )
            return
        }

        if !force,
           let cache = reservationCache[reservationID],
           !cache.isStale,
           Date().timeIntervalSince(cache.loadedAt) < cacheTTL,
           page == 1 {
            reservationLoadStateByID[reservationID] = cache.items.isEmpty ? .empty : .loaded(cache.items)
            ReservationActivityStoreTrace.store(
                scope: "reservation",
                id: "\(reservationID)",
                decision: "use_cache",
                reason: "fresh"
            )
            return
        }

        ReservationActivityStoreTrace.store(
            scope: "reservation",
            id: "\(reservationID)",
            decision: "fetch",
            reason: force ? "manual_refresh" : "first_load"
        )

        inFlightReservationIDs.insert(reservationID)
        if page == 1 {
            reservationLoadStateByID[reservationID] = .loading
        }

        defer { inFlightReservationIDs.remove(reservationID) }

        let startedAt = Date()
        ReservationActivityAPITrace.start(
            endpoint: "reservation",
            detail: "reservation=\(reservationID) page=\(page)"
        )

        do {
            let response = try await apiClient.fetchReservationActivity(
                reservationID: reservationID,
                page: page,
                perPage: perPage
            )
            let items = ReservationActivityViewStateBuilder.items(from: response.data)
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            ReservationActivityAPITrace.completed(
                endpoint: "reservation",
                detail: "reservation=\(reservationID)",
                count: response.data.count,
                durationMs: durationMs
            )

            let merged: [ReservationActivityItemViewState]
            if page > 1, let existing = reservationCache[reservationID]?.items {
                let existingIDs = Set(existing.map(\.id))
                merged = existing + items.filter { !existingIDs.contains($0.id) }
            } else {
                merged = items
            }

            reservationCache[reservationID] = ReservationActivityCacheEntry(
                items: merged,
                total: response.total,
                page: response.page,
                totalPages: response.totalPages,
                loadedAt: Date(),
                isStale: false
            )

            if merged.isEmpty {
                reservationLoadStateByID[reservationID] = .empty
                ReservationActivityDetailTrace.empty(reservationID: reservationID)
            } else {
                reservationLoadStateByID[reservationID] = .loaded(merged)
                ReservationActivityDetailTrace.loaded(reservationID: reservationID, count: merged.count)
            }
        } catch {
            let message = ReservationActivityViewStateBuilder.staffSafeErrorMessage(from: error)
            if page == 1 {
                reservationLoadStateByID[reservationID] = .failed(message)
            }
        }
    }

    // MARK: - Feed scope

    func feedState(for date: Date) -> ActivityLoadState {
        feedLoadStateByDateKey[normalizedDateKey(date)] ?? .idle
    }

    func feedItems(for date: Date) -> [ReservationActivityItemViewState] {
        feedCache[normalizedDateKey(date)]?.items ?? []
    }

    func feedSummaryChips(for date: Date) -> [ReservationActivitySummaryChip] {
        feedSummaryChipsByDateKey[normalizedDateKey(date)] ?? []
    }

    func loadActivityFeed(
        date: Date,
        page: Int = 1,
        perPage: Int = 50,
        force: Bool = false,
        guestNameByReservationID: [Int: String] = [:]
    ) async {
        let dateKey = normalizedDateKey(date)

        if inFlightFeedDateKeys.contains(dateKey) {
            ReservationActivityStoreTrace.store(
                scope: "date",
                id: dateKey,
                decision: "join_in_flight",
                reason: "already_loading"
            )
            return
        }

        if !force,
           let cache = feedCache[dateKey],
           !cache.isStale,
           Date().timeIntervalSince(cache.loadedAt) < cacheTTL,
           page == 1 {
            feedLoadStateByDateKey[dateKey] = cache.items.isEmpty ? .empty : .loaded(cache.items)
            feedSummaryChipsByDateKey[dateKey] = cache.summaryChips
            feedPaginationByDateKey[dateKey] = (cache.page, cache.totalPages, cache.total)
            ReservationActivityStoreTrace.store(
                scope: "date",
                id: dateKey,
                decision: "use_cache",
                reason: "fresh"
            )
            return
        }

        ReservationActivityStoreTrace.store(
            scope: "date",
            id: dateKey,
            decision: "fetch",
            reason: force ? "manual_refresh" : "visible"
        )

        inFlightFeedDateKeys.insert(dateKey)
        if page == 1 {
            feedLoadStateByDateKey[dateKey] = .loading
        }

        defer { inFlightFeedDateKeys.remove(dateKey) }

        let startedAt = Date()
        ReservationActivityAPITrace.start(
            endpoint: "feed",
            detail: "date=\(dateKey) page=\(page)"
        )

        do {
            let response = try await apiClient.fetchActivityFeed(
                date: date,
                page: page,
                perPage: perPage
            )
            let items = ReservationActivityViewStateBuilder.items(
                from: response.data,
                guestNameByReservationID: guestNameByReservationID,
                includeGuestContext: true
            )
            let chips = ReservationActivityViewStateBuilder.summaryChips(from: response.summary)
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            ReservationActivityAPITrace.completed(
                endpoint: "feed",
                detail: "date=\(dateKey)",
                count: response.data.count,
                durationMs: durationMs
            )

            let merged: [ReservationActivityItemViewState]
            if page > 1, let existing = feedCache[dateKey]?.items {
                let existingIDs = Set(existing.map(\.id))
                merged = existing + items.filter { !existingIDs.contains($0.id) }
            } else {
                merged = items
            }

            feedCache[dateKey] = ActivityFeedCacheEntry(
                items: merged,
                summaryChips: chips,
                total: response.total,
                page: response.page,
                totalPages: response.totalPages,
                loadedAt: Date(),
                isStale: false
            )
            feedSummaryChipsByDateKey[dateKey] = chips
            feedPaginationByDateKey[dateKey] = (response.page, response.totalPages, response.total)
            feedLoadStateByDateKey[dateKey] = merged.isEmpty ? .empty : .loaded(merged)
        } catch {
            let message = ReservationActivityViewStateBuilder.staffSafeErrorMessage(from: error)
            if page == 1 {
                feedLoadStateByDateKey[dateKey] = .failed(message)
            }
        }
    }

    // MARK: - Invalidation

    func markReservationStale(_ reservationID: Int) {
        reservationCache[reservationID]?.isStale = true
    }

    func markFeedStale(for dateKey: String) {
        feedCache[dateKey]?.isStale = true
    }

    private func handleInvalidation(_ notification: Notification) {
        guard let reservationID = notification.userInfo?[ReservationActivityInvalidation.UserInfoKey.reservationID] as? Int else {
            return
        }
        markReservationStale(reservationID)
        if let date = notification.userInfo?[ReservationActivityInvalidation.UserInfoKey.date] as? String {
            markFeedStale(for: date)
        }
    }

    private func normalizedDateKey(_ date: Date) -> String {
        date.reservationDateString()
    }
}
