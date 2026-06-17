//
//  GuestProfileStore.swift
//  Tryzub Reservations
//
//  Parallel cache for precomputed backend guest profile aggregates.
//

import Foundation

enum GuestProfileFilter: String, CaseIterable, Identifiable {
    case all
    case regular
    case upcoming
    case notes
    case needsReview

    var id: String { rawValue }

    var apiValue: String? {
        switch self {
        case .all, .needsReview:
            // needsReview falls back to backend default until a dedicated aggregate filter exists.
            return nil
        case .regular:
            return "regular"
        case .upcoming:
            return "upcoming"
        case .notes:
            return "notes"
        }
    }
}

enum GuestProfileSort: String, CaseIterable, Identifiable {
    case lastSeen
    case visitCount
    case upcoming
    case name

    var id: String { rawValue }

    var apiValue: String? {
        switch self {
        case .lastSeen, .name:
            // name falls back to backend default until a dedicated name sort exists.
            return nil
        case .visitCount:
            return "most_reservations"
        case .upcoming:
            return "upcoming"
        }
    }
}

@MainActor
final class GuestProfileStore: ObservableObject {
    @Published private(set) var listProfiles: [GuestProfileDTO] = []
    @Published private(set) var listPage: Int = 1
    @Published private(set) var listTotal: Int = 0
    @Published private(set) var listTotalPages: Int = 0
    @Published private(set) var isLoadingList = false
    @Published private(set) var hasLoadedList = false
    @Published private(set) var listErrorMessage: String?
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var detailErrorMessage: String?

    private struct CachedGuestProfile {
        let profile: GuestProfileDTO
        let loadedAt: Date
    }

    private struct GuestProfileListCacheKey: Hashable {
        let query: String
        let filter: String?
        let sort: String?
        let page: Int
        let perPage: Int
    }

    private struct GuestProfileListCacheEntry {
        let response: GuestProfileListResponseDTO
        let loadedAt: Date
    }

    private var profileByReservationID: [Int: CachedGuestProfile] = [:]
    private var profileByGuestKey: [String: CachedGuestProfile] = [:]
    private var listCache: [GuestProfileListCacheKey: GuestProfileListCacheEntry] = [:]
    private var listTasksByKey: [GuestProfileListCacheKey: Task<GuestProfileListResponseDTO, Error>] = [:]
    private var currentListRequestKey: GuestProfileListCacheKey?
    private var detailTasksByReservationID: [Int: Task<GuestProfileDTO?, Never>] = [:]
    private var detailTasksByGuestKey: [String: Task<GuestProfileDTO?, Never>] = [:]

    private let apiClient: any ReservationsAPIClientProtocol
    private let freshnessInterval: TimeInterval = 180

    init(apiClient: any ReservationsAPIClientProtocol) {
        self.apiClient = apiClient
    }

    func cachedProfile(byReservationID reservationID: Int) -> GuestProfileDTO? {
        cachedEntry(forReservationID: reservationID)?.profile
    }

    func cachedProfile(guestKey: String) -> GuestProfileDTO? {
        cachedEntry(forGuestKey: guestKey)?.profile
    }

