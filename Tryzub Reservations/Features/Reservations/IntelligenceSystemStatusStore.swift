//
//  IntelligenceSystemStatusStore.swift
//  Tryzub Reservations
//
//  Range-keyed cache for GET /intelligence/system-status.
//

import Foundation

@MainActor
final class IntelligenceSystemStatusStore: ObservableObject {
    @Published private(set) var responsesByRangeKey: [String: IntelligenceSystemStatusDTO] = [:]
    @Published private(set) var loadedAtByRangeKey: [String: Date] = [:]
    @Published private(set) var errorByRangeKey: [String: String] = [:]

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

    func response(from: String, to: String) -> IntelligenceSystemStatusDTO? {
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
        let checkCount = response?.checks.count ?? 0
        return "\(key)-\(loadedStamp)-\(generatedAt)-\(checkCount)"
    }

    func load(
        from: String,
        to: String,
        force: Bool = false,
        freshnessInterval: TimeInterval? = nil
    ) async {
        let key = rangeKey(from: from, to: to)
        guard !key.isEmpty, key != "|" else { return }

        let interval = freshnessInterval ?? self.freshnessInterval
        if !force, isFresh(key, interval: interval), responsesByRangeKey[key] != nil {
            return
        }

        activeTasksByRangeKey[key]?.cancel()
        let task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.performLoad(key: key, from: from, to: to)
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

    func reset() {
        activeTasksByRangeKey.values.forEach { $0.cancel() }
        activeTasksByRangeKey = [:]
        responsesByRangeKey = [:]
        loadedAtByRangeKey = [:]
        errorByRangeKey = [:]
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
            let response = try await apiClient.fetchIntelligenceSystemStatus(
                from: trimmedFrom,
                to: trimmedTo,
                reason: .intelligenceSystemStatus
            )
            guard !Task.isCancelled else { return }
            responsesByRangeKey[key] = response
            loadedAtByRangeKey[key] = Date()
            errorByRangeKey.removeValue(forKey: key)
        } catch {
            guard !error.isCancellationLike else { return }
            errorByRangeKey[key] = IntelligenceStoreMessaging.displayMessage(for: error)
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
