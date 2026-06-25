//
//  GuestLookupStore.swift
//  Tryzub Reservations
//

import Foundation
import SwiftData

// MARK: - Guest Lookup Store

@MainActor
final class GuestLookupStore: ObservableObject {
    @Published private(set) var results: [GuestLookupResult] = []
    @Published private(set) var isSearchActive = false
    @Published private(set) var phoneMatch: GuestLookupResult?

    private var cacheKey: GuestLookupCacheKey?
    private var searchIndex = GuestLookupSearchIndex.empty
    private var searchTask: Task<Void, Never>?
    private var lastExecutedQuery: GuestLookupNormalizedQuery?
    private var lastExecutedPhoneDigits: String?

    func updateCache(records: [ReservationRecord], cacheKey: GuestLookupCacheKey, context: ModelContext? = nil) {
        guard self.cacheKey != cacheKey else { return }
        self.cacheKey = cacheKey
        let cachedProfiles = (try? context.map { try GuestProfileRepository().allCachedProfiles(context: $0) }) ?? []
        searchIndex = GuestLookupSearchIndex.build(from: records, cachedProfiles: cachedProfiles)
    }

    func scheduleSearch(_ query: String) {
        searchTask?.cancel()

        let normalized = GuestLookupNormalizedQuery(query: query)
        guard normalized.isActive else {
            isSearchActive = false
            results = []
            lastExecutedQuery = nil
            return
        }

        if normalized == lastExecutedQuery {
            return
        }

        let index = searchIndex
        let debounce = normalized.debounceMilliseconds

        searchTask = Task {
            if debounce > 0 {
                try? await Task.sleep(for: .milliseconds(debounce))
            }
            guard !Task.isCancelled else { return }

            let matches = await Task.detached(priority: .userInitiated) {
                index.search(normalized)
            }.value

            guard !Task.isCancelled else { return }

            results = matches
            isSearchActive = true
            lastExecutedQuery = normalized
            MultiDeviceSyncTrace.guestLookup(
                query: normalized.raw,
                matched: matches.count,
                firstIDs: matches.map(\.id)
            )
        }
    }

    func updateSearch(_ query: String) {
        scheduleSearch(query)
    }

    func schedulePhoneLookup(_ phoneInput: String) {
        searchTask?.cancel()

        let queryDigits = GuestLookupPhoneNormalizer.digits(phoneInput)
        guard queryDigits.count >= ManualPhoneSuggestTrace.threshold else {
            phoneMatch = nil
            lastExecutedPhoneDigits = nil
            ManualPhoneSuggestTrace.lookup(digits: queryDigits.count, matches: 0, reason: "below_threshold")
            return
        }

        if queryDigits == lastExecutedPhoneDigits {
            return
        }

        let index = searchIndex
        let normalized = GuestLookupNormalizedQuery(query: queryDigits)
        let debounce = normalized.debounceMilliseconds

        searchTask = Task {
            if debounce > 0 {
                try? await Task.sleep(for: .milliseconds(debounce))
            }
            guard !Task.isCancelled else { return }

            let match = await Task.detached(priority: .userInitiated) {
                index.bestPhoneMatch(queryDigits: queryDigits)
            }.value

            guard !Task.isCancelled else { return }

            phoneMatch = match?.result
            lastExecutedPhoneDigits = queryDigits
            ManualPhoneSuggestTrace.lookup(
                digits: queryDigits.count,
                matches: match == nil ? 0 : 1,
                mode: match?.mode,
                reason: match == nil ? "no_normalized_match" : nil
            )
        }
    }
}

// MARK: - Search Index

private struct GuestLookupNormalizedQuery: Equatable {
    let raw: String
    let queryDigits: String
    let normalizedName: String
    let normalizedEmail: String

    init(query: String) {
        raw = GuestLookupNormalizer.collapsedWhitespace(query)
        queryDigits = GuestLookupPhoneNormalizer.digits(raw)
        normalizedName = GuestLookupNormalizer.normalizedName(raw)
        normalizedEmail = GuestLookupNormalizer.normalizedEmail(raw)
    }

    var isActive: Bool {
        queryDigits.count >= 4 || normalizedName.count >= 2
    }

