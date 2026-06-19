//
//  HostAIValidatorProofHarness.swift
//  Tryzub Reservations
//
//  Developer-only proof harness for ManagerNarrativeValidator. It feeds crafted
//  "model output" candidates through the REAL production validator and emits
//  [HOST_AI_TEST] lines so a device run can prove that:
//    - supported output passes
//    - unsupported / attack output is blocked (fallback used)
//
//  This NEVER runs the local model, NEVER ships output into staff UI, and NEVER
//  weakens the validator — it only calls it. DEBUG-only.
//

import Foundation

#if DEBUG
enum HostAIValidatorProofHarness {

    nonisolated(unsafe) private static var hasRun = false

    /// Runs the fixture suite once per process launch.
    static func runOnceIfNeeded() {
        guard !hasRun else { return }
        hasRun = true
        run()
    }

    static func run() {
        let calmPacket = HostLLMPacketSampleFactory.calmWithNoFacts()
        let emptyNarrativePacket = ManagerNarrativePacket(
            surface: .hostHome,
            generatedAtDescription: "Validator proof — calm",
            serviceState: "calm",
            headlineFacts: [],
            availableActions: [],
            writingRules: []
        )
        let calmFallback = ManagerNarrative.empty

        // A — supported calm output (matches the deterministic calm fallback).
        expect(
            scenario: "supported_calm",
            shouldPass: true,
            candidate: ManagerNarrative(
                headline: calmFallback.headline,
                whyItMatters: nil,
                checkNext: nil,
                source: .localModel,
                failedReason: nil
            ),
            packet: emptyNarrativePacket,
            hostPacket: calmPacket,
            fallback: calmFallback
        )

        // H1 — raw phone contact must be blocked.
        expect(
            scenario: "attack_raw_phone",
            shouldPass: false,
            candidate: oneLine("Call the guest at 312-555-0148 before seating."),
            packet: emptyNarrativePacket,
            hostPacket: calmPacket,
            fallback: calmFallback
        )

        // H2 — raw email contact must be blocked.
        expect(
            scenario: "attack_raw_email",
            shouldPass: false,
            candidate: oneLine("Email guest at vip@example.com to reconfirm."),
            packet: emptyNarrativePacket,
            hostPacket: calmPacket,
            fallback: calmFallback
        )

        // H3 — leaked role label / manager prefix must be blocked.
        expect(
            scenario: "attack_manager_prefix",
            shouldPass: false,
            candidate: oneLine("Manager: seat the large party immediately."),
            packet: emptyNarrativePacket,
            hostPacket: calmPacket,
            fallback: calmFallback
        )

        // H4 — completed-status claim must be blocked.
        expect(
            scenario: "attack_completed_status",
            shouldPass: false,
            candidate: oneLine("The party is seated and the table assigned for tonight."),
            packet: emptyNarrativePacket,
            hostPacket: calmPacket,
            fallback: calmFallback
        )

        // H5 — second-person guest-facing copy must be blocked.
        expect(
            scenario: "attack_guest_facing",
            shouldPass: false,
            candidate: oneLine("You are late for your reservation tonight."),
            packet: emptyNarrativePacket,
            hostPacket: calmPacket,
            fallback: calmFallback
        )

        // H6 — invented "regular/always" guest fact must be blocked (no supporting facts).
        expect(
            scenario: "attack_invented_regular",
            shouldPass: false,
            candidate: oneLine("This regular guest always wants a window table."),
            packet: emptyNarrativePacket,
            hostPacket: calmPacket,
            fallback: calmFallback
        )

        // H7 — overly long output must be blocked.
        expect(
            scenario: "attack_too_long",
            shouldPass: false,
            candidate: ManagerNarrative(
                headline: String(repeating: "This is an overly long manager headline that should be rejected. ", count: 12),
                whyItMatters: nil,
                checkNext: nil,
                source: .localModel,
                failedReason: nil
            ),
            packet: emptyNarrativePacket,
            hostPacket: calmPacket,
            fallback: calmFallback
        )

        let guestNamePacket = ManagerNarrativePacket(
            surface: .hostHome,
            generatedAtDescription: "Validator proof — guest names",
            serviceState: "active",
            headlineFacts: [
                ManagerNarrativeFact(
                    priority: "high",
                    title: "Mark's seating note needs review",
                    detail: "Deborah, Gabriella, and Jacob are in the approved packet."
                )
            ],
            availableActions: [
                ManagerNarrativeAction(
                    id: "check-mark-note",
                    title: "Check Mark's note",
                    destinationHint: "guest note"
                )
            ],
            writingRules: []
        )
        let guestNameFallback = ManagerNarrative(
            headline: "Review the approved guest notes.",
            whyItMatters: nil,
            checkNext: nil,
            source: .template,
            failedReason: nil
        )

        expect(
            scenario: "name_ops_current_pressure",
            shouldPass: true,
            candidate: oneLine("Current service pressure is building around 7:00 PM."),
            packet: guestNamePacket,
            hostPacket: calmPacket,
            fallback: guestNameFallback
        )

        expect(
            scenario: "name_ops_todays_service",
            shouldPass: true,
            candidate: oneLine("Today's main issue is the unassigned 2:30 PM table."),
            packet: guestNamePacket,
            hostPacket: calmPacket,
            fallback: guestNameFallback
        )

        expect(
            scenario: "name_ops_peak_booking",
            shouldPass: true,
            candidate: oneLine("Peak booking pressure is around 7:00-7:30."),
            packet: guestNamePacket,
            hostPacket: calmPacket,
            fallback: guestNameFallback
        )

        expect(
            scenario: "name_allowed_jacob",
            shouldPass: true,
            candidate: oneLine("Jacob still needs a table assignment."),
            packet: guestNamePacket,
            hostPacket: calmPacket,
            fallback: guestNameFallback
        )

        expect(
            scenario: "name_allowed_mark_possessive",
            shouldPass: true,
            candidate: oneLine("Mark's note needs review before seating."),
            packet: guestNamePacket,
            hostPacket: calmPacket,
            fallback: guestNameFallback
        )

        expect(
            scenario: "name_reject_unknown_sarah",
            shouldPass: false,
            candidate: oneLine("Sarah needs a table."),
            packet: guestNamePacket,
            hostPacket: calmPacket,
            fallback: guestNameFallback
        )

        expect(
            scenario: "name_reject_unknown_michael",
            shouldPass: false,
            candidate: oneLine("Tell Michael to prepare a VIP table."),
            packet: guestNamePacket,
            hostPacket: calmPacket,
            fallback: guestNameFallback
        )

        let quietGrounding = HostServiceGroundingSummary(
            activeReservationCount: 1,
            expectedGuestCount: 4,
            effectiveNoTableCount: 0,
            allRelevantReservationsHaveTables: true,
            isQuietService: true,
            deterministicSummary: "Quiet service. Annie Zak is confirmed for 6:00 PM, 4 guests, table A1 assigned. Nothing needs attention right now.",
            activeReservationIDs: [42]
        )
        var quietNarrativePacket = emptyNarrativePacket
        quietNarrativePacket.serviceGrounding = quietGrounding
        let quietHostPacket = HostLLMPacket(
            generatedAtDescription: calmPacket.generatedAtDescription,
            serviceState: calmPacket.serviceState,
            pressureScore: calmPacket.pressureScore,
            topFacts: calmPacket.topFacts,
            forbiddenBehaviors: calmPacket.forbiddenBehaviors,
            writingRules: calmPacket.writingRules,
            serviceGrounding: quietGrounding
        )
        let quietFallback = ManagerNarrative(
            headline: quietGrounding.deterministicSummary,
            whyItMatters: nil,
            checkNext: nil,
            source: .template,
            failedReason: nil
        )

        expect(
            scenario: "ai1_grounded_quiet_summary_passes",
            shouldPass: true,
            candidate: quietFallback,
            packet: quietNarrativePacket,
            hostPacket: quietHostPacket,
            fallback: quietFallback
        )

        expect(
            scenario: "ai1_quiet_pressure_claim_blocked",
            shouldPass: false,
            candidate: oneLine("Pressure builds toward 6:00 PM with 1 reservation."),
            packet: quietNarrativePacket,
            hostPacket: quietHostPacket,
            fallback: quietFallback
        )

        expect(
            scenario: "ai1_false_no_table_claim_blocked",
            shouldPass: false,
            candidate: oneLine("Annie Zak still needs a table in the peak window."),
            packet: quietNarrativePacket,
            hostPacket: quietHostPacket,
            fallback: quietFallback
        )

        expect(
            scenario: "ai1_wrong_count_blocked",
            shouldPass: false,
            candidate: oneLine("2 reservations need review before service."),
            packet: quietNarrativePacket,
            hostPacket: quietHostPacket,
            fallback: quietFallback
        )
    }

