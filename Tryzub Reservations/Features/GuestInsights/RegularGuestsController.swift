//
//  RegularGuestsController.swift
//  Tryzub Reservations
//

import Foundation

// MARK: - Read-Only Regular Guest Analysis

struct RegularGuestsController {
    private let identityResolver = GuestIdentityResolver()
    private let intentDeduper = GuestReservationIntentDeduper()

    // Intent: Builds guest-memory rows from cached SwiftData reservations only.
    // Network: None. Mutation: None.
    // Duplicate same-intent copies are collapsed before visit counts are shown.
    func buildSummaries(from reservations: [ReservationRecord]) -> [RegularGuestSummary] {
        let records = uniqueRecords(reservations)
        guard !records.isEmpty else { return [] }

        let clusters = exactAndStrongClusters(from: records)
        return clusters
            .compactMap { summary(for: $0, allRecords: records) }
            .sorted(by: defaultSort)
    }

    // MARK: - Filters / Sorting

    // Intent: Applies staff search/filter/sort choices in memory.
    func displayedSummaries(
        from reservations: [ReservationRecord],
        searchText: String,
        filter: RegularGuestFilter,
        sort: RegularGuestSort
    ) -> [RegularGuestSummary] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var summaries = buildSummaries(from: reservations)
            .filter { includes($0, filter: filter) }

        if !trimmedSearch.isEmpty {
            summaries = summaries.filter { $0.searchText.contains(trimmedSearch) }
        }

