//
//  ServiceIntelligenceContext.swift
//  Tryzub Reservations
//
//  Unified input packet for the Service Intelligence pipeline.
//
//  DESIGN:
//  Backend intelligence arrives asynchronously. The context is intentionally
//  partial — every backend field is Optional so the engine can produce a
//  useful briefing from reservations alone, then automatically upgrade when
//  backend data arrives.
//
//  Typical lifecycle:
//   1. View opens → build context from cache (guestSummaries: [], businessSummary: nil)
//   2. Background load completes → rebuild context with loaded backend data
//   3. Engine produces richer briefing; `freshness.sourceToken` moves from
//      "cache_only" → "mixed" → "backend_enriched"
//
//  This file owns the context model only. Builders live in ViewState files or views.
//

import Foundation

struct ServiceIntelligenceContext: Equatable {
    // MARK: - Core reservation data (always available)

    let selectedDate: Date
    let selectedDateKey: String
    let serviceMode: ServiceMode
    /// Reservations for the selected service day.
    let dayReservations: [ReservationRecord]

    // MARK: - Backend guest intelligence (optional — may arrive after first render)

    /// Per-reservation summaries from GET /guest-intelligence?date=YYYY-MM-DD
    let guestSummaries: [GuestIntelligenceSummaryDTO]
    /// Per-reservation profile packs from GET /guest-intelligence/reservation/{id}
    let profilePacks: [Int: GuestIntelligenceProfilePackDTO]

    // MARK: - Backend business/analytics intelligence (optional)

    /// From GET /business-intelligence/summary
    let businessSummary: BusinessIntelligenceSummaryDTO?
    /// From GET /reservation-analytics/summary (already cached in RestaurantSettingsStore)
    let reservationAnalyticsSummary: ReservationAnalyticsSummaryDTO?

    // MARK: - Freshness

    let freshness: ServiceIntelligenceFreshness

    // MARK: - Computed helpers

    /// Guests with at least one meaningful backend signal for today.
    /// Sorted: service issue first, then allergy, accessibility, occasion, returning.
    var prioritisedGuestsToKnow: [GuestIntelligenceSummaryDTO] {
        let relevant = guestSummaries.filter { s in
            s.hasPriorServiceIssue
                || s.hasAllergyNote
                || s.hasAccessibilityNote
                || s.hasSpecialOccasionNote
                || s.matchedVisitCount > 0
        }
        return relevant.sorted { a, b in
            signalPriority(a) > signalPriority(b)
        }
    }

    private func signalPriority(_ s: GuestIntelligenceSummaryDTO) -> Int {
        var score = 0
        if s.hasPriorServiceIssue     { score += 32 }
        if s.hasAllergyNote           { score += 16 }
        if s.hasAccessibilityNote     { score += 8  }
        if s.hasSpecialOccasionNote   { score += 4  }
        if s.matchedVisitCount > 0    { score += 2  }
        if s.hasSeatingPreference     { score += 1  }
        return score
    }

    // MARK: - Factory (cache-only, immediate)

    static func cacheOnly(
        selectedDate: Date,
        selectedDateKey: String,
        serviceMode: ServiceMode,
        dayReservations: [ReservationRecord]
    ) -> ServiceIntelligenceContext {
        ServiceIntelligenceContext(
            selectedDate: selectedDate,
            selectedDateKey: selectedDateKey,
            serviceMode: serviceMode,
            dayReservations: dayReservations,
            guestSummaries: [],
            profilePacks: [:],
            businessSummary: nil,
            reservationAnalyticsSummary: nil,
            freshness: .cacheOnly
        )
    }
}
