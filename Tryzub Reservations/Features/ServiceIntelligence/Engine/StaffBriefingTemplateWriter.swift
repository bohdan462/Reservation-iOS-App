//
//  StaffBriefingTemplateWriter.swift
//  Tryzub Reservations
//
//  4F-1 — Deterministic full staff briefing. Always available fallback when the
//  local model is off, unavailable, times out, or is rejected by the validator.
//
//  Produces the same section shape the model is asked to produce so the UI is
//  identical regardless of source.
//
//  STYLE (4F-2 polish): reads like one manager briefing another person — a
//  natural opener, one flowing overview paragraph (no repeated counts), and
//  bullets only for concrete things staff should check or do. Deliberately does
//  not pass through raw business-insight lines (they can reference a different
//  weekday/window than the selected service date); arrival timing comes only
//  from packet facts computed for the selected date.
//

import Foundation

enum StaffBriefingTemplateWriter {

    /// Rendered content (source-neutral). The writer wraps this into a StaffBriefingResult.
    struct Content: Equatable {
        let headline: String
        let sections: [StaffBriefingSection]
        let actionBullets: [String]
    }

    static func build(_ packet: StaffBriefingPacket) -> Content {
        switch packet.mode {
        case .preService:  return buildPreService(packet)
        case .liveService: return buildLiveService(packet)
        case .closingRecap: return buildClosingRecap(packet)
        }
    }

    // MARK: - Pre-service

    private static func buildPreService(_ packet: StaffBriefingPacket) -> Content {
        let headline = "Here's the picture before service."

        var sections: [StaffBriefingSection] = []
        sections.append(section("overview", "Overview", paragraphs: [preServiceOverview(packet)]))

        let guestLines = guestBullets(packet)
        if !guestLines.isEmpty {
            sections.append(section("guests", "Guests to know", bullets: guestLines))
        }

        var floor = attachmentBullets(packet)
        if let allergy = fact(packet, .allergy)?.count, allergy > 0 {
            floor.insert("\(allergy) \(allergy == 1 ? "guest has" : "guests have") an allergy or dietary note — confirm with the kitchen.", at: 0)
        }
        if !floor.isEmpty {
            sections.append(section("floor", "Floor", bullets: floor))
        }

        let actions = preServiceActions(packet)
        if !actions.isEmpty {
            sections.append(section("followup", "Focus before service", bullets: actions))
        }

        return Content(headline: headline, sections: sections.filter { !$0.isEmpty }, actionBullets: [])
    }

    private static func preServiceOverview(_ packet: StaffBriefingPacket) -> String {
        let counts = packet.statusCounts
        guard counts.totalReservations > 0 else {
            return "Nothing is booked yet — a quiet start."
        }

        var text = "You have \(counts.totalReservations) \(reservationWord(counts.totalReservations)) and about \(counts.expectedGuests) \(guestWord(counts.expectedGuests)) expected."

        if let noTable = fact(packet, .noTableToday)?.count, noTable > 0 {
            let subject = noTable == counts.totalReservations ? "all of them" : "\(noTable) \(reservationWord(noTable))"
            text += " The main thing to handle before service is table assignment: \(subject) still \(noTable == 1 ? "needs" : "need") a table."
        } else if counts.needsReviewCount > 0 {
            text += " \(counts.needsReviewCount) still \(counts.needsReviewCount == 1 ? "needs" : "need") review before doors open."
        }

        let missingReminders = packet.communicationSummary.remindersMissingCount
        if missingReminders > 0 {
            text += " There \(missingReminders == 1 ? "is" : "are") also \(missingReminders) \(missingReminders == 1 ? "reminder" : "reminders") that \(missingReminders == 1 ? "hasn't" : "haven't") gone out."
        }

        return text
    }

    private static func preServiceActions(_ packet: StaffBriefingPacket) -> [String] {
        let counts = packet.statusCounts
        var actions: [String] = []

        if let noTable = fact(packet, .noTableToday)?.count, noTable > 0 {
            actions.append(noTable == 1
                ? "Pick a table for the remaining reservation."
                : "Pick tables for the \(noTable) reservations still without one.")
        }
        if packet.communicationSummary.remindersMissingCount > 0 {
            actions.append("Send the missing reminders.")
        }
        if packet.communicationSummary.confirmationsMissingCount > 0 {
            actions.append("Confirm the \(packet.communicationSummary.confirmationsMissingCount) outstanding \(reservationWord(packet.communicationSummary.confirmationsMissingCount)).")
        }
        if let first = fact(packet, .arrivalWindow) ?? fact(packet, .nextArrival) ?? fact(packet, .timedArrival),
           let time = first.timeLabel {
            actions.append("Watch the first arrival around \(time).")
        }
        if counts.needsReviewCount > 0, fact(packet, .noTableToday) == nil {
            actions.append("Clear the review queue before doors open.")
        }

        return actions
    }

    // MARK: - Live service

