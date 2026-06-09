//
//  IntelligenceSystemStatusDTO.swift
//  Tryzub Reservations
//
//  DTOs for GET /intelligence/system-status.
//

import Foundation

// MARK: - Root

struct IntelligenceSystemStatusDTO: Decodable, Equatable {
    let contractVersion: String?
    let scope: String?
    let generatedAt: String?
    let range: BusinessIntelligenceRangeDTO
    let status: IntelligenceSystemOverallStatusDTO
    let managerSummary: IntelligenceManagerSummaryDTO
    let developerSummary: IntelligenceDeveloperSummaryDTO
    let checks: [IntelligenceSystemCheckDTO]
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case contractVersion
        case scope
        case generatedAt
        case range
        case status
        case managerSummary
        case developerSummary
        case checks
        case warnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contractVersion = try container.decodeIfPresent(String.self, forKey: .contractVersion)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
        range = try container.decodeIfPresent(BusinessIntelligenceRangeDTO.self, forKey: .range)
            ?? BusinessIntelligenceRangeDTO(from: nil, to: nil)
        status = try container.decodeIfPresent(IntelligenceSystemOverallStatusDTO.self, forKey: .status)
            ?? .warning
        managerSummary = try container.decodeIfPresent(IntelligenceManagerSummaryDTO.self, forKey: .managerSummary)
            ?? IntelligenceManagerSummaryDTO()
        developerSummary = try container.decodeIfPresent(IntelligenceDeveloperSummaryDTO.self, forKey: .developerSummary)
            ?? IntelligenceDeveloperSummaryDTO()
        checks = try container.decodeIfPresent([IntelligenceSystemCheckDTO].self, forKey: .checks) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}

// MARK: - Enums

enum IntelligenceSystemOverallStatusDTO: Equatable {
    case ok
    case warning
    case needsAttention
}

extension IntelligenceSystemOverallStatusDTO: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        switch raw {
        case "ok":
            self = .ok
        case "needs_attention":
            self = .needsAttention
        case "warning":
            self = .warning
        case "", "unknown":
            self = .warning
        default:
            self = .warning
        }
    }
}

enum IntelligenceSystemCheckSeverityDTO: Equatable {
    case info
    case warning
    case critical
}

extension IntelligenceSystemCheckSeverityDTO: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        switch raw {
        case "info":
            self = .info
        case "critical":
            self = .critical
        case "warning":
            self = .warning
        case "", "unknown":
            self = .warning
        default:
            self = .warning
        }
    }
}

// MARK: - Check

struct IntelligenceSystemCheckDTO: Decodable, Equatable, Identifiable {
    var id: String { key }

    let key: String
    let status: IntelligenceSystemOverallStatusDTO
    let severity: IntelligenceSystemCheckSeverityDTO
    let managerMessage: String?
    let developerMessage: String?

    enum CodingKeys: String, CodingKey {
        case key
        case status
        case severity
        case managerMessage
        case developerMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? "unknown"
        status = try container.decodeIfPresent(IntelligenceSystemOverallStatusDTO.self, forKey: .status)
            ?? .warning
        severity = try container.decodeIfPresent(IntelligenceSystemCheckSeverityDTO.self, forKey: .severity)
            ?? .warning
        managerMessage = try container.decodeIfPresent(String.self, forKey: .managerMessage)
        developerMessage = try container.decodeIfPresent(String.self, forKey: .developerMessage)
    }
}

// MARK: - Summaries

struct IntelligenceManagerSummaryDTO: Decodable, Equatable {
    let reservationsAvailable: Bool?
    let newImportsDetected: Int?
    let itemsNeedingReview: Int?
    let hiddenOrSupersededCount: Int?
    let possibleDuplicatesCount: Int?

