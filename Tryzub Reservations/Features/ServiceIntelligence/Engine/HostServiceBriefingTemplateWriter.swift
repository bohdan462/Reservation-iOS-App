//
//  HostServiceBriefingTemplateWriter.swift
//  Tryzub Reservations
//
//  Temporary human wording for HostServiceBriefingPacket.
//  Bohdan will replace tone later; keep phrases short and service-floor plain.
//

import Foundation

enum HostServiceBriefingTemplateWriter {

    static func presentation(for facts: [BriefingFact]) -> BriefingPresentation {
        presentation(
            for: facts,
            dateKey: Date.reservationDateString(),
            serviceMode: .beforeService,
            truthCounts: BriefingTruthCounts(
                activeReservations: 0,
                expectedGuests: 0,
                seatedReservations: 0,
                waitingArrivals: 0,
                noTable: 0,
                completedReservations: 0,
                walkInCompleted: 0,
                noShows: 0,
                newGuests: nil
            ),
            now: Date()
        )
    }

    static func presentation(
        for facts: [BriefingFact],
        dateKey: String,
        serviceMode: ServiceMode,
        truthCounts: BriefingTruthCounts,
        now: Date
    ) -> BriefingPresentation {
        let sortedFacts = facts
        let compact = compactLine(
            facts: sortedFacts,
            dateKey: dateKey,
            serviceMode: serviceMode,
            truthCounts: truthCounts
        )
        let chips = compactChips(
            for: sortedFacts,
            serviceMode: serviceMode,
            truthCounts: truthCounts
        )
        let sections = sectionedFacts(
            sortedFacts,
            serviceMode: serviceMode,
            truthCounts: truthCounts
        )
        return BriefingPresentation(
            compactLine: compact,
            compactChips: chips,
            sections: sections
        )
    }

    static func line(for fact: BriefingFact) -> String? {
        switch fact.kind {
        case .dayOverview:
            guard let reservations = fact.count, let guests = fact.secondaryCount else { return nil }
            return "\(reservations) \(reservations == 1 ? "reservation" : "reservations") today. \(guests) \(guests == 1 ? "guest" : "guests")."

        case .arrivalWindow:
            guard let time = fact.timeLabel, let reservations = fact.count else { return nil }
            return "\(time) is the busiest arrival window. \(reservations) \(reservations == 1 ? "reservation" : "reservations")."

        case .timedArrival:
            return reservationLine(fact: fact, reason: "Arrival.")

        case .nextArrival:
            return reservationLine(fact: fact)

        case .seatedOverview:
            guard let count = fact.count else { return nil }
            return count == 1 ? "1 party is seated." : "\(count) parties are seated."

        case .seatedDuration:
            guard let name = displayName(fact.guestName), let table = fact.tableLabel, let minutes = fact.minutes else { return nil }
            return "\(name) has been at \(table) for \(durationText(minutes: minutes))."

        case .tableWatch:
            if let table = fact.tableLabel {
                return "Keep an eye on \(table)."
            }
            return "Keep an eye on the floor."

        case .waitingArrivals:
            guard let count = fact.count else { return nil }
            return count == 1 ? "1 arrival is waiting." : "\(count) arrivals are waiting."

        case .noTableToday:
            guard let count = fact.count else { return nil }
            return count == 1 ? "1 table still needs to be picked." : "\(count) tables still need to be picked."

        case .newGuestCount:
            guard let count = fact.count else { return nil }
            return count == 1 ? "1 reservation looks like a first-time guest." : "\(count) reservations look like first-time guests."

        case .guestMemory:
            guard let name = displayName(fact.guestName) else { return nil }
            if let lastVisit = displayName(fact.timeLabel), !looksLikeClockTime(lastVisit) {
                return "\(firstName(from: name)) has been here before. Last visit \(lastVisit)."
            }
            return "\(firstName(from: name)) has been here before."

        case .allergy:
            return reservationLine(fact: fact, reason: "Allergy mentioned.")

        case .occasion:
            return reservationLine(fact: fact, reason: "Occasion note.")

        case .seatingPreference:
            guard let name = displayName(fact.guestName) else { return nil }
            return "\(firstName(from: name)) has a seating note. Open reservation to review."

        case .reminder:
            guard let count = fact.count else { return nil }
            return count == 1 ? "1 reminder has not gone out." : "\(count) reminders have not gone out."

        case .confirmation:
            guard let count = fact.count else { return nil }
            return count == 1 ? "1 reservation is not confirmed yet." : "\(count) reservations are not confirmed yet."

        case .deposit:
            return reservationLine(fact: fact, reason: "Deposit note.")

        case .preorder:
            return reservationLine(fact: fact, reason: "Preorder.")

        case .setup:
            return reservationLine(fact: fact, reason: "Setup note.")

        case .walkInCompleted:
            guard let count = fact.count else { return nil }
            return count == 1 ? "1 walk-in completed so far." : "\(count) walk-ins completed so far."

        case .completedRecap:
            guard let completed = fact.count else { return nil }
            if let walkIns = fact.secondaryCount, walkIns > 0 {
                return "\(completed) completed so far. \(walkIns) \(walkIns == 1 ? "was" : "were") walk-ins."
            }
            return "\(completed) completed so far."

        case .noShowFollowUp:
            guard let count = fact.count else { return nil }
            return count == 1 ? "1 no-show today." : "\(count) no-shows today."

        case .longStayRecap:
            guard let count = fact.count else { return nil }
            return count == 1 ? "1 table has been seated a while." : "\(count) tables have been seated a while."

        case .businessPeak:
            guard let time = fact.timeLabel else { return nil }
            return "\(time) has been the strongest booking hour."

        case .serviceCalm:
            return "Nothing urgent right now."
        }
    }

