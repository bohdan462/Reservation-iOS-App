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

    private var loadingRangeKeys: Set<String> = []
    private let apiClient: any ReservationsAPIClientProtocol
    private let freshnessInterval: TimeInterval = 300

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

    func loadedAt(from: String, to: String) -> Date? {
        loadedAtByRangeKey[rangeKey(from: from, to: to)]
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

    func load(from: String, to: String, force: Bool = false) async {
        let key = rangeKey(from: from, to: to)
        guard !key.isEmpty, key != "|" else { return }
        guard !loadingRangeKeys.contains(key) else { return }

        if !force, isFresh(key), responsesByRangeKey[key] != nil {
            return
        }

        loadingRangeKeys.insert(key)
        defer { loadingRangeKeys.remove(key) }

        let trimmedFrom = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTo = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFrom.isEmpty, !trimmedTo.isEmpty else { return }

        do {
            let response = try await apiClient.fetchBusinessIntelligenceSummary(
                from: trimmedFrom,
                to: trimmedTo,
                reason: .businessIntelligenceSummary
            )
            responsesByRangeKey[key] = response
            loadedAtByRangeKey[key] = Date()
            errorByRangeKey.removeValue(forKey: key)
        } catch {
            guard !error.isCancellationLike else { return }
            errorByRangeKey[key] = IntelligenceStoreMessaging.displayMessage(for: error)
        }
    }

    func reset() {
        responsesByRangeKey = [:]
        loadedAtByRangeKey = [:]
        errorByRangeKey = [:]
        loadingRangeKeys = []
    }

    // MARK: - Private

    private static func makeRangeKey(from: String, to: String) -> String {
        let trimmedFrom = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTo = to.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(trimmedFrom)|\(trimmedTo)"
    }

    private func isFresh(_ key: String) -> Bool {
        guard let loadedAt = loadedAtByRangeKey[key] else { return false }
        return Date().timeIntervalSince(loadedAt) < freshnessInterval
    }
}
