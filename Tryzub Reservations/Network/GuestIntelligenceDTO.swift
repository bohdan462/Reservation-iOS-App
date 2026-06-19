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

// MARK: - Reservation Profile Pack

struct GuestIntelligenceMatchedVisitPreviewDTO: Decodable, Equatable, Identifiable {
    var id: Int { reservationId }

    let reservationId: Int
    let date: String
    let time: String
    let partySize: Int
    let status: String
    let tableName: String?
    let source: String?
    let guestNotesPreview: String?
    let staffNotesPreview: String?
    let hasGuestNotes: Bool
    let hasStaffNotes: Bool
    let signals: GuestIntelligenceVisitSignalsDTO?
    let matchConfidence: String?
    let matchedBy: [String]

    enum CodingKeys: String, CodingKey {
        case reservationId
        case date
        case time
        case partySize
        case status
        case tableName
        case source
        case guestNotesPreview
        case staffNotesPreview
        case hasGuestNotes
        case hasStaffNotes
        case signals
        case matchConfidence
        case matchedBy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reservationId = try container.decodeFlexibleIntIfPresent(forKey: .reservationId) ?? 0
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        time = try container.decodeIfPresent(String.self, forKey: .time) ?? ""
        partySize = try container.decodeFlexibleIntIfPresent(forKey: .partySize) ?? 0
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        tableName = try container.decodeIfPresent(String.self, forKey: .tableName)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        guestNotesPreview = try container.decodeIfPresent(String.self, forKey: .guestNotesPreview)
        staffNotesPreview = try container.decodeIfPresent(String.self, forKey: .staffNotesPreview)
        hasGuestNotes = try container.decodeFlexibleBoolIfPresent(forKey: .hasGuestNotes) ?? false
        hasStaffNotes = try container.decodeFlexibleBoolIfPresent(forKey: .hasStaffNotes) ?? false
        signals = try container.decodeIfPresent(GuestIntelligenceVisitSignalsDTO.self, forKey: .signals)
        matchConfidence = try container.decodeIfPresent(String.self, forKey: .matchConfidence)
        matchedBy = try container.decodeIfPresent([String].self, forKey: .matchedBy) ?? []
    }
}

struct GuestIntelligenceVisitSignalsDTO: Decodable, Equatable {
    let occasion: String?
    let dietary: String?
    let allergy: String?
    let tablePreference: String?
    let accessibility: String?
    let serviceIssue: String?

    // Decoder uses .convertFromSnakeCase on ReservationsAPIClient.
    // All CodingKey cases must be camelCase — no raw snake_case overrides.
    // table_preference → tablePreference, service_issue → serviceIssue
    enum CodingKeys: String, CodingKey {
        case occasion
        case dietary
        case allergy
        case tablePreference
        case accessibility
        case serviceIssue
    }
}

struct GuestIntelligenceHistoryDTO: Decodable, Equatable {
    let seenBefore: Bool?
    let priorVisitCount: Int?
    let lastSeenDate: String?
    let safeCopy: String?
    let matchedVisitPreview: [GuestIntelligenceMatchedVisitPreviewDTO]
    let bookingHistory: [GuestHistoryRowDTO]
    let notesHistory: [GuestNoteHistoryItemDTO]

    enum CodingKeys: String, CodingKey {
        case seenBefore
        case priorVisitCount
        case lastSeenDate
        case safeCopy
        case matchedVisitPreview
        case bookingHistory
        case notesHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seenBefore = try container.decodeFlexibleBoolIfPresent(forKey: .seenBefore)
        priorVisitCount = try container.decodeFlexibleIntIfPresent(forKey: .priorVisitCount)
        lastSeenDate = try container.decodeIfPresent(String.self, forKey: .lastSeenDate)
        safeCopy = try container.decodeIfPresent(String.self, forKey: .safeCopy)
        matchedVisitPreview = try container.decodeIfPresent(
            [GuestIntelligenceMatchedVisitPreviewDTO].self,
            forKey: .matchedVisitPreview
        ) ?? []
        bookingHistory = try container.decodeIfPresent([GuestHistoryRowDTO].self, forKey: .bookingHistory) ?? []
        notesHistory = try container.decodeIfPresent([GuestNoteHistoryItemDTO].self, forKey: .notesHistory) ?? []
    }
}

