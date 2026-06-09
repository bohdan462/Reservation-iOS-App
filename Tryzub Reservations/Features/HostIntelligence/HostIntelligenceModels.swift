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
    case bookingDecision
    case analytics
    case sync
    case note
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
    case specialOccasion
    case seatingPreference
    case accessibility
    case cancellationRisk
    case noShowRisk
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
                "Do not override deterministic engine facts."
            ],
            writingRules: [
                "Use only provided facts.",
                "Write like a calm restaurant host.",
                "Mention only urgent or useful items.",
                "Maximum 4 short sentences."
            ]
        )
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
            templateBriefingText: "Service looks stable right now.",
            llmPacket: .empty
        )
    }
}

// MARK: - Settings & Table Config

struct HostIntelligenceSettings: Codable, Equatable {
    var isEnabled: Bool = true
    var slotIntervalMinutes: Int = 20
    var lookaheadMinutes: Int = 180
    var restaurantCapacity: Int = 100
    var largePartyThreshold: Int = 8
    var criticalPartyThreshold: Int = 12
    var maxReservationsPerSlot: Int = 4
    var maxLargePartiesPerSlot: Int = 1
    var comfortableCapacityRatio: Double = 0.85
    var criticalCapacityRatio: Double = 1.0
    var dueSoonMinutes: Int = 20
    var noTableDueSoonMinutes: Int = 30
    var longSeatedWarningMinutes: Int = 90
    var includeGuestSignals: Bool = true
    var includeAnalyticsSignals: Bool = false
    var includeLLMPacket: Bool = true
}

struct RestaurantTableConfig: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let capacity: Int
    let section: String
    let isActive: Bool
    let combinableTableIDs: [UUID]
    let preferredForLargeParties: Bool
    let preferredForWheelchair: Bool
    let preferredForQuietSeating: Bool
    let sortOrder: Int

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
}
