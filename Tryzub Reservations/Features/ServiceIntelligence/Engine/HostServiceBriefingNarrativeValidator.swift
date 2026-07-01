//
//  HostServiceBriefingNarrativeValidator.swift
//  Tryzub Reservations
//
//  Validates local-model output against HostServiceBriefingPacket facts.
//  Packet facts are the ground truth. Model output is accepted only when
//  it cannot contradict what the packet says.
//
//  Validation never blocks the template fallback path.
//

import Foundation

// MARK: - Result

struct ServiceBriefingNarrativeValidationResult: Equatable {
    let accepted: Bool
    /// Sanitized compact line if repair was safe; nil when rejected outright.
    let sanitizedCompactLine: String?
    /// Section lines that passed individual checks; empty if section was rejected.
    let acceptedSectionLinesByID: [String: [String]]
    /// Machine-readable rejection reason for traces.
    let rejectionReason: String?
    /// Developer-only detail (never logged in Release builds).
    let debugDetail: String?

    static let accepted = ServiceBriefingNarrativeValidationResult(
        accepted: true,
        sanitizedCompactLine: nil,
        acceptedSectionLinesByID: [:],
        rejectionReason: nil,
        debugDetail: nil
    )
}

// MARK: - Parser

/// Parses the structured model output into compact line + section lines.
enum ServiceBriefingNarrativeOutputParser {

    struct Parsed: Equatable {
        let compactLine: String
        let sectionLinesByID: [String: [String]]
    }

    static func parse(_ raw: String) -> Parsed? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var compactLine: String?
        var sectionLinesByID: [String: [String]] = [:]
        var currentSectionID: String?
        var currentLines: [String] = []

        func flushSection() {
            if let id = currentSectionID, !currentLines.isEmpty {
                sectionLinesByID[id] = currentLines
            }
        }

        for rawLine in trimmed.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.uppercased().hasPrefix("COMPACT:") {
                let value = String(line.dropFirst("COMPACT:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { compactLine = value }
            } else if line.uppercased().hasPrefix("SECTION ") {
                flushSection()
                currentLines = []
                let idPart = String(line.dropFirst("SECTION ".count))
                    .replacingOccurrences(of: ":", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                currentSectionID = idPart.isEmpty ? nil : idPart
            } else if let _ = currentSectionID {
                let itemLine = line.hasPrefix("-")
                    ? String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                    : line
                if !itemLine.isEmpty {
                    currentLines.append(itemLine)
                }
            }
        }
        flushSection()

        guard let compact = compactLine, !compact.isEmpty else { return nil }
        return Parsed(compactLine: compact, sectionLinesByID: sectionLinesByID)
    }
}

// MARK: - Validator

enum HostServiceBriefingNarrativeValidator {

    // MARK: - Banned phrases (meta/technical/certainty)

    private static let metaPhrases: [String] = [
        "ai", "model", "llm", "algorithm", "prediction", "machine learning",
        "neural", "backend", "cache", "api", "sync", "packet", "validation",
        "debug", "diagnostic", "database", "identifier", "flag",
        "staff needs review", "operational action required",
        "guest signal detected", "attention category",
        "metadata", "candidate", "threshold",
    ]

    private static let certaintyPhrases: [String] = [
        "guaranteed", "definitely will", "absolutely will", "will certainly",
        "100%", "without a doubt",
    ]

    private static let executionPhrases: [String] = [
        "i emailed", "i sent", "i called", "i confirmed", "i assigned",
        "we emailed", "we sent", "we called", "we confirmed",
        "has been sent", "has been confirmed automatically",
        "was automatically", "has been handled",
    ]

    private static let guestFacingPhrases: [String] = [
        "dear guest", "we are excited to welcome", "we look forward",
        "thank you for choosing", "we hope to see you",
        "dear customer", "dear reservation",
    ]

    // MARK: - Primary validation

    /// Validates model output against the ground-truth packet.
    /// Returns accepted=true only when all checks pass.
    static func validate(
        parsed: ServiceBriefingNarrativeOutputParser.Parsed,
        packet: HostServiceBriefingPacket
    ) -> ServiceBriefingNarrativeValidationResult {
        let compact = parsed.compactLine
        let lower = compact.lowercased()

        // 1. Non-empty
        guard !compact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return reject("empty_compact", detail: "Compact line is empty.")
        }

