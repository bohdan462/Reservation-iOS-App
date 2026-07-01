//
//  StaffBriefingModels.swift
//  Tryzub Reservations
//
//  4F-1 — On-demand full staff / management briefing foundation.
//
//  These types are a SEPARATE system from the compact 4E narrative
//  (HostServiceBriefingNarrative). The staff briefing is generated only when a
//  user explicitly requests it, produces a full multi-section briefing, and is
//  cached + stale-tracked by packet fingerprint.
//
//  SAFETY: The packet carries only deterministic safe facts. No raw notes, OCR
//  text, emails, phones, backend JSON, ReservationRecord, rendered template
//  lines, or HostLLMPacket ever enter this pipeline.
//
//  UI-neutral: no SwiftUI import.
//

import Foundation

// MARK: - Mode

/// The three on-demand briefing contexts. Distinct from `ServiceMode` (which is a
/// finer deterministic day-phase resolution); a `ServiceMode` maps into one of these.
enum StaffBriefingMode: String, Equatable, Sendable, CaseIterable {
    case preService
    case liveService
    case closingRecap

    /// Maps a resolved `ServiceMode` into the coarser briefing mode.
    static func from(serviceMode: ServiceMode) -> StaffBriefingMode {
        switch serviceMode {
        case .beforeService, .futurePlanning:
            return .preService
        case .duringService:
            return .liveService
        case .afterCloseNeedsCleanup, .afterCloseFinished, .pastRecap:
            return .closingRecap
        }
    }

    var displayName: String {
        switch self {
        case .preService:  return "Before service"
        case .liveService: return "Live service"
        case .closingRecap: return "Closing recap"
        }
    }
}

// MARK: - Source

enum StaffBriefingSource: String, Equatable, Sendable {
    /// Deterministic template prose.
    case template
    /// Validated local-model output.
    case localModel
    /// Template used as fallback after model gate/validation/timeout failure.
    case fallback

    var usesModel: Bool { self == .localModel }
}

// MARK: - Status counts (deterministic ground truth)

/// Per-status deterministic histogram for a service day. Never model-derived.
struct StaffBriefingStatusCounts: Equatable, Sendable {
    let totalReservations: Int
    let expectedGuests: Int
    let newCount: Int
    let needsReviewCount: Int
    let confirmedCount: Int
    let seatedCount: Int
    let completedCount: Int
    let cancelledCount: Int
    let noShowCount: Int
    /// Operational (non-terminal) reservations: new + needsReview + confirmed + seated.
    let activeCount: Int
    /// Not-yet-arrived operational reservations (new + needsReview + confirmed).
    let remainingArrivalsCount: Int
    /// Sum of party sizes for currently seated reservations.
    let currentlySeatedGuests: Int
    /// Count of currently seated reservations.
    let stillSeatedReservations: Int
    /// Items still needing a status decision (context dependent; used in recap).
    let unresolvedCount: Int

    static let empty = StaffBriefingStatusCounts(
        totalReservations: 0, expectedGuests: 0, newCount: 0, needsReviewCount: 0,
        confirmedCount: 0, seatedCount: 0, completedCount: 0, cancelledCount: 0,
        noShowCount: 0, activeCount: 0, remainingArrivalsCount: 0,
        currentlySeatedGuests: 0, stillSeatedReservations: 0, unresolvedCount: 0
    )
}

// MARK: - Attachment summary

/// Normalized, safe attachment tags. Never a filename, OCR text, or raw label string.
enum StaffBriefingAttachmentTag: String, Equatable, Sendable, CaseIterable {
    case setup
    case deposit
    case preorder
    case cake
    case decor
    case menu
    case banquet
    case event
    case photoReference
    case other

    /// Maps a raw lowercased token to a safe tag. Unknown tokens collapse to `.other`.
    static func normalize(_ raw: String) -> StaffBriefingAttachmentTag {
        let token = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch token {
        case "setup": return .setup
        case "deposit": return .deposit
        case "preorder", "pre-order", "pre_order": return .preorder
        case "cake": return .cake
        case "decor", "decoration", "decorations": return .decor
        case "menu": return .menu
        case "banquet": return .banquet
        case "event": return .event
        case "photo", "photoreference", "photo_reference", "reference": return .photoReference
        default: return .other
        }
    }
}

/// Safe, metadata-only summary of a reservation's attachments.
struct StaffBriefingAttachmentSummary: Equatable, Sendable, Identifiable {
    /// Stable safe ID (reservation remote ID as string).
    let id: String
    /// Guest name only when allowlisted; nil otherwise.
    let guestName: String?
    let timeLabel: String?
    let tags: [StaffBriefingAttachmentTag]
    let reviewNeeded: Bool
}

// MARK: - Communication summary

/// Deterministic reminder / confirmation state. Counts only — never per-guest
/// "was sent" claims that the model could turn into unsafe assertions.
struct StaffBriefingCommunicationSummary: Equatable, Sendable {
    let confirmationsMissingCount: Int
    /// Legacy-compatible recorded/attempted count; nil when not safely derivable.
    let confirmationsSentCount: Int?
    let confirmationDeliveredCount: Int
    let confirmationPendingDeliveryCount: Int
    let confirmationFailedDeliveryCount: Int
    let confirmationNeedsCorrectionCount: Int
    let remindersMissingCount: Int
    /// Legacy-compatible recorded/attempted count; nil when not safely derivable.
    let remindersSentCount: Int?
    let reminderDeliveredCount: Int
    let reminderPendingDeliveryCount: Int
    let reminderFailedDeliveryCount: Int
    let reminderNeedsCorrectionCount: Int
    /// nil when not reliably available from deterministic metadata. Never faked.
    let autoConfirmedCount: Int?

