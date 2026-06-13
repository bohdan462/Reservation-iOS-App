//
//  HostIntelligenceModels.swift
//  Tryzub Reservations
//
//  Deterministic data contracts for the Host Intelligence engine.
//  Pure types only — no business logic, network, UI, or timers.
//

import Foundation

// MARK: - Severity & Service State

enum HostSeverity: String, Codable, CaseIterable {
    case info
    case watch
    case warning
    case critical

    /// Lower rank means higher urgency (critical = 0).
    var rank: Int {
        switch self {
        case .critical: return 0
        case .warning: return 1
        case .watch: return 2
        case .info: return 3
        }
    }
}

enum HostServiceState: String, Codable, CaseIterable {
    case calm
    case building
    case busy
    case critical
}

enum HostFactCategory: String, Codable, CaseIterable {
    case timing
    case capacity
    case table
    case guest
    case allergy
    case largeParty
    case arrivalWave
    case cancellation
    case overdue
    case opportunity
    case bookingDecision
    case analytics
    case sync
    case note
    case preference
    case duplicate
    case unknown
}

// MARK: - Briefing Facts

struct HostBriefingFact: Identifiable, Codable, Equatable {
    let id: String
    let severity: HostSeverity
    let category: HostFactCategory
    let title: String
    let detail: String
    let evidence: [String]
    let relatedReservationIDs: [Int]
    let suggestedActionTitle: String?
}

// MARK: - Suggested Actions

enum HostActionKind: String, Codable, CaseIterable {
    case reviewReservation
    case assignTable
    case seatReservation
    case completeReservation
    case confirmReservation
    case suggestAlternateTime
    case closeSlot
    case holdTable
    case releaseTable
    case alertServer
    case generateEmailDraft
    case generateGuestManageLink
    case markNoShow
    case reviewCancellationOpportunity
    case noAction
}

struct HostSuggestedAction: Identifiable, Codable, Equatable {
    let id: String
    let severity: HostSeverity
    let kind: HostActionKind
    let title: String
    let reason: String
    let relatedReservationIDs: [Int]
    let targetSlotTime: String?
    let targetTableName: String?
    let requiresStaffConfirmation: Bool
}

// MARK: - Slot Pressure

enum HostPressureSeverity: String, Codable, CaseIterable {
    case calm
    case watch
    case busy
    case critical
}

struct HostSlotPressure: Identifiable, Codable, Equatable {
    let id: String
    let slotTime: String
    let reservationCount: Int
    let guestCount: Int
    let largePartyCount: Int
    let noTableCount: Int
    let projectedSeatedGuestCount: Int?
    let capacityRatio: Double?
    let isBlocked: Bool
    let severity: HostPressureSeverity
    let facts: [HostBriefingFact]
    let suggestedActions: [HostSuggestedAction]
}

// MARK: - Guest Signals

enum HostGuestSignalKind: String, Codable, CaseIterable {
    case allergy
    case regularGuest
    case vip
    case importantGuest
    case specialOccasion
    case seatingPreference
    case accessibility
    case cancellationRisk
    case noShowRisk
    case previousServiceIssue
    case manualCallIn
    case possibleDuplicate
    case noteReminder
    case unknown
}

struct HostGuestSignal: Identifiable, Codable, Equatable {
    let id: String
    let reservationID: Int
    let guestName: String
    let kind: HostGuestSignalKind
    let severity: HostSeverity
    let message: String
    let evidence: [String]
}

// MARK: - Table Signals

enum HostTableSignalKind: String, Codable, CaseIterable {
    case noTableAssigned
    case tableTurnRisk
    case doubleBookedTable
    case tableFreed
    case tableCapacityMismatch
    case longSeated
    case cancellationFreedTable
    case unknown
}

struct HostTableSignal: Identifiable, Codable, Equatable {
    let id: String
    let tableName: String?
    let kind: HostTableSignalKind
    let severity: HostSeverity
    let title: String
    let detail: String
    let relatedReservationIDs: [Int]
    let evidence: [String]
}

// MARK: - Seated Timing

enum SeatedTimeReliability: String, Codable, CaseIterable {
    case localTimestamp
    case inferredFromStatus
    case apiUpdatedAtFallback
    case unknown
}