    private static func compactLine(
        facts: [BriefingFact],
        dateKey: String,
        serviceMode: ServiceMode,
        truthCounts: BriefingTruthCounts
    ) -> String {
        switch serviceMode {
        case .futurePlanning, .beforeService:
            guard truthCounts.activeReservations > 0 else { return "Nothing urgent right now." }
            let lead = weekdayName(for: dateKey)
            let countLine = "\(truthCounts.activeReservations) \(reservationWord(truthCounts.activeReservations)), \(truthCounts.expectedGuests) \(guestWord(truthCounts.expectedGuests))"
            if truthCounts.noTable > 0 {
                return "\(lead): \(countLine). \(truthCounts.noTable) still need tables."
            }
            if let mainWindow = facts.first(where: { $0.kind == .arrivalWindow })?.timeLabel {
                return "\(lead): \(countLine). Main push around \(mainWindow)."
            }
            return "\(lead): \(countLine)."

        case .duringService, .afterCloseNeedsCleanup:
            if truthCounts.activeReservations == 0 && truthCounts.seatedReservations == 0 {
                return "Service is quiet right now."
            }
            let parties = truthCounts.seatedReservations
            let base = parties > 0
                ? "Now: \(parties) \(partyWord(parties)) seated, \(truthCounts.expectedGuests) \(guestWord(truthCounts.expectedGuests))."
                : "Now: \(truthCounts.activeReservations) \(reservationWord(truthCounts.activeReservations)), \(truthCounts.expectedGuests) \(guestWord(truthCounts.expectedGuests))."
            if let occasion = facts.first(where: { $0.kind == .occasion }),
               let name = displayName(occasion.guestName) {
                return "\(base) \(firstName(from: name)) has an occasion note."
            }
            if let allergy = facts.first(where: { $0.kind == .allergy }),
               let name = displayName(allergy.guestName) {
                return "\(base) \(firstName(from: name)) has an allergy note."
            }
            return base

        case .afterCloseFinished, .pastRecap:
            if truthCounts.completedReservations > 0 {
                return "Service is wrapped."
            }
            return "Service is wrapped."
        }
    }

