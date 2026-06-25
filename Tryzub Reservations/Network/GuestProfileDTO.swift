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