    var debounceMilliseconds: Int {
        if queryDigits.count >= 7 { return 0 }
        if queryDigits.count >= 5 { return 60 }
        if queryDigits.count >= 4 { return 120 }
        if normalizedName.count >= 5 { return 80 }
        if normalizedName.count >= 3 { return 150 }
        return 220
    }
}

private struct GuestLookupSearchIndex {
    let profiles: [GuestLookupProfile]
    let phonePrefixToProfileIndexes: [String: [Int]]

    static let empty = GuestLookupSearchIndex(profiles: [], phonePrefixToProfileIndexes: [:])

    static func build(
        from records: [ReservationRecord],
        cachedProfiles: [GuestProfileCacheRecord] = []
    ) -> GuestLookupSearchIndex {
        let profiles = buildProfiles(from: records, cachedProfiles: cachedProfiles)
        var phonePrefixToProfileIndexes: [String: [Int]] = [:]

        for (index, profile) in profiles.enumerated() {
            guard let phoneDigits = profile.phoneDigits, phoneDigits.count >= 4 else { continue }
            for length in 4...phoneDigits.count {
                let prefix = String(phoneDigits.prefix(length))
                phonePrefixToProfileIndexes[prefix, default: []].append(index)
            }
            if phoneDigits.count >= 4 {
                let suffix = String(phoneDigits.suffix(4))
                phonePrefixToProfileIndexes["s:\(suffix)", default: []].append(index)
            }
        }

        return GuestLookupSearchIndex(
            profiles: profiles,
            phonePrefixToProfileIndexes: phonePrefixToProfileIndexes
        )
    }

