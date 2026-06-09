//
//  GuestInsightsController.swift
//  Tryzub Reservations
//

import Foundation

// MARK: - Read-Only Guest Insight Analysis

struct GuestInsightsController {
    private let identityResolver = GuestIdentityResolver()
    private let intentDeduper = GuestReservationIntentDeduper()

    // Intent: Builds hospitality memory from cached SwiftData reservations only.
    // Network: None. Mutation: None.
    // Duplicate intent rows are collapsed before visit counts are calculated.
    func analyze(
        selected reservation: ReservationRecord,
        allReservations: [ReservationRecord]
    ) -> GuestInsightReport {
        let records = uniqueRecords([reservation] + allReservations)
        let selectedIdentity = identityResolver.identity(for: reservation)

        let matchResults = records.compactMap { record in
            identityResolver.match(record, against: selectedIdentity, selectedID: reservation.remoteID)
        }

        let matchedResults = matchResults.filter {
            $0.record.remoteID == reservation.remoteID
                || $0.confidence == .exact
                || $0.confidence == .strong
        }
        let dedupedMatchedRecords = intentDeduper.collapse(
            matchedResults.map(\.record),
            keeping: reservation.remoteID
        )
        let matchedRecords = dedupedMatchedRecords.records
            .sorted(by: newestFirst)
        let matchedResultByID = Dictionary(
            uniqueKeysWithValues: matchedResults.map { ($0.record.remoteID, $0) }
        )

        let possibleResults = matchResults.filter {
            $0.record.remoteID != reservation.remoteID
                && $0.confidence == .possible
                && !intentDeduper.isDuplicateIntent($0.record, ofAny: matchedRecords)
        }
        let possibleResultByID = Dictionary(
            uniqueKeysWithValues: possibleResults.map { ($0.record.remoteID, $0) }
        )

        let matchedItems = matchedRecords
            .compactMap { matchedResultByID[$0.remoteID] }
            .map(matchedReservation)
            .sorted(by: newestFirst)

        let possibleItems = intentDeduper.collapse(possibleResults.map(\.record)).records
            .compactMap { record in
                possibleResultByID[record.remoteID]
            }
            .map(matchedReservation)
            .sorted {
                if $0.confidence == $1.confidence {
                    return newestFirst($0, $1)
                }
                return confidenceRank($0.confidence) < confidenceRank($1.confidence)
            }

        let bookingHistory = matchedRecords.map(bookingHistoryItem)
        let noteHistory = noteHistoryItems(from: matchedRecords)
        let staffNoteHistory = noteHistory.filter { $0.noteType == .staff }
        let preferredTimes = timePreferences(from: matchedRecords)
        let preferredWeekdays = weekdayPreferences(from: matchedRecords)
        let partySizeStats = partyStats(from: matchedRecords)
        let statusStats = statusStats(from: matchedRecords)
        let summary = summary(
            from: matchedRecords,
            noteHistory: noteHistory,
            preferredTimes: preferredTimes,
            preferredWeekdays: preferredWeekdays,
            partySizeStats: partySizeStats,
            statusStats: statusStats
        )
        let hospitalitySnapshot = hospitalitySnapshot(
            from: matchedRecords,
            selectedIdentity: selectedIdentity,
            noteHistory: noteHistory,
            partySizeStats: partySizeStats
        )
        let bookingBehavior = bookingBehavior(
            from: matchedRecords,
            preferredTimes: preferredTimes,
            preferredWeekdays: preferredWeekdays,
            partySizeStats: partySizeStats,
            statusStats: statusStats
        )

        let primaryEmail = selectedIdentity.usefulEmail
        let primaryPhone = selectedIdentity.fullPhoneDigits.map { _ in reservation.formattedPhone }
        let isLikelyManualGuest = identityResolver.isLikelyManualCallIn(reservation)

        return GuestInsightReport(
            selectedReservationID: reservation.remoteID,
            displayName: reservation.guestName,
            primaryPhone: primaryPhone,
            primaryEmail: primaryEmail,
            isLikelyManualGuest: isLikelyManualGuest,
            regularityLevel: GuestRegularityLevel.level(for: matchedRecords.count),
            hospitalitySnapshot: hospitalitySnapshot,
            bookingBehavior: bookingBehavior,
            collapsedDuplicateReservationCount: dedupedMatchedRecords.collapsedDuplicateCount,
            summary: summary,
            matchedReservations: matchedItems,
            possibleMatches: possibleItems,
            bookingHistory: bookingHistory,
            noteHistory: noteHistory,
            staffMentionHistory: staffNoteHistory,
            preferredTimes: preferredTimes,
            preferredWeekdays: preferredWeekdays,
            partySizeStats: partySizeStats,
            statusStats: statusStats,
            warnings: warnings(
                selectedIdentity: selectedIdentity,
                isLikelyManualGuest: isLikelyManualGuest,
                possibleMatches: possibleItems,
                matchedRecords: matchedRecords,
                collapsedDuplicateCount: dedupedMatchedRecords.collapsedDuplicateCount,
                noteHistory: noteHistory,
                summary: summary,
                partySizeStats: partySizeStats,
                statusStats: statusStats
            )
        )
    }