struct GuestIntelligenceProfileSummaryDTO: Decodable, Equatable {
    let summaryText: String?
    let managementNotes: [String]
    let confidence: String?
    let historyScope: String?

    enum CodingKeys: String, CodingKey {
        case summaryText
        case managementNotes
        case confidence
        case historyScope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summaryText = try container.decodeIfPresent(String.self, forKey: .summaryText)
        confidence = try container.decodeIfPresent(String.self, forKey: .confidence)
        historyScope = try container.decodeIfPresent(String.self, forKey: .historyScope)
        if let notes = try? container.decode([String].self, forKey: .managementNotes) {
            managementNotes = notes.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } else if let legacyNote = try? container.decode(String.self, forKey: .managementNotes) {
            let trimmed = legacyNote.trimmingCharacters(in: .whitespacesAndNewlines)
            managementNotes = trimmed.isEmpty ? [] : [trimmed]
        } else {
            managementNotes = []
        }
    }
}

struct GuestIntelligencePreferencesDTO: Decodable, Equatable {
    let usualTime: String?
    let usualWeekday: String?
    let usualPartySize: Int?
    let largestPartySize: Int?
    let preferredTables: [String]?
    let preferredTableArea: String?
    let sourcePattern: String?
    let commonOccasion: String?

    enum CodingKeys: String, CodingKey {
        case usualTime
        case usualWeekday
        case usualPartySize
        case largestPartySize
        case preferredTables
        case preferredTableArea
        case sourcePattern
        case commonOccasion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usualTime = try container.decodeIfPresent(String.self, forKey: .usualTime)
        usualWeekday = try container.decodeIfPresent(String.self, forKey: .usualWeekday)
        usualPartySize = try container.decodeFlexibleIntIfPresent(forKey: .usualPartySize)
        largestPartySize = try container.decodeFlexibleIntIfPresent(forKey: .largestPartySize)
        preferredTables = try container.decodeIfPresent([String].self, forKey: .preferredTables)
        preferredTableArea = try container.decodeIfPresent(String.self, forKey: .preferredTableArea)
        sourcePattern = try container.decodeIfPresent(String.self, forKey: .sourcePattern)
        commonOccasion = try container.decodeIfPresent(String.self, forKey: .commonOccasion)
    }
}

struct GuestIntelligenceNoteIntelligenceDTO: Decodable, Equatable {
    let hasPriorGuestNotes: Bool
    let hasPriorStaffNotes: Bool
    let guestNoteCount: Int
    let staffNoteCount: Int
    let latestGuestNotePreview: String?
    let latestStaffNotePreview: String?
    let allNoteSignals: [String: [String]]

    enum CodingKeys: String, CodingKey {
        case hasPriorGuestNotes
        case hasPriorStaffNotes
        case guestNoteCount
        case staffNoteCount
        case latestGuestNotePreview
        case latestStaffNotePreview
        case allNoteSignals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasPriorGuestNotes = try container.decodeFlexibleBoolIfPresent(forKey: .hasPriorGuestNotes) ?? false
        hasPriorStaffNotes = try container.decodeFlexibleBoolIfPresent(forKey: .hasPriorStaffNotes) ?? false
        guestNoteCount = try container.decodeFlexibleIntIfPresent(forKey: .guestNoteCount) ?? 0
        staffNoteCount = try container.decodeFlexibleIntIfPresent(forKey: .staffNoteCount) ?? 0
        latestGuestNotePreview = try container.decodeIfPresent(String.self, forKey: .latestGuestNotePreview)
        latestStaffNotePreview = try container.decodeIfPresent(String.self, forKey: .latestStaffNotePreview)
        if let buckets = try? container.decode([String: [String]].self, forKey: .allNoteSignals) {
            allNoteSignals = buckets
        } else if let legacySignals = try? container.decode([String].self, forKey: .allNoteSignals) {
            allNoteSignals = legacySignals.isEmpty ? [:] : ["signals": legacySignals]
        } else {
            allNoteSignals = [:]
        }
    }
}

struct GuestIntelligenceVisitAnalyticsDTO: Decodable, Equatable {
    let knownVisitCount: Int?
    let priorVisitCount: Int?
    let completedCount: Int?
    let cancelledCount: Int?
    let noShowCount: Int?
    let averagePartySize: Double?
    let maxPartySize: Int?
    let lastSeenDate: String?
    let firstSeenDate: String?
    let sourceBreakdown: [String: Int]?
    let statusBreakdown: [String: Int]?