    func search(_ query: GuestLookupNormalizedQuery) -> [GuestLookupResult] {
        let candidateProfiles: [GuestLookupProfile]

        if query.queryDigits.count >= 4,
           let indexes = phonePrefixToProfileIndexes[query.queryDigits] {
            var seen = Set<Int>()
            candidateProfiles = indexes.compactMap { index in
                guard seen.insert(index).inserted else { return nil }
                return profiles[index]
            }
        } else {
            candidateProfiles = profiles
        }

        let scoredResults: [GuestLookupScoredResult] = candidateProfiles.compactMap { profile in
            guard let score = profile.score(
                queryDigits: query.queryDigits,
                normalizedName: query.normalizedName,
                normalizedEmail: query.normalizedEmail
            ) else {
                return nil
            }

            return GuestLookupScoredResult(score: score, profile: profile)
        }

        return scoredResults
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score < rhs.score
                }
                if lhs.profile.lastReservationDate != rhs.profile.lastReservationDate {
                    return (lhs.profile.lastReservationDate ?? "") > (rhs.profile.lastReservationDate ?? "")
                }
                if lhs.profile.totalReservations != rhs.profile.totalReservations {
                    return lhs.profile.totalReservations > rhs.profile.totalReservations
                }
                return lhs.profile.displayName.localizedCaseInsensitiveCompare(rhs.profile.displayName) == .orderedAscending
            }
            .prefix(25)
            .map(\.profile.result)
    }

    func bestPhoneMatch(queryDigits: String) -> GuestPhoneLookupMatch? {
        guard queryDigits.count >= ManualPhoneSuggestTrace.threshold else { return nil }

        var candidateIndexes: [Int] = []
        if let indexes = phonePrefixToProfileIndexes[queryDigits] {
            candidateIndexes.append(contentsOf: indexes)
        }
        if queryDigits.count == ManualPhoneSuggestTrace.threshold,
           let suffixIndexes = phonePrefixToProfileIndexes["s:\(queryDigits)"] {
            candidateIndexes.append(contentsOf: suffixIndexes)
        }

        let candidateProfiles: [GuestLookupProfile]
        if !candidateIndexes.isEmpty {
            var seen = Set<Int>()
            candidateProfiles = candidateIndexes.compactMap { index in
                guard seen.insert(index).inserted else { return nil }
                return profiles[index]
            }
        } else {
            candidateProfiles = profiles
        }

        let maxAllowedScore = maxPhoneMatchScore(for: queryDigits)

        let scoredMatches: [GuestPhoneLookupScoredResult] = candidateProfiles.compactMap { profile in
            guard let phoneDigits = profile.phoneDigits,
                  let score = profile.phoneMatchScore(
                      queryDigits: queryDigits,
                      phoneDigits: phoneDigits
                  ),
                  score <= maxAllowedScore else {
                return nil
            }
            return GuestPhoneLookupScoredResult(
                score: score,
                mode: GuestPhoneLookupMatch.mode(
                    queryDigits: queryDigits,
                    phoneDigits: phoneDigits,
                    score: score
                ),
                profile: profile
            )
        }

        guard let best = scoredMatches
            .sorted(by: GuestPhoneLookupScoredResult.preferredOrder)
            .first else {
            return nil
        }

        return GuestPhoneLookupMatch(result: best.profile.result, mode: best.mode)
    }

    private func maxPhoneMatchScore(for queryDigits: String) -> Int {
        if queryDigits.count == ManualPhoneSuggestTrace.threshold {
            // Exact, starts-with, and last-4 only — no weak contains-only matches.
            return 2
        }
        return 3
    }

    private static func buildProfiles(
        from records: [ReservationRecord],
        cachedProfiles: [GuestProfileCacheRecord]
    ) -> [GuestLookupProfile] {
        let visibleRecords = records.filter { !$0.isHidden }
        var profilesByKey: [String: GuestLookupProfileBuilder] = [:]
        var keyByPhone: [String: String] = [:]
        var keyByEmail: [String: String] = [:]

        for record in visibleRecords {
            let normalizedName = GuestLookupNormalizer.normalizedName(record.guestName)
            guard normalizedName.count >= 2 else { continue }

            let phoneDigits = GuestLookupPhoneNormalizer.digits(record.phone).nilIfBlank
            let email = GuestLookupNormalizer.normalizedEmail(record.email).nilIfBlank
            let key: String

            if let phoneDigits, phoneDigits.count >= 7 {
                key = "phone:\(phoneDigits)"
            } else if let email, !email.isManualPlaceholderEmail {
                key = "email:\(email)"
            } else {
                key = "name:\(normalizedName):\(record.remoteID)"
            }

            var builder = profilesByKey[key] ?? GuestLookupProfileBuilder(
                key: key,
                guestKey: nil,
                displayName: GuestLookupNormalizer.displayName(record.guestName),
                normalizedName: normalizedName,
                phoneDigits: phoneDigits,
                email: email?.isManualPlaceholderEmail == true ? nil : email,
                isBackendProfile: false,
                identitySource: .localReservationHistory
            )
            builder.add(record)
            profilesByKey[key] = builder
            if let phoneDigits, phoneDigits.count >= 7 {
                keyByPhone[phoneDigits] = key
            }
            if let email, !email.isManualPlaceholderEmail {
                keyByEmail[email] = key
            }
        }

        for cachedProfile in cachedProfiles {
            let phoneDigits = cachedProfile.normalizedPhone?.nilIfBlank
            let email = cachedProfile.email?.nilIfBlank
            let key = phoneDigits.flatMap { keyByPhone[$0] }
                ?? email.flatMap { keyByEmail[$0] }
                ?? "backend:\(cachedProfile.guestKey)"
            let normalizedName = GuestLookupNormalizer.normalizedName(cachedProfile.displayName)

            var builder = profilesByKey[key] ?? GuestLookupProfileBuilder(
                key: key,
                guestKey: cachedProfile.guestKey,
                displayName: cachedProfile.displayName,
                normalizedName: normalizedName,
                phoneDigits: phoneDigits,
                email: email,
                isBackendProfile: true,
                identitySource: .cachedProfile
            )
            builder.apply(cachedProfile)
            profilesByKey[key] = builder

            if let phoneDigits, phoneDigits.count >= 7 {
                keyByPhone[phoneDigits] = key
            }
            if let email {
                keyByEmail[email] = key
            }
        }

        return profilesByKey.values.map(\.profile)
    }
}

// MARK: - Cache Key

struct GuestLookupCacheKey: Hashable {
    let count: Int
    let maxRemoteID: Int
    let maxUpdatedAt: Date?
    let maxLastSyncedAt: Date?
    let cachedProfileCount: Int
    let maxCachedProfileFetchedAt: Date?
    let maxCachedProfileUpdatedAt: String?

