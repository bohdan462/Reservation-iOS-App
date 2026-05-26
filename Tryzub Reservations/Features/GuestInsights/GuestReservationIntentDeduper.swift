//
//  GuestReservationIntentDeduper.swift
//  Tryzub Reservations
//

import Foundation

struct GuestReservationIntentDeduplicationResult {
    let records: [ReservationRecord]
    let collapsedDuplicateCount: Int
}

struct GuestReservationIntentDeduper {
    private let identityResolver = GuestIdentityResolver()

    func collapse(
        _ records: [ReservationRecord],
        keeping selectedID: Int? = nil
    ) -> GuestReservationIntentDeduplicationResult {
        let grouped = Dictionary(grouping: records) { record in
            intentKey(for: record) ?? "record:\(record.remoteID)"
        }

        var collapsedDuplicateCount = 0
        var canonicalRecords: [ReservationRecord] = []

        for group in grouped.values {
            guard group.count > 1 else {
                canonicalRecords.append(contentsOf: group)
                continue
            }

            collapsedDuplicateCount += group.count - 1
            canonicalRecords.append(canonicalRecord(from: group, selectedID: selectedID))
        }

        return GuestReservationIntentDeduplicationResult(
            records: canonicalRecords,
            collapsedDuplicateCount: collapsedDuplicateCount
        )
    }

    func isDuplicateIntent(_ record: ReservationRecord, ofAny records: [ReservationRecord]) -> Bool {
        guard let recordKey = intentKey(for: record) else { return false }
        return records.contains { candidate in
            candidate.remoteID != record.remoteID && intentKey(for: candidate) == recordKey
        }
    }

    private func intentKey(for record: ReservationRecord) -> String? {
        guard let identityKey = identityKey(for: record) else { return nil }
        return [
            identityKey,
            record.reservationDate,
            normalizedTime(record.reservationTime),
            "\(record.partySize)"
        ].joined(separator: "|")
    }

    private func identityKey(for record: ReservationRecord) -> String? {
        let identity = identityResolver.identity(for: record)

        if let phone = identity.fullPhoneDigits {
            return "phone:\(phone)"
        }

        if let email = identity.usefulEmail {
            return "email:\(email)"
        }

        if !identity.normalizedName.isEmpty,
           let last4 = identity.phoneLast4 {
            return "name-last4:\(identity.normalizedName):\(last4)"
        }

        if !identity.normalizedName.isEmpty {
            return "name:\(identity.normalizedName)"
        }

        return nil
    }

    private func normalizedTime(_ value: String) -> String {
        let parts = value.split(separator: ":")
        guard parts.count >= 2 else { return value }
        return "\(parts[0]):\(parts[1])"
    }

    private func canonicalRecord(from records: [ReservationRecord], selectedID: Int?) -> ReservationRecord {
        records.max { lhs, rhs in
            canonicalRank(lhs, selectedID: selectedID) < canonicalRank(rhs, selectedID: selectedID)
        } ?? records[0]
    }

    private func canonicalRank(_ record: ReservationRecord, selectedID: Int?) -> Int {
        var rank = 0

        if record.remoteID == selectedID {
            rank += 10_000
        }

        if record.supersededById == nil {
            rank += 1_000
        }

        rank += statusRank(record.statusValue) * 100

        if record.hasTableAssignment {
            rank += 20
        }

        if record.hasConfirmationEmailRecord {
            rank += 10
        }

        // Prefer the original/lower remote ID when all practical keeper signals tie.
        return rank * 100_000 + max(0, 100_000 - min(record.remoteID, 100_000))
    }

    private func statusRank(_ status: ReservationStatus) -> Int {
        switch status {
        case .seated, .completed, .confirmed:
            return 3
        case .new, .needsReview:
            return 2
        case .cancelled, .noShow:
            return 1
        }
    }
}