    private static func buildLiveService(_ packet: StaffBriefingPacket) -> Content {
        let headline = "Here's what's happening right now."

        var sections: [StaffBriefingSection] = []
        sections.append(section("overview", "Overview", paragraphs: [liveServiceOverview(packet)]))

        let attention = liveServiceAttention(packet)
        if !attention.isEmpty {
            sections.append(section("attention", "Needs attention", bullets: attention))
        }

        let guestLines = guestBullets(packet)
        if !guestLines.isEmpty {
            sections.append(section("guests", "Guests to know", bullets: guestLines))
        }

        var floor: [String] = []
        if let noShow = fact(packet, .noShowFollowUp)?.count, noShow > 0 {
            floor.append("\(noShow) no-show\(noShow == 1 ? "" : "s") so far.")
        }
        if packet.statusCounts.cancelledCount > 0 {
            floor.append("\(packet.statusCounts.cancelledCount) cancelled so far.")
        }
        floor.append(contentsOf: attachmentBullets(packet))
        if !floor.isEmpty {
            sections.append(section("floor", "Floor & follow-up", bullets: floor))
        }

        return Content(headline: headline, sections: sections.filter { !$0.isEmpty }, actionBullets: [])
    }

    private static func liveServiceOverview(_ packet: StaffBriefingPacket) -> String {
        let counts = packet.statusCounts
        guard counts.stillSeatedReservations > 0 || counts.remainingArrivalsCount > 0 else {
            return "The floor is quiet right now."
        }

        var clauses: [String] = []
        if counts.stillSeatedReservations > 0 {
            clauses.append("\(counts.currentlySeatedGuests) \(guestWord(counts.currentlySeatedGuests)) seated across \(counts.stillSeatedReservations) \(tableWord(counts.stillSeatedReservations)) right now")
        }
        if counts.remainingArrivalsCount > 0 {
            clauses.append("\(counts.remainingArrivalsCount) more \(reservationWord(counts.remainingArrivalsCount)) still due")
        }

        var text = clauses.joined(separator: ", and ")
        text = text.prefix(1).uppercased() + text.dropFirst()

        if let next = fact(packet, .nextArrival), let time = next.timeLabel {
            text += ". Next arrival is around \(time)"
            if let name = next.guestName { text += " for \(name)" }
        }

        return text + "."
    }

    private static func liveServiceAttention(_ packet: StaffBriefingPacket) -> [String] {
        let counts = packet.statusCounts
        var attention: [String] = []

        if let longStay = fact(packet, .longStayRecap)?.count, longStay > 0 {
            attention.append("\(longStay) \(tableWord(longStay)) seated over 90 minutes.")
        }
        if let seatedDur = fact(packet, .seatedDuration), let name = seatedDur.guestName, let mins = seatedDur.minutes {
            attention.append("\(name) has been seated \(mins) min\(seatedDur.tableLabel.map { " at \($0)" } ?? "").")
        }
        if let waiting = fact(packet, .waitingArrivals)?.count, waiting > 0 {
            attention.append("\(waiting) \(arrivalWord(waiting)) waiting to be seated.")
        }
        if let noTable = fact(packet, .noTableToday)?.count, noTable > 0 {
            attention.append("\(noTable) \(reservationWord(noTable)) still need a table.")
        }
        if counts.needsReviewCount > 0 {
            attention.append("\(counts.needsReviewCount) unresolved review \(counts.needsReviewCount == 1 ? "item" : "items").")
        }

        return attention
    }

    // MARK: - Closing recap

    private static func buildClosingRecap(_ packet: StaffBriefingPacket) -> Content {
        let counts = packet.statusCounts
        let wrapped = counts.remainingArrivalsCount == 0 && counts.stillSeatedReservations == 0
        let headline = "Here's the wrap-up."

        var sections: [StaffBriefingSection] = []
        sections.append(section("overview", "Overview", paragraphs: [closingRecapOverview(packet, wrapped: wrapped)]))

        var attention: [String] = []
        if counts.stillSeatedReservations > 0 {
            attention.append("\(counts.stillSeatedReservations) \(tableWord(counts.stillSeatedReservations)) still marked seated — check cleanup.")
        }
        if counts.unresolvedCount > 0 {
            attention.append("\(counts.unresolvedCount) \(counts.unresolvedCount == 1 ? "item" : "items") still need a status update.")
        }
        if !attention.isEmpty {
            sections.append(section("attention", "Cleanup", bullets: attention))
        }

        var followup: [String] = []
        if counts.noShowCount > 0 {
            followup.append("Follow up on \(counts.noShowCount) no-show\(counts.noShowCount == 1 ? "" : "s").")
        }
        if let longStay = fact(packet, .longStayRecap)?.count, longStay > 0 {
            followup.append("\(longStay) long \(longStay == 1 ? "stay" : "stays") — worth noting for turn planning.")
        }
        if !followup.isEmpty {
            sections.append(section("followup", "Follow-up", bullets: followup))
        }

        if let preview = packet.tomorrowPreview, preview.hasData {
            sections.append(section("tomorrow", "Tomorrow", bullets: tomorrowBullets(preview)))
        } else {
            sections.append(section("tomorrow", "Tomorrow", paragraphs: ["Tomorrow's details aren't available yet."]))
        }

        return Content(headline: headline, sections: sections.filter { !$0.isEmpty }, actionBullets: [])
    }

