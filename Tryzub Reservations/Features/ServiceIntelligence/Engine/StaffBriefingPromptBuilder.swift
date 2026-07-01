//
//  StaffBriefingPromptBuilder.swift
//  Tryzub Reservations
//
//  4F-1 — Builds the full staff-briefing prompt from a StaffBriefingPacket.
//
//  STRICT CONSTRAINTS:
//  - Uses only safe packet fields: counts, allowlisted names/tables, fact kinds,
//    safe fact fields, normalized attachment tags, communication counts, and
//    tomorrow preview counts.
//  - Never includes raw notes, OCR text, emails, phones, backend JSON,
//    ReservationRecord, rendered template lines, compactLine, or HostLLMPacket.
//

import Foundation

enum StaffBriefingPromptBuilder {

    /// Bump when the prompt schema changes to invalidate cached output.
    static let promptVersion = "sb-full-v1"

    // NOTE: The system prompt actually sent to the runtime lives on
    // `HostLocalModelTaskProfile.staffBriefing` (HostLocalModelRuntime.swift) — the
    // runtime wraps that profile-level prompt around the user message built below.
    // This constant is kept in sync for reference/tests; update both together.
    static let systemPrompt = """
    You write an internal staff and management briefing for a restaurant team. \
    Use only the structured facts provided. Never address guests. Never invent \
    reservations, guests, tables, counts, attachments, reminders, confirmations, \
    cancellations, no-shows, allergies, birthdays, or regular status. Never claim \
    anything was sent, confirmed, seated, completed, assigned, or reviewed unless \
    the provided facts explicitly support it. Write like one manager briefing \
    another person: plain, warm, conversational sentences — not a report. Start \
    with a natural opener such as "Here's the picture before service," "Here's \
    what's happening right now," or "Here's the wrap-up." Use paragraphs first; \
    use bullets only for concrete action items. Do not mention data sources, \
    systems, packets, notes, or how this briefing was generated. No AI/meta \
    language. No marketing copy. If the day is quiet, keep it short. If it is \
    busy, expand naturally but stay focused.
    """