    init(records: [ReservationRecord], cachedProfiles: [GuestProfileCacheRecord] = []) {
        count = records.count
        maxRemoteID = records.map(\.remoteID).max() ?? 0
        maxUpdatedAt = records.compactMap(\.updatedAt).max()
        maxLastSyncedAt = records.map(\.lastSyncedAt).max()
        cachedProfileCount = cachedProfiles.count
        maxCachedProfileFetchedAt = cachedProfiles.map(\.fetchedAt).max()
        maxCachedProfileUpdatedAt = cachedProfiles.compactMap(\.backendUpdatedAt).max()
    }
}

// MARK: - Private Profiles

private struct GuestLookupScoredResult {
    let score: Int
    let profile: GuestLookupProfile
}

private struct GuestPhoneLookupMatch {
    let result: GuestLookupResult
    let mode: String

    static func mode(queryDigits: String, phoneDigits: String, score: Int) -> String {
        switch score {
        case 0:
            return "exact"
        case 1:
            return "prefix"
        case 2:
            return "last4"
        case 3:
            return "contains"
        default:
            if phoneDigits == queryDigits { return "exact" }
            if phoneDigits.hasPrefix(queryDigits) { return "prefix" }
            if queryDigits.count == ManualPhoneSuggestTrace.threshold,
               phoneDigits.hasSuffix(queryDigits) {
                return "last4"
            }
            return "contains"
        }
    }
}

private struct GuestPhoneLookupScoredResult {
    let score: Int
    let mode: String
    let profile: GuestLookupProfile

    static func preferredOrder(lhs: GuestPhoneLookupScoredResult, rhs: GuestPhoneLookupScoredResult) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score < rhs.score
        }
        if lhs.profile.lastReservationDate != rhs.profile.lastReservationDate {
            return (lhs.profile.lastReservationDate ?? "") > (rhs.profile.lastReservationDate ?? "")
        }
        if lhs.profile.totalReservations != rhs.profile.totalReservations {
            return lhs.profile.totalReservations > rhs.profile.totalReservations
        }
        return lhs.profile.displayName.localizedCaseInsensitiveCompare(rhs.profile.displayName) == .orderedAscending
    }
}

private struct GuestLookupProfile {
    let key: String
    let guestKey: String?
    let displayName: String
    let normalizedName: String
    let phoneDigits: String?
    let email: String?
    let lastReservationDate: String?
    let totalReservations: Int
    let latestGuestNotes: String?
    let latestStaffNotes: String?
    let labelSummary: String?
    let summaryLine: String?
    let hasDietaryNote: Bool
    let isRegularGuest: Bool
    let isBackendProfile: Bool
    let identitySource: GuestLookupIdentitySource
    let matchBasis: GuestProfileLookupMatchBasis?
    let matchConfidence: GuestProfileLookupMatchConfidence?

    var result: GuestLookupResult {
        GuestLookupResult(
            id: key,
            guestKey: guestKey,
            displayName: displayName,
            phoneDigits: phoneDigits,
            email: email,
            lastReservationDate: lastReservationDate,
            totalReservations: totalReservations,
            latestGuestNotes: latestGuestNotes,
            latestStaffNotes: latestStaffNotes,
            labelSummary: labelSummary,
            summaryLine: summaryLine,
            hasDietaryNote: hasDietaryNote,
            isRegularGuest: isRegularGuest,
            isBackendProfile: isBackendProfile,
            identitySource: identitySource,
            matchBasis: matchBasis,
            matchConfidence: matchConfidence
        )
    }

    func score(queryDigits: String, normalizedName: String, normalizedEmail: String) -> Int? {
        if !queryDigits.isEmpty, let phoneDigits {
            if let phoneScore = phoneMatchScore(queryDigits: queryDigits, phoneDigits: phoneDigits) {
                return phoneScore
            }
        }

        if normalizedEmail.count >= 3,
           let email,
           email.contains(normalizedEmail) {
            return 10
        }

        if normalizedName.count >= 2,
           self.normalizedName.contains(normalizedName) {
            return 11
        }

        return nil
    }

    /// Lower score = stronger phone match.
    func phoneMatchScore(queryDigits: String, phoneDigits: String) -> Int? {
        guard queryDigits.count >= ManualPhoneSuggestTrace.threshold else { return nil }

        if phoneDigits == queryDigits {
            return 0
        }
        if phoneDigits.hasPrefix(queryDigits) {
            return 1
        }
        if queryDigits.count == ManualPhoneSuggestTrace.threshold,
           phoneDigits.hasSuffix(queryDigits) {
            return 2
        }
        if phoneDigits.contains(queryDigits) {
            return 3
        }
        return nil
    }
}

