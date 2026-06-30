//
//  GuestProfileDTO.swift
//  Tryzub Reservations
//
//  DTOs for precomputed backend guest profile aggregates.
//

import Foundation

struct GuestProfileListResponseDTO: Decodable, Equatable {
    let success: Bool?
    let profiles: [GuestProfileDTO]?
    let page: Int?
    let perPage: Int?
    let total: Int?
    let totalPages: Int?
}

struct GuestProfileDetailResponseDTO: Decodable, Equatable {
    let success: Bool?
    let stale: Bool?
    let data: GuestProfileDTO?
}

struct GuestProfileLookupResponseDTO: Decodable, Equatable, @unchecked Sendable {
    let success: Bool
    let profiles: [GuestProfileLookupCandidateDTO]
    let bestMatchGuestKey: String?
    let bestMatchBasis: GuestProfileLookupMatchBasis?
    let bestMatchConfidence: GuestProfileLookupMatchConfidence?
    let query: GuestProfileLookupQueryDTO?
}

struct GuestProfileLookupCandidateDTO: Decodable, Equatable, @unchecked Sendable {
    let profile: GuestProfileDTO
    let matchBasis: GuestProfileLookupMatchBasis
    let matchConfidence: GuestProfileLookupMatchConfidence

    private enum CodingKeys: String, CodingKey {
        case matchBasis
        case matchConfidence
    }

    init(from decoder: Decoder) throws {
        profile = try GuestProfileDTO(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchBasis = try container.decodeIfPresent(GuestProfileLookupMatchBasis.self, forKey: .matchBasis) ?? .unknown
        matchConfidence = try container.decodeIfPresent(GuestProfileLookupMatchConfidence.self, forKey: .matchConfidence) ?? .unknown
    }

    init(
        profile: GuestProfileDTO,
        matchBasis: GuestProfileLookupMatchBasis,
        matchConfidence: GuestProfileLookupMatchConfidence
    ) {
        self.profile = profile
        self.matchBasis = matchBasis
        self.matchConfidence = matchConfidence
    }
}

struct GuestProfileLookupQueryDTO: Decodable, Equatable, Sendable {
    let phone: String?
    let email: String?
    let q: String?
    let limit: Int?
}

enum GuestProfileLookupMatchBasis: String, Codable, Equatable, Sendable {
    case email
    case phone
    case name
    case query
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = GuestProfileLookupMatchBasis(rawValue: value) ?? .unknown
    }
}

enum GuestProfileLookupMatchConfidence: String, Codable, Equatable, Sendable {
    case strong
    case possible
    case weak
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = GuestProfileLookupMatchConfidence(rawValue: value) ?? .unknown
    }
}

struct GuestProfileDTO: Decodable, Identifiable, Equatable {
    let guestKey: String?
    var id: String { stableIdentity }