    enum CodingKeys: String, CodingKey {
        case knownVisitCount
        case priorVisitCount
        case completedCount
        case cancelledCount
        case noShowCount
        case averagePartySize
        case maxPartySize
        case lastSeenDate
        case firstSeenDate
        case sourceBreakdown
        case statusBreakdown
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        knownVisitCount = try container.decodeFlexibleIntIfPresent(forKey: .knownVisitCount)
        priorVisitCount = try container.decodeFlexibleIntIfPresent(forKey: .priorVisitCount)
        completedCount = try container.decodeFlexibleIntIfPresent(forKey: .completedCount)
        cancelledCount = try container.decodeFlexibleIntIfPresent(forKey: .cancelledCount)
        noShowCount = try container.decodeFlexibleIntIfPresent(forKey: .noShowCount)
        averagePartySize = try container.decodeFlexibleDoubleIfPresent(forKey: .averagePartySize)
        maxPartySize = try container.decodeFlexibleIntIfPresent(forKey: .maxPartySize)
        lastSeenDate = try container.decodeIfPresent(String.self, forKey: .lastSeenDate)
        firstSeenDate = try container.decodeIfPresent(String.self, forKey: .firstSeenDate)
        sourceBreakdown = try container.decodeFlexibleStringIntMapIfPresent(forKey: .sourceBreakdown)
        statusBreakdown = try container.decodeFlexibleStringIntMapIfPresent(forKey: .statusBreakdown)
    }
}

struct GuestIntelligenceHostProfilePacketDTO: Decodable, Equatable {
    let guestName: String?
    let identityConfidence: String?
    let seenBefore: Bool?
    let safeHistoryLine: String?
    let lastSeenLine: String?
    let preferenceLines: [String]?
    let riskLines: [String]?
    let serviceLines: [String]?
    let previewCount: Int?

    enum CodingKeys: String, CodingKey {
        case guestName
        case identityConfidence
        case seenBefore
        case safeHistoryLine
        case lastSeenLine
        case preferenceLines
        case riskLines
        case serviceLines
        case previewCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guestName = try container.decodeIfPresent(String.self, forKey: .guestName)
        identityConfidence = try container.decodeIfPresent(String.self, forKey: .identityConfidence)
        seenBefore = try container.decodeFlexibleBoolIfPresent(forKey: .seenBefore)
        safeHistoryLine = try container.decodeIfPresent(String.self, forKey: .safeHistoryLine)
        lastSeenLine = try container.decodeIfPresent(String.self, forKey: .lastSeenLine)
        preferenceLines = try container.decodeIfPresent([String].self, forKey: .preferenceLines)
        riskLines = try container.decodeIfPresent([String].self, forKey: .riskLines)
        serviceLines = try container.decodeIfPresent([String].self, forKey: .serviceLines)
        previewCount = try container.decodeFlexibleIntIfPresent(forKey: .previewCount)
    }
}

/// Full reservation profile intelligence pack from GET /guest-intelligence/reservation/{id}.
/// Decoded via `ReservationsAPIClient` JSONDecoder with `.convertFromSnakeCase` — property names
/// use camelCase; no per-field CodingKeys required unless a backend key diverges from snake_case.
struct GuestIntelligenceProfilePackDTO: Equatable {
    let contractVersion: String?
    let profilePackVersion: String?
    let scope: String?
    let reservationId: Int
    let guestName: String?
    let history: GuestIntelligenceHistoryDTO?
    let profileSummary: GuestIntelligenceProfileSummaryDTO?
    let preferences: GuestIntelligencePreferencesDTO?
    let noteIntelligence: GuestIntelligenceNoteIntelligenceDTO?
    let visitAnalytics: GuestIntelligenceVisitAnalyticsDTO?
    let hostProfilePacket: GuestIntelligenceHostProfilePacketDTO?
    let item: GuestIntelligenceSummaryDTO?
    let bookingHistory: [GuestHistoryRowDTO]
    let notesHistory: [GuestNoteHistoryItemDTO]
    let historyCounts: GuestHistoryCountsDTO?

    var matchedVisitPreview: [GuestIntelligenceMatchedVisitPreviewDTO] {
        history?.matchedVisitPreview ?? []
    }
}