    static func build(_ packet: StaffBriefingPacket, serviceDateLabel: String?) -> String {
        var lines: [String] = []

        lines.append("BRIEFING MODE: \(packet.mode.rawValue)")
        lines.append("DATE: \(packet.dateKey)\(serviceDateLabel.map { " (\($0))" } ?? "")")
        lines.append("SERVICE STATE: \(packet.serviceStateLabel)")
        lines.append("")

        // Counts — explicit ground truth
        lines.append("COUNTS (ground truth — never change these numbers):")
        let t = packet.truthCounts
        lines.append("- Active reservations: \(t.activeReservations)")
        lines.append("- Expected guests: \(t.expectedGuests)")
        lines.append("- Seated: \(t.seatedReservations)")
        lines.append("- Waiting arrivals: \(t.waitingArrivals)")
        lines.append("- No table yet: \(t.noTable)")
        lines.append("- Completed: \(t.completedReservations)")
        lines.append("- No-shows: \(t.noShows)")
        lines.append("")

        // Status counts
        let s = packet.statusCounts
        lines.append("STATUS COUNTS (ground truth):")
        lines.append("- Total: \(s.totalReservations)")
        lines.append("- New: \(s.newCount)")
        lines.append("- Needs review: \(s.needsReviewCount)")
        lines.append("- Confirmed: \(s.confirmedCount)")
        lines.append("- Seated: \(s.seatedCount) (\(s.currentlySeatedGuests) guests)")
        lines.append("- Completed: \(s.completedCount)")
        lines.append("- Cancelled: \(s.cancelledCount)")
        lines.append("- No-show: \(s.noShowCount)")
        lines.append("- Remaining arrivals: \(s.remainingArrivalsCount)")
        lines.append("- Unresolved: \(s.unresolvedCount)")
        lines.append("")

        // Communication summary
        let c = packet.communicationSummary
        lines.append("COMMUNICATION SUMMARY (ground truth — do not claim delivery unless delivered):")
        lines.append("- Confirmations missing: \(c.confirmationsMissingCount)")
        if let recorded = c.confirmationsSentCount { lines.append("- Confirmations recorded/attempted: \(recorded)") }
        if c.confirmationDeliveredCount > 0 { lines.append("- Confirmation emails delivered: \(c.confirmationDeliveredCount)") }
        if c.confirmationPendingDeliveryCount > 0 { lines.append("- Confirmation emails waiting for delivery: \(c.confirmationPendingDeliveryCount)") }
        if c.confirmationFailedDeliveryCount > 0 { lines.append("- Confirmation emails failed: \(c.confirmationFailedDeliveryCount)") }
        if c.confirmationNeedsCorrectionCount > 0 { lines.append("- Confirmations needing email correction: \(c.confirmationNeedsCorrectionCount)") }
        lines.append("- Reminders missing: \(c.remindersMissingCount)")
        if let recorded = c.remindersSentCount { lines.append("- Reminders recorded/attempted: \(recorded)") }
        if c.reminderDeliveredCount > 0 { lines.append("- Reminders delivered: \(c.reminderDeliveredCount)") }
        if c.reminderPendingDeliveryCount > 0 { lines.append("- Reminders waiting for delivery: \(c.reminderPendingDeliveryCount)") }
        if c.reminderFailedDeliveryCount > 0 { lines.append("- Reminders failed; use manual follow-up: \(c.reminderFailedDeliveryCount)") }
        if c.reminderNeedsCorrectionCount > 0 { lines.append("- Reminders needing email correction: \(c.reminderNeedsCorrectionCount)") }
        if let auto = c.autoConfirmedCount { lines.append("- Auto-confirmed: \(auto)") }
        lines.append("")

        // Priority facts
        if packet.priorityFacts.isEmpty {
            lines.append("PRIORITY FACTS: none — service is quiet.")
        } else {
            lines.append("PRIORITY FACTS (safe — rewrite into prose, do not add facts):")
            for (i, fact) in packet.priorityFacts.enumerated() {
                lines.append(factLine(index: i + 1, fact: fact, packet: packet))
            }
        }
        lines.append("")

        // Attachment summaries
        if !packet.attachmentSummaries.isEmpty {
            lines.append("ATTACHMENT SUMMARIES (tags only — never invent contents):")
            for summary in packet.attachmentSummaries.prefix(20) {
                let who = summary.guestName ?? "reservation"
                let tags = summary.tags.map(\.rawValue).joined(separator: ", ")
                let review = summary.reviewNeeded ? " [review]" : ""
                lines.append("- \(who): \(tags)\(review)")
            }
            lines.append("")
        }

        // Business context
        if !packet.businessSummaryLines.isEmpty {
            lines.append("BUSINESS CONTEXT (safe summaries):")
            for line in packet.businessSummaryLines.prefix(5) {
                lines.append("- \(line)")
            }
            lines.append("")
        }

        // Tomorrow preview
        if packet.mode == .closingRecap, let preview = packet.tomorrowPreview, preview.hasData {
            lines.append("TOMORROW PREVIEW (ground truth):")
            lines.append("- Reservations: \(preview.reservationCount)")
            lines.append("- Expected guests: \(preview.expectedGuests)")
            lines.append("- Needs review: \(preview.needsReviewCount)")
            lines.append("- No table yet: \(preview.noTableCount)")
            lines.append("- Large parties: \(preview.largePartyCount)")
            lines.append("- Attachments to review: \(preview.attachmentCount)")
            lines.append("- Allergy notes: \(preview.allergyCount)")
            lines.append("- Occasions: \(preview.occasionCount)")
            lines.append("")
        }

        // Allowlists
        if !packet.allowedGuestNames.isEmpty {
            lines.append("ALLOWED GUEST NAMES (use only these; never other names): \(packet.allowedGuestNames.joined(separator: ", "))")
        }
        if !packet.allowedTableLabels.isEmpty {
            lines.append("ALLOWED TABLE LABELS (use only these): \(packet.allowedTableLabels.joined(separator: ", "))")
        }
        lines.append("")

        lines.append(styleBlock(for: packet))
        lines.append("")
        lines.append(forbiddenBlock)
        lines.append("")
        lines.append(outputFormat(for: packet))

        return lines.joined(separator: "\n")
    }

