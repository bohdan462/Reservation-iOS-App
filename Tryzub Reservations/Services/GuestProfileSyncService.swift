//
//  GuestProfileSyncService.swift
//  Tryzub Reservations
//

import Foundation
import SwiftData

struct GuestProfileSyncMetadata {
    let lastSyncAttemptAt: Date?
    let lastSyncSuccessAt: Date?
    let lastUpdatedSince: String?
    let fullListSyncCompleted: Bool
    let lastFullListSyncAt: Date?
    let backendProfileTotal: Int?
    let cachedProfileCount: Int
    let lastSyncFailureReason: String?
}

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
    private let fullListSyncCompletedKey = "tryzub.guestProfiles.fullListSyncCompleted.v1"
    private let lastFullListSyncAtKey = "tryzub.guestProfiles.lastFullListSyncAt.v1"
    private let backendProfileTotalKey = "tryzub.guestProfiles.backendProfileTotal.v1"
    private let cachedProfileCountKey = "tryzub.guestProfiles.cachedProfileCount.v1"
    private let lastFailureReasonKey = "tryzub.guestProfiles.lastSyncFailureReason.v1"

    init(
        apiClient: any ReservationsAPIClientProtocol,
        repository: GuestProfileRepository = GuestProfileRepository(),
        defaults: UserDefaults = .standard
    ) {
        self.apiClient = apiClient
        self.repository = repository
        self.defaults = defaults
    }

    var metadata: GuestProfileSyncMetadata {
        GuestProfileSyncMetadata(
            lastSyncAttemptAt: date(forKey: lastAttemptKey),
            lastSyncSuccessAt: date(forKey: lastSuccessKey),
            lastUpdatedSince: defaults.string(forKey: cursorKey).flatMap(normalizedText),
            fullListSyncCompleted: defaults.bool(forKey: fullListSyncCompletedKey),
            lastFullListSyncAt: date(forKey: lastFullListSyncAtKey),
            backendProfileTotal: defaults.object(forKey: backendProfileTotalKey) as? Int,
            cachedProfileCount: defaults.integer(forKey: cachedProfileCountKey),
            lastSyncFailureReason: defaults.string(forKey: lastFailureReasonKey).flatMap(normalizedText)
        )
    }

    func syncProfilesIfNeeded(context: ModelContext, force: Bool = false) async {
        let fullListSyncCompleted = defaults.bool(forKey: fullListSyncCompletedKey)
        if fullListSyncCompleted,
           !force,
           let lastSuccess = lastSuccessDate,
           Date().timeIntervalSince(lastSuccess) < syncTTL {
            return
        }

        defaults.set(Date().timeIntervalSince1970, forKey: lastAttemptKey)

        let updatedSince = fullListSyncCompleted
            ? defaults.string(forKey: cursorKey).flatMap(normalizedText)
            : nil
        let isFullListSync = updatedSince == nil
        var page = 1
        var latestBackendUpdatedAt = updatedSince
        var backendProfileTotal: Int?

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
                if isFullListSync, let total = response.total, total >= 0 {
                    backendProfileTotal = total
                }

                if let pageLatest = profiles.compactMap(\.updatedAt).max() {
                    latestBackendUpdatedAt = max(latestBackendUpdatedAt ?? pageLatest, pageLatest)
                }

                if shouldStop(response: response, profileCount: profiles.count, page: page) {
                    break
                }

                page += 1
                await Task.yield()
            }

            guard !Task.isCancelled else { return }
            let cachedCount = try repository.cacheCount(context: context)
            if let latestBackendUpdatedAt {
                defaults.set(latestBackendUpdatedAt, forKey: cursorKey)
            }
            let successAt = Date()
            defaults.set(successAt.timeIntervalSince1970, forKey: lastSuccessKey)
            defaults.set(cachedCount, forKey: cachedProfileCountKey)
            defaults.removeObject(forKey: lastFailureReasonKey)
            if isFullListSync {
                defaults.set(successAt.timeIntervalSince1970, forKey: lastFullListSyncAtKey)
                if let backendProfileTotal {
                    defaults.set(backendProfileTotal, forKey: backendProfileTotalKey)
                    defaults.set(cachedCount >= backendProfileTotal, forKey: fullListSyncCompletedKey)
                } else {
                    defaults.removeObject(forKey: backendProfileTotalKey)
                    defaults.set(false, forKey: fullListSyncCompletedKey)
                }
            } else if fullListSyncCompleted {
                if let knownTotal = defaults.object(forKey: backendProfileTotalKey) as? Int,
                   cachedCount < knownTotal {
                    defaults.set(false, forKey: fullListSyncCompletedKey)
                } else {
                    defaults.set(true, forKey: fullListSyncCompletedKey)
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            defaults.set(syncFailureReason(from: error), forKey: lastFailureReasonKey)
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

    private func date(forKey key: String) -> Date? {
        let value = defaults.double(forKey: key)
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

    private func syncFailureReason(from error: Error) -> String {
        let raw = String(describing: error).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "Unknown error" }
        return String(raw.prefix(240))
    }
}
