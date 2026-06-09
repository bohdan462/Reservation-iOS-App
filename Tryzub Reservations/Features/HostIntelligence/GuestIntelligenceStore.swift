//
//  GuestIntelligenceStore.swift
//  Tryzub Reservations
//
//  Date-keyed cache for GET /guest-intelligence.
//

import Foundation

@MainActor
final class GuestIntelligenceStore: ObservableObject {
    @Published private(set) var responsesByDateKey: [String: GuestIntelligenceDayResponseDTO] = [:]
    @Published private(set) var loadedAtByDateKey: [String: Date] = [:]
    @Published private(set) var errorByDateKey: [String: String] = [:]

    private var loadingDateKeys: Set<String> = []
    private let apiClient: any ReservationsAPIClientProtocol
    private let freshnessInterval: TimeInterval = 180

    init(apiClient: any ReservationsAPIClientProtocol) {
        self.apiClient = apiClient
    }

    func response(for dateKey: String) -> GuestIntelligenceDayResponseDTO? {
        responsesByDateKey[normalizedDateKey(dateKey)]
    }

    func summariesByReservationID(for dateKey: String) -> [Int: GuestIntelligenceSummaryDTO] {
        let key = normalizedDateKey(dateKey)
        guard let items = responsesByDateKey[key]?.items else { return [:] }
        return Dictionary(
            items.map { ($0.reservationId, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    func isLoading(dateKey: String) -> Bool {
        loadingDateKeys.contains(normalizedDateKey(dateKey))
    }

    func error(for dateKey: String) -> String? {
        errorByDateKey[normalizedDateKey(dateKey)]
    }

    func loadedAt(for dateKey: String) -> Date? {
        loadedAtByDateKey[normalizedDateKey(dateKey)]
    }

    /// Data-only fingerprint for Host pulse refresh keys. Excludes loading/error so pulse
    /// does not re-evaluate until cached guest intelligence actually changes.
    func cacheStamp(for dateKey: String) -> String {
        let key = normalizedDateKey(dateKey)
        let loadedStamp = loadedAtByDateKey[key]?.timeIntervalSince1970 ?? 0
        let response = responsesByDateKey[key]
        let generatedAt = response?.generatedAt ?? ""
        let itemCount = response?.items.count ?? 0
        return "\(key)-\(loadedStamp)-\(generatedAt)-\(itemCount)"
    }

    func load(dateKey: String, force: Bool = false) async {
        let key = normalizedDateKey(dateKey)
        guard !key.isEmpty else { return }
        guard !loadingDateKeys.contains(key) else { return }

        if !force, isFresh(key), responsesByDateKey[key] != nil {
            return
        }

        loadingDateKeys.insert(key)
        defer { loadingDateKeys.remove(key) }

        do {
            let response = try await apiClient.fetchGuestIntelligence(
                date: key,
                reason: .guestIntelligence
            )
            responsesByDateKey[key] = response
            loadedAtByDateKey[key] = Date()
            errorByDateKey.removeValue(forKey: key)
        } catch {
            guard !error.isCancellationLike else { return }
            errorByDateKey[key] = IntelligenceStoreMessaging.displayMessage(for: error)
        }
    }

    func reset() {
        responsesByDateKey = [:]
        loadedAtByDateKey = [:]
        errorByDateKey = [:]
        loadingDateKeys = []
    }

    // MARK: - Private

    private func normalizedDateKey(_ dateKey: String) -> String {
        dateKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isFresh(_ key: String) -> Bool {
        guard let loadedAt = loadedAtByDateKey[key] else { return false }
        return Date().timeIntervalSince(loadedAt) < freshnessInterval
    }
}