    // MARK: - Matching Rules

    private func matchedReservation(_ result: GuestIdentityMatch) -> GuestMatchedReservation {
        GuestMatchedReservation(
            reservationID: result.record.remoteID,
            date: result.record.reservationDate,
            time: result.record.reservationTime,
            displayDate: result.record.displayDate,
            displayTime: result.record.displayTime,
            guestName: result.record.guestName,
            partySize: result.record.partySize,
            status: result.record.statusValue,
            table: result.record.tableName?.nilIfBlank,
            confidence: result.confidence,
            matchReasons: result.reasons
        )
    }

    // MARK: - Booking History

    private func bookingHistoryItem(_ record: ReservationRecord) -> GuestBookingHistoryItem {
        GuestBookingHistoryItem(
            reservationID: record.remoteID,
            date: record.reservationDate,
            time: record.reservationTime,
            displayDate: record.displayDate,
            displayTime: record.displayTime,
            partySize: record.partySize,
            status: record.statusValue,
            table: record.tableName?.nilIfBlank,
            source: identityResolver.isLikelyManualCallIn(record) ? .manual : .online,
            hasGuestNotes: record.hasGuestNotes,
            hasStaffNotes: record.hasStaffNotes
        )
    }

    // MARK: - Notes History

    private func noteHistoryItems(from records: [ReservationRecord]) -> [GuestNoteHistoryItem] {
        records.flatMap { record in
            var notes: [GuestNoteHistoryItem] = []
            if let guestNotes = record.guestNotes?.nilIfBlank {
                notes.append(
                    GuestNoteHistoryItem(
                        reservationID: record.remoteID,
                        date: record.reservationDate,
                        time: record.reservationTime,
                        displayDate: record.displayDate,
                        displayTime: record.displayTime,
                        noteType: .guest,
                        text: guestNotes,
                        status: record.statusValue
                    )
                )
            }

            if let staffNotes = record.staffNotes?.nilIfBlank {
                notes.append(
                    GuestNoteHistoryItem(
                        reservationID: record.remoteID,
                        date: record.reservationDate,
                        time: record.reservationTime,
                        displayDate: record.displayDate,
                        displayTime: record.displayTime,
                        noteType: .staff,
                        text: staffNotes,
                        status: record.statusValue
                    )
                )
            }

            return notes
        }
        .sorted(by: newestFirst)
    }

    // MARK: - Preferences / Stats

    private func timePreferences(from records: [ReservationRecord]) -> [GuestTimePreference] {
        let buckets = records.reduce(into: [String: Int]()) { result, record in
            guard let bucket = hourBucket(from: record.reservationTime) else { return }
            result[bucket, default: 0] += 1
        }

        let total = max(buckets.values.reduce(0, +), 1)
        return buckets
            .map { bucket, count in
                GuestTimePreference(
                    bucket: bucket,
                    count: count,
                    percentage: Double(count) / Double(total)
                )
            }
            .sorted {
                if $0.count == $1.count {
                    return $0.bucket < $1.bucket
                }
                return $0.count > $1.count
            }
    }