    private static func reservationLine(fact: BriefingFact, reason: String? = nil) -> String? {
        guard let name = displayName(fact.guestName) else { return nil }
        var prefix: String?
        if let time = fact.timeLabel {
            prefix = time
        }
        var guest = name
        if let party = fact.partySize, party > 0 {
            guest += ", \(party) \(party == 1 ? "guest" : "guests")"
        }
        let lead = [prefix, guest].compactMap { $0 }.joined(separator: " · ")
        guard let reason, !reason.isEmpty else {
            return "\(lead)."
        }
        let sentence = reason.hasSuffix(".") || reason.hasSuffix("!") || reason.hasSuffix("?")
            ? reason
            : "\(reason)."
        return "\(lead). \(sentence)"
    }

    private static func chip(for fact: BriefingFact, serviceMode: ServiceMode) -> String? {
        switch fact.kind {
        case .allergy:
            return "Allergy"
        case .occasion:
            return "Occasion"
        case .seatingPreference:
            return nil
        case .arrivalWindow:
            guard let time = fact.timeLabel else { return nil }
            return "Push \(time)"
        case .reminder:
            guard let count = fact.count, count > 0 else { return nil }
            return count == 1 ? "1 reminder" : "\(count) reminders"
        case .noTableToday:
            guard serviceMode == .duringService || serviceMode == .afterCloseNeedsCleanup else { return nil }
            guard let count = fact.count else { return nil }
            return "\(count) no table"
        case .newGuestCount:
            return nil
        case .seatedDuration:
            guard let table = fact.tableLabel, let minutes = fact.minutes else { return nil }
            return "\(table) \(durationText(minutes: minutes))"
        case .walkInCompleted:
            guard let count = fact.count else { return nil }
            return "\(count) walk-in"
        case .completedRecap:
            guard let count = fact.count else { return nil }
            return "\(count) completed"
        case .serviceCalm:
            return "Calm"
        default:
            return nil
        }
    }

    private static func compactChips(
        for facts: [BriefingFact],
        serviceMode: ServiceMode,
        truthCounts: BriefingTruthCounts
    ) -> [String] {
        var chips = facts.compactMap { chip(for: $0, serviceMode: serviceMode) }
        if (serviceMode == .afterCloseFinished || serviceMode == .pastRecap),
           truthCounts.completedReservations > 0 {
            chips.append("no active guests")
        }
        return Array(deduped(chips).prefix(3))
    }

    private static func deduped(_ values: [String]) -> [String] {
        values.reduce(into: [String]()) { result, value in
            if !result.contains(value) {
                result.append(value)
            }
        }
    }

    private static func sectionedFacts(
        _ facts: [BriefingFact],
        serviceMode: ServiceMode,
        truthCounts: BriefingTruthCounts
    ) -> [BriefingSection] {
        let specs = sectionSpecs(for: serviceMode)
        return specs.compactMap { spec in
            let sectionFacts = facts.filter { spec.kinds.contains($0.kind) }
            let lines = visibleLines(
                for: sectionFacts,
                sectionID: spec.id,
                serviceMode: serviceMode,
                truthCounts: truthCounts
            )
            guard !lines.isEmpty else { return nil }
            return BriefingSection(
                id: spec.id,
                title: spec.title,
                facts: sectionFacts,
                lines: lines
            )
        }
    }

    private static func sectionSpecs(for serviceMode: ServiceMode) -> [(id: String, title: String, kinds: Set<BriefingFactKind>)] {
        switch serviceMode {
        case .afterCloseFinished, .pastRecap:
            return [
                ("recap", "Recap", [.completedRecap, .walkInCompleted, .noShowFollowUp, .longStayRecap]),
                ("guests", "Guests", [.guestMemory, .allergy, .occasion, .seatingPreference]),
                ("brief", "Brief", [.businessPeak, .serviceCalm])
            ]
        case .duringService, .afterCloseNeedsCleanup:
            return [
                ("arrivals", "Arrivals", [.waitingArrivals, .noTableToday, .nextArrival, .timedArrival, .arrivalWindow]),
                ("seated", "Seated", [.seatedOverview, .seatedDuration, .tableWatch, .longStayRecap]),
                ("guests", "Guests", [.allergy, .occasion, .seatingPreference, .guestMemory]),
                ("followup", "Follow-up", [.reminder, .confirmation, .deposit, .preorder, .setup, .noShowFollowUp]),
                ("brief", "Brief", [.serviceCalm, .businessPeak])
            ]
        case .beforeService, .futurePlanning:
            return [
                ("arrivals", "Arrivals", [.nextArrival, .timedArrival, .arrivalWindow, .waitingArrivals, .noTableToday]),
                ("followup", "Follow-up", [.reminder, .confirmation, .deposit, .preorder, .setup, .noShowFollowUp]),
                ("guests", "Guests", [.allergy, .occasion, .seatingPreference, .guestMemory, .newGuestCount]),
                ("brief", "Brief", [.serviceCalm, .businessPeak])
            ]
        }
    }

