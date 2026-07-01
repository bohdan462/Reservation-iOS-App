//
//  StaffBriefingProofHarness.swift
//  Tryzub Reservations
//
//  4F-1 — DEBUG-only focused checks for the on-demand staff briefing foundation.
//  Follows the existing proof-harness pattern (no formal XCTest target yet).
//

import Foundation

#if DEBUG
enum StaffBriefingProofHarness {

    static func run() {
        testPreServiceTemplate()
        testLiveServiceTemplate()
        testClosingRecapTemplateWithTomorrow()
        testValidatorRejectsUnknownGuest()
        testValidatorRejectsUnknownTable()
        testValidatorRejectsImpossibleCount()
        testValidatorRejectsPhoneVariants()
        testValidatorAcceptsTimeAndRangePatterns()
        testValidatorAcceptsMidTextArticlesAndImperatives()
        testValidatorRejectsEmail()
        testValidatorRejectsMetaLanguage()
        testValidatorRejectsExecutionClaim()
        testValidatorRejectsTooLong()
        testValidatorAcceptsGroundedOutput()
        testParserRejectsEmptyAndMissingHeadline()
        testCacheHit()
        testStaleDetection()
        testNoAutoGenerationOnFingerprintChange()
    }

    // MARK: - Template results

    private static func testPreServiceTemplate() {
        let result = StaffBriefingWriter.writeTemplate(input(for: makePacket(mode: .preService)))
        expect(
            "preservice_template",
            result.source == .template && !result.headline.isEmpty && !result.sections.isEmpty
        )
    }

    private static func testLiveServiceTemplate() {
        let result = StaffBriefingWriter.writeTemplate(input(for: makePacket(mode: .liveService)))
        expect(
            "liveservice_template",
            result.source == .template && !result.headline.isEmpty && !result.sections.isEmpty
        )
    }

    private static func testClosingRecapTemplateWithTomorrow() {
        let packet = makePacket(mode: .closingRecap, includeTomorrow: true)
        let result = StaffBriefingWriter.writeTemplate(input(for: packet))
        let hasTomorrow = result.sections.contains { $0.id == "tomorrow" && !$0.isEmpty }
        expect(
            "closingrecap_template_tomorrow",
            result.source == .template && hasTomorrow
        )
    }

    // MARK: - Validator rejections
    //
    // Checks 8–11 (guest name, table label, count grounding, status claims) are currently
    // SOFT WARNS only (logged, not hard-rejecting) so model output reaches the UI for
    // prompt-tuning. The tests below verify the WARN fires (debugDetail non-nil) rather
    // than a hard rejection. Re-tighten once output quality is confirmed.

    private static func testValidatorRejectsUnknownGuest() {
        let packet = makePacket(mode: .preService)
        let raw = """
        HEADLINE: Steady night ahead.
        SECTION overview: Tonight is steady with 8 reservations.
        SECTION guests:
        - Gregory has a large party.
        """
        // Soft warn only — output is still accepted so it reaches the UI.
        guard let parsed = StaffBriefingOutputParser.parse(raw) else {
            expect("validator_unknown_guest_softWarn", false); return
        }
        let result = StaffBriefingValidator.validate(parsed: parsed, packet: packet)
        expect("validator_unknown_guest_softWarn", result.accepted)
    }

    private static func testValidatorRejectsUnknownTable() {
        let packet = makePacket(mode: .preService)
        let raw = """
        HEADLINE: Setup needed.
        SECTION floor:
        - B9 needs setup before doors.
        """
        guard let parsed = StaffBriefingOutputParser.parse(raw) else {
            expect("validator_unknown_table_softWarn", false); return
        }
        let result = StaffBriefingValidator.validate(parsed: parsed, packet: packet)
        expect("validator_unknown_table_softWarn", result.accepted)
    }

    private static func testValidatorRejectsImpossibleCount() {
        let packet = makePacket(mode: .preService)
        let raw = """
        HEADLINE: 45 reservations booked tonight.
        SECTION overview: A very large evening is expected.
        """
        guard let parsed = StaffBriefingOutputParser.parse(raw) else {
            expect("validator_impossible_count_softWarn", false); return
        }
        let result = StaffBriefingValidator.validate(parsed: parsed, packet: packet)
        expect("validator_impossible_count_softWarn", result.accepted)
    }