    func loadProfiles(
        query: String?,
        filter: GuestProfileFilter?,
        sort: GuestProfileSort?,
        page: Int = 1,
        perPage: Int = 25
    ) async {
        let normalizedQuery = normalizedQueryValue(query)
        let normalizedPage = max(1, page)
        let normalizedPerPage = min(100, max(1, perPage))
        let cacheKey = GuestProfileListCacheKey(
            query: normalizedQuery,
            filter: filter?.apiValue,
            sort: sort?.apiValue,
            page: normalizedPage,
            perPage: normalizedPerPage
        )
        currentListRequestKey = cacheKey

        if let cached = listCache[cacheKey], isFresh(cached.loadedAt) {
            adoptListResponse(cached.response)
            listErrorMessage = nil
            refreshListLoadingState()
            return
        }

        isLoadingList = true
        listErrorMessage = nil
        let task: Task<GuestProfileListResponseDTO, Error>
        if let existingTask = listTasksByKey[cacheKey] {
            task = existingTask
        } else {
            task = Task<GuestProfileListResponseDTO, Error> { [apiClient] in
                try await apiClient.fetchGuestProfiles(
                    query: normalizedQuery.isEmpty ? nil : normalizedQuery,
                    filter: filter?.apiValue,
                    sort: sort?.apiValue,
                    page: normalizedPage,
                    perPage: normalizedPerPage
                )
            }
            listTasksByKey[cacheKey] = task
        }

        do {
            let response = try await task.value
            listCache[cacheKey] = GuestProfileListCacheEntry(
                response: response,
                loadedAt: Date()
            )
            cacheListProfiles(response.profiles ?? [])
            if currentListRequestKey == cacheKey {
                adoptListResponse(response)
                listErrorMessage = nil
            }
        } catch {
            if currentListRequestKey == cacheKey {
                guard !error.isCancellationLike else {
                    listTasksByKey.removeValue(forKey: cacheKey)
                    refreshListLoadingState()
                    return
                }
                listErrorMessage = listUnavailableMessage
            }
        }

        listTasksByKey.removeValue(forKey: cacheKey)
        refreshListLoadingState()
    }

    func loadProfile(byReservationID reservationID: Int, force: Bool = false) async -> GuestProfileDTO? {
        guard reservationID > 0 else { return nil }

        if !force, let cached = cachedEntry(forReservationID: reservationID), isFresh(cached.loadedAt) {
            detailErrorMessage = nil
            return cached.profile
        }

        if let existingTask = detailTasksByReservationID[reservationID], !force {
            isLoadingDetail = true
            defer { refreshDetailLoadingState() }
            return await existingTask.value
        }

        let task = Task<GuestProfileDTO?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.fetchProfile(byReservationID: reservationID, force: force)
        }

        detailTasksByReservationID[reservationID] = task
        isLoadingDetail = true
        defer {
            detailTasksByReservationID.removeValue(forKey: reservationID)
            refreshDetailLoadingState()
        }

