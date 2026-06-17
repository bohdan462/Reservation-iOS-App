//
//  BusinessIntelligenceStore.swift
//  Tryzub Reservations
//
//  Range-keyed cache for GET /business-intelligence/summary.
//

import Foundation

@MainActor
final class BusinessIntelligenceStore: ObservableObject {
    @Published private(set) var responsesByRangeKey: [String: BusinessIntelligenceSummaryDTO] = [:]
    @Published private(set) var loadedAtByRangeKey: [String: Date] = [:]
    @Published private(set) var errorByRangeKey: [String: String] = [:]
    @Published private(set) var timeoutRangeKeys: Set<String> = []

    private var loadingRangeKeys: Set<String> = []
    private var activeTasksByRangeKey: [String: Task<Void, Never>] = [:]
    private let apiClient: any ReservationsAPIClientProtocol
    private let freshnessInterval: TimeInterval = 600

    init(apiClient: any ReservationsAPIClientProtocol) {
        self.apiClient = apiClient
    }

    func rangeKey(from: String, to: String) -> String {
        Self.makeRangeKey(from: from, to: to)
    }

    func response(from: String, to: String) -> BusinessIntelligenceSummaryDTO? {
        responsesByRangeKey[rangeKey(from: from, to: to)]
    }

    func isLoading(from: String, to: String) -> Bool {
        loadingRangeKeys.contains(rangeKey(from: from, to: to))
    }

    func error(from: String, to: String) -> String? {
        errorByRangeKey[rangeKey(from: from, to: to)]
    }

    func isTimeout(from: String, to: String) -> Bool {
        timeoutRangeKeys.contains(rangeKey(from: from, to: to))
    }

    func loadedAt(from: String, to: String) -> Date? {
        loadedAtByRangeKey[rangeKey(from: from, to: to)]
    }

    func dailyCacheKey(from: String, to: String, date: Date = Date(), calendar: Calendar = .current) -> String {
        let dateKey = ReservationFormatters.reservationDateKey.string(from: calendar.startOfDay(for: date))
        let rangeComponent = rangeKey(from: from, to: to).replacingOccurrences(of: "|", with: ".")
        return "businessIntelligenceSummary.\(rangeComponent).\(dateKey)"
    }

    func hasFreshDailyCache(from: String, to: String, calendar: Calendar = .current) -> Bool {
        let key = rangeKey(from: from, to: to)
        guard responsesByRangeKey[key] != nil, let loadedAt = loadedAtByRangeKey[key] else { return false }
        return calendar.isDateInToday(loadedAt)
    }

    func cachedToday(from: String, to: String, calendar: Calendar = .current) -> BusinessIntelligenceSummaryDTO? {
        guard hasFreshDailyCache(from: from, to: to, calendar: calendar) else { return nil }
        return response(from: from, to: to)
    }

    /// Data-only fingerprint for future UI refresh keys.
    func cacheStamp(from: String, to: String) -> String {
        let key = rangeKey(from: from, to: to)
        let loadedStamp = loadedAtByRangeKey[key]?.timeIntervalSince1970 ?? 0
        let response = responsesByRangeKey[key]
        let generatedAt = response?.generatedAt ?? ""
        let reservationCount = response?.summary.totalReservations ?? 0
        return "\(key)-\(loadedStamp)-\(generatedAt)-\(reservationCount)"
    }

