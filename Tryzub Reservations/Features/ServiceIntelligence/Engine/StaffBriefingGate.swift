//
//  StaffBriefingGate.swift
//  Tryzub Reservations
//
//  4F-1 — Guards local-model invocation for the on-demand staff briefing.
//
//  Because the briefing is user-initiated, this gate is more permissive than the
//  compact narrative gate: it does NOT skip for startup / date navigation. It only
//  blocks when the model cannot or should not run (settings off, runtime/model
//  missing, another inference already running). Template is always available.
//

import Foundation

enum StaffBriefingGate {

    enum SkipReason: String {
        case enhanced_briefing_off
        case provider_not_local_model
        case host_board_model_off
        case model_not_ready
        case local_model_in_flight
        case empty_packet
    }

    struct Context {
        let isLocalModelInferenceActive: Bool

        init(isLocalModelInferenceActive: Bool) {
            self.isLocalModelInferenceActive = isLocalModelInferenceActive
        }
    }

    /// Returns a skip reason when the model must not run, nil when it may run.
    static func skipReason(
        settings: HostIntelligenceSettings,
        packet: StaffBriefingPacket,
        context: Context
    ) -> SkipReason? {
        guard settings.useEnhancedBriefing else { return .enhanced_briefing_off }
        guard settings.enhancedBriefingProvider == .localModel else { return .provider_not_local_model }
        guard settings.useLocalModelOnHostBoard else { return .host_board_model_off }

        guard HostLocalModelRuntimeFactory.isRuntimeIntegrated else { return .model_not_ready }
        let profile = HostLocalModelFileLocator.bestAvailableProfile()
        guard profile != .template else { return .model_not_ready }

        if context.isLocalModelInferenceActive { return .local_model_in_flight }

        guard packet.hasContent else { return .empty_packet }

        return nil
    }
}