struct HostSeatedTimingSignal: Identifiable, Codable, Equatable {
    let id: String
    let reservationID: Int
    let guestName: String
    let reliability: SeatedTimeReliability
    let seatedAtDescription: String?
    let elapsedMinutes: Int?
    let message: String
    let confidence: Double
}

// MARK: - Booking Decisions

enum HostBookingDecisionKind: String, Codable, CaseIterable {
    case autoConfirm
    case suggestAlternateTime
    case manualReview
    case reject
    case noDecision
}

struct HostBookingDecisionResult: Identifiable, Codable, Equatable {
    let id: String
    let reservationID: Int?
    let decision: HostBookingDecisionKind
    let requestedTime: String?
    let suggestedTime: String?
    let confidence: Double
    let reason: String
    let evidence: [String]
    let requiresStaffConfirmation: Bool
}

// MARK: - LLM Packet (writer-only; engine remains authoritative)

struct HostLLMFact: Codable, Equatable {
    let severity: HostSeverity
    let category: HostFactCategory
    let title: String
    let detail: String
    let evidence: [String]
    let suggestedAction: String?
}

struct HostLLMPacket: Codable, Equatable {
    let generatedAtDescription: String
    let serviceState: HostServiceState
    let pressureScore: Double
    let topFacts: [HostLLMFact]
    let forbiddenBehaviors: [String]
    let writingRules: [String]

    var hasMeaningfulBriefingFacts: Bool {
        !topFacts.isEmpty
    }

    /// True when every fact is low-risk guest memory / preference / note / booking queue copy.
    var isHostBoardTemplateOnlyPacket: Bool {
        guard hasMeaningfulBriefingFacts else { return true }
        if topFacts.contains(where: { $0.severity == .warning || $0.severity == .critical }) {
            return false
        }
        let lowRisk: Set<HostFactCategory> = [.guest, .preference, .note, .bookingDecision]
        return topFacts.allSatisfy { lowRisk.contains($0.category) }
    }

    /// Stable fingerprint for briefing deduplication — excludes volatile timestamps.
    var briefingFingerprint: String {
        let roundedPressure = (pressureScore * 10).rounded() / 10
        let factParts = topFacts.map { fact in
            [
                fact.severity.rawValue,
                fact.category.rawValue,
                fact.title,
                fact.detail,
                fact.suggestedAction ?? "",
                fact.evidence.joined(separator: ",")
            ].joined(separator: "|")
        }
        let factsKey = factParts.joined(separator: ";")
        return "\(serviceState.rawValue)|\(roundedPressure)|\(factsKey)"
    }

    static var empty: HostLLMPacket {
        HostLLMPacket(
            generatedAtDescription: "",
            serviceState: .calm,
            pressureScore: 0,
            topFacts: [],
            forbiddenBehaviors: [
                "Do not invent guests, tables, allergies, times, or counts.",
                "Do not make booking decisions.",
                "Do not claim an action was completed.",
                "Do not override deterministic engine facts.",
                "Do not recommend assigning a specific table for small parties.",
                "Table suggestions are review-only and should focus on large parties, capacity mismatches, or combined-table needs."
            ],
            writingRules: [
                "Use only provided facts.",
                "Write like a calm restaurant host.",
                "Maximum 2 short sentences.",
                "Lead with the highest-severity operational issue.",
                "Use review/check table-plan language; never say a table was assigned.",
                "One manual review action at most, only when suggested review adds value."
            ]
        )
    }
}

// MARK: - Host Card Render State

enum HostIntelligenceRenderState: String, Equatable {
  case evaluating
  case ready
}

struct HostEvaluationStabilityContext: Equatable {
  var isReservationRefreshInFlight: Bool = false
  var isAvailabilitySummaryLoading: Bool = false
  var isGuestIntelligenceLoading: Bool = false
  var selectedDateRecentlyChanged: Bool = false
  var hostSnapshotIncomplete: Bool = false

  var allowsEmptyReplacement: Bool {
    !isReservationRefreshInFlight
      && !hostSnapshotIncomplete
  }

  var isEnrichmentLoading: Bool {
    isAvailabilitySummaryLoading || isGuestIntelligenceLoading
  }
}

// MARK: - Decision Snapshot

