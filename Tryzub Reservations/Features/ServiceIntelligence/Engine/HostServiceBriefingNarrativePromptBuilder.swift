//
//  HostServiceBriefingNarrativePromptBuilder.swift
//  Tryzub Reservations
//
//  Builds prompts for the 4E Service Intelligence narrative pass from
//  HostServiceBriefingPacket fact fields only.
//
//  STRICT CONSTRAINTS:
//  - Uses only packet.facts safe fields (kind, priority, guestName when
//    allowlisted, count, timeLabel, tableLabel, minutes, partySize).
//  - Never includes: packet.compactLine, packet.compactChips, section.lines,
//    raw notes, OCR/extractedText, email, phone, reservation IDs as narrative
//    targets, HostDecisionSnapshot, or HostLLMPacket.
//  - The model is only allowed to rewrite wording. It must not decide facts.
//

import Foundation

enum HostServiceBriefingNarrativePromptBuilder {

    // MARK: - Version

    /// Bump this whenever the prompt schema changes to invalidate cached output.
    static let promptVersion = "sbn-v1"

    // MARK: - Output format markers (must match parser in Writer)

    static let compactMarker   = "COMPACT:"
    static let sectionMarker   = "SECTION "
    static let sectionItemMark = "-"

    // MARK: - Build

    struct Input {
        let packet: HostServiceBriefingPacket
        /// Human-readable service date for context (e.g. "Wednesday"). Never used as a narrative fact.
        let serviceDateLabel: String?
    }

    static func build(_ input: Input) -> String {
        let packet = input.packet
        var lines: [String] = []

        // System instructions
        lines.append(systemInstructions)

        // Context block (safe metadata only, never personal or raw note data)
        lines.append("Service context:")
        lines.append("- Date: \(packet.dateKey)")
        if let label = input.serviceDateLabel, !label.isEmpty {
            lines.append("- Day: \(label)")
        }
        lines.append("- Service mode: \(packet.serviceMode.rawValue)")
        lines.append("- Active reservations: \(packet.truthCounts.activeReservations)")
        lines.append("- Expected guests: \(packet.truthCounts.expectedGuests)")
        lines.append("- Seated parties: \(packet.truthCounts.seatedReservations)")
        lines.append("- Waiting arrivals: \(packet.truthCounts.waitingArrivals)")
        lines.append("- No table yet: \(packet.truthCounts.noTable)")
        lines.append("- Completed: \(packet.truthCounts.completedReservations)")
        lines.append("- No-shows: \(packet.truthCounts.noShows)")
        if let newGuests = packet.truthCounts.newGuests {
            lines.append("- First-time guests: \(newGuests)")
        }

        // Allowlists — validator enforces these; model receives them as context
        if !packet.allowedGuestNames.isEmpty {
            lines.append("Allowed guest names (use only these): \(packet.allowedGuestNames.joined(separator: ", "))")
        }
        if !packet.allowedTableLabels.isEmpty {
            lines.append("Allowed table labels (use only these): \(packet.allowedTableLabels.joined(separator: ", "))")
        }

        // Approved facts (safe fields only — no raw notes, no email/phone, no IDs as narrative)
        let priorityFacts = packet.facts.filter { $0.kind != .serviceCalm }
        if priorityFacts.isEmpty {
            lines.append("Approved facts: none — service is quiet.")
        } else {
            lines.append("Approved facts:")
            for (i, fact) in priorityFacts.prefix(12).enumerated() {
                lines.append(factLine(index: i + 1, fact: fact, allowedNames: packet.allowedGuestNames, allowedTables: packet.allowedTableLabels))
            }
        }

        // Forbidden instructions
        lines.append(forbiddenInstructions)

        // Output instructions
        lines.append(outputInstructions(packet: packet))

        return lines.joined(separator: "\n")
    }

    // MARK: - Fact serialization (safe fields only)

