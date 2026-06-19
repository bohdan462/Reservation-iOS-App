//
//  GuestInsightRecordSnapshot.swift
//  Tryzub Reservations
//

import Foundation

// MARK: - Identity Snapshot

struct GuestInsightIdentitySnapshot: Sendable, Equatable {
    let normalizedName: String
    let fullPhoneDigits: String?
    let phoneLast4: String?
    let usefulEmail: String?
    let emailLocalPart: String?
    let emailDomain: String?
    let isPlaceholderEmail: Bool

    var hasReliableContact: Bool {
        fullPhoneDigits != nil || usefulEmail != nil
    }
}

// MARK: - Match Snapshot

struct GuestInsightIdentityMatch: Sendable, Equatable {
    let remoteID: Int
    let confidence: GuestMatchConfidence
    let reasons: [String]

    var isPrimaryHistoryMatch: Bool {
        confidence == .exact || confidence == .strong
    }
}

// MARK: - Record Snapshot

struct GuestInsightRecordSnapshot: Sendable, Equatable {
    let remoteID: Int
    let guestName: String
    let email: String
    let phone: String
    let formattedPhone: String
    let reservationDate: String
    let reservationTime: String
    let displayDate: String
    let displayTime: String
    let partySize: Int
    let statusValue: ReservationStatus
    let tableName: String?
    let guestNotes: String?
    let staffNotes: String?
    let sourceSubmissionID: Int
    let supersededById: Int?
    let hasTableAssignment: Bool
    let hasConfirmationEmailRecord: Bool
    let hasGuestNotes: Bool
    let hasStaffNotes: Bool
    let identity: GuestInsightIdentitySnapshot
    let intentKey: String?
    let isLikelyManualCallIn: Bool
    let weekdayName: String?
}

// MARK: - Builder

enum GuestInsightRecordSnapshotBuilder {
    static func build(
        selected: ReservationRecord,
        pool: [ReservationRecord]
    ) -> (selected: GuestInsightRecordSnapshot, all: [GuestInsightRecordSnapshot]) {
        let resolver = GuestIdentityResolver()
        let deduper = GuestReservationIntentDeduper()
        let unique = uniqueRecords([selected] + pool).filter { record in
            record.remoteID == selected.remoteID
                || (!record.isHidden && (record.supersededById ?? 0) <= 0)
        }
        let all = unique.map { snapshot(for: $0, resolver: resolver, deduper: deduper) }
        let selectedSnapshot = all.first { $0.remoteID == selected.remoteID }
            ?? snapshot(for: selected, resolver: resolver, deduper: deduper)
        return (selectedSnapshot, all)
    }

    private static func snapshot(
        for record: ReservationRecord,
        resolver: GuestIdentityResolver,
        deduper: GuestReservationIntentDeduper
    ) -> GuestInsightRecordSnapshot {
        let resolved = resolver.identity(for: record)
        return GuestInsightRecordSnapshot(
            remoteID: record.remoteID,
            guestName: record.guestName,
            email: record.email,
            phone: record.phone,
            formattedPhone: record.formattedPhone,
            reservationDate: record.reservationDate,
            reservationTime: record.reservationTime,
            displayDate: record.displayDate,
            displayTime: record.displayTime,
            partySize: record.partySize,
            statusValue: record.statusValue,
            tableName: record.tableName,
            guestNotes: record.guestNotes,
            staffNotes: record.staffNotes,
            sourceSubmissionID: record.sourceSubmissionID,
            supersededById: record.supersededById,
            hasTableAssignment: record.hasTableAssignment,
            hasConfirmationEmailRecord: record.hasConfirmationEmailRecord,
            hasGuestNotes: record.hasGuestNotes,
            hasStaffNotes: record.hasStaffNotes,
            identity: GuestInsightIdentitySnapshot(
                normalizedName: resolved.normalizedName,
                fullPhoneDigits: resolved.fullPhoneDigits,
                phoneLast4: resolved.phoneLast4,
                usefulEmail: resolved.usefulEmail,
                emailLocalPart: resolved.emailLocalPart,
                emailDomain: resolved.emailDomain,
                isPlaceholderEmail: resolved.isPlaceholderEmail
            ),
            intentKey: deduper.intentKey(for: record),
            isLikelyManualCallIn: resolver.isLikelyManualCallIn(record),
            weekdayName: resolver.weekdayName(from: record)
        )
    }

    private static func uniqueRecords(_ records: [ReservationRecord]) -> [ReservationRecord] {
        var seen = Set<Int>()
        var unique: [ReservationRecord] = []

        for record in records where !seen.contains(record.remoteID) {
            seen.insert(record.remoteID)
            unique.append(record)
        }

        return unique
    }
}