struct HostDecisionSnapshot: Codable, Equatable {
    let generatedAt: Date
    let serviceState: HostServiceState
    let pressureScore: Double
    let slotPressures: [HostSlotPressure]
    let briefingFacts: [HostBriefingFact]
    let suggestedActions: [HostSuggestedAction]
    let guestSignals: [HostGuestSignal]
    let tableSignals: [HostTableSignal]
    let seatedTimingSignals: [HostSeatedTimingSignal]
    let bookingDecisions: [HostBookingDecisionResult]
    let templateBriefingText: String
    let llmPacket: HostLLMPacket
    let arrivalPressureFacts: ArrivalPressureManagerFacts?

    static var empty: HostDecisionSnapshot {
        HostDecisionSnapshot(
            generatedAt: Date(),
            serviceState: .calm,
            pressureScore: 0,
            slotPressures: [],
            briefingFacts: [],
            suggestedActions: [],
            guestSignals: [],
            tableSignals: [],
            seatedTimingSignals: [],
            bookingDecisions: [],
            templateBriefingText: "Nothing needs attention right now.",
            llmPacket: .empty,
            arrivalPressureFacts: nil
        )
    }

    var hasAttentionContent: Bool {
        !briefingFacts.isEmpty || !suggestedActions.isEmpty
    }

    var hasOperationalNoTableSoonContent: Bool {
        briefingFacts.contains { $0.id.hasPrefix("no-table-due-soon-") }
            || suggestedActions.contains { $0.id.hasPrefix("assign-table-") }
    }
}

// MARK: - Briefing Writer

enum HostBriefingProviderKind: String, Codable, CaseIterable {
    case template
    case localPlaceholder
    case localModel

    var displayName: String {
        switch self {
        case .template: return "Template"
        case .localPlaceholder: return "Local placeholder"
        case .localModel: return "Local model"
        }
    }
}

// MARK: - Settings & Table Config

struct HostIntelligenceSettings: Codable, Equatable {
    var isEnabled: Bool
    var slotIntervalMinutes: Int
    var lookaheadMinutes: Int
    var restaurantCapacity: Int
    /// Host advisory threshold for slot/table pressure (aligns with backend `largePartyReviewThreshold` default of 7).
    var largePartyThreshold: Int
    var criticalPartyThreshold: Int
    var maxReservationsPerSlot: Int
    var maxLargePartiesPerSlot: Int
    var comfortableCapacityRatio: Double
    var criticalCapacityRatio: Double
    var dueSoonMinutes: Int
    var noTableDueSoonMinutes: Int
    var longSeatedWarningMinutes: Int
    var includeGuestSignals: Bool
    var includeAnalyticsSignals: Bool
    var includeLLMPacket: Bool
    var enableBookingDecisioning: Bool
    /// Recommend as confirm candidate only — never auto-confirms.
    var autoConfirmRecommendationsEnabled: Bool
    var suggestAlternateTimesEnabled: Bool
    var autoConfirmWeekdaysOnly: Bool
    var minimumConfidenceForAutoConfirm: Double
    var maxPartySizeForAutoConfirm: Int
    var useEnhancedBriefing: Bool
    var enhancedBriefingProvider: HostBriefingProviderKind
    /// When false, Host board uses template briefing even if local model is selected.
    var useLocalModelOnHostBoard: Bool
    /// When true, Reservation Detail may use on-device wording for guest message drafts (staff reviews before send).
    var useLocalModelForGuestMessageDrafts: Bool
    /// When true, Reservation Detail enriches note signals with on-device model analysis
    /// (tone + classification). Deterministic keyword signals always remain the baseline.
    var useLocalModelForNoteAnalysis: Bool
    /// When true, Host board may show separated operational prompts from deterministic facts.
    var useSeparatedBriefingPrompts: Bool