        // 2. Maximum length
        guard compact.count <= 280 else {
            return reject("compact_too_long", detail: "Compact line exceeds 280 characters.")
        }

        // 3. Meta/technical language
        for phrase in metaPhrases where lower.contains(phrase) {
            return reject("meta_language", detail: "Compact contains meta phrase: \(phrase)")
        }

        // 4. Certainty language
        for phrase in certaintyPhrases where lower.contains(phrase) {
            return reject("certainty_language", detail: "Compact contains certainty phrase: \(phrase)")
        }

        // 5. Execution claims
        for phrase in executionPhrases where lower.contains(phrase) {
            return reject("execution_claim", detail: "Compact contains execution claim: \(phrase)")
        }

        // 6. Guest-facing phrases
        for phrase in guestFacingPhrases where lower.contains(phrase) {
            return reject("guest_facing", detail: "Compact contains guest-facing phrase: \(phrase)")
        }

        // 7. Contact data patterns
        if containsPhonePattern(compact) {
            return reject("contact_phone", detail: "Compact appears to contain a phone number.")
        }
        if containsEmailPattern(compact) {
            return reject("contact_email", detail: "Compact appears to contain an email address.")
        }

        // 8. Guest name grounding
        let nameCheck = guestNameCheck(text: compact, allowedNames: packet.allowedGuestNames)
        if let rejected = nameCheck {
            return reject("unknown_guest_name", detail: rejected)
        }

        // 9. Table label grounding
        let tableCheck = tableCheck(text: compact, allowedTables: packet.allowedTableLabels)
        if let rejected = tableCheck {
            return reject("unknown_table_label", detail: rejected)
        }

        // 10. Count grounding (only gross over-claims caught here)
        if let countIssue = countGroundingCheck(text: lower, counts: packet.truthCounts) {
            return reject("count_grounding", detail: countIssue)
        }

        // 11. Dangerous status claims not supported by packet facts
        if let statusIssue = unsupportedStatusClaimCheck(text: lower, packet: packet) {
            return reject("unsupported_status_claim", detail: statusIssue)
        }

        // Validate section lines with lighter rules (pass any that are clean)
        let acceptedSections = validatedSections(
            parsed.sectionLinesByID,
            allowedNames: packet.allowedGuestNames,
            allowedTables: packet.allowedTableLabels,
            counts: packet.truthCounts
        )

        #if DEBUG
        let detail = "compact=\(compact.prefix(60)) sections=\(acceptedSections.keys.joined(separator: ","))"
        #else
        let detail: String? = nil
        #endif

        return ServiceBriefingNarrativeValidationResult(
            accepted: true,
            sanitizedCompactLine: compact,
            acceptedSectionLinesByID: acceptedSections,
            rejectionReason: nil,
            debugDetail: detail
        )
    }

    // MARK: - Individual checks

