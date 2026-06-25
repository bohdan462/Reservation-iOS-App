//
//  GuestProfileSyncService.swift
//  Tryzub Reservations
//

import Foundation
import SwiftData

@MainActor
final class GuestProfileSyncService {
    private let apiClient: any ReservationsAPIClientProtocol
    private let repository: GuestProfileRepository
    private let defaults: UserDefaults

    private let perPage = 100
    private let syncTTL: TimeInterval = 15 * 60
    private let cursorKey = "tryzub.guestProfiles.lastUpdatedSince.v1"
    private let lastAttemptKey = "tryzub.guestProfiles.lastSyncAttemptAt.v1"
    private let lastSuccessKey = "tryzub.guestProfiles.lastSyncSuccessAt.v1"

    init(
        apiClient: any ReservationsAPIClientProtocol,
        repository: GuestProfileRepository = GuestProfileRepository(),
        defaults: UserDefaults = .standard
    ) {
        self.apiClient = apiClient
        self.repository = repository
        self.defaults = defaults
    }

    func syncProfilesIfNeeded(context: ModelContext, force: Bool = false) async {
        if !force, let lastSuccess = lastSuccessDate, Date().timeIntervalSince(lastSuccess) < syncTTL {
            return
        }

        defaults.set(Date().timeIntervalSince1970, forKey: lastAttemptKey)

        let updatedSince = defaults.string(forKey: cursorKey).flatMap(normalizedText)
        var page = 1
        var latestBackendUpdatedAt = updatedSince

        do {
            while !Task.isCancelled {
                let response = try await apiClient.fetchGuestProfiles(
                    query: nil,
                    filter: nil,
                    sort: nil,
                    page: page,
                    perPage: perPage,
                    updatedSince: updatedSince
                )
                let profiles = response.profiles ?? []
                try repository.upsertProfiles(profiles, context: context)

                if let pageLatest = profiles.compactMap(\.updatedAt).max() {
                    latestBackendUpdatedAt = max(latestBackendUpdatedAt ?? pageLatest, pageLatest)
                }

                if shouldStop(response: response, profileCount: profiles.count, page: page) {
                    break
                }

                page += 1
                await Task.yield()
            }

            if let latestBackendUpdatedAt {
                defaults.set(latestBackendUpdatedAt, forKey: cursorKey)
            }
            defaults.set(Date().timeIntervalSince1970, forKey: lastSuccessKey)
        } catch {
            guard !Task.isCancelled else { return }
            #if DEBUG
            print("[GUEST_PROFILE_SYNC] failed: \(error)")
            #endif
        }
    }

    private var lastSuccessDate: Date? {
        let value = defaults.double(forKey: lastSuccessKey)
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    private func shouldStop(
        response: GuestProfileListResponseDTO,
        profileCount: Int,
        page: Int
    ) -> Bool {
        if profileCount < perPage {
            return true
        }
        if let totalPages = response.totalPages, totalPages > 0, page >= totalPages {
            return true
        }
        if let total = response.total, total >= 0, page * perPage >= total {
            return true
        }
        return profileCount == 0
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