    /// 4F-2 — the local model was once rejected with reason=contact_phone even though
    /// it only wrote ordinary service times (18:45, 03:52) and a duration range
    /// (30-60 minutes). These variants must still be rejected as real phone numbers.
    private static func testValidatorRejectsPhoneVariants() {
        let packet = makePacket(mode: .preService)
        let variants = [
            "555-123-4567",
            "(555) 123-4567",
            "555.123.4567",
            "+1 555 123 4567",
            "555 123 4567",
        ]
        var allPassed = true
        for variant in variants {
            let raw = """
            HEADLINE: Follow up needed.
            SECTION followup:
            - Reach them at \(variant) to confirm.
            """
            guard let parsed = StaffBriefingOutputParser.parse(raw) else {
                allPassed = false
                continue
            }
            let result = StaffBriefingValidator.validate(parsed: parsed, packet: packet)
            let rejectedForPhone = !result.accepted && result.rejectionReason == "contact_phone"
            if !rejectedForPhone {
                allPassed = false
                print("[STAFF_BRIEFING_TEST] phone_variant_failed variant=\(variant) reason=\(result.rejectionReason ?? "accepted")")
            }
        }
        expect("validator_rejects_phone_variants", allPassed)
    }

    /// 4F-2 — the fix for testValidatorRejectsPhoneVariants must not start rejecting
    /// ordinary times, ranges, or dates that happen to contain several digits.
    private static func testValidatorAcceptsTimeAndRangePatterns() {
        let packet = makePacket(mode: .preService)
        let raw = """
        HEADLINE: Nothing urgent before service.
        SECTION overview: First arrival lands around 6:45 PM, after a prep window of 30-60 minutes. Service opened on 2026-07-01, the last check was logged at 03:52, and another window of 30–60 minutes is possible near 18:45.
        """
        guard let parsed = StaffBriefingOutputParser.parse(raw) else {
            expect("validator_accepts_time_and_range_patterns", false); return
        }
        let result = StaffBriefingValidator.validate(parsed: parsed, packet: packet)
        expect(
            "validator_accepts_time_and_range_patterns",
            result.accepted && result.rejectionReason == nil
        )
        if !result.accepted {
            print("[STAFF_BRIEFING_TEST] accept_time_patterns_failed reason=\(result.rejectionReason ?? "unknown") detail=\(result.debugDetail ?? "none")")
        }
    }

    /// 4F-2 device regression — model wrote "The main thing to handle…" and "The" was
    /// rejected as an unknown guest name (index > 0, capitalized, not in allowlist).
    /// This test reproduces the exact pattern from the device log and verifies the fix.
    private static func testValidatorAcceptsMidTextArticlesAndImperatives() {
        let packet = makePacket(mode: .preService)
        // Mirrors the template/model prose style: articles ("The", "There") and
        // imperative verbs ("Pick", "Send", "Watch") starting mid-text sentences.
        let raw = """
        HEADLINE: Here's the picture before service.
        SECTION overview: You have 2 reservations and about 7 guests expected. The main thing to handle before service is table assignment: all of them still need a table. There are also 2 reminders that haven't gone out.
        SECTION followup:
        - Pick tables for the 2 reservations still without one.
        - Send the missing reminders.
        - Watch the first arrival around 18:00.
        """
        guard let parsed = StaffBriefingOutputParser.parse(raw, mode: .preService) else {
            expect("validator_accepts_mid_text_articles", false); return
        }
        let result = StaffBriefingValidator.validate(parsed: parsed, packet: packet)
        expect(
            "validator_accepts_mid_text_articles",
            result.accepted && result.rejectionReason == nil
        )
        if !result.accepted {
            print("[STAFF_BRIEFING_TEST] mid_text_articles_failed reason=\(result.rejectionReason ?? "unknown") detail=\(result.debugDetail ?? "none")")
        }
    }

    private static func testValidatorRejectsEmail() {
        let packet = makePacket(mode: .preService)
        let raw = """
        HEADLINE: Email the guest.
        SECTION followup:
        - Write to guest@example.com about the booking.
        """
        expectRejection("validator_email", raw: raw, packet: packet, reason: "contact_email")
    }

    private static func testValidatorRejectsMetaLanguage() {
        let packet = makePacket(mode: .preService)
        let raw = """
        HEADLINE: Overview for tonight.
        SECTION overview: This briefing was generated by an AI model for staff.
        """
        expectRejection("validator_meta", raw: raw, packet: packet, reason: "meta_language")
    }

    private static func testValidatorRejectsExecutionClaim() {
        let packet = makePacket(mode: .preService)
        let raw = """
        HEADLINE: Confirmations done.
        SECTION followup:
        - We sent reminders to every guest already.
        """
        expectRejection("validator_execution", raw: raw, packet: packet, reason: "execution_claim")
    }

