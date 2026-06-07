//
//  GuestLookupStore.swift
//  Tryzub Reservations
//

import Foundation

// MARK: - Guest Lookup Store

@MainActor
final class GuestLookupStore: ObservableObject {
    @Published private(set) var results: [GuestLookupResult] = []
    @Published private(set) var isSearchActive = false

    private var cacheKey: GuestLookupCacheKey?
    private var searchIndex = GuestLookupSearchIndex.empty
    private var searchTask: Task<Void, Never>?
    private var lastExecutedQuery: GuestLookupNormalizedQuery?

    func updateCache(records: [ReservationRecord], cacheKey: GuestLookupCacheKey) {
        guard self.cacheKey != cacheKey else { return }
        self.cacheKey = cacheKey
        searchIndex = GuestLookupSearchIndex.build(from: records)
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
        }
    }

    func updateSearch(_ query: String) {
        scheduleSearch(query)
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
        queryDigits = GuestLookupNormalizer.phoneDigits(raw)
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

    static func build(from records: [ReservationRecord]) -> GuestLookupSearchIndex {
        let profiles = buildProfiles(from: records)
        var phonePrefixToProfileIndexes: [String: [Int]] = [:]

        for (index, profile) in profiles.enumerated() {
            guard let phoneDigits = profile.phoneDigits, phoneDigits.count >= 4 else { continue }
            for length in 4...phoneDigits.count {
                let prefix = String(phoneDigits.prefix(length))
                phonePrefixToProfileIndexes[prefix, default: []].append(index)
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

    private static func buildProfiles(from records: [ReservationRecord]) -> [GuestLookupProfile] {
        let visibleRecords = records.filter { !$0.isHidden }
        var profilesByKey: [String: GuestLookupProfileBuilder] = [:]

        for record in visibleRecords {
            let normalizedName = GuestLookupNormalizer.normalizedName(record.guestName)
            guard normalizedName.count >= 2 else { continue }

            let phoneDigits = GuestLookupNormalizer.phoneDigits(record.phone).nilIfBlank
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
                displayName: GuestLookupNormalizer.displayName(record.guestName),
                normalizedName: normalizedName,
                phoneDigits: phoneDigits,
                email: email?.isManualPlaceholderEmail == true ? nil : email
            )
            builder.add(record)
            profilesByKey[key] = builder
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

    init(records: [ReservationRecord]) {
        count = records.count
        maxRemoteID = records.map(\.remoteID).max() ?? 0
        maxUpdatedAt = records.compactMap(\.updatedAt).max()
        maxLastSyncedAt = records.map(\.lastSyncedAt).max()
    }
}

// MARK: - Private Profiles

private struct GuestLookupScoredResult {
    let score: Int
    let profile: GuestLookupProfile
}

private struct GuestLookupProfile {
    let key: String
    let displayName: String
    let normalizedName: String
    let phoneDigits: String?
    let email: String?
    let lastReservationDate: String?
    let totalReservations: Int
    let latestGuestNotes: String?
    let latestStaffNotes: String?

    var result: GuestLookupResult {
        GuestLookupResult(
            id: key,
            displayName: displayName,
            phoneDigits: phoneDigits,
            email: email,
            lastReservationDate: lastReservationDate,
            totalReservations: totalReservations,
            latestGuestNotes: latestGuestNotes,
            latestStaffNotes: latestStaffNotes
        )
    }

    func score(queryDigits: String, normalizedName: String, normalizedEmail: String) -> Int? {
        if !queryDigits.isEmpty, let phoneDigits {
            if phoneDigits == queryDigits {
                return 0
            }
            if phoneDigits.hasSuffix(queryDigits) || phoneDigits.contains(queryDigits) {
                return 1
            }
        }

        if normalizedEmail.count >= 3,
           let email,
           email.contains(normalizedEmail) {
            return 2
        }

        if normalizedName.count >= 2,
           self.normalizedName.contains(normalizedName) {
            return 3
        }

        return nil
    }
}

private struct GuestLookupProfileBuilder {
    let key: String
    var displayName: String
    var normalizedName: String
    var phoneDigits: String?
    var email: String?
    var lastReservationDate: String?
    var totalReservations = 0
    var latestGuestNotes: String?
    var latestStaffNotes: String?

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

            let digits = GuestLookupNormalizer.phoneDigits(record.phone).nilIfBlank
            if let digits {
                phoneDigits = digits
            }

            let normalizedEmail = GuestLookupNormalizer.normalizedEmail(record.email).nilIfBlank
            if let normalizedEmail, !normalizedEmail.isManualPlaceholderEmail {
                email = normalizedEmail
            }
        }
    }

    var profile: GuestLookupProfile {
        GuestLookupProfile(
            key: key,
            displayName: displayName,
            normalizedName: normalizedName,
            phoneDigits: phoneDigits,
            email: email,
            lastReservationDate: lastReservationDate,
            totalReservations: totalReservations,
            latestGuestNotes: latestGuestNotes,
            latestStaffNotes: latestStaffNotes
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
        value.filter(\.isNumber)
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