private struct GuestLookupProfileBuilder {
    let key: String
    var guestKey: String?
    var displayName: String
    var normalizedName: String
    var phoneDigits: String?
    var email: String?
    var lastReservationDate: String?
    var totalReservations = 0
    var latestGuestNotes: String?
    var latestStaffNotes: String?
    var labelSummary: String?
    var summaryLine: String?
    var hasDietaryNote = false
    var isRegularGuest = false
    var isBackendProfile = false
    var identitySource: GuestLookupIdentitySource = .localReservationHistory
    var matchBasis: GuestProfileLookupMatchBasis?
    var matchConfidence: GuestProfileLookupMatchConfidence?

    mutating func add(_ record: ReservationRecord) {
        totalReservations += 1

        let recordDate = record.reservationDate
        if lastReservationDate == nil || recordDate > (lastReservationDate ?? "") {
            lastReservationDate = recordDate
            latestGuestNotes = record.guestNotes?.nilIfBlank
            latestStaffNotes = record.staffNotes?.nilIfBlank

            let name = GuestLookupNormalizer.displayName(record.guestName)
            if !name.isEmpty {
                displayName = name
                normalizedName = GuestLookupNormalizer.normalizedName(name)
            }

            let digits = GuestLookupPhoneNormalizer.digits(record.phone).nilIfBlank
            if let digits {
                phoneDigits = digits
            }

            let normalizedEmail = GuestLookupNormalizer.normalizedEmail(record.email).nilIfBlank
            if let normalizedEmail, !normalizedEmail.isManualPlaceholderEmail {
                email = normalizedEmail
            }
        }
    }

    mutating func apply(_ cachedProfile: GuestProfileCacheRecord) {
        isBackendProfile = true
        guestKey = cachedProfile.guestKey
        identitySource = .cachedProfile
        displayName = cachedProfile.displayName
        normalizedName = GuestLookupNormalizer.normalizedName(cachedProfile.displayName)
        if let digits = cachedProfile.normalizedPhone?.nilIfBlank {
            phoneDigits = digits
        }
        if let email = cachedProfile.email?.nilIfBlank {
            self.email = email
        }
        if let lastSeenDate = cachedProfile.lastSeenDate?.nilIfBlank {
            lastReservationDate = max(lastReservationDate ?? lastSeenDate, lastSeenDate)
        }
        totalReservations = max(totalReservations, cachedProfile.totalReservations)
        latestGuestNotes = cachedProfile.latestGuestNotePreview?.nilIfBlank ?? latestGuestNotes
        latestStaffNotes = cachedProfile.latestStaffNotePreview?.nilIfBlank ?? latestStaffNotes
        labelSummary = cachedProfile.topLabelTitles?.nilIfBlank ?? labelSummary
        summaryLine = cachedProfile.summaryLine?.nilIfBlank ?? summaryLine
        hasDietaryNote = hasDietaryNote || cachedProfile.hasDietaryNote
        isRegularGuest = isRegularGuest || cachedProfile.isLikelyRegular
    }

    var profile: GuestLookupProfile {
        GuestLookupProfile(
            key: key,
            guestKey: guestKey,
            displayName: displayName,
            normalizedName: normalizedName,
            phoneDigits: phoneDigits,
            email: email,
            lastReservationDate: lastReservationDate,
            totalReservations: totalReservations,
            latestGuestNotes: latestGuestNotes,
            latestStaffNotes: latestStaffNotes,
            labelSummary: labelSummary,
            summaryLine: summaryLine,
            hasDietaryNote: hasDietaryNote,
            isRegularGuest: isRegularGuest,
            isBackendProfile: isBackendProfile,
            identitySource: identitySource,
            matchBasis: matchBasis,
            matchConfidence: matchConfidence
        )
    }
}

private enum GuestLookupNormalizer {
    static func collapsedWhitespace(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func normalizedName(_ value: String) -> String {
        collapsedWhitespace(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func displayName(_ value: String) -> String {
        collapsedWhitespace(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func phoneDigits(_ value: String) -> String {
        GuestLookupPhoneNormalizer.digits(value)
    }

    static func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