        return await task.value
    }

    func loadProfile(guestKey: String, force: Bool = false) async -> GuestProfileDTO? {
        guard let normalizedKey = normalizedGuestKey(guestKey), !normalizedKey.isEmpty else { return nil }

        if !force, let cached = cachedEntry(forGuestKey: normalizedKey), isFresh(cached.loadedAt) {
            detailErrorMessage = nil
            return cached.profile
        }

        if let existingTask = detailTasksByGuestKey[normalizedKey], !force {
            isLoadingDetail = true
            defer { refreshDetailLoadingState() }
            return await existingTask.value
        }

        let task = Task<GuestProfileDTO?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.fetchProfile(guestKey: normalizedKey, force: force)
        }

        detailTasksByGuestKey[normalizedKey] = task
        isLoadingDetail = true
        defer {
            detailTasksByGuestKey.removeValue(forKey: normalizedKey)
            refreshDetailLoadingState()
        }

        return await task.value
    }

    func resetList() {
        listProfiles = []
        listPage = 1
        listTotal = 0
        listTotalPages = 0
        hasLoadedList = false
        listErrorMessage = nil
        listTasksByKey.values.forEach { $0.cancel() }
        listTasksByKey = [:]
        currentListRequestKey = nil
        isLoadingList = false
        listCache = [:]
    }

    func reset() {
        resetList()
        profileByReservationID = [:]
        profileByGuestKey = [:]
        detailErrorMessage = nil
        detailTasksByReservationID.values.forEach { $0.cancel() }
        detailTasksByGuestKey.values.forEach { $0.cancel() }
        detailTasksByReservationID = [:]
        detailTasksByGuestKey = [:]
        isLoadingDetail = false
    }

    // MARK: - Private

    private var listUnavailableMessage: String {
        "Guest profiles unavailable."
    }

    private var detailUnavailableMessage: String {
        "Guest profile unavailable."
    }

    private func adoptListResponse(_ response: GuestProfileListResponseDTO) {
        let profiles = response.profiles ?? []
        listProfiles = profiles
        listPage = max(1, response.page ?? 1)
        listTotal = max(0, response.total ?? profiles.count)
        listTotalPages = max(0, response.totalPages ?? 0)
        hasLoadedList = true
    }

    private func fetchProfile(byReservationID reservationID: Int, force: Bool) async -> GuestProfileDTO? {
        if !force, let cached = cachedEntry(forReservationID: reservationID), isFresh(cached.loadedAt) {
            detailErrorMessage = nil
            return cached.profile
        }

        do {
            let profile = try await apiClient.fetchGuestProfile(byReservationID: reservationID)
            adoptProfile(profile)
            detailErrorMessage = nil
            return profile
        } catch {
            guard !error.isCancellationLike else { return nil }
            if isNotFound(error) {
                detailErrorMessage = detailUnavailableMessage
                return nil
            }
            detailErrorMessage = detailUnavailableMessage
            return cachedEntry(forReservationID: reservationID)?.profile
        }
    }

    private func fetchProfile(guestKey: String, force: Bool) async -> GuestProfileDTO? {
        if !force, let cached = cachedEntry(forGuestKey: guestKey), isFresh(cached.loadedAt) {
            detailErrorMessage = nil
            return cached.profile
        }

        do {
            let profile = try await apiClient.fetchGuestProfile(guestKey: guestKey)
            adoptProfile(profile)
            detailErrorMessage = nil
            return profile
        } catch {
            guard !error.isCancellationLike else { return nil }
            if isNotFound(error) {
                detailErrorMessage = detailUnavailableMessage
                return nil
            }
            detailErrorMessage = detailUnavailableMessage
            return cachedEntry(forGuestKey: guestKey)?.profile
        }
    }

    private func adoptProfile(_ profile: GuestProfileDTO) {
        let now = Date()
        let entry = CachedGuestProfile(profile: profile, loadedAt: now)
        if let guestKey = normalizedGuestKey(profile.guestKey), !guestKey.isEmpty {
            profileByGuestKey[guestKey] = entry
        }

        if let reservationID = resolvedReservationID(from: profile) {
            profileByReservationID[reservationID] = entry
        }
    }

    private func cacheListProfiles(_ profiles: [GuestProfileDTO]) {
        let now = Date()
        for profile in profiles {
            let entry = CachedGuestProfile(profile: profile, loadedAt: now)
            if let guestKey = normalizedGuestKey(profile.guestKey), !guestKey.isEmpty {
                profileByGuestKey[guestKey] = entry
            }
            if let reservationID = resolvedReservationID(from: profile) {
                profileByReservationID[reservationID] = entry
            }
        }
    }

    private func cachedEntry(forReservationID reservationID: Int) -> CachedGuestProfile? {
        profileByReservationID[reservationID]
    }

    private func cachedEntry(forGuestKey guestKey: String) -> CachedGuestProfile? {
        guard let normalizedKey = normalizedGuestKey(guestKey), !normalizedKey.isEmpty else { return nil }
        return profileByGuestKey[normalizedKey]
    }

    private func resolvedReservationID(from profile: GuestProfileDTO) -> Int? {
        let candidates = [
            profile.nextReservation?.id,
            profile.nextReservation?.reservationId
        ]
        for candidate in candidates {
            if let candidate, candidate > 0 {
                return candidate
            }
        }
        return nil
    }

    private func isFresh(_ loadedAt: Date) -> Bool {
        Date().timeIntervalSince(loadedAt) < freshnessInterval
    }

    private func normalizedGuestKey(_ guestKey: String?) -> String? {
        guard let guestKey else { return nil }
        return guestKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedQueryValue(_ query: String?) -> String {
        query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func refreshDetailLoadingState() {
        isLoadingDetail = !detailTasksByReservationID.isEmpty || !detailTasksByGuestKey.isEmpty
    }

    private func refreshListLoadingState() {
        guard let currentListRequestKey else {
            isLoadingList = false
            return
        }
        isLoadingList = listTasksByKey[currentListRequestKey] != nil
    }

    private func isNotFound(_ error: Error) -> Bool {
        if case ReservationAPIError.serverError(let code, _) = error, code == 404 {
            return true
        }
        return false
    }
}
