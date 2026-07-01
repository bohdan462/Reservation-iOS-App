//
//  HostServiceBriefingNarrativeGate.swift
//  Tryzub Reservations
//
//  Guards local-model invocation for the 4E Service Intelligence narrative pass.
//  Pattern mirrors HostBriefingHostBoardGate for the legacy path.
//
//  The gate never blocks the template fallback path; it only controls whether
//  the local model runs. Template is always available.
//

import Foundation

enum HostServiceBriefingNarrativeGate {

    // MARK: - Skip reasons

    enum SkipReason: String {
        /// Enhanced briefing is turned off in settings.
        case enhanced_briefing_off
        /// Provider is not set to local model.
        case provider_not_local_model
        /// Local model runtime or model file is not available.
        case model_not_ready
        /// Startup network pass is still in flight.
        case startup_in_flight
        /// Reservation refresh is in flight (counts may be stale).
        case reservation_refresh_in_flight
        /// Date navigation is active (avoid stale-date generation).
        case date_navigation_active
        /// Another local model inference is already running.
        case local_model_in_flight
        /// Packet is absent, stale, or belongs to a different date.
        case packet_not_current
        /// Packet has no meaningful facts (template is sufficient).
        case packet_no_meaningful_facts
        /// Service mode does not benefit from model narrative yet.
        case mode_not_applicable
    }

    // MARK: - Context

    struct Context {
        let selectedDateKey: String
        let isStartupNetworkPassInFlight: Bool
        let isReservationRefreshInFlight: Bool
        let isLocalModelInferenceActive: Bool
        let hostBoardDateNavigationAt: Date?
        let now: Date
    }

    // MARK: - Gate evaluation

    /// Returns a skip reason when the model should not run, nil when it may run.
    static func skipReason(
        settings: HostIntelligenceSettings,
        packet: HostServiceBriefingPacket,
        context: Context
    ) -> SkipReason? {
        // 1. Must have enhanced briefing enabled
        guard settings.useEnhancedBriefing else { return .enhanced_briefing_off }

        // 2. Provider must be local model
        guard settings.enhancedBriefingProvider == .localModel else { return .provider_not_local_model }

        // 3. Host board model flag must be on (reuses same user-facing toggle)
        guard settings.useLocalModelOnHostBoard else { return .provider_not_local_model }

        // 4. Runtime + model file must be present
        guard HostLocalModelRuntimeFactory.isRuntimeIntegrated else { return .model_not_ready }
        let profile = HostLocalModelFileLocator.bestAvailableProfile()
        guard profile != .template else { return .model_not_ready }

        // 5. Packet must be current for the selected date
        guard packet.inputFingerprint != "empty",
              !packet.dateKey.isEmpty,
              packet.dateKey == context.selectedDateKey else {
            return .packet_not_current
        }

        // 6. Skip during startup to avoid running on incomplete data
        if context.isStartupNetworkPassInFlight { return .startup_in_flight }

        // 7. Skip while reservation data refresh is in flight
        if context.isReservationRefreshInFlight { return .reservation_refresh_in_flight }

        // 8. Skip while another local model is running (single-flight)
        if context.isLocalModelInferenceActive { return .local_model_in_flight }

        // 9. Skip during date navigation (4s cooldown mirrors legacy gate)
        if let navAt = context.hostBoardDateNavigationAt {
            if context.now.timeIntervalSince(navAt) < 4.0 { return .date_navigation_active }
        }

        // 10. Skip when packet has no meaningful facts (template is already good)
        guard hasMeaningfulFacts(packet) else { return .packet_no_meaningful_facts }

        return nil
    }

    // MARK: - Meaningful-facts check

    /// Returns true when the packet has enough complexity to benefit from model rewriting.
    /// Simple calm/day-overview-only packets are served well by the template.
    static func hasMeaningfulFacts(_ packet: HostServiceBriefingPacket) -> Bool {
        let interestingKinds: Set<BriefingFactKind> = [
            .allergy, .occasion, .seatingPreference, .guestMemory,
            .seatedDuration, .tableWatch, .waitingArrivals, .noTableToday,
            .reminder, .confirmation, .deposit, .preorder, .setup,
            .noShowFollowUp, .longStayRecap,
        ]
        return packet.facts.contains { interestingKinds.contains($0.kind) }
    }
}