    init(
        isEnabled: Bool = true,
        slotIntervalMinutes: Int = 20,
        lookaheadMinutes: Int = 180,
        restaurantCapacity: Int = 100,
        largePartyThreshold: Int = 7,
        criticalPartyThreshold: Int = 12,
        maxReservationsPerSlot: Int = 4,
        maxLargePartiesPerSlot: Int = 1,
        comfortableCapacityRatio: Double = 0.85,
        criticalCapacityRatio: Double = 1.0,
        dueSoonMinutes: Int = 20,
        noTableDueSoonMinutes: Int = 30,
        longSeatedWarningMinutes: Int = 90,
        includeGuestSignals: Bool = true,
        includeAnalyticsSignals: Bool = false,
        includeLLMPacket: Bool = true,
        enableBookingDecisioning: Bool = true,
        autoConfirmRecommendationsEnabled: Bool = false,
        suggestAlternateTimesEnabled: Bool = true,
        autoConfirmWeekdaysOnly: Bool = true,
        minimumConfidenceForAutoConfirm: Double = 0.8,
        maxPartySizeForAutoConfirm: Int = 6,
        // iPad / demo build defaults: 3B model on by default when present.
        // Enhanced briefing is enabled and the local model runs on the Host board.
        // Existing persisted user settings still override these via the decoder below.
        useEnhancedBriefing: Bool = true,
        enhancedBriefingProvider: HostBriefingProviderKind = .localModel,
        useLocalModelOnHostBoard: Bool = true,
        useLocalModelForGuestMessageDrafts: Bool = true,
        useLocalModelForNoteAnalysis: Bool = true,
        useSeparatedBriefingPrompts: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.slotIntervalMinutes = slotIntervalMinutes
        self.lookaheadMinutes = lookaheadMinutes
        self.restaurantCapacity = restaurantCapacity
        self.largePartyThreshold = largePartyThreshold
        self.criticalPartyThreshold = criticalPartyThreshold
        self.maxReservationsPerSlot = maxReservationsPerSlot
        self.maxLargePartiesPerSlot = maxLargePartiesPerSlot
        self.comfortableCapacityRatio = comfortableCapacityRatio
        self.criticalCapacityRatio = criticalCapacityRatio
        self.dueSoonMinutes = dueSoonMinutes
        self.noTableDueSoonMinutes = noTableDueSoonMinutes
        self.longSeatedWarningMinutes = longSeatedWarningMinutes
        self.includeGuestSignals = includeGuestSignals
        self.includeAnalyticsSignals = includeAnalyticsSignals
        self.includeLLMPacket = includeLLMPacket
        self.enableBookingDecisioning = enableBookingDecisioning
        self.autoConfirmRecommendationsEnabled = autoConfirmRecommendationsEnabled
        self.suggestAlternateTimesEnabled = suggestAlternateTimesEnabled
        self.autoConfirmWeekdaysOnly = autoConfirmWeekdaysOnly
        self.minimumConfidenceForAutoConfirm = minimumConfidenceForAutoConfirm
        self.maxPartySizeForAutoConfirm = maxPartySizeForAutoConfirm
        self.useEnhancedBriefing = useEnhancedBriefing
        self.enhancedBriefingProvider = enhancedBriefingProvider
        self.useLocalModelOnHostBoard = useLocalModelOnHostBoard
        self.useLocalModelForGuestMessageDrafts = useLocalModelForGuestMessageDrafts
        self.useLocalModelForNoteAnalysis = useLocalModelForNoteAnalysis
        self.useSeparatedBriefingPrompts = useSeparatedBriefingPrompts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            slotIntervalMinutes: try container.decodeIfPresent(Int.self, forKey: .slotIntervalMinutes) ?? 20,
            lookaheadMinutes: try container.decodeIfPresent(Int.self, forKey: .lookaheadMinutes) ?? 180,
            restaurantCapacity: try container.decodeIfPresent(Int.self, forKey: .restaurantCapacity) ?? 100,
            largePartyThreshold: try container.decodeIfPresent(Int.self, forKey: .largePartyThreshold) ?? 7,
            criticalPartyThreshold: try container.decodeIfPresent(Int.self, forKey: .criticalPartyThreshold) ?? 12,
            maxReservationsPerSlot: try container.decodeIfPresent(Int.self, forKey: .maxReservationsPerSlot) ?? 4,
            maxLargePartiesPerSlot: try container.decodeIfPresent(Int.self, forKey: .maxLargePartiesPerSlot) ?? 1,
            comfortableCapacityRatio: try container.decodeIfPresent(Double.self, forKey: .comfortableCapacityRatio) ?? 0.85,
            criticalCapacityRatio: try container.decodeIfPresent(Double.self, forKey: .criticalCapacityRatio) ?? 1.0,
            dueSoonMinutes: try container.decodeIfPresent(Int.self, forKey: .dueSoonMinutes) ?? 20,
            noTableDueSoonMinutes: try container.decodeIfPresent(Int.self, forKey: .noTableDueSoonMinutes) ?? 30,
            longSeatedWarningMinutes: try container.decodeIfPresent(Int.self, forKey: .longSeatedWarningMinutes) ?? 90,
            includeGuestSignals: try container.decodeIfPresent(Bool.self, forKey: .includeGuestSignals) ?? true,
            includeAnalyticsSignals: try container.decodeIfPresent(Bool.self, forKey: .includeAnalyticsSignals) ?? false,
            includeLLMPacket: try container.decodeIfPresent(Bool.self, forKey: .includeLLMPacket) ?? true,
            enableBookingDecisioning: try container.decodeIfPresent(Bool.self, forKey: .enableBookingDecisioning) ?? true,
            autoConfirmRecommendationsEnabled: try container.decodeIfPresent(Bool.self, forKey: .autoConfirmRecommendationsEnabled) ?? false,
            suggestAlternateTimesEnabled: try container.decodeIfPresent(Bool.self, forKey: .suggestAlternateTimesEnabled) ?? true,
            autoConfirmWeekdaysOnly: try container.decodeIfPresent(Bool.self, forKey: .autoConfirmWeekdaysOnly) ?? true,
            minimumConfidenceForAutoConfirm: try container.decodeIfPresent(Double.self, forKey: .minimumConfidenceForAutoConfirm) ?? 0.8,
            maxPartySizeForAutoConfirm: try container.decodeIfPresent(Int.self, forKey: .maxPartySizeForAutoConfirm) ?? 6,
            useEnhancedBriefing: try container.decodeIfPresent(Bool.self, forKey: .useEnhancedBriefing) ?? true,
            enhancedBriefingProvider: try container.decodeIfPresent(HostBriefingProviderKind.self, forKey: .enhancedBriefingProvider) ?? .localModel,
            useLocalModelOnHostBoard: try container.decodeIfPresent(Bool.self, forKey: .useLocalModelOnHostBoard) ?? true,
            useLocalModelForGuestMessageDrafts: try container.decodeIfPresent(Bool.self, forKey: .useLocalModelForGuestMessageDrafts) ?? true,
            useLocalModelForNoteAnalysis: try container.decodeIfPresent(Bool.self, forKey: .useLocalModelForNoteAnalysis) ?? true,
            useSeparatedBriefingPrompts: try container.decodeIfPresent(Bool.self, forKey: .useSeparatedBriefingPrompts) ?? false
        )
    }

    /// Stable stamp for Host pulse refresh — excludes guest-draft-only toggles.
    var hostDecisionFingerprint: String {
        [
            isEnabled ? "1" : "0",
            "\(slotIntervalMinutes)",
            "\(lookaheadMinutes)",
            "\(restaurantCapacity)",
            "\(largePartyThreshold)",
            "\(criticalPartyThreshold)",
            "\(maxReservationsPerSlot)",
            "\(maxLargePartiesPerSlot)",
            String(format: "%.3f", comfortableCapacityRatio),
            String(format: "%.3f", criticalCapacityRatio),
            "\(dueSoonMinutes)",
            "\(noTableDueSoonMinutes)",
            "\(longSeatedWarningMinutes)",
            includeGuestSignals ? "1" : "0",
            includeAnalyticsSignals ? "1" : "0",
            includeLLMPacket ? "1" : "0",
            enableBookingDecisioning ? "1" : "0",
            autoConfirmRecommendationsEnabled ? "1" : "0",
            suggestAlternateTimesEnabled ? "1" : "0",
            autoConfirmWeekdaysOnly ? "1" : "0",
            String(format: "%.2f", minimumConfidenceForAutoConfirm),
            "\(maxPartySizeForAutoConfirm)",
            useEnhancedBriefing ? "1" : "0",
            enhancedBriefingProvider.rawValue,
            useLocalModelOnHostBoard ? "1" : "0",
            useSeparatedBriefingPrompts ? "1" : "0",
        ].joined(separator: "|")
    }
}