    let primaryName: String?
    let primaryEmail: String?
    let primaryPhone: String?
    let identityConfidence: String?
    let identitySource: String?
    let firstSeenDate: String?
    let lastSeenDate: String?
    let lastBookedAt: String?
    let totalReservations: Int?
    let cleanVisitCount: Int?
    let cleanPastVisitCount: Int?
    let totalBookingCount: Int?
    let completedCount: Int?
    let confirmedCount: Int?
    let cancelledCount: Int?
    let noShowCount: Int?
    let needsReviewCount: Int?
    let upcomingCount: Int?
    let duplicateOrCorrectionCount: Int?
    let lastCleanVisitDate: String?
    let lastCleanVisitId: Int?
    let guestNotesCount: Int?
    let staffNotesCount: Int?
    let bookingHistory: [GuestHistoryRowDTO]?
    let notesHistory: [GuestNoteHistoryItemDTO]?
    let usualPartySize: Int?
    let averagePartySize: Double?
    let largestPartySize: Int?
    let usualHour: Int?
    let usualWeekday: Int?
    let nextReservation: GuestProfileNextReservationDTO?
    let labels: [GuestProfileLabelDTO]?
    let evidence: GuestProfileEvidenceDTO?
    let summary: GuestProfileSummaryDTO?
    let sourceCoverage: GuestProfileSourceCoverageDTO?
    let counts: GuestProfileCountsDTO?
    let preferences: GuestProfilePreferencesDTO?
    let noteFlags: GuestProfileNoteFlagsDTO?
    let sourceMix: GuestProfileSourceMixDTO?
    let sourceCounts: GuestProfileSourceMixDTO?
    let stale: Bool?
    let dirtyAt: String?
    let dirtyReason: String?
    let lastCalculatedAt: String?
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case guestKey
        case primaryName
        case primaryEmail
        case primaryPhone
        case identityConfidence
        case identitySource
        case firstSeenDate
        case lastSeenDate
        case lastBookedAt
        case totalReservations
        case cleanVisitCount
        case cleanPastVisitCount
        case totalBookingCount
        case completedCount
        case confirmedCount
        case cancelledCount
        case noShowCount
        case needsReviewCount
        case upcomingCount
        case duplicateOrCorrectionCount
        case lastCleanVisitDate
        case lastCleanVisitId
        case guestNotesCount
        case staffNotesCount
        case bookingHistory
        case notesHistory
        case usualPartySize
        case averagePartySize
        case largestPartySize
        case usualHour
        case usualWeekday
        case nextReservation
        case labels
        case evidence
        case summary
        case sourceCoverage
        case counts
        case preferences
        case noteFlags
        case sourceMix
        case sourceCounts
        case stale
        case dirtyAt
        case dirtyReason
        case lastCalculatedAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guestKey = try container.decodeIfPresent(String.self, forKey: .guestKey)
        primaryName = try container.decodeIfPresent(String.self, forKey: .primaryName)
        primaryEmail = try container.decodeIfPresent(String.self, forKey: .primaryEmail)
        primaryPhone = try container.decodeIfPresent(String.self, forKey: .primaryPhone)
        identityConfidence = try container.decodeIfPresent(String.self, forKey: .identityConfidence)
        identitySource = try container.decodeIfPresent(String.self, forKey: .identitySource)
        firstSeenDate = try container.decodeIfPresent(String.self, forKey: .firstSeenDate)
        lastSeenDate = try container.decodeIfPresent(String.self, forKey: .lastSeenDate)
        lastBookedAt = try container.decodeIfPresent(String.self, forKey: .lastBookedAt)
        totalReservations = try container.decodeIfPresent(Int.self, forKey: .totalReservations)
        cleanVisitCount = try container.decodeIfPresent(Int.self, forKey: .cleanVisitCount)
        cleanPastVisitCount = try container.decodeIfPresent(Int.self, forKey: .cleanPastVisitCount)
        totalBookingCount = try container.decodeIfPresent(Int.self, forKey: .totalBookingCount)
        completedCount = try container.decodeIfPresent(Int.self, forKey: .completedCount)
        confirmedCount = try container.decodeIfPresent(Int.self, forKey: .confirmedCount)
        cancelledCount = try container.decodeIfPresent(Int.self, forKey: .cancelledCount)
        noShowCount = try container.decodeIfPresent(Int.self, forKey: .noShowCount)
        needsReviewCount = try container.decodeIfPresent(Int.self, forKey: .needsReviewCount)
        upcomingCount = try container.decodeIfPresent(Int.self, forKey: .upcomingCount)
        duplicateOrCorrectionCount = try container.decodeIfPresent(Int.self, forKey: .duplicateOrCorrectionCount)
        lastCleanVisitDate = try container.decodeIfPresent(String.self, forKey: .lastCleanVisitDate)
        lastCleanVisitId = try container.decodeIfPresent(Int.self, forKey: .lastCleanVisitId)
        guestNotesCount = try container.decodeIfPresent(Int.self, forKey: .guestNotesCount)
        staffNotesCount = try container.decodeIfPresent(Int.self, forKey: .staffNotesCount)
        bookingHistory = try container.decodeIfPresent([GuestHistoryRowDTO].self, forKey: .bookingHistory)
        notesHistory = try container.decodeIfPresent([GuestNoteHistoryItemDTO].self, forKey: .notesHistory)
        usualPartySize = try container.decodeIfPresent(Int.self, forKey: .usualPartySize)
        averagePartySize = try container.decodeIfPresent(Double.self, forKey: .averagePartySize)
        largestPartySize = try container.decodeIfPresent(Int.self, forKey: .largestPartySize)
        usualHour = try container.decodeIfPresent(Int.self, forKey: .usualHour)
        usualWeekday = try container.decodeIfPresent(Int.self, forKey: .usualWeekday)
        nextReservation = try container.decodeIfPresent(GuestProfileNextReservationDTO.self, forKey: .nextReservation)
        labels = try container.decodeIfPresent([GuestProfileLabelDTO].self, forKey: .labels)
        evidence = try container.decodeIfPresent(GuestProfileEvidenceDTO.self, forKey: .evidence)
        summary = try? container.decodeIfPresent(GuestProfileSummaryDTO.self, forKey: .summary)
        sourceCoverage = try container.decodeIfPresent(GuestProfileSourceCoverageDTO.self, forKey: .sourceCoverage)
        counts = try container.decodeIfPresent(GuestProfileCountsDTO.self, forKey: .counts)
        preferences = try container.decodeIfPresent(GuestProfilePreferencesDTO.self, forKey: .preferences)
        noteFlags = try container.decodeIfPresent(GuestProfileNoteFlagsDTO.self, forKey: .noteFlags)
        sourceMix = try container.decodeIfPresent(GuestProfileSourceMixDTO.self, forKey: .sourceMix)
        sourceCounts = try container.decodeIfPresent(GuestProfileSourceMixDTO.self, forKey: .sourceCounts)
        stale = try container.decodeIfPresent(Bool.self, forKey: .stale)
        dirtyAt = try container.decodeIfPresent(String.self, forKey: .dirtyAt)
        dirtyReason = try container.decodeIfPresent(String.self, forKey: .dirtyReason)
        lastCalculatedAt = try container.decodeIfPresent(String.self, forKey: .lastCalculatedAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    private var stableIdentity: String {
        let candidates = [
            guestKey,
            primaryName,
            primaryEmail,
            primaryPhone,
            lastSeenDate,
            lastBookedAt
        ]
        let joined = candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "|")
        return joined.isEmpty ? "guest-profile-empty" : joined
    }