    private static func visibleLines(
        for facts: [BriefingFact],
        sectionID: String,
        serviceMode: ServiceMode,
        truthCounts: BriefingTruthCounts
    ) -> [String] {
        var seen = Set<String>()
        let hasReturningGuestFact = facts.contains { $0.kind == .guestMemory }
        return facts.compactMap { fact in
            guard shouldShow(
                fact,
                sectionID: sectionID,
                serviceMode: serviceMode,
                truthCounts: truthCounts,
                hasReturningGuestFact: hasReturningGuestFact
            ) else {
                return nil
            }
            let line = lineForSectionFact(fact, sectionID: sectionID, serviceMode: serviceMode)
            guard let line, !line.isEmpty else { return nil }
            let key = line.lowercased()
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return line
        }
    }

    private static func shouldShow(
        _ fact: BriefingFact,
        sectionID: String,
        serviceMode: ServiceMode,
        truthCounts: BriefingTruthCounts,
        hasReturningGuestFact: Bool
    ) -> Bool {
        if fact.kind == .dayOverview {
            return false
        }
        if fact.kind == .noTableToday && (serviceMode == .beforeService || serviceMode == .futurePlanning) {
            return false
        }
        if fact.kind == .newGuestCount {
            guard sectionID == "guests",
                  let count = fact.count,
                  count > 0,
                  truthCounts.activeReservations > 1 else {
                return false
            }
            if hasReturningGuestFact && count >= truthCounts.activeReservations {
                return false
            }
        }
        if fact.kind == .seatingPreference && displayName(fact.guestName) == nil {
            return false
        }
        return true
    }

    private static func lineForSectionFact(
        _ fact: BriefingFact,
        sectionID: String,
        serviceMode: ServiceMode
    ) -> String? {
        if fact.kind == .nextArrival || fact.kind == .timedArrival {
            if (serviceMode == .futurePlanning || serviceMode == .beforeService),
               fact.tableLabel == nil,
               let base = reservationLine(fact: fact) {
                return String(base.dropLast()) + " No table picked."
            }
        }
        if fact.kind == .newGuestCount, let count = fact.count {
            return "\(count) look like first-time guests."
        }
        return line(for: fact)
    }

    private static func displayName(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstName(from name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    private static func looksLikeClockTime(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: #"^\d{1,2}:\d{2}(\s?[AP]M)?$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func weekdayName(for dateKey: String) -> String {
        guard let date = ReservationFormatters.reservationDateKey.date(from: dateKey) else {
            return "Service"
        }
        return date.formatted(.dateTime.weekday(.wide))
    }

    private static func reservationWord(_ count: Int) -> String {
        count == 1 ? "reservation" : "reservations"
    }

    private static func guestWord(_ count: Int) -> String {
        count == 1 ? "guest" : "guests"
    }

    private static func partyWord(_ count: Int) -> String {
        count == 1 ? "party" : "parties"
    }

    private static func durationText(minutes: Int) -> String {
        let safeMinutes = max(minutes, 1)
        if safeMinutes < 60 {
            return "\(safeMinutes)m"
        }
        let hours = safeMinutes / 60
        let remaining = safeMinutes % 60
        if remaining == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remaining)m"
    }
}