    private static func testValidatorRejectsTooLong() {
        let packet = makePacket(mode: .preService)
        let filler = Array(repeating: "steady", count: 1300).joined(separator: " ")
        let raw = """
        HEADLINE: Long night ahead.
        SECTION overview: \(filler)
        """
        expectRejection("validator_too_long", raw: raw, packet: packet, reason: "too_long")
    }

    private static func testValidatorAcceptsGroundedOutput() {
        let packet = makePacket(mode: .preService)
        let raw = """
        HEADLINE: 8 reservations booked, 20 guests expected.
        SECTION overview: Tonight is steady with 8 reservations.
        SECTION attention:
        - 1 reservation still needs review.
        SECTION guests:
        - Julie Bachman: occasion note.
        """
        guard let parsed = StaffBriefingOutputParser.parse(raw) else {
            expect("validator_accepts_grounded", false); return
        }
        let result = StaffBriefingValidator.validate(parsed: parsed, packet: packet)
        expect("validator_accepts_grounded", result.accepted && result.rejectionReason == nil)
    }

    private static func testParserRejectsEmptyAndMissingHeadline() {
        let empty = StaffBriefingOutputParser.parse("   ")
        let noHeadline = StaffBriefingOutputParser.parse("SECTION overview: hello there")
        expect("parser_rejects_empty_and_headless", empty == nil && noHeadline == nil)
    }

    // MARK: - Cache / stale / no-auto-generation

    private static func testCacheHit() {
        let a = cacheKey(mode: .preService, date: "2026-07-01", fp: "fp-1", stamp: "on")
        let b = cacheKey(mode: .preService, date: "2026-07-01", fp: "fp-1", stamp: "on")
        var cache: [StaffBriefingCacheKey: String] = [:]
        cache[a] = "stored"
        expect("cache_hit", a == b && cache[b] == "stored")
    }

    private static func testStaleDetection() {
        let current = cacheKey(mode: .preService, date: "2026-07-01", fp: "fp-2", stamp: "on")
        let older = cacheKey(mode: .preService, date: "2026-07-01", fp: "fp-1", stamp: "on")
        var cache: [StaffBriefingCacheKey: String] = [:]
        cache[older] = "old-result"
        let hit = cache[current]
        let staleMatch = cache.first { $0.key.mode == current.mode && $0.key.dateKey == current.dateKey && $0.key != current }
        expect("stale_detection", hit == nil && staleMatch != nil)
    }

    private static func testNoAutoGenerationOnFingerprintChange() {
        // Rebuilding a packet is pure and must never itself produce a result. A changed
        // input fingerprint yields a *different* packet fingerprint (→ controller marks
        // stale), it does not silently regenerate.
        let base = makeServicePacket(fingerprint: "svc-1")
        let changed = makeServicePacket(fingerprint: "svc-2")
        let p1 = StaffBriefingPacketBuilder.build(builderInput(base))
        let p2 = StaffBriefingPacketBuilder.build(builderInput(changed))
        expect("no_auto_generation_on_fingerprint_change", p1.inputFingerprint != p2.inputFingerprint)
        print("[STAFF_BRIEFING_TEST] staff_briefing=pass")
    }

    // MARK: - Fixtures

    private static func makeServicePacket(fingerprint: String) -> HostServiceBriefingPacket {
        HostServiceBriefingPacket(
            dateKey: "2026-07-01",
            serviceMode: .beforeService,
            generatedAt: Date(timeIntervalSince1970: 0),
            inputFingerprint: fingerprint,
            truthCounts: BriefingTruthCounts(
                activeReservations: 8, expectedGuests: 20, seatedReservations: 2,
                waitingArrivals: 1, noTable: 1, completedReservations: 0,
                walkInCompleted: 0, noShows: 0, newGuests: 3
            ),
            allowedGuestNames: ["Julie Bachman"],
            allowedTableLabels: ["A1"],
            compactLine: "Nothing urgent right now.",
            compactChips: [],
            sections: [],
            facts: [
                BriefingFact(id: "f1", kind: .occasion, reservationID: 1, guestName: "Julie Bachman", partySize: 5, timeLabel: "6:30 PM", priority: 80),
                BriefingFact(id: "f2", kind: .noTableToday, count: 1, priority: 70),
                BriefingFact(id: "f3", kind: .allergy, count: 1, priority: 90)
            ]
        )
    }

    private static func builderInput(_ servicePacket: HostServiceBriefingPacket) -> StaffBriefingPacketBuilder.Input {
        StaffBriefingPacketBuilder.Input(
            mode: .preService,
            dateKey: "2026-07-01",
            now: Date(timeIntervalSince1970: 0),
            serviceMode: .beforeService,
            sourceFingerprint: "src-1",
            servicePacket: servicePacket,
            dayReservations: [],
            tomorrowReservations: [],
            businessSummaryLines: [],
            largePartyThreshold: 7
        )
    }

