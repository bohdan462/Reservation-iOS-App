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
        testDuplicateNoTablePresentation()
        testCompactLineDateContext()
        testVagueSeatingPreferenceNotTopLine()
        testSeenBeforeLineNamesGuestAndLastVisit()
        testSeenBeforeNeverRendersWithoutGuestName()
        testReturningGuestSuppressesAllFirstTimeAggregate()
        testSeatingNoteFallbackAction()
        testBusinessInsightNoOperationalNoTableCopy()
        testBusinessInsightRemovesDuplicatePeakLine()
        testWrappedServicePresentation()
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

    private static func testDuplicateNoTablePresentation() {
        let dateKey = "2026-07-02"
        let facts = [
            BriefingFact(id: "no-table-day", kind: .noTableToday, count: 5, priority: 64),
            BriefingFact(id: "no-table-canonical", kind: .noTableToday, count: 5, priority: 62),
            BriefingFact(id: "arrival", kind: .nextArrival, guestName: "Corey Engele", partySize: 2, timeLabel: "18:00", priority: 72)
        ]
        let presentation = HostServiceBriefingTemplateWriter.presentation(
            for: facts,
            dateKey: dateKey,
            serviceMode: .futurePlanning,
            truthCounts: BriefingTruthCounts(
                activeReservations: 5,
                expectedGuests: 14,
                seatedReservations: 0,
                waitingArrivals: 0,
                noTable: 5,
                completedReservations: 0,
                walkInCompleted: 0,
                noShows: 0,
                newGuests: 5
            ),
            now: ReservationFormatters.serverDateMinute.date(from: "\(dateKey) 12:00")!
        )
        let text = ([presentation.compactLine] + presentation.sections.flatMap(\.lines)).joined(separator: " ")
        expect(
            "duplicate_no_table_not_repeated",
            text.components(separatedBy: "tables still need to be picked").count - 1 == 0
                && text.components(separatedBy: "still need tables").count - 1 == 1
        )
    }

    private static func testCompactLineDateContext() {
        let dateKey = "2026-07-02"
        let presentation = HostServiceBriefingTemplateWriter.presentation(
            for: [BriefingFact(id: "no-table", kind: .noTableToday, count: 5, priority: 70)],
            dateKey: dateKey,
            serviceMode: .futurePlanning,
            truthCounts: BriefingTruthCounts(
                activeReservations: 5,
                expectedGuests: 14,
                seatedReservations: 0,
                waitingArrivals: 0,
                noTable: 5,
                completedReservations: 0,
                walkInCompleted: 0,
                noShows: 0,
                newGuests: nil
            ),
            now: ReservationFormatters.serverDateMinute.date(from: "\(dateKey) 12:00")!
        )
        expect(
            "compact_line_date_context",
            presentation.compactLine.hasPrefix("Thursday:")
        )
    }

    private static func testVagueSeatingPreferenceNotTopLine() {
        let dateKey = "2026-07-02"
        let presentation = HostServiceBriefingTemplateWriter.presentation(
            for: [
                BriefingFact(id: "seat", kind: .seatingPreference, reservationID: 12, guestName: "Corey Engele", partySize: 2, timeLabel: "18:00", priority: 80),
                BriefingFact(id: "overview", kind: .dayOverview, count: 1, secondaryCount: 2, priority: 40)
            ],
            dateKey: dateKey,
            serviceMode: .futurePlanning,
            truthCounts: BriefingTruthCounts(
                activeReservations: 1,
                expectedGuests: 2,
                seatedReservations: 0,
                waitingArrivals: 0,
                noTable: 0,
                completedReservations: 0,
                walkInCompleted: 0,
                noShows: 0,
                newGuests: nil
            ),
            now: ReservationFormatters.serverDateMinute.date(from: "\(dateKey) 12:00")!
        )
        expect(
            "vague_seating_not_top_line",
            !presentation.compactLine.localizedCaseInsensitiveContains("seating")
                && !presentation.compactLine.localizedCaseInsensitiveContains("preference")
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

    private static func testSeenBeforeLineNamesGuestAndLastVisit() {
        let dateKey = "2026-07-02"
        let now = ReservationFormatters.serverDateMinute.date(from: "\(dateKey) 12:00")!
        let reservation = ReservationRecord(
            fixtureRemoteID: 4237,
            reservationDate: dateKey,
            reservationTime: "18:00:00",
            partySize: 2,
            status: .confirmed
        )
        reservation.guestName = "Anna Kowalski"
        let snapshot = HostServiceIntelligenceSnapshot(
            dateKey: dateKey,
            generatedAt: now,
            serviceMode: .futurePlanning,
            headline: "Seen before · Last visit Nov 29, 2024",
            subline: nil,
            reservationCount: 1,
            guestCount: 2,
            rankedFacts: [
                ServiceIntelligenceFact(
                    id: "seen-before-4237",
                    reservationID: 4237,
                    guestName: "Anna Kowalski",
                    category: .regularGuest,
                    priority: 45,
                    headline: "Seen before · Last visit Nov 29, 2024",
                    detail: "Seen before · Last visit Nov 29, 2024"
                )
            ],
            inputFingerprint: "snapshot-proof"
        )
        let packet = HostServiceBriefingPacketBuilder.build(
            HostServiceBriefingPacketBuilder.Input(
                now: now,
                selectedDate: now,
                dateKey: dateKey,
                serviceMode: .futurePlanning,
                dayReservations: [reservation],
                historyReservations: [reservation],
                serviceSnapshot: snapshot,
                decisionSnapshot: .empty,
                localSeatedAtByReservationID: [:],
                sourceFingerprint: "proof-source"
            )
        )
        let text = packetText(packet)
        expect(
            "seen_before_guest_name_last_visit",
            text.contains("Anna has been here before. Last visit Nov 29, 2024.")
        )
    }

    private static func testSeenBeforeNeverRendersWithoutGuestName() {
        let fact = BriefingFact(
            id: "memory",
            kind: .guestMemory,
            reservationID: 4237,
            guestName: "Anna Kowalski",
            timeLabel: "Nov 29, 2024",
            priority: 60
        )
        let line = HostServiceBriefingTemplateWriter.line(for: fact) ?? ""
        expect(
            "seen_before_not_naked",
            line.contains("Anna")
                && !line.hasPrefix("Seen before")
                && !line.hasPrefix("Regular")
        )
    }

    private static func testReturningGuestSuppressesAllFirstTimeAggregate() {
        let dateKey = "2026-07-02"
        let presentation = HostServiceBriefingTemplateWriter.presentation(
            for: [
                BriefingFact(id: "memory", kind: .guestMemory, reservationID: 4237, guestName: "Anna Kowalski", timeLabel: "Nov 29, 2024", priority: 60),
                BriefingFact(id: "new-guests", kind: .newGuestCount, count: 5, priority: 35)
            ],
            dateKey: dateKey,
            serviceMode: .futurePlanning,
            truthCounts: BriefingTruthCounts(
                activeReservations: 5,
                expectedGuests: 14,
                seatedReservations: 0,
                waitingArrivals: 0,
                noTable: 0,
                completedReservations: 0,
                walkInCompleted: 0,
                noShows: 0,
                newGuests: 5
            ),
            now: ReservationFormatters.serverDateMinute.date(from: "\(dateKey) 12:00")!
        )
        let text = ([presentation.compactLine] + presentation.sections.flatMap(\.lines)).joined(separator: " ")
        expect(
            "returning_guest_suppresses_all_first_time",
            !text.contains("All 5 look like first-time guests.")
        )
    }

    private static func testSeatingNoteFallbackAction() {
        let fact = BriefingFact(
            id: "seat",
            kind: .seatingPreference,
            reservationID: 12,
            guestName: "Corey Engele",
            priority: 70
        )
        expect(
            "seating_note_fallback_action",
            HostServiceBriefingTemplateWriter.line(for: fact)
                == "Corey has a seating note. Open reservation to review."
        )
    }

    private static func testBusinessInsightNoOperationalNoTableCopy() {
        let json = """
        {
          "summary": { "totalGuests": 14 },
          "risk": { "noTableCount": 7 },
          "demand": {},
          "guestRelationships": {},
          "breakdowns": {},
          "pipeline": {}
        }
        """
        let data = Data(json.utf8)
        let summary = try? JSONDecoder().decode(BusinessIntelligenceSummaryDTO.self, from: data)
        let lines = summary.map {
            BusinessIntelligenceInsightBuilder.build(summary: $0, systemStatus: nil)
        } ?? []
        let text = lines.joined(separator: " ").lowercased()
        expect(
            "business_no_operational_no_table_copy",
            summary != nil
                && !text.contains("need tables")
                && !text.contains("no table")
                && !text.contains("without tables")
        )
    }

    private static func testBusinessInsightRemovesDuplicatePeakLine() {
        let json = """
        {
          "summary": { "totalGuests": 14 },
          "risk": {},
          "demand": { "busiestWeekdayLabel": "Sunday", "peak15MinWindow": "18:45" },
          "guestRelationships": {},
          "breakdowns": {},
          "pipeline": {}
        }
        """
        let data = Data(json.utf8)
        let summary = try? JSONDecoder().decode(BusinessIntelligenceSummaryDTO.self, from: data)
        let lines = summary.map {
            BusinessIntelligenceInsightBuilder.build(summary: $0, systemStatus: nil)
        } ?? []
        expect(
            "business_peak_duplicate_removed",
            lines.contains { $0.localizedCaseInsensitiveContains("Main pressure builds around") }
                && !lines.contains { $0.localizedCaseInsensitiveContains("Peak window:") }
        )
    }

    private static func testWrappedServicePresentation() {
        let dateKey = "2026-06-30"
        let presentation = HostServiceBriefingTemplateWriter.presentation(
            for: [
                BriefingFact(id: "completed", kind: .completedRecap, count: 2, priority: 40)
            ],
            dateKey: dateKey,
            serviceMode: .afterCloseFinished,
            truthCounts: BriefingTruthCounts(
                activeReservations: 0,
                expectedGuests: 0,
                seatedReservations: 0,
                waitingArrivals: 0,
                noTable: 0,
                completedReservations: 2,
                walkInCompleted: 0,
                noShows: 0,
                newGuests: nil
            ),
            now: ReservationFormatters.serverDateMinute.date(from: "\(dateKey) 22:00")!
        )
        expect(
            "wrapped_service_compact_copy",
            presentation.compactLine == "Service is wrapped."
                && presentation.compactChips == ["2 completed", "no active guests"]
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
            "threshold"
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
