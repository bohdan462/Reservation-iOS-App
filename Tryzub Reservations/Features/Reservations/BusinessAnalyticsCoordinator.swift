//
//  BusinessAnalyticsCoordinator.swift
//  Tryzub Reservations
//
//  Range-aware, debounced, cache-first loading for Business Analytics.
//

import Foundation

@MainActor
final class BusinessAnalyticsCoordinator: ObservableObject {
    @Published private(set) var selectedRange: AnalyticsRangeOption = .thisMonth
    @Published private(set) var reservationSummary: ReservationAnalyticsSummaryDTO?
    @Published private(set) var isReservationLoading = false
    @Published private(set) var isEnrichmentLoading = false
    @Published private(set) var reservationError: String?
    @Published private(set) var enrichmentWarning: String?

    private let settingsStore: RestaurantSettingsStore
    private let businessIntelligenceStore: BusinessIntelligenceStore
    private let intelligenceSystemStatusStore: IntelligenceSystemStatusStore

    private var debounceTask: Task<Void, Never>?
    private var activeLoadTask: Task<Void, Never>?
    private var loadGeneration: UInt = 0
    private let debounceInterval: TimeInterval = 0.4
    private let freshnessInterval: TimeInterval = 600

    init(
        settingsStore: RestaurantSettingsStore,
        businessIntelligenceStore: BusinessIntelligenceStore,
        intelligenceSystemStatusStore: IntelligenceSystemStatusStore
    ) {
        self.settingsStore = settingsStore
        self.businessIntelligenceStore = businessIntelligenceStore
        self.intelligenceSystemStatusStore = intelligenceSystemStatusStore
    }

    var selectedRangeKey: AnalyticsRangeKey {
        AnalyticsRangeKey(mode: selectedRange)
    }

    var businessIntelligenceSummary: BusinessIntelligenceSummaryDTO? {
        let key = selectedRangeKey
        return businessIntelligenceStore.response(from: key.intelligenceFrom, to: key.intelligenceTo)
    }

    var intelligenceSystemStatus: IntelligenceSystemStatusDTO? {
        let key = selectedRangeKey
        return intelligenceSystemStatusStore.response(from: key.intelligenceFrom, to: key.intelligenceTo)
    }

    var isScreenVisible = false {
        didSet {
            if isScreenVisible {
                applyCachedDisplay(for: selectedRangeKey)
                scheduleLoad(force: false)
            } else {
                cancelPendingWork(reason: "screen_hidden")
            }
        }
    }

    func setSelectedRange(_ range: AnalyticsRangeOption) {
        guard range != selectedRange else { return }
        let previousKey = AnalyticsRangeKey(mode: selectedRange)
        AnalyticsTrace.cancelled(range: previousKey, reason: "range_changed")
        businessIntelligenceStore.cancelLoad(from: previousKey.intelligenceFrom, to: previousKey.intelligenceTo)
        intelligenceSystemStatusStore.cancelLoad(from: previousKey.intelligenceFrom, to: previousKey.intelligenceTo)
        activeLoadTask?.cancel()
        activeLoadTask = nil
        loadGeneration &+= 1
        selectedRange = range
        applyCachedDisplay(for: selectedRangeKey)
        scheduleLoad(force: false)
    }

    func refresh(force: Bool = true) {
        scheduleLoad(force: force, debounce: false)
    }

    func cancelPendingWork(reason: String) {
        if debounceTask != nil {
            debounceTask?.cancel()
            debounceTask = nil
        }
        if activeLoadTask != nil {
            activeLoadTask?.cancel()
            activeLoadTask = nil
            AnalyticsTrace.cancelled(range: selectedRangeKey, reason: reason)
        }
        let key = selectedRangeKey
        businessIntelligenceStore.cancelLoad(from: key.intelligenceFrom, to: key.intelligenceTo)
        intelligenceSystemStatusStore.cancelLoad(from: key.intelligenceFrom, to: key.intelligenceTo)
        loadGeneration &+= 1
        isReservationLoading = false
        isEnrichmentLoading = false
    }

    func scheduleLoad(force: Bool, debounce: Bool = true) {
        guard isScreenVisible else { return }

        debounceTask?.cancel()
        let rangeKey = selectedRangeKey
        let delayMilliseconds = debounce ? Int(debounceInterval * 1000) : 0
        AnalyticsTrace.scheduled(range: rangeKey, delayMilliseconds: delayMilliseconds)

        debounceTask = Task { [weak self] in
            guard let self else { return }
            if debounce {
                try? await Task.sleep(for: .seconds(self.debounceInterval))
            }
            guard !Task.isCancelled else { return }
            self.debounceTask = nil
            await self.loadSelectedRange(force: force)
        }
    }

