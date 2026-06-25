//
//  GuestProfileStore.swift
//  Tryzub Reservations
//
//  Parallel cache for precomputed backend guest profile aggregates.
//

import Foundation
import SwiftData

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

struct GuestProfileLookupResult: Equatable {
    let candidates: [GuestProfileLookupCandidate]
    let bestMatchGuestKey: String?
    let bestMatchBasis: GuestProfileLookupMatchBasis?
    let bestMatchConfidence: GuestProfileLookupMatchConfidence?
}

struct GuestProfileLookupCandidate: Identifiable, Equatable {
    let profile: GuestProfileDTO
    let matchBasis: GuestProfileLookupMatchBasis
    let matchConfidence: GuestProfileLookupMatchConfidence

    var id: String {
        profile.guestKey ?? profile.id
    }

    var guestKey: String? {
        profile.guestKey
    }

    var lookupResult: GuestLookupResult {
        GuestLookupResult(
            id: "backend:\(id)",
            guestKey: guestKey,
            displayName: profile.primaryName?.nilIfBlank ?? "Guest",
            phoneDigits: profile.primaryPhone.map(GuestLookupPhoneNormalizer.digits)?.nilIfBlank,
            email: profile.primaryEmail?.nilIfBlank,
            lastReservationDate: profile.lastSeenDate ?? profile.lastBookedAt,
            totalReservations: profile.totalReservations ?? profile.totalBookingCount ?? 0,
            latestGuestNotes: nil,
            latestStaffNotes: nil,
            labelSummary: profile.labels?.compactMap { $0.title?.nilIfBlank }.prefix(3).joined(separator: ", ").nilIfBlank,
            summaryLine: profile.summary?.summaryText?.nilIfBlank,
            hasDietaryNote: profile.noteFlags?.hasDietaryNote == true
                || profile.labels?.contains { label in
                    let text = [label.id, label.title, label.detail]
                        .compactMap { $0?.lowercased() }
                        .joined(separator: " ")
                    return text.contains("dietary") || text.contains("allerg")
                } == true,
            isRegularGuest: (profile.cleanVisitCount ?? profile.cleanPastVisitCount ?? 0) >= 3
                || profile.labels?.contains { label in
                    let text = [label.id, label.title]
                        .compactMap { $0?.lowercased() }
                        .joined(separator: " ")
                    return text.contains("regular")
                } == true,
            isBackendProfile: true,
            identitySource: .backendLookup,
            matchBasis: matchBasis,
            matchConfidence: matchConfidence,
            nextReservation: profile.nextReservation.map {
                GuestLookupNextReservationSummary(
                    date: $0.date ?? $0.reservationDate,
                    time: $0.time ?? $0.reservationTime,
                    partySize: $0.partySize,
                    status: $0.status,
                    tableName: $0.tableName
                )
            }
        )
    }

    var isStrongBackendMatch: Bool {
        lookupResult.isStrongBackendMatch
    }