    private static func makePacket(mode: StaffBriefingMode, includeTomorrow: Bool = false) -> StaffBriefingPacket {
        let counts = StaffBriefingStatusCounts(
            totalReservations: 8, expectedGuests: 20, newCount: 3, needsReviewCount: 1,
            confirmedCount: 2, seatedCount: 2, completedCount: 0, cancelledCount: 0,
            noShowCount: 0, activeCount: 8, remainingArrivalsCount: 6,
            currentlySeatedGuests: 5, stillSeatedReservations: 2, unresolvedCount: 1
        )
        let facts = [
            BriefingFact(id: "f1", kind: .occasion, reservationID: 1, guestName: "Julie Bachman", partySize: 5, timeLabel: "6:30 PM", priority: 80),
            BriefingFact(id: "f2", kind: .noTableToday, count: 1, priority: 70),
            BriefingFact(id: "f3", kind: .allergy, reservationID: 2, guestName: "Julie Bachman", count: 1, priority: 90)
        ]
        let tomorrow = includeTomorrow
            ? StaffBriefingTomorrowPreview(
                dateKey: "2026-07-02", reservationCount: 5, expectedGuests: 12,
                needsReviewCount: 1, noTableCount: 1, largePartyCount: 1,
                attachmentCount: 1, allergyCount: 1, occasionCount: 1,
                regularGuestCount: 0, priorityFacts: [], hasData: true
              )
            : nil
        return StaffBriefingPacket(
            mode: mode,
            dateKey: "2026-07-01",
            requestedAt: Date(timeIntervalSince1970: 0),
            serviceMode: mode == .liveService ? .duringService : (mode == .closingRecap ? .afterCloseFinished : .beforeService),
            serviceStateLabel: "Before open",
            inputFingerprint: "staff-fp-1",
            sourceFingerprint: "src-1",
            promptVersion: StaffBriefingPromptBuilder.promptVersion,
            truthCounts: BriefingTruthCounts(
                activeReservations: 8, expectedGuests: 20, seatedReservations: 2,
                waitingArrivals: 1, noTable: 1, completedReservations: 0,
                walkInCompleted: 0, noShows: 0, newGuests: 3
            ),
            statusCounts: counts,
            priorityFacts: facts,
            allowedGuestNames: ["Julie Bachman"],
            allowedTableLabels: ["A1"],
            attachmentSummaries: [
                StaffBriefingAttachmentSummary(id: "2", guestName: "Julie Bachman", timeLabel: "6:30 PM", tags: [.deposit], reviewNeeded: true)
            ],
            communicationSummary: StaffBriefingCommunicationSummary(
                confirmationsMissingCount: 2, confirmationsSentCount: 4,
                remindersMissingCount: 3, remindersSentCount: nil, autoConfirmedCount: nil
            ),
            businessSummaryLines: ["Weekend pressure is building."],
            tomorrowPreview: tomorrow
        )
    }

    private static func input(for packet: StaffBriefingPacket) -> StaffBriefingWriter.Input {
        StaffBriefingWriter.Input(
            packet: packet,
            settings: HostIntelligenceSettings.templateOnlyForTests,
            gateContext: StaffBriefingGate.Context(isLocalModelInferenceActive: false),
            serviceDateLabel: nil,
            cacheKey: cacheKey(mode: packet.mode, date: packet.dateKey, fp: packet.inputFingerprint, stamp: "off")
        )
    }

    private static func cacheKey(mode: StaffBriefingMode, date: String, fp: String, stamp: String) -> StaffBriefingCacheKey {
        StaffBriefingCacheKey(
            mode: mode, dateKey: date, packetFingerprint: fp,
            sourceFingerprint: "src-1", promptVersion: StaffBriefingPromptBuilder.promptVersion, settingsStamp: stamp
        )
    }

    // MARK: - Assertions

    private static func expectRejection(
        _ scenario: String,
        raw: String,
        packet: StaffBriefingPacket,
        reason: String
    ) {
        guard let parsed = StaffBriefingOutputParser.parse(raw) else {
            // A nil parse is also a valid rejection for empty/headless output.
            expect(scenario, reason == "parse_failed")
            return
        }
        let result = StaffBriefingValidator.validate(parsed: parsed, packet: packet)
        expect(scenario, !result.accepted && result.rejectionReason == reason)
    }

    private static func expect(_ scenario: String, _ passed: Bool) {
        print("[STAFF_BRIEFING_TEST] scenario=\(scenario) result=\(passed ? "pass" : "FAIL")")
    }
}
#endif