    private static func closingRecapOverview(_ packet: StaffBriefingPacket, wrapped: Bool) -> String {
        let counts = packet.statusCounts
        var text = wrapped
            ? "Service is wrapped: \(counts.completedCount) \(counts.completedCount == 1 ? "table" : "tables") completed and about \(counts.expectedGuests) \(guestWord(counts.expectedGuests)) served."
            : "Service isn't fully wrapped yet — \(counts.stillSeatedReservations) still seated and \(counts.remainingArrivalsCount) not yet arrived."

        var extras: [String] = []
        if counts.cancelledCount > 0 {
            extras.append("\(counts.cancelledCount) cancelled")
        }
        if counts.noShowCount > 0 {
            extras.append("\(counts.noShowCount) no-show\(counts.noShowCount == 1 ? "" : "s")")
        }
        if !extras.isEmpty {
            let verb = (extras.count == 1 && (counts.cancelledCount + counts.noShowCount) == 1) ? "was" : "were"
            text += " There \(verb) also \(extras.joined(separator: " and "))."
        }

        return text
    }

    private static func tomorrowBullets(_ preview: StaffBriefingTomorrowPreview) -> [String] {
        var bullets: [String] = [
            "\(preview.reservationCount) \(preview.reservationCount == 1 ? "reservation" : "reservations") · \(preview.expectedGuests) \(preview.expectedGuests == 1 ? "guest" : "guests") expected."
        ]
        if preview.needsReviewCount > 0 { bullets.append("\(preview.needsReviewCount) to review.") }
        if preview.noTableCount > 0 { bullets.append("\(preview.noTableCount) without a table yet.") }
        if preview.largePartyCount > 0 { bullets.append("\(preview.largePartyCount) large \(preview.largePartyCount == 1 ? "party" : "parties").") }
        if preview.allergyCount > 0 { bullets.append("\(preview.allergyCount) allergy \(preview.allergyCount == 1 ? "note" : "notes").") }
        if preview.occasionCount > 0 { bullets.append("\(preview.occasionCount) \(preview.occasionCount == 1 ? "occasion" : "occasions").") }
        if preview.attachmentCount > 0 { bullets.append("\(preview.attachmentCount) with attachments to review.") }
        return bullets
    }

    // MARK: - Shared fact rendering

    private static func guestBullets(_ packet: StaffBriefingPacket) -> [String] {
        let allowed = Set(packet.allowedGuestNames)
        var bullets: [String] = []
        for fact in packet.priorityFacts {
            guard bullets.count < 6 else { break }
            switch fact.kind {
            case .allergy:
                if let name = safeName(fact, allowed) {
                    bullets.append("\(name): allergy / dietary note — confirm with kitchen.")
                }
            case .occasion:
                if let name = safeName(fact, allowed) {
                    bullets.append("\(name): occasion note.")
                }
            case .guestMemory:
                if let name = safeName(fact, allowed) {
                    bullets.append("\(name): returning guest.")
                }
            case .seatingPreference:
                if let name = safeName(fact, allowed) {
                    bullets.append("\(name): seating preference noted.")
                }
            default:
                break
            }
        }
        return bullets
    }

    private static func attachmentBullets(_ packet: StaffBriefingPacket) -> [String] {
        packet.attachmentSummaries.prefix(6).map { summary in
            let who = summary.guestName ?? "A reservation"
            let tagText = summary.tags.map(tagLabel).joined(separator: ", ")
            return "\(who): \(tagText.isEmpty ? "attachment to review" : tagText)."
        }
    }

    // MARK: - Helpers

    private static func fact(_ packet: StaffBriefingPacket, _ kind: BriefingFactKind) -> BriefingFact? {
        packet.priorityFacts.first { $0.kind == kind }
    }

    private static func safeName(_ fact: BriefingFact, _ allowed: Set<String>) -> String? {
        guard let name = fact.guestName, allowed.contains(name) else { return nil }
        return name
    }

    private static func section(
        _ id: String,
        _ title: String,
        paragraphs: [String] = [],
        bullets: [String] = []
    ) -> StaffBriefingSection {
        StaffBriefingSection(
            id: id,
            title: title,
            paragraphs: paragraphs.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
            bullets: bullets.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        )
    }

    private static func tagLabel(_ tag: StaffBriefingAttachmentTag) -> String {
        switch tag {
        case .setup: return "setup"
        case .deposit: return "deposit"
        case .preorder: return "preorder"
        case .cake: return "cake"
        case .decor: return "decor"
        case .menu: return "menu"
        case .banquet: return "banquet"
        case .event: return "event"
        case .photoReference: return "photo reference"
        case .other: return "attachment"
        }
    }

    private static func reservationWord(_ n: Int) -> String { n == 1 ? "reservation" : "reservations" }
    private static func guestWord(_ n: Int) -> String { n == 1 ? "guest" : "guests" }
    private static func tableWord(_ n: Int) -> String { n == 1 ? "party" : "parties" }
    private static func arrivalWord(_ n: Int) -> String { n == 1 ? "arrival" : "arrivals" }
}
