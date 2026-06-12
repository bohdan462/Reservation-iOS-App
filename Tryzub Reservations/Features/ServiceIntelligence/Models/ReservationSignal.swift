//
//  ReservationSignal.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 1 foundation.
//
//  A ReservationSignal is a meaningful thing found in data, notes, guest history,
//  an attachment, or backend intelligence. A signal is NOT a hard fact: a vague
//  note becomes `depositMentioned` (requiresReview = true), never `depositVerified`,
//  unless a structured/backend source proves it. Staff-safe wording lives in
//  `staffText` ("Deposit mentioned — manager should verify.").
//

import Foundation

enum ReservationSignalType: String, Codable, CaseIterable {
    case depositMentioned
    case depositVerified
    case preorderMentioned
    case banquetMentioned
    case attachmentNeedsReview
    case kitchenNote
    case barNote
    case managerNote
    case guestPreference
    case allergyOrDietary
    case accessibility
    case occasion
    case serviceIssue
    case largeParty
    case setupNeeded
    case statusNeedsCheck
    case notMarkedSeated
    case notMarkedComplete
    case noTablePicked
    case guestCommunicationNeeded
    case historyContext
    case businessSummary
    // Phase 4 — Booking Load Suggestions (known reservations only, walk-ins excluded).
    case bookingWindowBusy
    case sameTimeReservationsHigh
    case knownGuestCountHigh
    case slotCloseSuggested
    case alternateTimeSuggested
    // Phase 10 — Model note analysis: the emotional tone the model read in the note
    // (e.g. excited, anxious, disappointed). Advisory only; never a hard fact.
    case guestSentiment

    /// Signals that assert something happened/exists and therefore must always be
    /// staff-reviewed rather than treated as confirmed fact.
    var alwaysRequiresReview: Bool {
        switch self {
        case .depositMentioned, .preorderMentioned, .banquetMentioned,
             .attachmentNeedsReview, .allergyOrDietary, .serviceIssue:
            return true
        default:
            return false
        }
    }
}

enum SignalConfidence: String, Codable, CaseIterable {
    case low
    case medium
    case high
    /// Backed by a structured/backend field — safe to treat as fact.
    case confirmed
}

enum SignalSource: String, Codable, CaseIterable {
    case reservationData
    case staffNote
    case guestNote
    case attachment
    case attachmentOCR
    case backendGuestIntelligence
    case backendBusinessAnalytics
    case localModel
    case deterministic
}

enum SignalPriority: Int, Codable, CaseIterable, Comparable {
    case info = 0
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    static func < (lhs: SignalPriority, rhs: SignalPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ReservationSignal: Identifiable, Equatable, Codable {
    let id: String
    let reservationID: String?
    let type: ReservationSignalType
    let title: String
    let staffText: String
    let evidence: String?
    let confidence: SignalConfidence
    let source: SignalSource
    let requiresReview: Bool
    let priority: SignalPriority

    init(
        id: String,
        reservationID: String?,
        type: ReservationSignalType,
        title: String,
        staffText: String,
        evidence: String? = nil,
        confidence: SignalConfidence,
        source: SignalSource,
        requiresReview: Bool? = nil,
        priority: SignalPriority
    ) {
        self.id = id
        self.reservationID = reservationID
        self.type = type
        self.title = title
        self.staffText = staffText
        self.evidence = evidence
        self.confidence = confidence
        self.source = source
        self.requiresReview = requiresReview ?? type.alwaysRequiresReview
        self.priority = priority
    }
}
