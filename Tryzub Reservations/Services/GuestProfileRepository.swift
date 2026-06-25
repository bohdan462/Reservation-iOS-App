//
//  GuestProfileRepository.swift
//  Tryzub Reservations
//

import Foundation
import SwiftData

@MainActor
struct GuestProfileRepository {
    func upsertProfiles(_ profiles: [GuestProfileDTO], context: ModelContext) throws {
        guard !profiles.isEmpty else { return }
        for profile in profiles {
            try upsertProfileWithoutSave(profile, hasDetailPayload: false, context: context)
        }
        try context.save()
    }

    func upsertProfile(
        _ profile: GuestProfileDTO,
        hasDetailPayload: Bool,
        context: ModelContext
    ) throws {
        try upsertProfileWithoutSave(profile, hasDetailPayload: hasDetailPayload, context: context)
        try context.save()
    }

    private func upsertProfileWithoutSave(
        _ profile: GuestProfileDTO,
        hasDetailPayload: Bool,
        context: ModelContext
    ) throws {
        guard let guestKey = normalizedText(profile.guestKey) else { return }
        let existing = try cachedProfile(guestKey: guestKey, context: context)
        let mapped = mappedProfile(profile, guestKey: guestKey, hasDetailPayload: hasDetailPayload)

        if let existing {
            update(existing, with: mapped, preservingDetailPayload: !hasDetailPayload)
        } else {
            context.insert(mapped)
        }
    }