struct RestaurantTableConfig: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var capacity: Int
    var section: String
    var isActive: Bool
    var combinableTableIDs: [UUID]
    var preferredForLargeParties: Bool
    var preferredForWheelchair: Bool
    var preferredForQuietSeating: Bool
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        capacity: Int,
        section: String = "",
        isActive: Bool = true,
        combinableTableIDs: [UUID] = [],
        preferredForLargeParties: Bool = false,
        preferredForWheelchair: Bool = false,
        preferredForQuietSeating: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.capacity = capacity
        self.section = section
        self.isActive = isActive
        self.combinableTableIDs = combinableTableIDs
        self.preferredForLargeParties = preferredForLargeParties
        self.preferredForWheelchair = preferredForWheelchair
        self.preferredForQuietSeating = preferredForQuietSeating
        self.sortOrder = sortOrder
    }
}

// MARK: - Table Intelligence

enum HostTableFitQuality: String, Codable, CaseIterable {
    case exact
    case comfortable
    case oversized
    case tight
    case unavailable
}

struct HostTableFitOption: Identifiable, Codable, Equatable {
    let id: String
    let reservationID: Int
    let guestName: String
    let partySize: Int
    let tableNames: [String]
    let tableIDs: [UUID]
    let totalCapacity: Int
    let isCombination: Bool
    let section: String?
    let fitQuality: HostTableFitQuality
}