    private static func guestNameCheck(text: String, allowedNames: [String]) -> String? {
        guard !allowedNames.isEmpty else { return nil }
        // Tokenize into word groups to avoid false positives on partial matches
        let words = text.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: CharacterSet.letters.inverted) }
            .filter { $0.count >= 2 }
        let allowedFirst = Set(
            allowedNames.compactMap { $0.components(separatedBy: .whitespaces).first?.lowercased() }
        )
        for word in words {
            let lw = word.lowercased()
            // Skip common operational words that look like proper names
            guard !commonOperationalWords.contains(lw) else { continue }
            // If it starts uppercase and is not in the allowed set, flag it
            if word.first?.isUppercase == true, !allowedFirst.contains(lw) {
                // Double-check full name match before rejecting
                let inFull = allowedNames.contains { $0.localizedCaseInsensitiveContains(word) }
                if !inFull {
                    return "Name '\(word)' not in allowed guest names."
                }
            }
        }
        return nil
    }

    private static let commonOperationalWords: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "today", "tonight", "morning", "evening", "afternoon",
        "now", "soon", "next", "last", "first", "second",
        "arrivals", "arrival", "tables", "table", "seated", "seating",
        "party", "parties", "guest", "guests", "reservation", "reservations",
        "service", "floor", "review", "check", "open", "close",
        "nothing", "urgent", "quiet", "calm",
        "walk", "walkable", "walkins",
    ]

    private static func tableCheck(text: String, allowedTables: [String]) -> String? {
        guard !allowedTables.isEmpty else { return nil }
        // Look for table-like tokens (e.g. A1, B2, Table 3, T4)
        let pattern = try? NSRegularExpression(pattern: #"\b([A-Z][0-9]{1,2}|[Tt]able\s+\w+)\b"#)
        let nsText = text as NSString
        guard let matches = pattern?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) else {
            return nil
        }
        for match in matches {
            let token = nsText.substring(with: match.range)
            let inAllowed = allowedTables.contains { $0.localizedCaseInsensitiveContains(token) || token.localizedCaseInsensitiveContains($0) }
            if !inAllowed {
                return "Table '\(token)' not in allowed table labels."
            }
        }
        return nil
    }

    private static func countGroundingCheck(text: String, counts: BriefingTruthCounts) -> String? {
        // Extract integers from the compact line and verify none grossly exceeds known truth
        let pattern = try? NSRegularExpression(pattern: #"\b(\d+)\b"#)
        let nsText = text as NSString
        guard let matches = pattern?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) else {
            return nil
        }
        let maxAllowed = max(
            counts.activeReservations,
            counts.expectedGuests,
            counts.completedReservations + counts.activeReservations,
            counts.noShows,
            counts.walkInCompleted
        )
        // Allow some tolerance for combined counts; flag anything 50% above maximum
        let ceiling = max(maxAllowed + 2, Int(Double(maxAllowed) * 1.5))
        for match in matches {
            let token = nsText.substring(with: match.range)
            if let n = Int(token), n > ceiling {
                return "Count \(n) exceeds packet maximum (\(maxAllowed))."
            }
        }
        return nil
    }

    private static func unsupportedStatusClaimCheck(text: String, packet: HostServiceBriefingPacket) -> String? {
        // If packet has zero completions, reject claims about "completed"
        if packet.truthCounts.completedReservations == 0,
           packet.truthCounts.walkInCompleted == 0,
           text.contains("completed") {
            return "Compact claims completion when packet shows none."
        }
        // If packet has zero no-shows, reject no-show claims
        if packet.truthCounts.noShows == 0, text.contains("no-show") || text.contains("no show") {
            return "Compact claims no-show when packet shows none."
        }
        // If packet has zero seated, reject seated claims
        if packet.truthCounts.seatedReservations == 0,
           text.contains("seated") || text.contains("at the table") {
            return "Compact claims seated party when packet shows none."
        }
        return nil
    }

    private static func containsPhonePattern(_ text: String) -> Bool {
        let pattern = try? NSRegularExpression(pattern: #"\b\d[\d\s\-\(\)]{6,}\d\b"#)
        return pattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func containsEmailPattern(_ text: String) -> Bool {
        let pattern = try? NSRegularExpression(pattern: #"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}"#)
        return pattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: - Section line validation (lighter rules)

    private static func validatedSections(
        _ sectionsByID: [String: [String]],
        allowedNames: [String],
        allowedTables: [String],
        counts: BriefingTruthCounts
    ) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for (id, lines) in sectionsByID {
            let clean = lines.filter { line in
                let lower = line.lowercased()
                // Reject lines with forbidden phrases
                let hasMeta = metaPhrases.contains { lower.contains($0) }
                let hasExec = executionPhrases.contains { lower.contains($0) }
                let hasGuest = guestFacingPhrases.contains { lower.contains($0) }
                let hasPhone = containsPhonePattern(line)
                let hasEmail = containsEmailPattern(line)
                return !hasMeta && !hasExec && !hasGuest && !hasPhone && !hasEmail
            }
            if !clean.isEmpty {
                result[id] = clean
            }
        }
        return result
    }

    // MARK: - Convenience

    private static func reject(_ reason: String, detail: String?) -> ServiceBriefingNarrativeValidationResult {
        #if DEBUG
        print("[SERVICE_BRIEFING_NARRATIVE_VALIDATOR_TRACE] reason=\(reason) detail=\(detail ?? "none")")
        #endif
        return ServiceBriefingNarrativeValidationResult(
            accepted: false,
            sanitizedCompactLine: nil,
            acceptedSectionLinesByID: [:],
            rejectionReason: reason,
            debugDetail: detail
        )
    }

    // MARK: - Public: containsLeaked (for harness)

    static func containsLeakedMetaLanguage(_ text: String) -> Bool {
        let lower = text.lowercased()
        return metaPhrases.contains { lower.contains($0) }
    }
}
