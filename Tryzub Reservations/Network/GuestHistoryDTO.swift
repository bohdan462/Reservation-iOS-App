//
//  GuestHistoryDTO.swift
//  Tryzub Reservations
//

import Foundation

enum GuestHistoryOutcome: String, Codable, Hashable {
    case cleanVisit = "clean_visit"
    case upcoming
    case cancelled
    case noShow = "no_show"
    case duplicateOrCorrection = "duplicate_or_correction"
    case hidden
    case superseded
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = GuestHistoryOutcome(rawValue: (try? container.decode(String.self)) ?? "") ?? .unknown
    }
}

enum GuestHistoryRelationship: String, Codable, Hashable {
    case none
    case duplicateOf = "duplicate_of"
    case supersededBy = "superseded_by"
    case sameDayCorrection = "same_day_correction"
    case replacedByNewer = "replaced_by_newer"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = GuestHistoryRelationship(rawValue: (try? container.decode(String.self)) ?? "") ?? .none
    }
}

enum GuestIdentityConfidence: String, Codable, Hashable {
    case exact
    case strong
    case possible
    case weak
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = GuestIdentityConfidence(rawValue: (try? container.decode(String.self)) ?? "") ?? .unknown
    }
}

enum GuestNoteKind: String, Codable, Hashable {
    case guestNote = "guest_note"
    case staffNote = "staff_note"
}

struct GuestHistoryRowDTO: Decodable, Equatable {
    let reservationId: Int
    let sourceSubmissionId: Int?
    let reservationDate: String
    let reservationTime: String
    let serviceDatetime: String?
    let submittedAt: String?
    let updatedAt: String?
    let status: String
    let outcomeCategory: GuestHistoryOutcome
    let partySize: Int
    let tableName: String?
    let guestNotes: String?
    let staffNotes: String?
    let isHidden: Bool
    let supersededById: Int?
    let duplicateOfReservationId: Int?
    let duplicateReason: String?
    let relationship: GuestHistoryRelationship
    let relationshipLabel: String?
    let matchConfidence: GuestIdentityConfidence
    let matchedBy: [String]

    enum CodingKeys: String, CodingKey {
        case reservationId
        case sourceSubmissionId
        case reservationDate
        case reservationTime
        case serviceDatetime
        case submittedAt
        case updatedAt
        case status
        case outcomeCategory
        case partySize
        case tableName
        case guestNotes
        case staffNotes
        case isHidden
        case supersededById
        case duplicateOfReservationId
        case duplicateReason
        case relationship
        case relationshipLabel
        case matchConfidence
        case matchedBy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reservationId = try container.decodeFlexibleIntIfPresent(forKey: .reservationId) ?? 0
        sourceSubmissionId = try container.decodeFlexibleIntIfPresent(forKey: .sourceSubmissionId)
        reservationDate = try container.decodeIfPresent(String.self, forKey: .reservationDate) ?? ""
        reservationTime = try container.decodeIfPresent(String.self, forKey: .reservationTime) ?? ""
        serviceDatetime = try container.decodeIfPresent(String.self, forKey: .serviceDatetime)
        submittedAt = try container.decodeIfPresent(String.self, forKey: .submittedAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        outcomeCategory = try container.decodeIfPresent(GuestHistoryOutcome.self, forKey: .outcomeCategory) ?? .unknown
        partySize = try container.decodeFlexibleIntIfPresent(forKey: .partySize) ?? 0
        tableName = try container.decodeIfPresent(String.self, forKey: .tableName)
        guestNotes = try container.decodeIfPresent(String.self, forKey: .guestNotes)
        staffNotes = try container.decodeIfPresent(String.self, forKey: .staffNotes)
        isHidden = try container.decodeFlexibleBoolIfPresent(forKey: .isHidden) ?? false
        supersededById = try container.decodeFlexibleIntIfPresent(forKey: .supersededById)
        duplicateOfReservationId = try container.decodeFlexibleIntIfPresent(forKey: .duplicateOfReservationId)
        duplicateReason = try container.decodeIfPresent(String.self, forKey: .duplicateReason)
        relationship = try container.decodeIfPresent(GuestHistoryRelationship.self, forKey: .relationship) ?? .none
        relationshipLabel = try container.decodeIfPresent(String.self, forKey: .relationshipLabel)
        matchConfidence = try container.decodeIfPresent(GuestIdentityConfidence.self, forKey: .matchConfidence) ?? .unknown
        matchedBy = try container.decodeIfPresent([String].self, forKey: .matchedBy) ?? []
    }
}

struct GuestNoteHistoryItemDTO: Decodable, Equatable {
    let reservationId: Int
    let reservationDate: String
    let reservationTime: String?
    let kind: GuestNoteKind
    let text: String

    enum CodingKeys: String, CodingKey {
        case reservationId
        case reservationDate
        case reservationTime
        case kind
        case text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reservationId = try container.decodeFlexibleIntIfPresent(forKey: .reservationId) ?? 0
        reservationDate = try container.decodeIfPresent(String.self, forKey: .reservationDate) ?? ""
        reservationTime = try container.decodeIfPresent(String.self, forKey: .reservationTime)
        kind = try container.decodeIfPresent(GuestNoteKind.self, forKey: .kind) ?? .guestNote
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    }
}

struct GuestHistoryCountsDTO: Decodable, Equatable {
    let cleanPastVisitCount: Int?
    let totalBookingCount: Int?
    let upcomingCount: Int?
    let cancelledCount: Int?
    let noShowCount: Int?
    let duplicateOrCorrectionCount: Int?
    let lastCleanVisitDate: String?
    let lastCleanVisitId: Int?
    let firstSeenDate: String?
    let guestNotesCount: Int?
    let staffNotesCount: Int?
}