    func cachedProfile(guestKey: String, context: ModelContext) throws -> GuestProfileCacheRecord? {
        guard let key = normalizedText(guestKey) else { return nil }
        var descriptor = FetchDescriptor<GuestProfileCacheRecord>(
            predicate: #Predicate { record in
                record.guestKey == key
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func searchProfiles(
        query: String,
        limit: Int = 12,
        context: ModelContext
    ) throws -> [GuestProfileCacheRecord] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredQuery = trimmedQuery.lowercased()
        let queryDigits = normalizedPhoneDigits(trimmedQuery)
        guard !loweredQuery.isEmpty || queryDigits.count >= 4 else { return [] }

        let descriptor = FetchDescriptor<GuestProfileCacheRecord>(
            sortBy: [
                SortDescriptor(\.cleanVisitCount, order: .reverse),
                SortDescriptor(\.totalReservations, order: .reverse),
                SortDescriptor(\.fetchedAt, order: .reverse)
            ]
        )
        let records = try context.fetch(descriptor)
        return Array(records.filter { record in
            if queryDigits.count >= 4, record.matchesPhoneDigits(queryDigits) {
                return true
            }
            if record.displayName.lowercased().contains(loweredQuery) {
                return true
            }
            if record.email?.lowercased().contains(loweredQuery) == true {
                return true
            }
            return record.topLabelTitles?.lowercased().contains(loweredQuery) == true
        }.prefix(max(1, limit)))
    }

    func cachedProfiles(limit: Int = 500, context: ModelContext) throws -> [GuestProfileCacheRecord] {
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

    func matchProfile(
        for reservation: ReservationRecord,
        context: ModelContext
    ) throws -> GuestProfileCacheRecord? {
        if let phoneMatch = try matchPhoneDigits(reservation.phone, context: context) {
            return phoneMatch
        }

        guard let email = normalizedEmail(reservation.email) else { return nil }
        let descriptor = FetchDescriptor<GuestProfileCacheRecord>(
            sortBy: [
                SortDescriptor(\.cleanVisitCount, order: .reverse),
                SortDescriptor(\.totalReservations, order: .reverse),
                SortDescriptor(\.fetchedAt, order: .reverse)
            ]
        )
        return try context.fetch(descriptor).first { record in
            record.email?.caseInsensitiveCompare(email) == .orderedSame
        }
    }

    func matchPhoneDigits(_ digits: String, context: ModelContext) throws -> GuestProfileCacheRecord? {
        let normalizedDigits = normalizedPhoneDigits(digits)
        guard normalizedDigits.count >= 7 else { return nil }

        let descriptor = FetchDescriptor<GuestProfileCacheRecord>(
            sortBy: [
                SortDescriptor(\.cleanVisitCount, order: .reverse),
                SortDescriptor(\.totalReservations, order: .reverse),
                SortDescriptor(\.fetchedAt, order: .reverse)
            ]
        )
        return try context.fetch(descriptor).first { record in
            record.normalizedPhone == normalizedDigits || record.normalizedPhone?.hasSuffix(normalizedDigits) == true
        }
    }

    func latestBackendUpdatedAt(context: ModelContext) throws -> String? {
        let descriptor = FetchDescriptor<GuestProfileCacheRecord>()
        return try context.fetch(descriptor)
            .compactMap(\.backendUpdatedAt)
            .max()
    }

    func cacheCount(context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<GuestProfileCacheRecord>()).count
    }

    // MARK: - Mapping

    private func mappedProfile(
        _ profile: GuestProfileDTO,
        guestKey: String,
        hasDetailPayload: Bool
    ) -> GuestProfileCacheRecord {
        let cleanVisitCount = profile.cleanVisitCount
            ?? profile.cleanPastVisitCount
            ?? profile.counts?.completed
            ?? 0
        let totalReservations = profile.totalReservations
            ?? profile.totalBookingCount
            ?? totalFromCounts(profile)
        let latestNotes = latestNotePreviews(from: profile)

        return GuestProfileCacheRecord(
            guestKey: guestKey,
            displayName: displayName(from: profile, guestKey: guestKey),
            normalizedPhone: normalizedText(profile.primaryPhone).map(normalizedPhoneDigits),
            email: normalizedEmail(profile.primaryEmail),
            primaryPhone: normalizedText(profile.primaryPhone),
            cleanVisitCount: max(0, cleanVisitCount),
            totalReservations: max(0, totalReservations),
            upcomingCount: max(0, profile.upcomingCount ?? 0),
            firstSeenDate: normalizedText(profile.firstSeenDate),
            lastSeenDate: normalizedText(profile.lastSeenDate),
            lastBookedAt: normalizedText(profile.lastBookedAt),
            nextReservationDate: normalizedText(profile.nextReservation?.date ?? profile.nextReservation?.reservationDate),
            nextReservationTime: normalizedText(profile.nextReservation?.time ?? profile.nextReservation?.reservationTime),
            summaryLine: summaryLine(from: profile),
            topLabelTitles: topLabelTitles(from: profile.labels),
            hasDietaryNote: hasDietarySignal(in: profile),
            isRegularGuest: isRegularGuest(profile: profile, cleanVisitCount: cleanVisitCount, totalReservations: totalReservations),
            latestGuestNotePreview: latestNotes.guest,
            latestStaffNotePreview: latestNotes.staff,
            backendUpdatedAt: normalizedText(profile.updatedAt),
            fetchedAt: Date(),
            hasDetailPayload: hasDetailPayload,
            labelsJSON: nil,
            listProfileJSON: nil,
            detailProfileJSON: nil,
            bookingHistoryJSON: nil,
            notesHistoryJSON: nil
        )
    }

    private func update(
        _ record: GuestProfileCacheRecord,
        with mapped: GuestProfileCacheRecord,
        preservingDetailPayload: Bool
    ) {
        let previousHasDetailPayload = record.hasDetailPayload
        let previousDetailProfileJSON = record.detailProfileJSON
        let previousBookingHistoryJSON = record.bookingHistoryJSON
        let previousNotesHistoryJSON = record.notesHistoryJSON

        record.displayName = mapped.displayName
        record.normalizedPhone = mapped.normalizedPhone
        record.email = mapped.email
        record.primaryPhone = mapped.primaryPhone
        record.cleanVisitCount = mapped.cleanVisitCount
        record.totalReservations = mapped.totalReservations
        record.upcomingCount = mapped.upcomingCount
        record.firstSeenDate = mapped.firstSeenDate
        record.lastSeenDate = mapped.lastSeenDate
        record.lastBookedAt = mapped.lastBookedAt
        record.nextReservationDate = mapped.nextReservationDate
        record.nextReservationTime = mapped.nextReservationTime
        record.summaryLine = mapped.summaryLine
        record.topLabelTitles = mapped.topLabelTitles
        record.hasDietaryNote = mapped.hasDietaryNote
        record.isRegularGuest = mapped.isRegularGuest
        record.latestGuestNotePreview = mapped.latestGuestNotePreview ?? record.latestGuestNotePreview
        record.latestStaffNotePreview = mapped.latestStaffNotePreview ?? record.latestStaffNotePreview
        record.backendUpdatedAt = mapped.backendUpdatedAt
        record.fetchedAt = mapped.fetchedAt
        record.labelsJSON = mapped.labelsJSON
        record.listProfileJSON = mapped.listProfileJSON

        if preservingDetailPayload {
            record.hasDetailPayload = previousHasDetailPayload
            record.detailProfileJSON = previousDetailProfileJSON
            record.bookingHistoryJSON = previousBookingHistoryJSON
            record.notesHistoryJSON = previousNotesHistoryJSON
        } else {
            record.hasDetailPayload = mapped.hasDetailPayload
            record.detailProfileJSON = mapped.detailProfileJSON
            record.bookingHistoryJSON = mapped.bookingHistoryJSON
            record.notesHistoryJSON = mapped.notesHistoryJSON
        }
    }

    private func displayName(from profile: GuestProfileDTO, guestKey: String) -> String {
        normalizedText(profile.primaryName)
            ?? normalizedText(profile.primaryEmail)
            ?? normalizedText(profile.primaryPhone)
            ?? guestKey
    }

    private func summaryLine(from profile: GuestProfileDTO) -> String? {
        normalizedText(profile.summary?.summaryText)
            ?? (profile.labels ?? []).compactMap { normalizedText($0.title) }.first
    }

    private func topLabelTitles(from labels: [GuestProfileLabelDTO]?) -> String? {
        let titles = (labels ?? [])
            .compactMap { normalizedText($0.title) }
            .prefix(3)
        let joined = titles.joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    private func isRegularGuest(
        profile: GuestProfileDTO,
        cleanVisitCount: Int,
        totalReservations: Int
    ) -> Bool {
        if cleanVisitCount >= 3 || totalReservations >= 5 {
            return true
        }
        return labelTokens(profile.labels).contains { token in
            token.contains("regular_guest") || token.contains("regular guest") || token == "regular"
        }
    }

    private func hasDietarySignal(in profile: GuestProfileDTO) -> Bool {
        if profile.noteFlags?.hasDietaryNote == true {
            return true
        }
        return labelTokens(profile.labels).contains { token in
            token.contains("dietary")
                || token.contains("allergy")
                || token.contains("allerg")
                || token.contains("gluten")
                || token.contains("vegan")
                || token.contains("vegetarian")
        }
    }

    private func labelTokens(_ labels: [GuestProfileLabelDTO]?) -> [String] {
        (labels ?? []).flatMap { label in
            [label.id, label.category, label.title, label.detail]
                .compactMap { normalizedText($0)?.lowercased() }
        }
    }

    private func latestNotePreviews(from profile: GuestProfileDTO) -> (guest: String?, staff: String?) {
        let sortedNotes = (profile.notesHistory ?? []).sorted { lhs, rhs in
            "\(lhs.reservationDate) \(lhs.reservationTime ?? "")" > "\(rhs.reservationDate) \(rhs.reservationTime ?? "")"
        }
        let guest = sortedNotes.first { $0.kind == .guestNote }.flatMap { preview($0.text) }
        let staff = sortedNotes.first { $0.kind == .staffNote }.flatMap { preview($0.text) }
        return (guest, staff)
    }

    private func totalFromCounts(_ profile: GuestProfileDTO) -> Int {
        let counts = [
            profile.completedCount,
            profile.confirmedCount,
            profile.cancelledCount,
            profile.noShowCount,
            profile.needsReviewCount
        ]
        return counts.compactMap { $0 }.reduce(0, +)
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedEmail(_ value: String?) -> String? {
        normalizedText(value)?.lowercased()
    }

    private func normalizedPhoneDigits(_ value: String) -> String {
        GuestLookupPhoneNormalizer.digits(value)
    }

    private func preview(_ value: String, limit: Int = 120) -> String? {
        guard let text = normalizedText(value) else { return nil }
        guard text.count > limit else { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
