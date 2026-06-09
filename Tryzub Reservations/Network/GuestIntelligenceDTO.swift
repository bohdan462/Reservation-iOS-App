//
//  GuestIntelligenceDTO.swift
//  Tryzub Reservations
//
//  DTOs for GET /guest-intelligence.
//

import Foundation

// MARK: - Day Response

struct GuestIntelligenceDayResponseDTO: Decodable, Equatable {
    let contractVersion: String?
    let scope: String?
    let source: String?
    let dataQuality: IntelligenceDataQualityDTO?
    let date: String
    let generatedAt: String?
    let items: [GuestIntelligenceSummaryDTO]

    enum CodingKeys: String, CodingKey {
        case contractVersion
        case scope
        case source
        case dataQuality
        case date
        case generatedAt
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contractVersion = try container.decodeIfPresent(String.self, forKey: .contractVersion)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        dataQuality = try container.decodeIfPresent(IntelligenceDataQualityDTO.self, forKey: .dataQuality)
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
        items = try container.decodeIfPresent([GuestIntelligenceSummaryDTO].self, forKey: .items) ?? []
    }
}

// MARK: - Summary Item

struct GuestIntelligenceSummaryDTO: Decodable, Equatable, Identifiable {
    var id: Int { reservationId }

    let reservationId: Int
    let guestKey: String?
    let guestName: String?
    let identityConfidence: GuestIdentityConfidenceDTO
    let classification: GuestClassificationDTO
    let matchedVisitCount: Int
    let cleanVisitCount: Int
    let lastVisitDate: String?
    let firstVisitDate: String?
    let usualTime: String?
    let usualWeekday: String?
    let averagePartySize: Double?
    let maxPartySize: Int?
    let onlineCount: Int
    let callInCount: Int
    let manualCount: Int
    let cancelledCount: Int
    let noShowCount: Int
    let hasSeatingPreference: Bool
    let hasAllergyNote: Bool
    let hasAccessibilityNote: Bool
    let hasSpecialOccasionNote: Bool
    let hasPriorServiceIssue: Bool
    let possibleDuplicate: Bool
    let relatedReservationIds: [Int]

    enum CodingKeys: String, CodingKey {
        case reservationId
        case guestKey
        case guestName
        case identityConfidence
        case classification
        case matchedVisitCount
        case cleanVisitCount
        case lastVisitDate
        case firstVisitDate
        case usualTime
        case usualWeekday
        case averagePartySize
        case maxPartySize
        case onlineCount
        case callInCount
        case manualCount
        case cancelledCount
        case noShowCount
        case hasSeatingPreference
        case hasAllergyNote
        case hasAccessibilityNote
        case hasSpecialOccasionNote
        case hasPriorServiceIssue
        case possibleDuplicate
        case relatedReservationIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reservationId = try container.decodeFlexibleIntIfPresent(forKey: .reservationId) ?? 0
        guestKey = try container.decodeIfPresent(String.self, forKey: .guestKey)
        guestName = try container.decodeIfPresent(String.self, forKey: .guestName)
        identityConfidence = try container.decodeIfPresent(GuestIdentityConfidenceDTO.self, forKey: .identityConfidence)
            ?? .unknown
        classification = try container.decodeIfPresent(GuestClassificationDTO.self, forKey: .classification)
            ?? .unknown
        matchedVisitCount = try container.decodeFlexibleIntIfPresent(forKey: .matchedVisitCount) ?? 0
        cleanVisitCount = try container.decodeFlexibleIntIfPresent(forKey: .cleanVisitCount) ?? 0
        lastVisitDate = try container.decodeIfPresent(String.self, forKey: .lastVisitDate)
        firstVisitDate = try container.decodeIfPresent(String.self, forKey: .firstVisitDate)
        usualTime = try container.decodeIfPresent(String.self, forKey: .usualTime)
        usualWeekday = try container.decodeIfPresent(String.self, forKey: .usualWeekday)
        averagePartySize = try container.decodeFlexibleDoubleIfPresent(forKey: .averagePartySize)
        maxPartySize = try container.decodeFlexibleIntIfPresent(forKey: .maxPartySize)
        onlineCount = try container.decodeFlexibleIntIfPresent(forKey: .onlineCount) ?? 0
        callInCount = try container.decodeFlexibleIntIfPresent(forKey: .callInCount) ?? 0
        manualCount = try container.decodeFlexibleIntIfPresent(forKey: .manualCount) ?? 0
        cancelledCount = try container.decodeFlexibleIntIfPresent(forKey: .cancelledCount) ?? 0
        noShowCount = try container.decodeFlexibleIntIfPresent(forKey: .noShowCount) ?? 0
        hasSeatingPreference = try container.decodeFlexibleBoolIfPresent(forKey: .hasSeatingPreference) ?? false
        hasAllergyNote = try container.decodeFlexibleBoolIfPresent(forKey: .hasAllergyNote) ?? false
        hasAccessibilityNote = try container.decodeFlexibleBoolIfPresent(forKey: .hasAccessibilityNote) ?? false
        hasSpecialOccasionNote = try container.decodeFlexibleBoolIfPresent(forKey: .hasSpecialOccasionNote) ?? false
        hasPriorServiceIssue = try container.decodeFlexibleBoolIfPresent(forKey: .hasPriorServiceIssue) ?? false
        possibleDuplicate = try container.decodeFlexibleBoolIfPresent(forKey: .possibleDuplicate) ?? false
        relatedReservationIds = try container.decodeFlexibleIntArrayIfPresent(forKey: .relatedReservationIds) ?? []
    }
}

// MARK: - Enums

enum GuestIdentityConfidenceDTO: Equatable {
    case exact
    case strong
    case possible
    case weak
    case unknown
}

extension GuestIdentityConfidenceDTO: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        switch raw {
        case "exact":
            self = .exact
        case "strong":
            self = .strong
        case "possible":
            self = .possible
        case "weak":
            self = .weak
        case "unknown", "":
            self = .unknown
        default:
            self = .unknown
        }
    }
}

enum GuestClassificationDTO: Equatable {
    case unknown
    case new
    case returning
    case regular
    case frequentRegular
    case needsReview
}

extension GuestClassificationDTO: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        switch raw {
        case "new":
            self = .new
        case "returning":
            self = .returning
        case "regular":
            self = .regular
        case "frequent_regular":
            self = .frequentRegular
        case "needs_review":
            self = .needsReview
        case "unknown", "":
            self = .unknown
        default:
            self = .unknown
        }
    }
}

// MARK: - Decoding Helpers

private extension KeyedDecodingContainer {
    func decodeFlexibleIntArrayIfPresent(forKey key: Key) throws -> [Int]? {
        if let values = try? decodeIfPresent([Int].self, forKey: key) {
            return values
        }

        if let stringValues = try? decodeIfPresent([String].self, forKey: key) {
            return stringValues.compactMap {
                Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        if let intValue = try? decodeFlexibleIntIfPresent(forKey: key) {
            return [intValue]
        }

        return nil
    }
}
