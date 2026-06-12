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