    func load(
        from: String,
        to: String,
        force: Bool = false,
        freshnessInterval: TimeInterval? = nil
    ) async {
        let key = rangeKey(from: from, to: to)
        guard !key.isEmpty, key != "|" else { return }
        let dailyKey = dailyCacheKey(from: from, to: to)

        if !force, hasFreshDailyCache(from: from, to: to) {
            AnalyticsTrace.businessIntelligenceCache(event: "daily_cache_hit", key: dailyKey)
            errorByRangeKey.removeValue(forKey: key)
            timeoutRangeKeys.remove(key)
            return
        }

        if responsesByRangeKey[key] != nil {
            AnalyticsTrace.businessIntelligenceCache(event: "daily_cache_stale", key: dailyKey)
        } else {
            AnalyticsTrace.businessIntelligenceCache(event: "daily_cache_miss", key: dailyKey)
        }

        if let activeTask = activeTasksByRangeKey[key], !force {
            await activeTask.value
            return
        }

        activeTasksByRangeKey[key]?.cancel()
        errorByRangeKey.removeValue(forKey: key)
        timeoutRangeKeys.remove(key)
        let task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.performLoad(
                key: key,
                from: from,
                to: to
            )
        }
        activeTasksByRangeKey[key] = task
        await task.value
        if activeTasksByRangeKey[key] != nil {
            activeTasksByRangeKey[key] = nil
        }
    }

    func cancelLoad(from: String, to: String) {
        let key = rangeKey(from: from, to: to)
        activeTasksByRangeKey[key]?.cancel()
        activeTasksByRangeKey[key] = nil
        loadingRangeKeys.remove(key)
    }

    func clearError(from: String, to: String) {
        let key = rangeKey(from: from, to: to)
        errorByRangeKey.removeValue(forKey: key)
        timeoutRangeKeys.remove(key)
    }

    func reset() {
        activeTasksByRangeKey.values.forEach { $0.cancel() }
        activeTasksByRangeKey = [:]
        responsesByRangeKey = [:]
        loadedAtByRangeKey = [:]
        errorByRangeKey = [:]
        timeoutRangeKeys = []
        loadingRangeKeys = []
    }

    private func performLoad(key: String, from: String, to: String) async {
        guard !loadingRangeKeys.contains(key) else { return }

        loadingRangeKeys.insert(key)
        defer { loadingRangeKeys.remove(key) }

        let trimmedFrom = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTo = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFrom.isEmpty, !trimmedTo.isEmpty else { return }

        do {
            AnalyticsTrace.businessIntelligenceCache(
                event: "business_intelligence_fetch_started",
                key: dailyCacheKey(from: trimmedFrom, to: trimmedTo)
            )
            let response = try await apiClient.fetchBusinessIntelligenceSummary(
                from: trimmedFrom,
                to: trimmedTo,
                reason: .businessIntelligenceSummary
            )
            guard !Task.isCancelled else { return }
            responsesByRangeKey[key] = response
            loadedAtByRangeKey[key] = Date()
            errorByRangeKey.removeValue(forKey: key)
            timeoutRangeKeys.remove(key)
            AnalyticsTrace.businessIntelligenceCache(
                event: "business_intelligence_fetch_succeeded",
                key: dailyCacheKey(from: trimmedFrom, to: trimmedTo)
            )
        } catch {
            guard !error.isCancellationLike else { return }
            errorByRangeKey[key] = IntelligenceStoreMessaging.displayMessage(for: error)
            if error.isTimeoutLike {
                timeoutRangeKeys.insert(key)
                AnalyticsTrace.businessIntelligenceCache(
                    event: "business_intelligence_fetch_timeout",
                    key: dailyCacheKey(from: trimmedFrom, to: trimmedTo)
                )
            } else {
                timeoutRangeKeys.remove(key)
                AnalyticsTrace.businessIntelligenceCache(
                    event: "business_intelligence_fetch_failed",
                    key: dailyCacheKey(from: trimmedFrom, to: trimmedTo)
                )
            }
        }
    }

    // MARK: - Private

    private static func makeRangeKey(from: String, to: String) -> String {
        let trimmedFrom = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTo = to.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(trimmedFrom)|\(trimmedTo)"
    }

    private func isFresh(_ key: String, interval: TimeInterval? = nil) -> Bool {
        guard let loadedAt = loadedAtByRangeKey[key] else { return false }
        return Date().timeIntervalSince(loadedAt) < (interval ?? freshnessInterval)
    }
}

private extension Error {
    var isTimeoutLike: Bool {
        let nsError = self as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut {
            return true
        }
        if let urlError = self as? URLError {
            return urlError.code == .timedOut
        }
        if let reservationError = self as? ReservationAPIError,
           case .networkFailure(let urlError) = reservationError {
            return urlError.code == .timedOut
        }
        return localizedDescription.localizedCaseInsensitiveContains("timed out")
    }
}
