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
        let sortedFacts = facts.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.id < $1.id
        }
        let compact = sortedFacts.first.flatMap(line(for:)) ?? "Nothing urgent right now."
        let chips = Array(sortedFacts.compactMap(chip(for:)).prefix(3))
        let sections = sectionedFacts(sortedFacts)
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
            return count == 1 ? "1 reservation is a new guest." : "\(count) reservations are new guests."

        case .guestMemory:
            return reservationLine(fact: fact, reason: "has been here before")

        case .allergy:
            return reservationLine(fact: fact, reason: "Allergy mentioned.")

        case .occasion:
            return reservationLine(fact: fact, reason: "Occasion note.")

        case .seatingPreference:
            return reservationLine(fact: fact, reason: "Seating preference.")

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

    private static func chip(for fact: BriefingFact) -> String? {
        switch fact.kind {
        case .allergy:
            return "Allergy"
        case .occasion:
            return "Occasion"
        case .seatingPreference:
            return "Seating"
        case .noTableToday:
            guard let count = fact.count else { return nil }
            return "\(count) no table"
        case .newGuestCount:
            guard let count = fact.count else { return nil }
            return "\(count) new"
        case .seatedDuration:
            guard let table = fact.tableLabel else { return nil }
            return table
        case .walkInCompleted:
            guard let count = fact.count else { return nil }
            return "\(count) walk-in"
        case .serviceCalm:
            return "Calm"
        default:
            return nil
        }
    }

    private static func sectionedFacts(_ facts: [BriefingFact]) -> [BriefingSection] {
        let specs: [(id: String, title: String, kinds: Set<BriefingFactKind>)] = [
            ("today", "Today", [.dayOverview, .serviceCalm, .newGuestCount, .businessPeak]),
            ("arrivals", "Arrivals", [.arrivalWindow, .nextArrival, .timedArrival, .waitingArrivals, .noTableToday]),
            ("seated", "Seated", [.seatedOverview, .seatedDuration, .tableWatch, .longStayRecap]),
            ("guests", "Guests", [.guestMemory, .allergy, .occasion, .seatingPreference]),
            ("followup", "Follow-up", [.reminder, .confirmation, .deposit, .preorder, .setup, .noShowFollowUp]),
            ("recap", "Recap", [.completedRecap, .walkInCompleted])
        ]
        return specs.compactMap { spec in
            let sectionFacts = facts.filter { spec.kinds.contains($0.kind) }
            let lines = sectionFacts.compactMap(line(for:))
            guard !lines.isEmpty else { return nil }
            return BriefingSection(
                id: spec.id,
                title: spec.title,
                facts: sectionFacts,
                lines: lines
            )
        }
    }

    private static func displayName(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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