        return summaries.sorted { lhs, rhs in
            compare(lhs, rhs, sort: sort)
        }
    }

    // MARK: - Guest Clustering

    // Exact/strong matches form clusters. Weak matches stay separate as possible matches.
    private func exactAndStrongClusters(from records: [ReservationRecord]) -> [[ReservationRecord]] {
        var unionFind = UnionFind(indices: Array(records.indices))
        let identities = records.map(identityResolver.identity)

        for lhsIndex in records.indices {
            for rhsIndex in records.indices where rhsIndex > lhsIndex {
                if let match = identityResolver.match(
                    records[rhsIndex],
                    against: identities[lhsIndex],
                    selectedID: nil
                ),
                   match.isPrimaryHistoryMatch {
                    unionFind.union(lhsIndex, rhsIndex)
                }
            }
        }

        var grouped: [Int: [ReservationRecord]] = [:]
        for index in records.indices {
            grouped[unionFind.find(index), default: []].append(records[index])
        }

        return grouped.values.map { $0.sorted(by: newestFirst) }
    }

    // MARK: - Summary Building

    private func summary(
        for records: [ReservationRecord],
        allRecords: [ReservationRecord]
    ) -> RegularGuestSummary? {
        let dedupedRecords = intentDeduper.collapse(records)
        let cleanRecords = dedupedRecords.records
        guard let representative = cleanRecords.sorted(by: newestFirst).first else { return nil }

        let identities = cleanRecords.map(identityResolver.identity)
        let primaryPhoneDigits = mostCommon(identities.compactMap(\.fullPhoneDigits))
        let primaryPhone = primaryPhoneDigits.flatMap { digits in
            cleanRecords.first { identityResolver.fullPhoneDigits($0.phone) == digits }?.formattedPhone
        }
        let primaryEmail = mostCommon(identities.compactMap(\.usefulEmail))
        let displayName = mostCommon(cleanRecords.map(\.guestName).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ?? representative.guestName

        let sortedNewest = cleanRecords.sorted(by: newestFirst)
        let sortedOldest = cleanRecords.sorted(by: oldestFirst)
        let noteCount = cleanRecords.reduce(0) { count, record in
            count
                + (record.staffNotes?.nilIfBlank == nil ? 0 : 1)
                + (record.guestNotes?.nilIfBlank == nil ? 0 : 1)
        }
        let cancelledNoShowCount = statusCounts(from: cleanRecords)

        return RegularGuestSummary(
            id: stableID(for: cleanRecords, identities: identities, representative: representative),
            displayName: displayName,
            primaryPhone: primaryPhone,
            primaryEmail: primaryEmail,
            regularityLevel: GuestRegularityLevel.level(for: cleanRecords.count),
            totalReservations: cleanRecords.count,
            firstSeenDate: sortedOldest.first?.displayDate,
            lastBookedDate: sortedNewest.first?.displayDate,
            firstSeenSortKey: sortedOldest.first?.reservationDate,
            lastBookedSortKey: sortedNewest.first?.reservationDate,
            upcomingCount: cleanRecords.filter { isUpcomingActive($0) }.count,
            cancelledNoShowCount: cancelledNoShowCount,
            mostCommonTime: mostCommonTime(from: cleanRecords),
            mostCommonPartySize: mostCommon(cleanRecords.map(\.partySize)),
            hasStaffNotes: cleanRecords.contains(where: \.hasStaffNotes),
            hasGuestNotes: cleanRecords.contains(where: \.hasGuestNotes),
            isLikelyManualGuest: cleanRecords.contains { identityResolver.isLikelyManualCallIn($0) },
            possibleMatchCount: possibleMatchCount(for: records, cleanRecords: cleanRecords, allRecords: allRecords),
            matchedReservationIDs: cleanRecords.map(\.remoteID),
            representativeReservationID: representative.remoteID,
            collapsedDuplicateReservationCount: dedupedRecords.collapsedDuplicateCount,
            noteCount: noteCount,
            visitsLast90Days: visitCount(inLastDays: 90, records: cleanRecords),
            visitsLast12Months: visitCount(inLastDays: 365, records: cleanRecords),
            searchText: searchText(
                displayName: displayName,
                primaryPhone: primaryPhone,
                primaryEmail: primaryEmail,
                records: cleanRecords
            )
        )
    }

    // MARK: - Filter Rules

    private func includes(_ summary: RegularGuestSummary, filter: RegularGuestFilter) -> Bool {
        switch filter {
        case .allSeenBefore:
            return summary.totalReservations >= 2
        case .regulars:
            return summary.regularityLevel.rank >= GuestRegularityLevel.regular.rank
        case .becomingRegular:
            return summary.regularityLevel == .becomingRegular
        case .notesFound:
            return summary.hasStaffNotes || summary.hasGuestNotes
        case .staffNotesFound:
            return summary.hasStaffNotes
        case .callIn:
            return summary.isLikelyManualGuest
        case .possibleMatches:
            return summary.possibleMatchCount > 0
        case .cancellationOrNoShow:
            return summary.cancelledNoShowCount > 0
        case .upcoming:
            return summary.upcomingCount > 0
        }
    }

    // MARK: - Sort Rules

    private func compare(
        _ lhs: RegularGuestSummary,
        _ rhs: RegularGuestSummary,
        sort: RegularGuestSort
    ) -> Bool {
        switch sort {
        case .mostReservations:
            return defaultSort(lhs, rhs)
        case .recentlyBooked:
            if lhs.lastBookedSortKey == rhs.lastBookedSortKey {
                return defaultSort(lhs, rhs)
            }
            return (lhs.lastBookedSortKey ?? "") > (rhs.lastBookedSortKey ?? "")
        case .firstSeen:
            if lhs.firstSeenSortKey == rhs.firstSeenSortKey {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return (lhs.firstSeenSortKey ?? "9999-99-99") < (rhs.firstSeenSortKey ?? "9999-99-99")
        case .mostNotes:
            if lhs.noteCount == rhs.noteCount {
                return defaultSort(lhs, rhs)
            }
            return lhs.noteCount > rhs.noteCount
        case .upcomingFirst:
            if lhs.upcomingCount == rhs.upcomingCount {
                return defaultSort(lhs, rhs)
            }
            return lhs.upcomingCount > rhs.upcomingCount
        case .name:
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func defaultSort(_ lhs: RegularGuestSummary, _ rhs: RegularGuestSummary) -> Bool {
        if lhs.regularityLevel.rank != rhs.regularityLevel.rank {
            return lhs.regularityLevel.rank > rhs.regularityLevel.rank
        }

        if lhs.totalReservations != rhs.totalReservations {
            return lhs.totalReservations > rhs.totalReservations
        }

        if lhs.lastBookedSortKey != rhs.lastBookedSortKey {
            return (lhs.lastBookedSortKey ?? "") > (rhs.lastBookedSortKey ?? "")
        }

        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    // MARK: - Identity / Possible Matches

    private func stableID(
        for records: [ReservationRecord],
        identities: [GuestResolvedIdentity],
        representative: ReservationRecord
    ) -> String {
        if let phone = mostCommon(identities.compactMap(\.fullPhoneDigits)) {
            return "phone:\(phone)"
        }

        if let email = mostCommon(identities.compactMap(\.usefulEmail)) {
            return "email:\(email)"
        }

        if let name = mostCommon(identities.map(\.normalizedName).filter({ !$0.isEmpty })),
           let last4 = mostCommon(identities.compactMap(\.phoneLast4)) {
            return "name-phone:\(name)-\(last4)"
        }

        return "reservation:\(representative.remoteID)"
    }

    private func possibleMatchCount(
        for clusterRecords: [ReservationRecord],
        cleanRecords: [ReservationRecord],
        allRecords: [ReservationRecord]
    ) -> Int {
        let clusterIDs = Set(clusterRecords.map(\.remoteID))
        var possibleIDs = Set<Int>()

        for record in allRecords where !clusterIDs.contains(record.remoteID) {
            if intentDeduper.isDuplicateIntent(record, ofAny: cleanRecords) {
                continue
            }

            for clusterRecord in clusterRecords {
                let identity = identityResolver.identity(for: clusterRecord)
                guard let match = identityResolver.match(
                    record,
                    against: identity,
                    selectedID: nil
                ) else {
                    continue
                }

                if match.confidence == .possible || match.confidence == .weak {
                    possibleIDs.insert(record.remoteID)
                    break
                }
            }
        }

        return possibleIDs.count
    }

    // MARK: - Date / Search Helpers

    private func statusCounts(from records: [ReservationRecord]) -> Int {
        records.filter {
                $0.statusValue == .cancelled || $0.statusValue == .noShow
        }.count
    }

    private func mostCommonTime(from records: [ReservationRecord]) -> String? {
        mostCommon(records.compactMap { identityResolver.hourBucket(from: $0.reservationTime) })
    }

    private func isUpcomingActive(_ record: ReservationRecord) -> Bool {
        guard Self.activeStatuses.contains(record.statusValue) else { return false }

        guard let date = identityResolver.dateTime(from: record) else {
            return record.reservationDate >= Date.reservationDateString()
        }

        return date >= Date()
    }

    private func visitCount(inLastDays days: Int, records: [ReservationRecord]) -> Int {
        let cutoff = Date().addingTimeInterval(Double(-days * 24 * 60 * 60))
        return records.filter { record in
            guard let date = identityResolver.dateTime(from: record) else { return false }
            return date >= cutoff
        }.count
    }

    private func searchText(
        displayName: String,
        primaryPhone: String?,
        primaryEmail: String?,
        records: [ReservationRecord]
    ) -> String {
        ([displayName, primaryPhone, primaryEmail] + records.flatMap { record in
            [
                record.guestName,
                record.phone,
                record.email,
                record.staffNotes,
                record.guestNotes
            ]
        })
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
    }

    private func uniqueRecords(_ records: [ReservationRecord]) -> [ReservationRecord] {
        var seen = Set<Int>()
        var unique: [ReservationRecord] = []

        for record in records where !seen.contains(record.remoteID) {
            seen.insert(record.remoteID)
            unique.append(record)
        }

        return unique
    }

    private func mostCommon<T: Hashable>(_ values: [T]) -> T? {
        values
            .reduce(into: [T: Int]()) { result, value in
                result[value, default: 0] += 1
            }
            .sorted {
                if $0.value == $1.value {
                    return String(describing: $0.key) < String(describing: $1.key)
                }
                return $0.value > $1.value
            }
            .first?.key
    }

    private func newestFirst(_ lhs: ReservationRecord, _ rhs: ReservationRecord) -> Bool {
        if lhs.reservationDate == rhs.reservationDate {
            if lhs.reservationTime == rhs.reservationTime {
                return lhs.remoteID > rhs.remoteID
            }
            return lhs.reservationTime > rhs.reservationTime
        }
        return lhs.reservationDate > rhs.reservationDate
    }

    private func oldestFirst(_ lhs: ReservationRecord, _ rhs: ReservationRecord) -> Bool {
        if lhs.reservationDate == rhs.reservationDate {
            if lhs.reservationTime == rhs.reservationTime {
                return lhs.remoteID < rhs.remoteID
            }
            return lhs.reservationTime < rhs.reservationTime
        }
        return lhs.reservationDate < rhs.reservationDate
    }

    private static let activeStatuses: Set<ReservationStatus> = [
        .new,
        .needsReview,
        .confirmed,
        .seated
    ]
}

// MARK: - Union Find

private struct UnionFind {
    private var parent: [Int: Int]

    init(indices: [Int]) {
        parent = Dictionary(uniqueKeysWithValues: indices.map { ($0, $0) })
    }

    mutating func find(_ index: Int) -> Int {
        let parentIndex = parent[index] ?? index
        if parentIndex == index {
            return index
        }

        let root = find(parentIndex)
        parent[index] = root
        return root
    }

    mutating func union(_ lhs: Int, _ rhs: Int) {
        let lhsRoot = find(lhs)
        let rhsRoot = find(rhs)
        guard lhsRoot != rhsRoot else { return }
        parent[rhsRoot] = lhsRoot
    }
}

// MARK: - String Helpers

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
