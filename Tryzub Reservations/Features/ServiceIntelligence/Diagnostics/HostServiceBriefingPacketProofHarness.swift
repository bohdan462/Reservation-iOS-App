//
//  HostServiceBriefingPacketProofHarness.swift
//  Tryzub Reservations
//
//  DEBUG-only focused checks for the parent Service Briefing Packet. This follows
//  the existing proof-harness pattern until the project has a formal XCTest target.
//

import Foundation

#if DEBUG
enum HostServiceBriefingPacketProofHarness {

    static func run() {
        testBirthdayLine()
        testSeatedDurationLine()
        testSeatedOverviewLine()
        testSeatedMinuteFingerprint()
        testNoTableCountLine()
        testNewGuestCountLine()
        testWalkInCompletedRecap()
        testBannedPhraseAbsence()
        testNoRawContactOrNotes()
    }

    private static func testBirthdayLine() {
        let fact = BriefingFact(
            id: "occasion-1",
            kind: .occasion,
            reservationID: 1,
            guestName: "Julie Bachman",
            partySize: 5,
            timeLabel: "6:30 PM",
            priority: 80
        )
        let line = HostServiceBriefingTemplateWriter.line(for: fact) ?? ""
        expect(
            "birthday_occasion_line",
            line.contains("Occasion note.") && !line.localizedCaseInsensitiveContains("birthday or occasion")
        )
    }

    private static func testSeatedDurationLine() {
        let fact = BriefingFact(
            id: "seated-1",
            kind: .seatedDuration,
            guestName: "Tristan",
            tableLabel: "A1",
            minutes: 84,
            priority: 80
        )
        expect(
            "seated_duration_line",
            HostServiceBriefingTemplateWriter.line(for: fact) == "Tristan has been at A1 for 1h 24m."
        )
    }

    private static func testSeatedOverviewLine() {
        let one = BriefingFact(
            id: "seated-one",
            kind: .seatedOverview,
            count: 1,
            priority: 40
        )
        let many = BriefingFact(
            id: "seated-many",
            kind: .seatedOverview,
            count: 2,
            priority: 40
        )
        let lines = [
            HostServiceBriefingTemplateWriter.line(for: one) ?? "",
            HostServiceBriefingTemplateWriter.line(for: many) ?? ""
        ]
        expect(
            "seated_overview_party_wording",
            lines == ["1 party is seated.", "2 parties are seated."]
                && !lines.joined(separator: " ").contains("table is seated")
                && !lines.joined(separator: " ").contains("tables are seated")
        )
    }

    private static func testSeatedMinuteFingerprint() {
        let dateKey = "2026-06-12"
        let now = ReservationFormatters.serverDateMinute.date(from: "\(dateKey) 18:24")!
        let seatedAt = ReservationFormatters.serverDateMinute.date(from: "\(dateKey) 17:00")!
        let reservation = ReservationRecord(
            fixtureRemoteID: 44,
            reservationDate: dateKey,
            reservationTime: "17:00:00",
            partySize: 2,
            status: .seated,
            tableName: "A1"
        )
        let snapshot = HostServiceIntelligenceSnapshot(
            dateKey: dateKey,
            generatedAt: now,
            serviceMode: .duringService,
            headline: "",
            subline: nil,
            reservationCount: 1,
            guestCount: 2,
            rankedFacts: [],
            inputFingerprint: "snapshot-proof"
        )
        let first = HostServiceBriefingPacketBuilder.Input(
            now: now,
            selectedDate: now,
            dateKey: dateKey,
            serviceMode: .duringService,
            dayReservations: [reservation],
            historyReservations: [reservation],
            serviceSnapshot: snapshot,
            decisionSnapshot: .empty,
            localSeatedAtByReservationID: [44: seatedAt],
            sourceFingerprint: "proof-source"
        )
        let second = HostServiceBriefingPacketBuilder.Input(
            now: now.addingTimeInterval(60),
            selectedDate: now,
            dateKey: dateKey,
            serviceMode: .duringService,
            dayReservations: [reservation],
            historyReservations: [reservation],
            serviceSnapshot: snapshot,
            decisionSnapshot: .empty,
            localSeatedAtByReservationID: [44: seatedAt],
            sourceFingerprint: "proof-source"
        )
        expect(
            "seated_minute_fingerprint",
            HostServiceBriefingPacketBuilder.inputFingerprint(first)
                != HostServiceBriefingPacketBuilder.inputFingerprint(second)
        )
    }

