//
//  ServiceIntelligenceFreshness.swift
//  Tryzub Reservations
//
//  Tracks which data sources are available for a Service Intelligence evaluation.
//  Used to:
//   • set `ServiceBriefing.source` honestly (.deterministic / .mixed / .backend)
//   • emit [SERVICE_CONTEXT_TRACE] so device logs prove what intelligence was used
//   • show subtle freshness notes in staff UI when backend data is stale or absent
//
//  Rules:
//   * `.loaded`  — backend answered and data is within the freshness window.
//   * `.stale`   — data was loaded before but the freshness window has expired.
//   * `.missing` — never loaded for this date/range in this session.
//   * UI shows a note only when staff would benefit from knowing (e.g. stale > 24 h).
//

import Foundation

// MARK: - Data status

enum IntelligenceDataStatus: String, Equatable {
    case loaded
    case stale
    case missing

    var isUsable: Bool { self == .loaded || self == .stale }
}

// MARK: - Freshness snapshot

struct ServiceIntelligenceFreshness: Equatable {
    let reservationCacheFresh: Bool
    let guestSummaryStatus: IntelligenceDataStatus
    let businessSummaryStatus: IntelligenceDataStatus
    let profilePacksLoadedCount: Int
    let evaluatedAt: Date

    // MARK: - Derived source label (for traces + UI)

    /// Stable token for [SERVICE_CONTEXT_TRACE] source= field.
    var sourceToken: String {
        switch (guestSummaryStatus.isUsable, businessSummaryStatus.isUsable) {
        case (true, true):   return "backend_enriched"
        case (true, false),
             (false, true):  return "mixed"
        default:             return "cache_only"
        }
    }

    /// Mapped `BriefingSource` for `ServiceBriefing.source`.
    var briefingSource: BriefingSource {
        switch (guestSummaryStatus.isUsable, businessSummaryStatus.isUsable) {
        case (true, true):   return .backend
        case (true, false),
             (false, true):  return .mixed
        default:             return .deterministic
        }
    }

    /// Subtle staff-facing note. Nil when data is current or absence is expected.
    var staffNote: String? {
        if guestSummaryStatus == .stale {
            return "Guest summary updating in background."
        }
        if guestSummaryStatus == .missing && businessSummaryStatus == .missing {
            return "Using saved reservation data."
        }
        return nil
    }

    // MARK: - Factory

    static var cacheOnly: ServiceIntelligenceFreshness {
        ServiceIntelligenceFreshness(
            reservationCacheFresh: true,
            guestSummaryStatus: .missing,
            businessSummaryStatus: .missing,
            profilePacksLoadedCount: 0,
            evaluatedAt: Date()
        )
    }
}
