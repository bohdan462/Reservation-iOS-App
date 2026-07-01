//
//  StaffBriefingTemplateWriter.swift
//  Tryzub Reservations
//
//  4F-1 — Deterministic full staff briefing. Always available fallback when the
//  local model is off, unavailable, times out, or is rejected by the validator.
//
//  Produces the same section shape the model is asked to produce so the UI is
//  identical regardless of source. Plain, useful, non-robotic staff language.
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
        let counts = packet.statusCounts
        let headline: String
        if counts.totalReservations == 0 {
            headline = "No reservations on the books yet for \(dayWord(packet)). Quiet start."
        } else {
            headline = "\(counts.totalReservations) \(reservationWord(counts.totalReservations)) booked · \(counts.expectedGuests) \(guestWord(counts.expectedGuests)) expected."
        }

        var sections: [StaffBriefingSection] = []

        // Overview
        var overview: [String] = []
        if counts.totalReservations > 0 {
            overview.append("Today is shaping up with \(counts.totalReservations) \(reservationWord(counts.totalReservations)) and about \(counts.expectedGuests) \(guestWord(counts.expectedGuests)).")
        }
        for line in packet.businessSummaryLines.prefix(2) { overview.append(line) }
        if let peak = fact(packet, .arrivalWindow), let time = peak.timeLabel {
            overview.append("Busiest window looks like \(time)\(peak.count.map { " with \($0) \(reservationWord($0))" } ?? "").")
        }
        sections.append(section("overview", "Today's shape", paragraphs: overview))

        // Attention
        var attention: [String] = []
        if counts.needsReviewCount > 0 {
            attention.append("\(counts.needsReviewCount) \(reservationWord(counts.needsReviewCount)) still need review.")
        }
        if let noTable = fact(packet, .noTableToday)?.count, noTable > 0 {
            attention.append("\(noTable) \(reservationWord(noTable)) without a table yet.")
        }
        if packet.communicationSummary.confirmationsMissingCount > 0 {
            attention.append("\(packet.communicationSummary.confirmationsMissingCount) awaiting confirmation.")
        }
        if packet.communicationSummary.remindersMissingCount > 0 {
            attention.append("\(packet.communicationSummary.remindersMissingCount) with no reminder sent.")
        }
        if let large = fact(packet, .setup)?.count, large > 0 {
            attention.append("\(large) large \(large == 1 ? "party" : "parties") needing setup.")
        }
        sections.append(section("attention", "Needs attention", bullets: attention))

        // Guests
        sections.append(section("guests", "Guests to know", bullets: guestBullets(packet)))

        // Floor / attachments
        var floor = attachmentBullets(packet)
        if let allergy = fact(packet, .allergy)?.count, allergy > 0 {
            floor.insert("\(allergy) \(allergy == 1 ? "guest has" : "guests have") an allergy or dietary note.", at: 0)
        }
        sections.append(section("floor", "Setup & attachments", bullets: floor))

        // Followup
        var followup: [String] = []
        if packet.communicationSummary.confirmationsMissingCount > 0 {
            followup.append("Confirm the \(packet.communicationSummary.confirmationsMissingCount) outstanding \(reservationWord(packet.communicationSummary.confirmationsMissingCount)).")
        }
        if counts.needsReviewCount > 0 {
            followup.append("Clear the review queue before doors open.")
        }
        sections.append(section("followup", "Before service", bullets: followup))

        return Content(
            headline: headline,
            sections: sections.filter { !$0.isEmpty || $0.id == "overview" },
            actionBullets: []
        )
    }

    // MARK: - Live service

    private static func buildLiveService(_ packet: StaffBriefingPacket) -> Content {
        let counts = packet.statusCounts
        let headline: String
        if counts.stillSeatedReservations > 0 {
            headline = "\(counts.stillSeatedReservations) \(tableWord(counts.stillSeatedReservations)) seated · \(counts.remainingArrivalsCount) still to arrive."
        } else if counts.remainingArrivalsCount > 0 {
            headline = "\(counts.remainingArrivalsCount) \(reservationWord(counts.remainingArrivalsCount)) still to arrive."
        } else {
            headline = "Floor is quiet right now."
        }

        var sections: [StaffBriefingSection] = []

        // Now
        var now: [String] = []
        if counts.stillSeatedReservations > 0 {
            now.append("\(counts.stillSeatedReservations) \(tableWord(counts.stillSeatedReservations)) currently seated (\(counts.currentlySeatedGuests) \(guestWord(counts.currentlySeatedGuests))).")
        }
        if let waiting = fact(packet, .waitingArrivals)?.count, waiting > 0 {
            now.append("\(waiting) \(arrivalWord(waiting)) waiting to be seated.")
        }
        if let next = fact(packet, .nextArrival) {
            now.append(nextArrivalLine(next))
        }
        sections.append(section("overview", "Right now", paragraphs: now))

        // Attention
        var attention: [String] = []
        if let longStay = fact(packet, .longStayRecap)?.count, longStay > 0 {
            attention.append("\(longStay) \(tableWord(longStay)) seated over 90 minutes.")
        }
        if let seatedDur = fact(packet, .seatedDuration), let name = seatedDur.guestName, let mins = seatedDur.minutes {
            attention.append("\(name) has been seated \(mins) min\(seatedDur.tableLabel.map { " at \($0)" } ?? "").")
        }
        if let noTable = fact(packet, .noTableToday)?.count, noTable > 0 {
            attention.append("\(noTable) \(reservationWord(noTable)) still need a table.")
        }
        if counts.needsReviewCount > 0 {
            attention.append("\(counts.needsReviewCount) unresolved review \(counts.needsReviewCount == 1 ? "item" : "items").")
        }
        sections.append(section("attention", "Needs attention", bullets: attention))

        // Guests
        sections.append(section("guests", "Guests to know", bullets: guestBullets(packet)))

        // Floor
        var floor: [String] = []
        if let noShow = fact(packet, .noShowFollowUp)?.count, noShow > 0 {
            floor.append("\(noShow) no-show\(noShow == 1 ? "" : "s") so far.")
        }
        if counts.cancelledCount > 0 {
            floor.append("\(counts.cancelledCount) cancelled today.")
        }
        floor.append(contentsOf: attachmentBullets(packet))
        sections.append(section("floor", "Floor & follow-up", bullets: floor))

        return Content(headline: headline, sections: sections.filter { !$0.isEmpty || $0.id == "overview" }, actionBullets: [])
    }

    // MARK: - Closing recap

    private static func buildClosingRecap(_ packet: StaffBriefingPacket) -> Content {
        let counts = packet.statusCounts
        let wrapped = counts.remainingArrivalsCount == 0 && counts.stillSeatedReservations == 0
        let headline = wrapped
            ? "Service wrapped · \(counts.completedCount) completed, \(counts.expectedGuests) \(guestWord(counts.expectedGuests)) served."
            : "Winding down · \(counts.stillSeatedReservations) still seated, \(counts.remainingArrivalsCount) not yet arrived."

        var sections: [StaffBriefingSection] = []

        // Overview
        var overview: [String] = []
        overview.append(wrapped
            ? "Today's service is complete."
            : "Service is not fully wrapped yet.")
        overview.append("\(counts.totalReservations) \(reservationWord(counts.totalReservations)) total · \(counts.completedCount) completed · \(counts.cancelledCount) cancelled · \(counts.noShowCount) no-show.")
        sections.append(section("overview", "Service recap", paragraphs: overview))

        // Attention / cleanup
        var attention: [String] = []
        if counts.stillSeatedReservations > 0 {
            attention.append("\(counts.stillSeatedReservations) \(tableWord(counts.stillSeatedReservations)) still marked seated — check cleanup.")
        }
        if counts.unresolvedCount > 0 {
            attention.append("\(counts.unresolvedCount) \(counts.unresolvedCount == 1 ? "item" : "items") still need a status update.")
        }
        sections.append(section("attention", "Cleanup", bullets: attention))

        // Followup
        var followup: [String] = []
        if counts.noShowCount > 0 {
            followup.append("Follow up on \(counts.noShowCount) no-show\(counts.noShowCount == 1 ? "" : "s").")
        }
        if let longStay = fact(packet, .longStayRecap)?.count, longStay > 0 {
            followup.append("\(longStay) long \(longStay == 1 ? "stay" : "stays") today — note for turn planning.")
        }
        sections.append(section("followup", "Follow-up", bullets: followup))

        // Tomorrow
        if let preview = packet.tomorrowPreview, preview.hasData {
            var tomorrow: [String] = []
            tomorrow.append("\(preview.reservationCount) \(reservationWord(preview.reservationCount)) · \(preview.expectedGuests) \(guestWord(preview.expectedGuests)) expected.")
            if preview.needsReviewCount > 0 { tomorrow.append("\(preview.needsReviewCount) to review.") }
            if preview.noTableCount > 0 { tomorrow.append("\(preview.noTableCount) without a table yet.") }
            if preview.largePartyCount > 0 { tomorrow.append("\(preview.largePartyCount) large \(preview.largePartyCount == 1 ? "party" : "parties").") }
            if preview.allergyCount > 0 { tomorrow.append("\(preview.allergyCount) allergy \(preview.allergyCount == 1 ? "note" : "notes").") }
            if preview.occasionCount > 0 { tomorrow.append("\(preview.occasionCount) \(preview.occasionCount == 1 ? "occasion" : "occasions").") }
            if preview.attachmentCount > 0 { tomorrow.append("\(preview.attachmentCount) with attachments to review.") }
            sections.append(section("tomorrow", "Tomorrow preview", bullets: tomorrow))
        } else {
            sections.append(section("tomorrow", "Tomorrow preview", paragraphs: ["Tomorrow's details are not available yet."]))
        }

        return Content(headline: headline, sections: sections.filter { !$0.isEmpty || $0.id == "overview" || $0.id == "tomorrow" }, actionBullets: [])
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

    private static func nextArrivalLine(_ fact: BriefingFact) -> String {
        var parts = "Next arrival"
        if let time = fact.timeLabel { parts += " at \(time)" }
        if let name = fact.guestName { parts += " · \(name)" }
        if let party = fact.partySize { parts += ", \(party) \(guestWord(party))" }
        if let table = fact.tableLabel { parts += " (\(table))" }
        return parts + "."
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

    private static func dayWord(_ packet: StaffBriefingPacket) -> String {
        packet.serviceStateLabel.lowercased().contains("future") ? "that day" : "today"
    }

    private static func reservationWord(_ n: Int) -> String { n == 1 ? "reservation" : "reservations" }
    private static func guestWord(_ n: Int) -> String { n == 1 ? "guest" : "guests" }
    private static func tableWord(_ n: Int) -> String { n == 1 ? "party" : "parties" }
    private static func arrivalWord(_ n: Int) -> String { n == 1 ? "arrival" : "arrivals" }
}