extension GuestIntelligenceProfilePackDTO: Decodable {
    enum CodingKeys: String, CodingKey {
        case contractVersion
        case profilePackVersion
        case scope
        case reservationId
        case guestName
        case history
        case profileSummary
        case preferences
        case noteIntelligence
        case visitAnalytics
        case hostProfilePacket
        case item
        case bookingHistory
        case notesHistory
        case historyCounts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contractVersion = try container.decodeIfPresent(String.self, forKey: .contractVersion)
        profilePackVersion = try container.decodeIfPresent(String.self, forKey: .profilePackVersion)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        reservationId = try container.decodeFlexibleIntIfPresent(forKey: .reservationId) ?? 0
        guestName = try container.decodeIfPresent(String.self, forKey: .guestName)
        history = try container.decodeIfPresent(GuestIntelligenceHistoryDTO.self, forKey: .history)
        profileSummary = try container.decodeIfPresent(
            GuestIntelligenceProfileSummaryDTO.self,
            forKey: .profileSummary
        )
        preferences = try container.decodeIfPresent(GuestIntelligencePreferencesDTO.self, forKey: .preferences)
        noteIntelligence = try container.decodeIfPresent(
            GuestIntelligenceNoteIntelligenceDTO.self,
            forKey: .noteIntelligence
        )
        visitAnalytics = try container.decodeIfPresent(
            GuestIntelligenceVisitAnalyticsDTO.self,
            forKey: .visitAnalytics
        )
        hostProfilePacket = try container.decodeIfPresent(
            GuestIntelligenceHostProfilePacketDTO.self,
            forKey: .hostProfilePacket
        )
        item = try container.decodeIfPresent(GuestIntelligenceSummaryDTO.self, forKey: .item)
        bookingHistory = try container.decodeIfPresent([GuestHistoryRowDTO].self, forKey: .bookingHistory) ?? []
        notesHistory = try container.decodeIfPresent([GuestNoteHistoryItemDTO].self, forKey: .notesHistory) ?? []
        historyCounts = try container.decodeIfPresent(GuestHistoryCountsDTO.self, forKey: .historyCounts)
    }
}

/// Legacy envelope alias — full pack decodes as GuestIntelligenceProfilePackDTO.
typealias GuestIntelligenceReservationProfileDTO = GuestIntelligenceProfilePackDTO

extension GuestIntelligenceProfilePackDTO {
    func replacingReservationID(_ reservationID: Int) -> GuestIntelligenceProfilePackDTO {
        GuestIntelligenceProfilePackDTO(
            contractVersion: contractVersion,
            profilePackVersion: profilePackVersion,
            scope: scope,
            reservationId: reservationID,
            guestName: guestName,
            history: history,
            profileSummary: profileSummary,
            preferences: preferences,
            noteIntelligence: noteIntelligence,
            visitAnalytics: visitAnalytics,
            hostProfilePacket: hostProfilePacket,
            item: item,
            bookingHistory: bookingHistory,
            notesHistory: notesHistory,
            historyCounts: historyCounts
        )
    }

    static func fromLegacySummary(_ summary: GuestIntelligenceSummaryDTO) -> GuestIntelligenceProfilePackDTO {
        GuestIntelligenceProfilePackDTO(
            contractVersion: nil,
            profilePackVersion: nil,
            scope: nil,
            reservationId: summary.reservationId,
            guestName: summary.guestName,
            history: nil,
            profileSummary: nil,
            preferences: nil,
            noteIntelligence: nil,
            visitAnalytics: nil,
            hostProfilePacket: nil,
            item: summary,
            bookingHistory: [],
            notesHistory: [],
            historyCounts: nil
        )
    }

    var resolvedSummary: GuestIntelligenceSummaryDTO? {
        if var summary = item {
            if summary.reservationId == 0, reservationId > 0 {
                summary = summary.withReservationID(reservationId)
            }
            return summary
        }
        return nil
    }

    var fullProfile: GuestFullProfile {
        GuestFullProfile(
            bookingHistory: bookingHistory.isEmpty ? (history?.bookingHistory ?? []) : bookingHistory,
            notesHistory: notesHistory.isEmpty ? (history?.notesHistory ?? []) : notesHistory
        )
    }
}