struct HostTableCapacitySummary: Codable, Equatable {
    let activeTableCount: Int
    let inactiveTableCount: Int
    let totalActiveCapacity: Int
    let largestSingleTableCapacity: Int
    let largestCombinationCapacity: Int
}

// MARK: - Engine Input

/// Immutable input bundle for the deterministic Host Intelligence engine.
/// Not `Equatable` because `ReservationRecord` is a SwiftData reference type.
struct HostEngineInput {
    let now: Date
    let selectedDate: Date
    let reservations: [ReservationRecord]
    let availabilitySummary: ReservationAvailabilitySummary?
    let analyticsSummary: ReservationAnalyticsSummaryDTO?
    let restaurantSetup: RestaurantSetup?
    let localSeatedAtByReservationID: [Int: Date]
    let settings: HostIntelligenceSettings
    let tableConfigs: [RestaurantTableConfig]
    /// Broader local cache for guest memory. Falls back to `reservations` when empty.
    let allKnownReservations: [ReservationRecord]
    /// Active backend floor tables from GET /floor-plan.
    /// When non-empty, the engine prefers these over tableConfigs for capacity-based table suggestions
    /// because they reflect actual backend table inventory, not the local UserDefaults store.
    let backendFloorTables: [RestaurantTableDTO]
    /// Backend guest intelligence summaries for the selected service date, keyed by reservation ID.
    let guestIntelligenceSummariesByReservationID: [Int: GuestIntelligenceSummaryDTO]
    /// Loaded reservation profile packs (Detail/Guest Insights), keyed by reservation ID.
    let guestProfilePacksByReservationID: [Int: GuestIntelligenceProfilePackDTO]

    init(
        now: Date,
        selectedDate: Date,
        reservations: [ReservationRecord],
        availabilitySummary: ReservationAvailabilitySummary?,
        analyticsSummary: ReservationAnalyticsSummaryDTO?,
        restaurantSetup: RestaurantSetup?,
        localSeatedAtByReservationID: [Int: Date],
        settings: HostIntelligenceSettings,
        tableConfigs: [RestaurantTableConfig],
        allKnownReservations: [ReservationRecord],
        backendFloorTables: [RestaurantTableDTO] = [],
        guestIntelligenceSummariesByReservationID: [Int: GuestIntelligenceSummaryDTO] = [:],
        guestProfilePacksByReservationID: [Int: GuestIntelligenceProfilePackDTO] = [:]
    ) {
        self.now = now
        self.selectedDate = selectedDate
        self.reservations = reservations
        self.availabilitySummary = availabilitySummary
        self.analyticsSummary = analyticsSummary
        self.restaurantSetup = restaurantSetup
        self.localSeatedAtByReservationID = localSeatedAtByReservationID
        self.settings = settings
        self.tableConfigs = tableConfigs
        self.allKnownReservations = allKnownReservations
        self.backendFloorTables = backendFloorTables
        self.guestIntelligenceSummariesByReservationID = guestIntelligenceSummariesByReservationID
        self.guestProfilePacksByReservationID = guestProfilePacksByReservationID
    }
}
