//
//  HostServiceIntelligenceSnapshot.swift
//  Tryzub Reservations
//
//  LOCAL-FIRST-OPS-4A — Unified deterministic per-date staff intelligence.
//
//  A single, date-scoped read model consumed by Host card and More → Service
//  Intelligence. Built by HostServiceIntelligenceSnapshotBuilder from already-
//  computed HostDecisionSnapshot + day reservations + NoteSignalAnalyzer.
//
//  Constraints:
//  - Never built in SwiftUI body.
//  - No network. No LLM. No full-history scan.
//  - Skip-gated by inputFingerprint.
//  - Emits [SERVICE_INTEL_SNAPSHOT_TRACE] on build and skip.
//

import Foundation

// MARK: - Fact category

/// Ordered by baseline staff importance (highest first).
enum ServiceIntelligenceFactCategory: String, Equatable, CaseIterable {
    /// Allergy or serious dietary restriction.
    case allergy
    /// Prior service issue documented in notes.
    case staffNote
    /// Deposit, preorder, or banquet event mentioned in notes.
    case attachment
    /// Accessibility or seating accommodation.
    case accessibility
    /// Special occasion — birthday, anniversary, etc.
    case occasion
    /// Returning, VIP, or otherwise important guest.
    case returningGuest
    /// Confirmed regular guest.
    case regularGuest
    /// Generic guest note reminder.
    case guestNote
    /// Large party requiring setup or floor-plan attention.
    case largeParty
    /// Busiest service slot / main arrival wave.
    case mainWave
    /// Pending reminder.
    case reminder
    /// Pending confirmation.
    case confirmation
    /// Reservations without table assignments (future-date planning only).
    case noTable
    /// Cancellation or no-show context from guest history.
    case cancellationNoShow

    /// Baseline priority — higher value surfaces the fact first.
    var basePriority: Int {
        switch self {
        case .allergy:            return 100
        case .staffNote:          return 90
        case .attachment:         return 80
        case .accessibility:      return 70
        case .occasion:           return 60
        case .returningGuest:     return 50
        case .regularGuest:       return 45
        case .guestNote:          return 40
        case .largeParty:         return 30
        case .mainWave:           return 20
        case .reminder:           return 15
        case .confirmation:       return 12
        case .noTable:            return 10
        case .cancellationNoShow: return 5
        }
    }
}

enum ServiceIntelligenceAttachmentCategory: String, Codable, Equatable, CaseIterable {
    case deposit
    case preorder
    case banquetMenu
    case setup
    case genericPhoto
}

/// Metadata-only attachment input for day-bounded Service Intelligence.
/// No image bytes and no raw OCR text; `signalTypes` are derived from existing
/// cached labels/OCR via AttachmentSignalAnalyzer before the builder sees them.
struct ServiceIntelligenceAttachmentMetadata: Equatable {
    let reservationID: Int
    let attachmentID: String
    let label: AttachmentLabel
    /// Stable digest of metadata tags that can affect staff-facing attachment facts.
    /// This intentionally excludes image bytes and raw OCR text.
    let labelTypeTagDigest: String
    let signalTypes: [ReservationSignalType]
    let updatedAt: String?

    init(
        reservationID: Int,
        attachmentID: String,
        label: AttachmentLabel,
        labelTypeTagDigest: String? = nil,
        signalTypes: [ReservationSignalType],
        updatedAt: String? = nil
    ) {
        self.reservationID = reservationID
        self.attachmentID = attachmentID
        self.label = label
        self.labelTypeTagDigest = labelTypeTagDigest ?? HostAttentionStableDigest.hexDigest(label.backendValue)
        self.signalTypes = signalTypes
        self.updatedAt = updatedAt
    }
}

// MARK: - Fact

/// A single ranked staff-facing intelligence item for a date.
struct ServiceIntelligenceFact: Identifiable, Equatable {
    /// Stable, dedupe-safe ID — format: "{source}-{reservationID|day}-{category}".
    let id: String
    /// Nil for day-level facts (mainWave, noTable, cancellationNoShow).
    let reservationID: Int?
    /// Guest display name — nil for day-level facts.
    let guestName: String?
    let category: ServiceIntelligenceFactCategory
    /// Effective priority after HostSeverity adjustment (used for sort).
    let priority: Int
    /// Short staff-facing one-liner shown in cards ("Julie has an allergy note.").
    let headline: String
    /// Optional expanded context for detail and More → Service Intelligence views.
    let detail: String?
}

// MARK: - Snapshot

/// Unified per-date staff intelligence snapshot.
///
/// Built once per meaningful input change; consumed by Host card (today) and
/// More → Service Intelligence (any selected date) without duplication or
/// fact repetition across sections.
struct HostServiceIntelligenceSnapshot: Equatable {
    let dateKey: String
    let generatedAt: Date
    let serviceMode: ServiceMode
    /// Primary staff headline for the selected date.
    let headline: String
    /// Secondary context line shown below or appended to headline.
    let subline: String?
    let reservationCount: Int
    let guestCount: Int
    /// Deduplicated, ranked facts (max 12).
    /// One entry per (reservationID, category) pair.
    let rankedFacts: [ServiceIntelligenceFact]
    /// Stable FNV-1a fingerprint of all builder inputs (used as skip gate).
    let inputFingerprint: String

    static var empty: HostServiceIntelligenceSnapshot {
        HostServiceIntelligenceSnapshot(
            dateKey: "",
            generatedAt: Date(timeIntervalSince1970: 0),
            serviceMode: .beforeService,
            headline: "",
            subline: nil,
            reservationCount: 0,
            guestCount: 0,
            rankedFacts: [],
            inputFingerprint: "empty"
        )
    }
}
