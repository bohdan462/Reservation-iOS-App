//
//  GuestHistoryModels.swift
//  Tryzub Reservations
//

import Foundation

struct GuestHistoryRow: Identifiable, Hashable {
    let id: Int
    let sourceSubmissionID: Int?
    let serviceDate: String
    let serviceTime: String
    let serviceDateTime: Date?
    let submittedAt: Date?
    let updatedAt: Date?
    let status: ReservationStatus
    let outcome: GuestHistoryOutcome
    let partySize: Int
    let tableName: String?
    let guestNotes: String?
    let staffNotes: String?
    let isHidden: Bool
    let supersededByID: Int?
    let duplicateOfReservationID: Int?
    let duplicateReason: String?
    let relationship: GuestHistoryRelationship
    let relationshipLabel: String?
    let matchConfidence: GuestIdentityConfidence
    let matchedBy: [String]

    init(
        id: Int,
        sourceSubmissionID: Int?,
        serviceDate: String,
        serviceTime: String,
        serviceDateTime: Date?,
        submittedAt: Date?,
        updatedAt: Date?,
        status: ReservationStatus,
        outcome: GuestHistoryOutcome,
        partySize: Int,
        tableName: String?,
        guestNotes: String?,
        staffNotes: String?,
        isHidden: Bool,
        supersededByID: Int?,
        duplicateOfReservationID: Int?,
        duplicateReason: String?,
        relationship: GuestHistoryRelationship,
        relationshipLabel: String?,
        matchConfidence: GuestIdentityConfidence,
        matchedBy: [String]
    ) {
        self.id = id
        self.sourceSubmissionID = sourceSubmissionID
        self.serviceDate = serviceDate
        self.serviceTime = serviceTime
        self.serviceDateTime = serviceDateTime
        self.submittedAt = submittedAt
        self.updatedAt = updatedAt
        self.status = status
        self.outcome = outcome
        self.partySize = partySize
        self.tableName = tableName
        self.guestNotes = guestNotes
        self.staffNotes = staffNotes
        self.isHidden = isHidden
        self.supersededByID = supersededByID
        self.duplicateOfReservationID = duplicateOfReservationID
        self.duplicateReason = duplicateReason
        self.relationship = relationship
        self.relationshipLabel = relationshipLabel
        self.matchConfidence = matchConfidence
        self.matchedBy = matchedBy
    }

    init(dto: GuestHistoryRowDTO) {
        id = dto.reservationId
        sourceSubmissionID = dto.sourceSubmissionId
        serviceDate = dto.reservationDate
        serviceTime = dto.reservationTime
        serviceDateTime = GuestHistoryDateParser.dateTime(dto.serviceDatetime)
            ?? GuestHistoryDateParser.serviceDateTime(date: dto.reservationDate, time: dto.reservationTime)
        submittedAt = GuestHistoryDateParser.dateTime(dto.submittedAt)
        updatedAt = GuestHistoryDateParser.dateTime(dto.updatedAt)
        status = ReservationStatus(rawValue: dto.status) ?? .needsReview
        outcome = dto.outcomeCategory
        partySize = dto.partySize
        tableName = dto.tableName?.nilIfBlank
        guestNotes = dto.guestNotes?.nilIfBlank
        staffNotes = dto.staffNotes?.nilIfBlank
        isHidden = dto.isHidden
        supersededByID = dto.supersededById
        duplicateOfReservationID = dto.duplicateOfReservationId
        duplicateReason = dto.duplicateReason?.nilIfBlank
        relationship = dto.relationship
        relationshipLabel = dto.relationshipLabel?.nilIfBlank
        matchConfidence = dto.matchConfidence
        matchedBy = dto.matchedBy
    }
}

struct GuestProfileSummaryCounts: Hashable {
    let cleanPastVisitCount: Int
    let totalBookingCount: Int
    let upcomingCount: Int
    let cancelledCount: Int
    let noShowCount: Int
    let duplicateOrCorrectionCount: Int
    let hiddenCount: Int
    let supersededCount: Int
}

struct GuestFullProfile: Hashable {
    let bookingHistoryRows: [GuestHistoryRow]
    let notesHistory: [GuestNoteHistoryItem]
    let counts: GuestProfileSummaryCounts

    init(bookingHistory: [GuestHistoryRowDTO], notesHistory: [GuestNoteHistoryItemDTO]) {
        bookingHistoryRows = bookingHistory.map(GuestHistoryRow.init(dto:))
        let statuses = Dictionary(uniqueKeysWithValues: bookingHistoryRows.map { ($0.id, $0.status) })
        self.notesHistory = notesHistory.compactMap { dto in
            let item = GuestNoteHistoryItem(dto: dto, status: statuses[dto.reservationId] ?? .needsReview)
            return item.text.isEmpty ? nil : item
        }
        counts = GuestOperationalTruth.summaryCounts(from: bookingHistoryRows)
    }
}