    private func weekdayPreferences(from records: [ReservationRecord]) -> [GuestWeekdayPreference] {
        let weekdays = records.reduce(into: [String: Int]()) { result, record in
            guard let date = Self.dateParser.date(from: record.reservationDate) else { return }
            result[Self.weekdayFormatter.string(from: date), default: 0] += 1
        }

        return weekdays
            .map { GuestWeekdayPreference(weekday: $0.key, count: $0.value) }
            .sorted {
                if $0.count == $1.count {
                    return weekdayRank($0.weekday) < weekdayRank($1.weekday)
                }
                return $0.count > $1.count
            }
    }

    private func partyStats(from records: [ReservationRecord]) -> GuestPartySizeStats {
        let partySizes = records.map(\.partySize)
        guard !partySizes.isEmpty else {
            return GuestPartySizeStats(
                min: nil,
                max: nil,
                average: nil,
                mostCommon: nil,
                largePartyCount: 0
            )
        }

        let counts = partySizes.reduce(into: [Int: Int]()) { result, size in
            result[size, default: 0] += 1
        }

        return GuestPartySizeStats(
            min: partySizes.min(),
            max: partySizes.max(),
            average: Double(partySizes.reduce(0, +)) / Double(partySizes.count),
            mostCommon: counts.sorted {
                if $0.value == $1.value {
                    return $0.key < $1.key
                }
                return $0.value > $1.value
            }.first?.key,
            largePartyCount: partySizes.filter { $0 >= 7 }.count
        )
    }

    private func statusStats(from records: [ReservationRecord]) -> GuestStatusStats {
        GuestStatusStats(
            new: records.filter { $0.statusValue == .new }.count,
            needsReview: records.filter { $0.statusValue == .needsReview }.count,
            confirmed: records.filter { $0.statusValue == .confirmed }.count,
            seated: records.filter { $0.statusValue == .seated }.count,
            completed: records.filter { $0.statusValue == .completed }.count,
            cancelled: records.filter { $0.statusValue == .cancelled }.count,
            noShow: records.filter { $0.statusValue == .noShow }.count
        )
    }

    // MARK: - Hospitality Summary

    private func summary(
        from records: [ReservationRecord],
        noteHistory: [GuestNoteHistoryItem],
        preferredTimes: [GuestTimePreference],
        preferredWeekdays: [GuestWeekdayPreference],
        partySizeStats: GuestPartySizeStats,
        statusStats: GuestStatusStats
    ) -> GuestInsightSummary {
        let upcomingCount = records.filter(isUpcoming).count
        let pastCount = max(records.count - upcomingCount, 0)

        return GuestInsightSummary(
            totalMatchedReservations: records.count,
            upcomingReservationsCount: upcomingCount,
            pastReservationsCount: pastCount,
            cancelledNoShowCount: statusStats.cancelledOrNoShow,
            firstSeenDate: records.sorted(by: oldestFirst).first?.displayDate,
            lastBookedDate: records.sorted(by: newestFirst).first?.displayDate,
            mostCommonReservationTime: preferredTimes.first?.bucket,
            mostCommonWeekday: preferredWeekdays.first?.weekday,
            mostCommonPartySize: partySizeStats.mostCommon,
            lastStaffNote: noteHistory.first { $0.noteType == .staff },
            lastGuestNote: noteHistory.first { $0.noteType == .guest }
        )
    }

    private func hospitalitySnapshot(
        from records: [ReservationRecord],
        selectedIdentity: GuestResolvedIdentity,
        noteHistory: [GuestNoteHistoryItem],
        partySizeStats: GuestPartySizeStats
    ) -> GuestHospitalitySnapshot {
        let newestRecordDate = records
            .compactMap(dateTime)
            .max()
        let upcomingRecord = records
            .filter(isUpcoming)
            .sorted(by: oldestFirst)
            .first

        return GuestHospitalitySnapshot(
            visitsLast90Days: visitCount(inLastDays: 90, records: records),
            visitsLast12Months: visitCount(inLastDays: 365, records: records),
            lastUpcomingReservationDate: upcomingRecord.map {
                "\($0.displayDate) at \($0.displayTime)"
            },
            averagePartySize: partySizeStats.average,
            largestPartySize: partySizeStats.max,
            hasRealEmail: selectedIdentity.usefulEmail != nil,
            hasPhone: selectedIdentity.fullPhoneDigits != nil,
            hasStaffNotes: noteHistory.contains { $0.noteType == .staff },
            hasGuestNotes: noteHistory.contains { $0.noteType == .guest },
            noteCount: noteHistory.count,
            isRecent: newestRecordDate.map { $0 >= Date().addingTimeInterval(-90 * 24 * 60 * 60) } ?? false,
            isNotRecent: newestRecordDate.map { $0 < Date().addingTimeInterval(-365 * 24 * 60 * 60) } ?? false
        )
    }

