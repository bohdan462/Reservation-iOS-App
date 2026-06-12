//
//  ServiceAlertRouter.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 1 foundation.
//
//  Decides WHERE a signal/action belongs so the same fact does not appear
//  everywhere with identical wording. Host Board = live "right now". Reservation
//  Detail = everything specific to one reservation. Global Intelligence = combined
//  action hub + summaries. Dev = diagnostics only.
//

import Foundation

enum ServiceAlertDestination: String, Codable, CaseIterable {
    case host
    case detail
    case global
    case dev
}

enum ServiceAlertRouter {

    /// Primary destination for a signal given the current service mode. A signal may
    /// also be shown in Reservation Detail (its home), but the *alert* surface — where
    /// staff are nudged to act — is chosen here to avoid duplication.
    static func primaryDestination(
        for type: ReservationSignalType,
        mode: ServiceMode
    ) -> (destination: ServiceAlertDestination, reason: String) {
        // After close: never route live operational facts to Host Board.
        if mode.isAfterClose || mode.isRecapContext {
            switch type {
            case .notMarkedSeated, .notMarkedComplete, .statusNeedsCheck:
                return (.host, "after_close_cleanup")
            case .businessSummary, .historyContext:
                return (.global, "summary_context")
            default:
                return (.global, "not_live_after_close")
            }
        }

        switch type {
        // Live, time-sensitive — Host Board during service.
        case .notMarkedSeated, .notMarkedComplete, .statusNeedsCheck,
             .noTablePicked, .largeParty:
            return (.host, "live_check")

        // Pre-seating relevance — Host Board, but only because they affect seating now.
        case .allergyOrDietary, .accessibility, .setupNeeded, .occasion:
            return (.host, "relevant_before_seating")

        // Manager / kitchen / bar review — Global action hub (not urgent live).
        case .depositMentioned, .depositVerified, .managerNote:
            return (.global, "manager_review")
        case .preorderMentioned, .banquetMentioned, .kitchenNote:
            return (.global, "kitchen_review")
        case .barNote:
            return (.global, "bar_review")
        case .attachmentNeedsReview:
            return (.global, "attachment_review")

        // Guest-specific context — lives on the reservation.
        case .guestPreference, .serviceIssue, .guestCommunicationNeeded, .guestSentiment:
            return (.detail, "reservation_specific")
        case .historyContext:
            return (.detail, "guest_history")

        // Aggregate/business — Global summary only.
        case .businessSummary:
            return (.global, "business_summary")

        // Phase 4 — booking-load signals belong to the global hub (and a concise Host
        // heads-up). They describe the booking window, not a single reservation.
        case .bookingWindowBusy, .sameTimeReservationsHigh, .knownGuestCountHigh,
             .slotCloseSuggested, .alternateTimeSuggested:
            return (.global, "booking_load")
        }
    }

    static func route(_ signal: ReservationSignal, mode: ServiceMode) -> ServiceAlertDestination {
        let decision = primaryDestination(for: signal.type, mode: mode)
        ServiceIntelligenceTrace.alertRoute(
            signal: signal.type.rawValue,
            routedTo: decision.destination.rawValue,
            reason: decision.reason
        )
        return decision.destination
    }
}