private extension GuestNoteHistoryItem {
    init(dto: GuestNoteHistoryItemDTO, status: ReservationStatus) {
        let time = dto.reservationTime ?? ""
        self.init(
            reservationID: dto.reservationId,
            date: dto.reservationDate,
            time: time,
            displayDate: GuestHistoryDateParser.displayDate(dto.reservationDate),
            displayTime: GuestHistoryDateParser.displayTime(time),
            noteType: dto.kind == .staffNote ? .staff : .guest,
            text: dto.text.trimmingCharacters(in: .whitespacesAndNewlines),
            status: status
        )
    }
}

enum GuestHistoryRowMapper {
    static func rows(from records: [ReservationRecord], selected: ReservationRecord) -> [GuestHistoryRow] {
        let deduper = GuestReservationIntentDeduper()
        let collapsed = deduper.collapse(records, keeping: selected.remoteID).records
        let keptIDs = Set(collapsed.map(\.remoteID))
        let resolver = GuestIdentityResolver()
        let selectedIdentity = resolver.identity(for: selected)

        return records.map { record in
            let duplicateIntent = !keptIDs.contains(record.remoteID)
            let outcome = outcome(for: record, selected: selected, duplicateIntent: duplicateIntent)
            let identity = resolver.identity(for: record)
            var matchedBy: [String] = []
            if let phone = identity.fullPhoneDigits, phone == selectedIdentity.fullPhoneDigits { matchedBy.append("phone") }
            if let email = identity.usefulEmail, email == selectedIdentity.usefulEmail { matchedBy.append("email") }
            let match = resolver.match(record, against: selectedIdentity, selectedID: selected.remoteID)
            let confidence: GuestIdentityConfidence = {
                if matchedBy.count > 1 { return .exact }
                switch match?.confidence {
                case .exact: return .exact
                case .strong: return .strong
                case .possible: return .possible
                case .weak: return .weak
                case nil: return .unknown
                }
            }()

            return GuestHistoryRow(
                id: record.remoteID,
                sourceSubmissionID: record.sourceSubmissionID > 0 ? record.sourceSubmissionID : nil,
                serviceDate: record.reservationDate,
                serviceTime: record.reservationTime,
                serviceDateTime: GuestHistoryDateParser.serviceDateTime(date: record.reservationDate, time: record.reservationTime),
                submittedAt: GuestHistoryDateParser.dateTime(record.createdAt),
                updatedAt: GuestHistoryDateParser.dateTime(record.apiUpdatedAt) ?? record.updatedAt,
                status: record.statusValue,
                outcome: outcome,
                partySize: record.partySize,
                tableName: record.tableName?.nilIfBlank,
                guestNotes: record.guestNotes?.nilIfBlank,
                staffNotes: record.staffNotes?.nilIfBlank,
                isHidden: record.isHidden,
                supersededByID: record.supersededById,
                duplicateOfReservationID: nil,
                duplicateReason: duplicateIntent ? "local_same_intent" : nil,
                relationship: duplicateIntent ? .sameDayCorrection : ((record.supersededById ?? 0) > 0 ? .supersededBy : .none),
                relationshipLabel: duplicateIntent ? "Possible correction" : ((record.supersededById ?? 0) > 0 ? "Superseded by newer reservation" : nil),
                matchConfidence: confidence,
                matchedBy: matchedBy
            )
        }
        .sorted { ($0.serviceDateTime ?? .distantPast) > ($1.serviceDateTime ?? .distantPast) }
    }

    private static func outcome(
        for record: ReservationRecord,
        selected: ReservationRecord,
        duplicateIntent: Bool
    ) -> GuestHistoryOutcome {
        if record.isHidden { return .hidden }
        if (record.supersededById ?? 0) > 0 { return .superseded }
        if duplicateIntent { return .duplicateOrCorrection }
        if record.statusValue == .cancelled { return .cancelled }
        if record.statusValue == .noShow { return .noShow }
        let candidateKey = "\(record.reservationDate) \(record.reservationTime)"
        let selectedKey = "\(selected.reservationDate) \(selected.reservationTime)"
        if candidateKey >= selectedKey { return .upcoming }
        if record.statusValue == .confirmed || record.statusValue == .seated || record.statusValue == .completed {
            return .cleanVisit
        }
        return .unknown
    }
}

private enum GuestHistoryDateParser {
    static func serviceDateTime(date: String, time: String) -> Date? {
        ReservationFormatters.serverDateMinute.date(from: "\(date) \(String(time.prefix(5)))")
    }

    static func dateTime(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let value = ISO8601DateFormatter().date(from: raw) { return value }
        let normalized = raw.replacingOccurrences(of: "T", with: " ")
        if let value = ReservationFormatters.serverDateMinute.date(from: String(normalized.prefix(16))) { return value }
        return ReservationFormatters.reservationDateKey.date(from: String(raw.prefix(10)))
    }

    static func displayDate(_ value: String) -> String {
        guard let date = ReservationFormatters.reservationDateKey.date(from: value) else { return value }
        return ReservationFormatters.mediumDate.string(from: date)
    }

    static func displayTime(_ value: String) -> String {
        guard let date = ReservationFormatters.apiTime.date(from: String(value.prefix(5))) else { return value }
        return ReservationFormatters.shortTime.string(from: date)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