    static let empty = StaffBriefingCommunicationSummary(
        confirmationsMissingCount: 0,
        confirmationsSentCount: nil,
        confirmationDeliveredCount: 0,
        confirmationPendingDeliveryCount: 0,
        confirmationFailedDeliveryCount: 0,
        confirmationNeedsCorrectionCount: 0,
        remindersMissingCount: 0,
        remindersSentCount: nil,
        reminderDeliveredCount: 0,
        reminderPendingDeliveryCount: 0,
        reminderFailedDeliveryCount: 0,
        reminderNeedsCorrectionCount: 0,
        autoConfirmedCount: nil
    )
}

// MARK: - Tomorrow preview

/// Best-effort safe preview of the next service day, for closingRecap only.
/// Any field that cannot be computed safely is left at zero and the section is
/// marked unavailable in the template rather than invented.
struct StaffBriefingTomorrowPreview: Equatable, Sendable {
    let dateKey: String
    let reservationCount: Int
    let expectedGuests: Int
    let needsReviewCount: Int
    let noTableCount: Int
    let largePartyCount: Int
    let attachmentCount: Int
    let allergyCount: Int
    let occasionCount: Int
    let regularGuestCount: Int
    /// Safe summarized facts (kind + safe fields only).
    let priorityFacts: [BriefingFact]
    /// True when at least one meaningful field was computed.
    let hasData: Bool
}

// MARK: - Packet

/// Full, safe input to the staff briefing writer. Deterministic truth only.
struct StaffBriefingPacket: Equatable, Sendable {
    let mode: StaffBriefingMode
    let dateKey: String
    let requestedAt: Date
    let serviceMode: ServiceMode
    let serviceStateLabel: String
    let inputFingerprint: String
    let sourceFingerprint: String
    let promptVersion: String
    let truthCounts: BriefingTruthCounts
    let statusCounts: StaffBriefingStatusCounts
    /// Ranked safe facts (kind + safe fields only), capped for the context window.
    let priorityFacts: [BriefingFact]
    let allowedGuestNames: [String]
    let allowedTableLabels: [String]
    let attachmentSummaries: [StaffBriefingAttachmentSummary]
    let communicationSummary: StaffBriefingCommunicationSummary
    let businessSummaryLines: [String]
    let tomorrowPreview: StaffBriefingTomorrowPreview?

    static let empty = StaffBriefingPacket(
        mode: .preService,
        dateKey: "",
        requestedAt: Date(timeIntervalSince1970: 0),
        serviceMode: .beforeService,
        serviceStateLabel: "",
        inputFingerprint: "empty",
        sourceFingerprint: "",
        promptVersion: "",
        truthCounts: HostServiceBriefingPacket.empty.truthCounts,
        statusCounts: .empty,
        priorityFacts: [],
        allowedGuestNames: [],
        allowedTableLabels: [],
        attachmentSummaries: [],
        communicationSummary: .empty,
        businessSummaryLines: [],
        tomorrowPreview: nil
    )

    /// True when the packet contains anything worth briefing on.
    var hasContent: Bool {
        statusCounts.totalReservations > 0 || !priorityFacts.isEmpty
    }
}

// MARK: - Result

/// One rendered section of the briefing.
struct StaffBriefingSection: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let paragraphs: [String]
    let bullets: [String]

    var isEmpty: Bool {
        paragraphs.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
            && bullets.isEmpty
    }
}

/// Cache key for a generated briefing. Equal keys are safe to reuse.
struct StaffBriefingCacheKey: Hashable, Sendable {
    let mode: StaffBriefingMode
    let dateKey: String
    let packetFingerprint: String
    let sourceFingerprint: String
    let promptVersion: String
    let settingsStamp: String
}

/// Final output of a staff briefing generation pass (model or template).
struct StaffBriefingResult: Equatable, Sendable {
    let mode: StaffBriefingMode
    let headline: String
    let sections: [StaffBriefingSection]
    let actionBullets: [String]
    let source: StaffBriefingSource
    let generatedAt: Date
    let cacheKey: StaffBriefingCacheKey
    let failedReason: String?
    let wordCount: Int

    var isFallback: Bool { source == .fallback }

    /// Full plaintext (headline + sections + actions) for word counting and display fallback.
    var plainText: String {
        var parts: [String] = [headline]
        for section in sections {
            parts.append(section.title)
            parts.append(contentsOf: section.paragraphs)
            parts.append(contentsOf: section.bullets)
        }
        parts.append(contentsOf: actionBullets)
        return parts.joined(separator: "\n")
    }

    static func wordCount(of text: String) -> Int {
        text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }
}

// MARK: - Display state

/// UI-facing state for the staff briefing surface. Owned by HostIntelligenceController.
enum StaffBriefingDisplayState: Equatable, Sendable {
    case none
    case current(StaffBriefingResult)
    case stale(StaffBriefingResult, reason: String)
    case generating(mode: StaffBriefingMode)
    case unavailable(reason: String)

    var result: StaffBriefingResult? {
        switch self {
        case .current(let r): return r
        case .stale(let r, _): return r
        case .none, .generating, .unavailable: return nil
        }
    }

    var isGenerating: Bool {
        if case .generating = self { return true }
        return false
    }
}