struct GuestIntelligenceProfilePackDiagnostics: Equatable {
    var reservationID: Int
    var profilePackVersion: String?
    var source: String?
    var hasHistory: Bool
    var hasProfileSummary: Bool
    var hasPreferences: Bool
    var hasNoteIntelligence: Bool
    var hasVisitAnalytics: Bool
    var hasHostProfilePacket: Bool
    var previewRowCount: Int
    var hasNotes: Bool
}

struct GuestIntelligenceOpaqueSection: Decodable, Equatable {}

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

    func withReservationID(_ reservationID: Int) -> GuestIntelligenceSummaryDTO {
        GuestIntelligenceSummaryDTO(
            reservationId: reservationID,
            guestKey: guestKey,
            guestName: guestName,
            identityConfidence: identityConfidence,
            classification: classification,
            matchedVisitCount: matchedVisitCount,
            cleanVisitCount: cleanVisitCount,
            lastVisitDate: lastVisitDate,
            firstVisitDate: firstVisitDate,
            usualTime: usualTime,
            usualWeekday: usualWeekday,
            averagePartySize: averagePartySize,
            maxPartySize: maxPartySize,
            onlineCount: onlineCount,
            callInCount: callInCount,
            manualCount: manualCount,
            cancelledCount: cancelledCount,
            noShowCount: noShowCount,
            hasSeatingPreference: hasSeatingPreference,
            hasAllergyNote: hasAllergyNote,
            hasAccessibilityNote: hasAccessibilityNote,
            hasSpecialOccasionNote: hasSpecialOccasionNote,
            hasPriorServiceIssue: hasPriorServiceIssue,
            possibleDuplicate: possibleDuplicate,
            relatedReservationIds: relatedReservationIds
        )
    }
}

extension GuestIntelligenceSummaryDTO {
    init(
        reservationId: Int,
        guestKey: String?,
        guestName: String?,
        identityConfidence: GuestIdentityConfidenceDTO,
        classification: GuestClassificationDTO,
        matchedVisitCount: Int,
        cleanVisitCount: Int,
        lastVisitDate: String?,
        firstVisitDate: String?,
        usualTime: String?,
        usualWeekday: String?,
        averagePartySize: Double?,
        maxPartySize: Int?,
        onlineCount: Int,
        callInCount: Int,
        manualCount: Int,
        cancelledCount: Int,
        noShowCount: Int,
        hasSeatingPreference: Bool,
        hasAllergyNote: Bool,
        hasAccessibilityNote: Bool,
        hasSpecialOccasionNote: Bool,
        hasPriorServiceIssue: Bool,
        possibleDuplicate: Bool,
        relatedReservationIds: [Int]
    ) {
        self.reservationId = reservationId
        self.guestKey = guestKey
        self.guestName = guestName
        self.identityConfidence = identityConfidence
        self.classification = classification
        self.matchedVisitCount = matchedVisitCount
        self.cleanVisitCount = cleanVisitCount
        self.lastVisitDate = lastVisitDate
        self.firstVisitDate = firstVisitDate
        self.usualTime = usualTime
        self.usualWeekday = usualWeekday
        self.averagePartySize = averagePartySize
        self.maxPartySize = maxPartySize
        self.onlineCount = onlineCount
        self.callInCount = callInCount
        self.manualCount = manualCount
        self.cancelledCount = cancelledCount
        self.noShowCount = noShowCount
        self.hasSeatingPreference = hasSeatingPreference
        self.hasAllergyNote = hasAllergyNote
        self.hasAccessibilityNote = hasAccessibilityNote
        self.hasSpecialOccasionNote = hasSpecialOccasionNote
        self.hasPriorServiceIssue = hasPriorServiceIssue
        self.possibleDuplicate = possibleDuplicate
        self.relatedReservationIds = relatedReservationIds
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
    func decodeFlexibleStringIntMapIfPresent(forKey key: Key) throws -> [String: Int]? {
        if let values = try? decodeIfPresent([String: Int].self, forKey: key) {
            return values
        }

        if let stringValues = try? decodeIfPresent([String: String].self, forKey: key) {
            var mapped: [String: Int] = [:]
            for (key, value) in stringValues {
                if let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    mapped[key] = intValue
                }
            }
            return mapped.isEmpty ? nil : mapped
        }

        return nil
    }

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