    var requiresStaffConfirmation: Bool {
        lookupResult.requiresStaffConfirmation
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

    private struct GuestProfileLookupRequestKey: Hashable {
        let phone: String
        let email: String
        let query: String
        let limit: Int
    }

    private struct GuestProfileLookupInFlight {
        let id = UUID()
        let task: Task<GuestProfileLookupResult, Error>
    }

    private var profileByReservationID: [Int: CachedGuestProfile] = [:]
    private var profileByGuestKey: [String: CachedGuestProfile] = [:]
    private var listCache: [GuestProfileListCacheKey: GuestProfileListCacheEntry] = [:]
    private var listTasksByKey: [GuestProfileListCacheKey: Task<GuestProfileListResponseDTO, Error>] = [:]
    private var lookupTasksByKey: [GuestProfileLookupRequestKey: GuestProfileLookupInFlight] = [:]
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

    func cachedFullProfile(byReservationID reservationID: Int) -> GuestFullProfile? {
        cachedProfile(byReservationID: reservationID)?.fullProfile
    }

    func cachedFullProfile(guestKey: String) -> GuestFullProfile? {
        cachedProfile(guestKey: guestKey)?.fullProfile
    }

    func loadProfiles(
        query: String?,
        filter: GuestProfileFilter?,
        sort: GuestProfileSort?,
        page: Int = 1,
        perPage: Int = 25,
        context: ModelContext? = nil
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
            writeProfilesToDisk(response.profiles ?? [], context: context)
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

    func loadProfile(
        byReservationID reservationID: Int,
        force: Bool = false,
        context: ModelContext? = nil
    ) async -> GuestProfileDTO? {
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
            return await self.fetchProfile(byReservationID: reservationID, force: force, context: context)
        }

        detailTasksByReservationID[reservationID] = task
        isLoadingDetail = true
        defer {
            detailTasksByReservationID.removeValue(forKey: reservationID)
            refreshDetailLoadingState()
        }

        return await task.value
    }

    func loadProfile(
        guestKey: String,
        force: Bool = false,
        context: ModelContext? = nil
    ) async -> GuestProfileDTO? {
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
            return await self.fetchProfile(guestKey: normalizedKey, force: force, context: context)
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
        lookupTasksByKey.values.forEach { $0.task.cancel() }
        lookupTasksByKey = [:]
        isLoadingDetail = false
    }

    func loadCachedProfiles(context: ModelContext, limit: Int = 100) throws -> [GuestProfileCacheRecord] {
        var descriptor = FetchDescriptor<GuestProfileCacheRecord>(
            sortBy: [
                SortDescriptor(\.cleanVisitCount, order: .reverse),
                SortDescriptor(\.totalReservations, order: .reverse),
                SortDescriptor(\.fetchedAt, order: .reverse)
            ]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func cachedProfile(guestKey: String, context: ModelContext) throws -> GuestProfileCacheRecord? {
        try GuestProfileRepository().cachedProfile(guestKey: guestKey, context: context)
    }

    func searchCachedProfiles(
        query: String,
        limit: Int = 12,
        context: ModelContext
    ) throws -> [GuestProfileCacheRecord] {
        try GuestProfileRepository().searchProfiles(query: query, limit: limit, context: context)
    }

    func lookupProfiles(
        phone: String? = nil,
        email: String? = nil,
        query: String? = nil,
        limit: Int = 5,
        context: ModelContext
    ) async throws -> GuestProfileLookupResult {
        let requestKey = GuestProfileLookupRequestKey(
            phone: phone.map(GuestLookupPhoneNormalizer.digits) ?? "",
            email: normalizedQueryValue(email).lowercased(),
            query: normalizedQueryValue(query),
            limit: min(10, max(1, limit))
        )
        guard !requestKey.phone.isEmpty || !requestKey.email.isEmpty || !requestKey.query.isEmpty else {
            throw ReservationAPIError.invalidURL
        }

        if let inFlight = lookupTasksByKey[requestKey] {
            return try await inFlight.task.value
        }

        let task = Task<GuestProfileLookupResult, Error> { [apiClient] in
            let response = try await apiClient.fetchGuestProfileLookup(
                phone: requestKey.phone.isEmpty ? nil : requestKey.phone,
                email: requestKey.email.isEmpty ? nil : requestKey.email,
                query: requestKey.query.isEmpty ? nil : requestKey.query,
                limit: requestKey.limit
            )
            return GuestProfileLookupResult(
                candidates: response.profiles.map { candidate in
                    GuestProfileLookupCandidate(
                        profile: candidate.profile,
                        matchBasis: candidate.matchBasis,
                        matchConfidence: candidate.matchConfidence
                    )
                },
                bestMatchGuestKey: response.bestMatchGuestKey,
                bestMatchBasis: response.bestMatchBasis,
                bestMatchConfidence: response.bestMatchConfidence
            )
        }
        let inFlight = GuestProfileLookupInFlight(task: task)
        lookupTasksByKey[requestKey] = inFlight

        do {
            let result = try await task.value
            clearLookupTask(id: inFlight.id, for: requestKey)
            let profiles = result.candidates.map(\.profile)
            if !profiles.isEmpty {
                try GuestProfileRepository().upsertProfiles(profiles, context: context)
            }
            cacheListProfiles(result.candidates.map(\.profile))
            return result
        } catch {
            clearLookupTask(id: inFlight.id, for: requestKey)
            throw error
        }
    }

    // MARK: - Private

    private var listUnavailableMessage: String {
        "Guest history unavailable."
    }

    private var detailUnavailableMessage: String {
        "Guest history unavailable."
    }

    private func clearLookupTask(
        id: UUID,
        for key: GuestProfileLookupRequestKey
    ) {
        guard lookupTasksByKey[key]?.id == id else { return }
        lookupTasksByKey.removeValue(forKey: key)
    }

    private func adoptListResponse(_ response: GuestProfileListResponseDTO) {
        let profiles = response.profiles ?? []
        listProfiles = profiles
        listPage = max(1, response.page ?? 1)
        listTotal = max(0, response.total ?? profiles.count)
        listTotalPages = max(0, response.totalPages ?? 0)
        hasLoadedList = true
    }

    private func fetchProfile(
        byReservationID reservationID: Int,
        force: Bool,
        context: ModelContext?
    ) async -> GuestProfileDTO? {
        if !force, let cached = cachedEntry(forReservationID: reservationID), isFresh(cached.loadedAt) {
            detailErrorMessage = nil
            return cached.profile
        }

        do {
            let profile = try await apiClient.fetchGuestProfile(byReservationID: reservationID)
            adoptProfile(profile)
            writeProfileToDisk(profile, hasDetailPayload: true, context: context)
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

    private func fetchProfile(
        guestKey: String,
        force: Bool,
        context: ModelContext?
    ) async -> GuestProfileDTO? {
        if !force, let cached = cachedEntry(forGuestKey: guestKey), isFresh(cached.loadedAt) {
            detailErrorMessage = nil
            return cached.profile
        }

        do {
            let profile = try await apiClient.fetchGuestProfile(guestKey: guestKey)
            adoptProfile(profile)
            writeProfileToDisk(profile, hasDetailPayload: true, context: context)
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

    private func writeProfilesToDisk(_ profiles: [GuestProfileDTO], context: ModelContext?) {
        guard let context, !profiles.isEmpty else { return }
        do {
            try GuestProfileRepository().upsertProfiles(profiles, context: context)
        } catch {
            #if DEBUG
            print("[GUEST_PROFILE_CACHE] list write failed: \(error)")
            #endif
        }
    }

    private func writeProfileToDisk(
        _ profile: GuestProfileDTO,
        hasDetailPayload: Bool,
        context: ModelContext?
    ) {
        guard let context else { return }
        do {
            try GuestProfileRepository().upsertProfile(profile, hasDetailPayload: hasDetailPayload, context: context)
        } catch {
            #if DEBUG
            print("[GUEST_PROFILE_CACHE] detail write failed: \(error)")
            #endif
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