    private func loadSelectedRange(force: Bool) async {
        activeLoadTask?.cancel()
        loadGeneration &+= 1
        let generation = loadGeneration
        let rangeKey = selectedRangeKey

        if !force,
           let cached = settingsStore.cachedReservationAnalytics(for: rangeKey),
           settingsStore.isReservationAnalyticsFresh(for: rangeKey, interval: freshnessInterval) {
            reservationSummary = cached
            reservationError = nil
            AnalyticsTrace.displayCached(range: rangeKey, fresh: true)
            await loadEnrichmentIfNeeded(rangeKey: rangeKey, generation: generation, force: false)
            return
        }

        if let cached = settingsStore.cachedReservationAnalytics(for: rangeKey) {
            reservationSummary = cached
            AnalyticsTrace.displayCached(range: rangeKey, fresh: false)
        } else {
            AnalyticsTrace.cacheMiss(range: rangeKey)
        }

        activeLoadTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.loadReservationAnalytics(rangeKey: rangeKey, generation: generation, force: force)
            guard !Task.isCancelled, generation == self.loadGeneration else {
                AnalyticsTrace.ignoredResponse(range: rangeKey, reason: "not_selected")
                return
            }
            await self.loadEnrichmentIfNeeded(rangeKey: rangeKey, generation: generation, force: force)
        }
        await activeLoadTask?.value
        activeLoadTask = nil
    }

    private func loadReservationAnalytics(
        rangeKey: AnalyticsRangeKey,
        generation: UInt,
        force: Bool
    ) async {
        guard generation == loadGeneration else { return }

        isReservationLoading = reservationSummary == nil
        reservationError = nil
        AnalyticsTrace.start(range: rangeKey, endpoint: "reservation_analytics")

        do {
            let summary = try await settingsStore.loadReservationAnalyticsSummary(
                for: rangeKey,
                force: force,
                freshnessInterval: freshnessInterval
            )
            guard !Task.isCancelled, generation == loadGeneration else {
                AnalyticsTrace.ignoredResponse(range: rangeKey, reason: "not_selected")
                return
            }
            reservationSummary = summary
            reservationError = nil
            AnalyticsTrace.end(range: rangeKey, endpoint: "reservation_analytics")
        } catch {
            guard !Task.isCancelled, generation == loadGeneration else {
                AnalyticsTrace.ignoredResponse(range: rangeKey, reason: "not_selected")
                return
            }
            if error.isCancellationLike {
                AnalyticsTrace.cancelled(range: rangeKey, reason: "task_cancelled")
                return
            }
            if reservationSummary == nil {
                reservationError = error.localizedDescription
            }
            AnalyticsTrace.fail(
                range: rangeKey,
                endpoint: "reservation_analytics",
                timeout: error.isTimeoutLike,
                keepReservationAnalytics: reservationSummary != nil
            )
        }

        isReservationLoading = false
    }

    private func loadEnrichmentIfNeeded(
        rangeKey: AnalyticsRangeKey,
        generation: UInt,
        force: Bool
    ) async {
        guard generation == loadGeneration else { return }
        guard reservationSummary != nil else { return }

        isEnrichmentLoading = true
        enrichmentWarning = nil
        defer {
            if generation == loadGeneration {
                isEnrichmentLoading = false
            }
        }

        AnalyticsTrace.start(
            range: rangeKey,
            endpoint: "business_intelligence",
            enrichment: true
        )

        await businessIntelligenceStore.load(
            from: rangeKey.intelligenceFrom,
            to: rangeKey.intelligenceTo,
            force: force,
            freshnessInterval: freshnessInterval
        )

        guard !Task.isCancelled, generation == loadGeneration else {
            AnalyticsTrace.ignoredResponse(range: rangeKey, reason: "not_selected")
            return
        }

        if let error = businessIntelligenceStore.error(
            from: rangeKey.intelligenceFrom,
            to: rangeKey.intelligenceTo
        ) {
            enrichmentWarning = businessIntelligenceSummary == nil
                ? "Advanced insight delayed. Core reservation analytics are available."
                : nil
            AnalyticsTrace.fail(
                range: rangeKey,
                endpoint: "business_intelligence",
                timeout: error.localizedCaseInsensitiveContains("timed out")
                    || error.localizedCaseInsensitiveContains("time out"),
                keepReservationAnalytics: reservationSummary != nil
            )
        } else if businessIntelligenceSummary != nil {
            AnalyticsTrace.end(range: rangeKey, endpoint: "business_intelligence")
            await loadSystemStatusIfNeeded(rangeKey: rangeKey, generation: generation, force: force)
        }
    }

    private func loadSystemStatusIfNeeded(
        rangeKey: AnalyticsRangeKey,
        generation: UInt,
        force: Bool
    ) async {
        guard generation == loadGeneration else { return }
        guard businessIntelligenceSummary != nil else { return }

        AnalyticsTrace.start(range: rangeKey, endpoint: "intelligence_system_status", enrichment: true)
        await intelligenceSystemStatusStore.load(
            from: rangeKey.intelligenceFrom,
            to: rangeKey.intelligenceTo,
            force: force,
            freshnessInterval: freshnessInterval
        )

        guard !Task.isCancelled, generation == loadGeneration else {
            AnalyticsTrace.ignoredResponse(range: rangeKey, reason: "not_selected")
            return
        }

        if intelligenceSystemStatus != nil {
            AnalyticsTrace.end(range: rangeKey, endpoint: "intelligence_system_status")
        }
    }

    private func applyCachedDisplay(for rangeKey: AnalyticsRangeKey) {
        reservationSummary = settingsStore.cachedReservationAnalytics(for: rangeKey)
        reservationError = nil
        enrichmentWarning = nil
        if reservationSummary != nil {
            let fresh = settingsStore.isReservationAnalyticsFresh(
                for: rangeKey,
                interval: freshnessInterval
            )
            AnalyticsTrace.displayCached(range: rangeKey, fresh: fresh)
        }
    }
}

private extension Error {
    var isTimeoutLike: Bool {
        let nsError = self as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut {
            return true
        }
        return localizedDescription.localizedCaseInsensitiveContains("timed out")
    }
}