    var fullProfile: GuestFullProfile {
        GuestFullProfile(
            bookingHistory: bookingHistory ?? [],
            notesHistory: notesHistory ?? []
        )
    }
}

struct GuestProfileLabelDTO: Decodable, Equatable {
    let id: String?
    let category: String?
    let title: String?
    let detail: String?
    let evidence: String?
    let confidence: Double?
    let priority: Int?
    let source: String?
    let visibility: String?
}

// Placeholder until backend evidence is consumed by a later UI migration.
// Keep this intentionally shape-agnostic so unknown evidence fields do not break decoding.
struct GuestProfileEvidenceDTO: Decodable, Equatable {}

struct GuestProfileNextReservationDTO: Decodable, Equatable {
    let id: Int?
    let reservationId: Int?
    let date: String?
    let reservationDate: String?
    let time: String?
    let reservationTime: String?
    let partySize: Int?
    let status: String?
    let tableName: String?
}

struct GuestProfileSourceCoverageDTO: Decodable, Equatable {
    let backendProfile: Bool?
    let backendPrecomputed: Bool?
    let localCacheSupplement: Bool?
    let posConnected: Bool?
    let stale: Bool?
}

struct GuestProfileSummaryDTO: Decodable, Equatable {
    let summaryText: String?
    let classification: String?
    let managementNotes: [String]?
    let confidence: String?
    let historyScope: String?
}

struct GuestProfileCountsDTO: Decodable, Equatable {
    let completed: Int?
    let confirmed: Int?
    let cancelled: Int?
    let noShow: Int?
    let needsReview: Int?
    let guestNotes: Int?
    let staffNotes: Int?
}

struct GuestProfilePreferencesDTO: Decodable, Equatable {
    let usualPartySize: Int?
    let averagePartySize: Double?
    let largestPartySize: Int?
    let usualHour: Int?
    let usualWeekday: Int?
}

struct GuestProfileNoteFlagsDTO: Decodable, Equatable {
    let hasBirthdayNote: Bool?
    let hasOccasionNote: Bool?
    let hasReplyNeededNote: Bool?
    let hasGroupNote: Bool?
    let hasDietaryNote: Bool?
    let hasLargePartyHistory: Bool?
}

struct GuestProfileSourceMixDTO: Decodable, Equatable {
    let websiteCount: Int?
    let callInCount: Int?
    let manualCount: Int?
    let unknownSourceCount: Int?
}