    private static func factLine(
        index: Int,
        fact: BriefingFact,
        allowedNames: [String],
        allowedTables: [String]
    ) -> String {
        var parts: [String] = ["\(index). [\(fact.kind.rawValue)/priority:\(fact.priority)]"]

        // Guest name only if explicitly allowlisted
        if let name = fact.guestName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty,
           allowedNames.contains(name) {
            parts.append("guest:\(name)")
        }

        if let size = fact.partySize {
            parts.append("party:\(size)")
        }
        if let time = fact.timeLabel {
            parts.append("time:\(time)")
        }
        // Table only if allowlisted
        if let table = fact.tableLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !table.isEmpty,
           allowedTables.contains(table) {
            parts.append("table:\(table)")
        }
        if let count = fact.count {
            parts.append("count:\(count)")
        }
        if let secondary = fact.secondaryCount {
            parts.append("guestCount:\(secondary)")
        }
        if let minutes = fact.minutes {
            parts.append("minutes:\(minutes)")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Fixed instruction blocks

    private static let systemInstructions = """
    You are a restaurant host briefing assistant. \
    Rewrite the approved facts below into calm, direct staff language.
    Rules:
    - Use only the facts provided below. Do not invent guests, tables, times, counts, or events.
    - Write in a direct restaurant host voice (not hospitality marketing copy).
    - Do not address guests. Do not write "we are delighted" or "welcome".
    - Do not claim anything was completed, confirmed, sent, assigned, or resolved unless that is the explicit fact kind.
    - Do not mention AI, models, algorithms, prediction, backend, cache, API, or diagnostics.
    - Do not use uncertain language like "might", "possibly", "guaranteed", "definitely".
    - Do not use "staff needs review", "operational action required", "guest signal detected", or similar system labels.
    - Keep wording short. A busy host must read this in five seconds.
    - If service is quiet and there are no priority facts, write one calm sentence.
    """

    private static let forbiddenInstructions = """
    Forbidden in output:
    - Email addresses or phone numbers.
    - Reservation IDs or database identifiers.
    - Guest names not in the allowed list above.
    - Table labels not in the allowed list above.
    - Guest counts higher than the numbers in the context block.
    - Any claim an email or reminder was sent.
    - Words: AI, model, LLM, backend, cache, API, sync, packet, validation, algorithm.
    - Guest-facing phrases: "Dear guest", "we are excited", "we look forward".
    - Unsafe certainty: "guaranteed", "definitely will", "absolutely".
    """

    private static func outputInstructions(packet: HostServiceBriefingPacket) -> String {
        let sectionIDs = Set(packet.sections.map(\.id))
        var block = """
        Output format — use this exactly:
        COMPACT: <one or two short staff sentences for the top card>
        """
        // Only request section rewrites for sections that exist in the packet
        for sectionID in ["arrivals", "seated", "guests", "followup", "recap", "brief"] where sectionIDs.contains(sectionID) {
            block += "\nSECTION \(sectionID):\n- <line>\n- <line>"
        }
        block += "\n\nOutput only the formatted block above. Do not add any preamble, labels, or explanation."
        return block
    }

    // MARK: - Proof helper (for harness tests only)

    /// Returns true if the generated prompt contains none of the forbidden strings.
    /// Called from HostServiceBriefingPacketProofHarness to verify prompt construction.
    static func promptPassesSafetyCheck(prompt: String, packet: HostServiceBriefingPacket) -> Bool {
        let lower = prompt.lowercased()
        // Must not contain rendered template lines
        let renderedLines = ([packet.compactLine] + packet.compactChips + packet.sections.flatMap(\.lines))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for line in renderedLines {
            if lower.contains(line.lowercased()) { return false }
        }
        return true
    }

    static func promptExcludesRawContactData(prompt: String) -> Bool {
        let lower = prompt.lowercased()
        // Rough phone pattern check
        let phonePattern = try? NSRegularExpression(pattern: #"\b\d{7,}\b"#)
        if let match = phonePattern?.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           match.range.location != NSNotFound {
            return false
        }
        // Email pattern check
        let emailPattern = try? NSRegularExpression(pattern: #"[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}"#)
        if let match = emailPattern?.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           match.range.location != NSNotFound {
            return false
        }
        return true
    }
}