    // MARK: - Fact serialization (safe fields only)

    private static func factLine(index: Int, fact: BriefingFact, packet: StaffBriefingPacket) -> String {
        var parts: [String] = ["\(index). [\(fact.kind.rawValue)]"]
        if let name = fact.guestName, packet.allowedGuestNames.contains(name) {
            parts.append("guest:\(name)")
        }
        if let party = fact.partySize { parts.append("party:\(party)") }
        if let time = fact.timeLabel { parts.append("time:\(time)") }
        if let table = fact.tableLabel, packet.allowedTableLabels.contains(table) {
            parts.append("table:\(table)")
        }
        if let count = fact.count { parts.append("count:\(count)") }
        if let secondary = fact.secondaryCount { parts.append("guests:\(secondary)") }
        if let minutes = fact.minutes { parts.append("minutes:\(minutes)") }
        return parts.joined(separator: " ")
    }

    private static let forbiddenBlock = """
    FORBIDDEN IN OUTPUT:
    - Email addresses or phone numbers.
    - Reservation IDs or database identifiers.
    - Guest names not in the allowed list.
    - Table labels not in the allowed list.
    - Counts higher than the ground-truth numbers above.
    - Any claim that a message, reminder, or confirmation was sent.
    - Any claim a reservation was confirmed, seated, completed, or assigned unless a fact says so.
    - Words: AI, model, LLM, backend, cache, API, sync, packet, validation, algorithm, prompt.
    - Guest-facing phrases like "Dear guest", "we are excited", "we look forward".
    - Uncertain hype: "guaranteed", "definitely will", "absolutely".
    - Meta descriptions of how this briefing was written or where the data came from.
    """

    /// Mode-aware opener + conversational instructions. Kept separate from
    /// forbiddenBlock so the safety rules above stay unambiguous and unchanged.
    private static func styleBlock(for packet: StaffBriefingPacket) -> String {
        let opener: String
        switch packet.mode {
        case .preService:  opener = "\"Here's the picture before service.\""
        case .liveService: opener = "\"Here's what's happening right now.\""
        case .closingRecap: opener = "\"Here's the wrap-up.\""
        }
        return """
        STYLE:
        Write like one manager briefing another person — plain, conversational sentences, not a report or a status dump.
        Open with a natural line like \(opener)
        Use paragraphs first. Use bullets only for concrete things staff should check or do.
        Do not restate the same count twice. Do not mention data sources, systems, or how this briefing was generated.
        """
    }

    private static func outputFormat(for packet: StaffBriefingPacket) -> String {
        var block = """
        OUTPUT FORMAT — use these labels exactly, one per line where shown (write natural sentences inside each):
        HEADLINE: <one short, natural line>
        SECTION overview: <1-2 conversational sentences, opening the way STYLE describes>
        SECTION attention: <bullet lines starting with "- ", only for things needing attention>
        SECTION guests: <bullets or a short sentence, only if there are guests worth flagging>
        SECTION floor: <bullets or a short sentence, only if there is something to report>
        SECTION followup: <bullets, only for concrete actions>
        """
        if packet.mode == .closingRecap, packet.tomorrowPreview?.hasData == true {
            block += "\nSECTION tomorrow: <bullets covering tomorrow's counts>"
        }
        block += """

        ACTIONS: (optional, max 5 advisory bullets starting with "- ")

        Length: quiet day under 400 words; normal day 400-700 words; busy day up to 900 words; never exceed 1200 words.
        Output only the formatted block. No preamble or explanation.
        """
        return block
    }
}