    private func bookingBehavior(
        from records: [ReservationRecord],
        preferredTimes: [GuestTimePreference],
        preferredWeekdays: [GuestWeekdayPreference],
        partySizeStats: GuestPartySizeStats,
        statusStats: GuestStatusStats
    ) -> GuestBookingBehavior {
        GuestBookingBehavior(
            mostCommonTime: preferredTimes.first?.bucket,
            mostCommonWeekday: preferredWeekdays.first?.weekday,
            mostCommonPartySize: partySizeStats.mostCommon,
            commonTable: commonTable(from: records),
            onlineCount: records.filter { !identityResolver.isLikelyManualCallIn($0) }.count,
            manualCount: records.filter { identityResolver.isLikelyManualCallIn($0) }.count,
            upcomingActiveCount: records.filter { record in
                isUpcoming(record) && Self.activeStatuses.contains(record.statusValue)
            }.count,
            pastServedCount: statusStats.seated + statusStats.completed,
            cancelledNoShowCount: statusStats.cancelledOrNoShow
        )
    }

    // MARK: - Watchouts

    // Intent: Calm operational watchouts for staff, not judgmental guest scoring.
    private func warnings(
        selectedIdentity: GuestResolvedIdentity,
        isLikelyManualGuest: Bool,
        possibleMatches: [GuestMatchedReservation],
        matchedRecords: [ReservationRecord],
        collapsedDuplicateCount: Int,
        noteHistory: [GuestNoteHistoryItem],
        summary: GuestInsightSummary,
        partySizeStats: GuestPartySizeStats,
        statusStats: GuestStatusStats
    ) -> [GuestInsightWarning] {
        var warnings: [GuestInsightWarning] = []

        if collapsedDuplicateCount > 0 {
            warnings.append(
                GuestInsightWarning(
                    id: "duplicate-intent-collapsed",
                    title: "Duplicate-looking copies ignored",
                    message: "Guest counts use clean booking intent, so copied submissions do not inflate visits.",
                    systemImage: "doc.on.doc"
                )
            )
        }

        if !possibleMatches.isEmpty {
            warnings.append(
                GuestInsightWarning(
                    id: "possible-duplicates",
                    title: "Possible same guest",
                    message: "Shared phone/email or similar full name evidence was found. Review only; nothing is merged.",
                    systemImage: "person.2"
                )
            )
        }

        let sameDayCounts = matchedRecords.reduce(into: [String: Int]()) { result, record in
            result[record.reservationDate, default: 0] += 1
        }
        if sameDayCounts.values.contains(where: { $0 > 1 }) {
            warnings.append(
                GuestInsightWarning(
                    id: "same-day",
                    title: "Multiple reservations same day",
                    message: "Check timing and party details before service.",
                    systemImage: "calendar.badge.exclamationmark"
                )
            )
        }

        if partySizeStats.largePartyCount >= 2 {
            warnings.append(
                GuestInsightWarning(
                    id: "large-party",
                    title: "Frequent large party",
                    message: "This guest has more than one reservation for seven or more guests.",
                    systemImage: "person.3"
                )
            )
        }

        if selectedIdentity.fullPhoneDigits == nil && selectedIdentity.usefulEmail == nil {
            warnings.append(
                GuestInsightWarning(
                    id: "no-contact",
                    title: "No reliable contact identity",
                    message: "Matching is limited because this record has no full phone or real email.",
                    systemImage: "person.crop.circle.badge.questionmark"
                )
            )
        }

        if isLikelyManualGuest {
            warnings.append(
                GuestInsightWarning(
                    id: "manual-email",
                    title: "Manual call-in record",
                    message: "The email may be a placeholder and is not used as identity evidence.",
                    systemImage: "phone"
                )
            )
        }

        if statusStats.cancelledOrNoShow > 0 {
            warnings.append(
                GuestInsightWarning(
                    id: "past-cancellations",
                    title: "Prior cancellation or no-show",
                    message: "A previous matched reservation was cancelled or marked no-show.",
                    systemImage: "exclamationmark.circle"
                )
            )
        }

        if summary.upcomingReservationsCount > 0 {
            warnings.append(
                GuestInsightWarning(
                    id: "upcoming",
                    title: "Has upcoming reservation",
                    message: "This guest has an upcoming matched reservation in the local cache.",
                    systemImage: "calendar"
                )
            )
        }

        if !noteHistory.isEmpty {
            warnings.append(
                GuestInsightWarning(
                    id: "notes-found",
                    title: "Notes found",
                    message: "Review prior staff and guest notes before service.",
                    systemImage: "note.text"
                )
            )
        }

        return warnings
    }