    private static func testNoTableCountLine() {
        let fact = BriefingFact(
            id: "no-table",
            kind: .noTableToday,
            count: 4,
            priority: 70
        )
        expect(
            "no_table_count_line",
            HostServiceBriefingTemplateWriter.line(for: fact) == "4 tables still need to be picked."
        )
    }

    private static func testNewGuestCountLine() {
        let fact = BriefingFact(
            id: "new-guests",
            kind: .newGuestCount,
            count: 4,
            priority: 40
        )
        expect(
            "new_guest_count_line",
            HostServiceBriefingTemplateWriter.line(for: fact) == "4 reservations are new guests."
        )
    }

    private static func testWalkInCompletedRecap() {
        let fact = BriefingFact(
            id: "completed",
            kind: .completedRecap,
            count: 7,
            secondaryCount: 5,
            priority: 40
        )
        expect(
            "walk_in_completed_recap",
            HostServiceBriefingTemplateWriter.line(for: fact) == "7 completed so far. 5 were walk-ins."
        )
    }

    private static func testBannedPhraseAbsence() {
        let facts = [
            BriefingFact(id: "calm", kind: .serviceCalm, priority: 10),
            BriefingFact(id: "allergy", kind: .allergy, guestName: "Heather", partySize: 5, timeLabel: "7:00 PM", priority: 90),
            BriefingFact(id: "notable", kind: .noTableToday, count: 2, priority: 70)
        ]
        let presentation = HostServiceBriefingTemplateWriter.presentation(for: facts)
        let text = ([presentation.compactLine] + presentation.compactChips + presentation.sections.flatMap(\.lines))
            .joined(separator: " ")
            .lowercased()
        let banned = [
            "staff needs review",
            "check guest note",
            "operational action required",
            "operational action",
            "guest signal detected",
            "guest signal",
            "metadata",
            "attention category",
            "candidate",
            "threshold",
            "review"
        ]
        expect(
            "banned_phrase_absence",
            !banned.contains { text.contains($0) }
        )
    }

    private static func testNoRawContactOrNotes() {
        let dateKey = "2026-06-12"
        let now = ReservationFormatters.serverDateMinute.date(from: "\(dateKey) 18:00")!
        let reservation = ReservationRecord(
            fixtureRemoteID: 11,
            reservationDate: dateKey,
            reservationTime: "18:30:00",
            partySize: 5,
            status: .confirmed
        )
        reservation.guestName = "Julie Bachman"
        reservation.email = "julie@example.com"
        reservation.phone = "3125550199"
        reservation.guestNotes = "raw birthday note with secret phrase"
        reservation.staffNotes = "raw staff note with private setup"

        let snapshot = HostServiceIntelligenceSnapshot(
            dateKey: dateKey,
            generatedAt: now,
            serviceMode: .beforeService,
            headline: "Julie has an occasion note.",
            subline: nil,
            reservationCount: 1,
            guestCount: 5,
            rankedFacts: [
                ServiceIntelligenceFact(
                    id: "occasion-11",
                    reservationID: 11,
                    guestName: "Julie Bachman",
                    category: .occasion,
                    priority: 80,
                    headline: "Julie has an occasion note.",
                    detail: "raw birthday note with secret phrase"
                )
            ],
            inputFingerprint: "snapshot-proof"
        )
        let packet = HostServiceBriefingPacketBuilder.build(
            HostServiceBriefingPacketBuilder.Input(
                now: now,
                selectedDate: now,
                dateKey: dateKey,
                serviceMode: .beforeService,
                dayReservations: [reservation],
                historyReservations: [reservation],
                serviceSnapshot: snapshot,
                decisionSnapshot: .empty,
                localSeatedAtByReservationID: [:],
                sourceFingerprint: "proof-source"
            )
        )
        let text = packetText(packet).lowercased()
        expect(
            "no_raw_contact_in_packet",
            !text.contains("julie@example.com") && !text.contains("3125550199")
        )
        expect(
            "no_raw_notes_in_packet",
            !text.contains("secret phrase") && !text.contains("private setup")
        )
    }

    private static func packetText(_ packet: HostServiceBriefingPacket) -> String {
        (
            [packet.compactLine]
            + packet.compactChips
            + packet.sections.flatMap(\.lines)
            + packet.facts.compactMap(\.guestName)
            + packet.facts.compactMap(\.tableLabel)
        ).joined(separator: " ")
    }

    private static func expect(_ scenario: String, _ passed: Bool) {
        print("[SERVICE_BRIEFING_PACKET_TEST] scenario=\(scenario) result=\(passed ? "pass" : "FAIL")")
    }
}
#endif