    init(
        reservationsAvailable: Bool? = nil,
        newImportsDetected: Int? = nil,
        itemsNeedingReview: Int? = nil,
        hiddenOrSupersededCount: Int? = nil,
        possibleDuplicatesCount: Int? = nil
    ) {
        self.reservationsAvailable = reservationsAvailable
        self.newImportsDetected = newImportsDetected
        self.itemsNeedingReview = itemsNeedingReview
        self.hiddenOrSupersededCount = hiddenOrSupersededCount
        self.possibleDuplicatesCount = possibleDuplicatesCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reservationsAvailable = try container.decodeFlexibleBoolIfPresent(forKey: .reservationsAvailable)
        newImportsDetected = try container.decodeFlexibleIntIfPresent(forKey: .newImportsDetected)
        itemsNeedingReview = try container.decodeFlexibleIntIfPresent(forKey: .itemsNeedingReview)
        hiddenOrSupersededCount = try container.decodeFlexibleIntIfPresent(forKey: .hiddenOrSupersededCount)
        possibleDuplicatesCount = try container.decodeFlexibleIntIfPresent(forKey: .possibleDuplicatesCount)
    }

    private enum CodingKeys: String, CodingKey {
        case reservationsAvailable
        case newImportsDetected
        case itemsNeedingReview
        case hiddenOrSupersededCount
        case possibleDuplicatesCount
    }
}

struct IntelligenceDeveloperSummaryDTO: Decodable, Equatable {
    let managedRowsInRange: Int?
    let formSourceRowsInRange: Int?
    let manualSourceRowsInRange: Int?
    let hiddenRowsInRange: Int?
    let supersededRowsInRange: Int?
    let duplicateMarkedRowsInRange: Int?
    let importFailureCount: Int?
    let spamOrRejectedSubmissionCount: Int?
    let lastManagedUpdateAt: String?
    let lastGeneratedAt: String?

    init(
        managedRowsInRange: Int? = nil,
        formSourceRowsInRange: Int? = nil,
        manualSourceRowsInRange: Int? = nil,
        hiddenRowsInRange: Int? = nil,
        supersededRowsInRange: Int? = nil,
        duplicateMarkedRowsInRange: Int? = nil,
        importFailureCount: Int? = nil,
        spamOrRejectedSubmissionCount: Int? = nil,
        lastManagedUpdateAt: String? = nil,
        lastGeneratedAt: String? = nil
    ) {
        self.managedRowsInRange = managedRowsInRange
        self.formSourceRowsInRange = formSourceRowsInRange
        self.manualSourceRowsInRange = manualSourceRowsInRange
        self.hiddenRowsInRange = hiddenRowsInRange
        self.supersededRowsInRange = supersededRowsInRange
        self.duplicateMarkedRowsInRange = duplicateMarkedRowsInRange
        self.importFailureCount = importFailureCount
        self.spamOrRejectedSubmissionCount = spamOrRejectedSubmissionCount
        self.lastManagedUpdateAt = lastManagedUpdateAt
        self.lastGeneratedAt = lastGeneratedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        managedRowsInRange = try container.decodeFlexibleIntIfPresent(forKey: .managedRowsInRange)
        formSourceRowsInRange = try container.decodeFlexibleIntIfPresent(forKey: .formSourceRowsInRange)
        manualSourceRowsInRange = try container.decodeFlexibleIntIfPresent(forKey: .manualSourceRowsInRange)
        hiddenRowsInRange = try container.decodeFlexibleIntIfPresent(forKey: .hiddenRowsInRange)
        supersededRowsInRange = try container.decodeFlexibleIntIfPresent(forKey: .supersededRowsInRange)
        duplicateMarkedRowsInRange = try container.decodeFlexibleIntIfPresent(forKey: .duplicateMarkedRowsInRange)
        importFailureCount = try container.decodeFlexibleIntIfPresent(forKey: .importFailureCount)
        spamOrRejectedSubmissionCount = try container.decodeFlexibleIntIfPresent(forKey: .spamOrRejectedSubmissionCount)
        lastManagedUpdateAt = try container.decodeIfPresent(String.self, forKey: .lastManagedUpdateAt)
        lastGeneratedAt = try container.decodeIfPresent(String.self, forKey: .lastGeneratedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case managedRowsInRange
        case formSourceRowsInRange
        case manualSourceRowsInRange
        case hiddenRowsInRange
        case supersededRowsInRange
        case duplicateMarkedRowsInRange
        case importFailureCount
        case spamOrRejectedSubmissionCount
        case lastManagedUpdateAt
        case lastGeneratedAt
    }
}
