//
//  IntelligenceDataQualityDTO.swift
//  Tryzub Reservations
//
//  Shared contract metadata for backend intelligence endpoints.
//

import Foundation

struct IntelligenceDataQualityDTO: Decodable, Equatable {
    let includesAllSourceTypes: Bool?
    let excludesHidden: Bool?
    let excludesSuperseded: Bool?
    let relationshipMetricsMode: String?
    let identityMatching: String?
    let notesMode: String?
    let historyMatching: String?
    let nameOnlyHistoryMatching: Bool?
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case includesAllSourceTypes
        case excludesHidden
        case excludesSuperseded
        case relationshipMetricsMode
        case identityMatching
        case notesMode
        case historyMatching
        case nameOnlyHistoryMatching
        case warnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        includesAllSourceTypes = try container.decodeFlexibleBoolIfPresent(forKey: .includesAllSourceTypes)
        excludesHidden = try container.decodeFlexibleBoolIfPresent(forKey: .excludesHidden)
        excludesSuperseded = try container.decodeFlexibleBoolIfPresent(forKey: .excludesSuperseded)
        relationshipMetricsMode = try container.decodeIfPresent(String.self, forKey: .relationshipMetricsMode)
        identityMatching = try container.decodeIfPresent(String.self, forKey: .identityMatching)
        notesMode = try container.decodeIfPresent(String.self, forKey: .notesMode)
        historyMatching = try container.decodeIfPresent(String.self, forKey: .historyMatching)
        nameOnlyHistoryMatching = try container.decodeFlexibleBoolIfPresent(forKey: .nameOnlyHistoryMatching)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }

    var hasWarnings: Bool {
        !warnings.isEmpty
    }

    var warningSet: Set<String> {
        Set(warnings)
    }
}