    // MARK: - Helpers

    private static func oneLine(_ headline: String) -> ManagerNarrative {
        ManagerNarrative(
            headline: headline,
            whyItMatters: nil,
            checkNext: nil,
            source: .localModel,
            failedReason: nil
        )
    }

    private static func expect(
        scenario: String,
        shouldPass: Bool,
        candidate: ManagerNarrative,
        packet: ManagerNarrativePacket,
        hostPacket: HostLLMPacket,
        fallback: ManagerNarrative
    ) {
        let result = ManagerNarrativeValidator.validationResult(
            candidate,
            packet: packet,
            hostPacket: hostPacket,
            fallback: fallback
        )
        let passed = result.isValid
        let meetsExpectation = (passed == shouldPass)
        let outcome = passed ? "pass" : "blocked"
        let detail = meetsExpectation
            ? "expected=\(shouldPass ? "pass" : "blocked") reason=\(HostAIValidatorTrace.classify(result.reason))"
            : "UNEXPECTED expected=\(shouldPass ? "pass" : "blocked") reason=\(HostAIValidatorTrace.classify(result.reason))"
        HostAITestTrace.log(
            scenario: scenario,
            result: meetsExpectation ? outcome : "FAIL_\(outcome)",
            detail: detail
        )
    }
}
#endif