    // MARK: - Date / Sorting Helpers

    private func commonTable(from records: [ReservationRecord]) -> String? {
        let counts = records.reduce(into: [String: Int]()) { result, record in
            guard let table = record.tableName?.nilIfBlank else { return }
            result[table, default: 0] += 1
        }

        return counts.sorted {
            if $0.value == $1.value {
                return $0.key < $1.key
            }
            return $0.value > $1.value
        }.first?.key
    }

    private func visitCount(inLastDays days: Int, records: [ReservationRecord]) -> Int {
        let cutoff = Date().addingTimeInterval(Double(-days * 24 * 60 * 60))
        return records.filter { record in
            guard let date = dateTime(from: record) else { return false }
            return date >= cutoff
        }.count
    }

    private func isUpcoming(_ record: ReservationRecord) -> Bool {
        guard let date = dateTime(from: record) else {
            return record.reservationDate >= Date.reservationDateString()
        }

        return date >= Date()
    }

    private func dateTime(from record: ReservationRecord) -> Date? {
        let combined = "\(record.reservationDate) \(record.reservationTime)"
        return Self.dateTimeParser.date(from: combined)
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

    private func newestFirst(_ lhs: GuestMatchedReservation, _ rhs: GuestMatchedReservation) -> Bool {
        if lhs.date == rhs.date {
            if lhs.time == rhs.time {
                return lhs.reservationID > rhs.reservationID
            }
            return lhs.time > rhs.time
        }
        return lhs.date > rhs.date
    }

    private func newestFirst(_ lhs: GuestNoteHistoryItem, _ rhs: GuestNoteHistoryItem) -> Bool {
        if lhs.date == rhs.date {
            if lhs.time == rhs.time {
                return lhs.reservationID > rhs.reservationID
            }
            return lhs.time > rhs.time
        }
        return lhs.date > rhs.date
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

    // MARK: - Formatting Helpers

    private func hourBucket(from time: String) -> String? {
        guard let hour = hour(from: time) else { return nil }
        let adjustedHour = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return "\(adjustedHour) \(suffix)"
    }

    private func hour(from time: String) -> Int? {
        guard let hourString = time.split(separator: ":").first,
              let hour = Int(hourString),
              (0...23).contains(hour) else {
            return nil
        }
        return hour
    }

    private func weekdayRank(_ weekday: String) -> Int {
        Self.weekdays.firstIndex(of: weekday) ?? Self.weekdays.count
    }

    private func confidenceRank(_ confidence: GuestMatchConfidence) -> Int {
        switch confidence {
        case .exact:
            return 0
        case .strong:
            return 1
        case .possible:
            return 2
        case .weak:
            return 3
        }
    }

    private static let weekdays = [
        "Sunday",
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday"
    ]

    private static let activeStatuses: Set<ReservationStatus> = [
        .new,
        .needsReview,
        .confirmed,
        .seated
    ]

    private static let dateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dateTimeParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}

// MARK: - String Helpers

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
