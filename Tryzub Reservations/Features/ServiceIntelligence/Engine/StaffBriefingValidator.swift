//
//  StaffBriefingValidator.swift
//  Tryzub Reservations
//
//  4F-1 — Parses and validates the full staff briefing model output against the
//  ground-truth StaffBriefingPacket. Packet facts are truth; model output is
//  accepted only when it cannot contradict them.
//
//  Partial repair is limited to whitespace/duplicate cleanup. Any count / name /
//  table mismatch triggers full template fallback (accepted = false).
//

import Foundation

// MARK: - Parser

enum StaffBriefingOutputParser {

    struct Parsed: Equatable {
        let headline: String
        let sections: [StaffBriefingSection]
        let actionBullets: [String]
    }

    private static let sectionTitles: [String: String] = [
        "overview": "Overview",
        "attention": "Needs attention",
        "guests": "Guests to know",
        "floor": "Floor",
        "followup": "Follow-up",
        "tomorrow": "Tomorrow"
    ]

    /// "followup" reads better as "Focus before service" when the briefing is
    /// preService; other modes and ids keep the default mapping.
    private static func sectionTitle(id: String, mode: StaffBriefingMode) -> String {
        if id == "followup", mode == .preService {
            return "Focus before service"
        }
        return sectionTitles[id] ?? id.capitalized
    }

    static func parse(_ raw: String, mode: StaffBriefingMode = .preService) -> Parsed? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var headline: String?
        var sectionOrder: [String] = []
        var paragraphsByID: [String: [String]] = [:]
        var bulletsByID: [String: [String]] = [:]
        var actions: [String] = []

        enum Cursor { case none, section(String), actions }
        var cursor: Cursor = .none

        func appendSection(_ id: String) {
            if !sectionOrder.contains(id) { sectionOrder.append(id) }
        }

        for rawLine in trimmed.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let upper = line.uppercased()

            if upper.hasPrefix("HEADLINE:") {
                headline = String(line.dropFirst("HEADLINE:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                cursor = .none
            } else if upper.hasPrefix("SECTION ") {
                let remainder = String(line.dropFirst("SECTION ".count))
                let idPart = remainder.components(separatedBy: ":").first?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() ?? ""
                guard !idPart.isEmpty else { continue }
                appendSection(idPart)
                cursor = .section(idPart)
                let afterColon = remainder.contains(":")
                    ? String(remainder[remainder.range(of: ":")!.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
                if !afterColon.isEmpty {
                    addContent(afterColon, to: idPart, paragraphs: &paragraphsByID, bullets: &bulletsByID)
                }
            } else if upper.hasPrefix("ACTIONS:") {
                cursor = .actions
                let rest = String(line.dropFirst("ACTIONS:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !rest.isEmpty { actions.append(cleanBullet(rest)) }
            } else {
                switch cursor {
                case .none:
                    break
                case .section(let id):
                    addContent(line, to: id, paragraphs: &paragraphsByID, bullets: &bulletsByID)
                case .actions:
                    actions.append(cleanBullet(line))
                }
            }
        }

        guard let head = headline, !head.isEmpty else { return nil }

        let sections: [StaffBriefingSection] = sectionOrder.map { id in
            StaffBriefingSection(
                id: id,
                title: sectionTitle(id: id, mode: mode),
                paragraphs: dedupe(paragraphsByID[id] ?? []),
                bullets: dedupe(bulletsByID[id] ?? [])
            )
        }.filter { !$0.isEmpty }

        return Parsed(headline: head, sections: sections, actionBullets: dedupe(actions))
    }

    private static func addContent(
        _ line: String,
        to id: String,
        paragraphs: inout [String: [String]],
        bullets: inout [String: [String]]
    ) {
        if line.hasPrefix("-") || line.hasPrefix("•") || line.hasPrefix("*") {
            bullets[id, default: []].append(cleanBullet(line))
        } else {
            paragraphs[id, default: []].append(line)
        }
    }

    private static func cleanBullet(_ line: String) -> String {
        var s = line
        for prefix in ["- ", "-", "• ", "•", "* ", "*"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
            break
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func dedupe(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in items {
            let clean = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            let key = clean.lowercased()
            if seen.insert(key).inserted { out.append(clean) }
        }
        return out
    }
}

// MARK: - Validation result

struct StaffBriefingValidationResult: Equatable {
    let accepted: Bool
    let sanitized: StaffBriefingOutputParser.Parsed?
    let rejectionReason: String?
    let debugDetail: String?
}

// MARK: - Validator

enum StaffBriefingValidator {

    static let maxWords = 1200

    private static let metaPhrases: [String] = [
        "ai ", "a.i.", "llm", "language model", "algorithm", "prediction",
        "machine learning", "neural", "backend", "cache", "api", "sync ",
        "packet", "validation", "prompt", "diagnostic", "database", "identifier",
        "staff needs review", "operational action required", "guest signal detected",
        "attention category", "metadata",
    ]

    private static let certaintyPhrases: [String] = [
        "guaranteed", "definitely will", "absolutely will", "will certainly",
        "100%", "without a doubt",
    ]

    private static let executionPhrases: [String] = [
        "i emailed", "i sent", "i called", "i confirmed", "i assigned", "i seated",
        "we emailed", "we sent", "we called", "we confirmed", "we assigned", "we seated",
        "has been sent", "have been sent", "were sent",
        "has been confirmed automatically", "was automatically", "has been handled",
    ]

    private static let guestFacingPhrases: [String] = [
        "dear guest", "dear customer", "we are excited to welcome", "we look forward",
        "thank you for choosing", "we hope to see you", "dear reservation",
    ]

    // MARK: - Validate

    static func validate(
        parsed: StaffBriefingOutputParser.Parsed,
        packet: StaffBriefingPacket
    ) -> StaffBriefingValidationResult {
        let fullText = plainText(parsed)
        let lower = fullText.lowercased()

        // 1. Non-empty + headline present
        guard !parsed.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return reject("missing_headline", "Headline is empty.")
        }
        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return reject("empty_output", "Output is empty.")
        }

        // 2. Word cap
        let words = StaffBriefingResult.wordCount(of: fullText)
        guard words <= maxWords else {
            return reject("too_long", "Output has \(words) words (max \(maxWords)).")
        }

        // 3. Meta / technical language
        for phrase in metaPhrases where lower.contains(phrase) {
            return reject("meta_language", "Contains meta phrase: \(phrase)")
        }
        // 4. Certainty language
        for phrase in certaintyPhrases where lower.contains(phrase) {
            return reject("certainty_language", "Contains certainty phrase: \(phrase)")
        }
        // 5. Execution / send claims
        for phrase in executionPhrases where lower.contains(phrase) {
            return reject("execution_claim", "Contains execution claim: \(phrase)")
        }
        // 6. Guest-facing tone
        for phrase in guestFacingPhrases where lower.contains(phrase) {
            return reject("guest_facing", "Contains guest-facing phrase: \(phrase)")
        }

        // 7. Contact data — hard safety: real PII must never appear in staff-facing UI.
        if containsPhonePattern(fullText) {
            return reject("contact_phone", "Contains a phone-like pattern.")
        }
        if containsEmailPattern(fullText) {
            return reject("contact_email", "Contains an email pattern.")
        }

        // 8–11 are quality/grounding checks (not safety checks).
        // During active prompt-tuning they are logged but NOT used as hard rejection gates,
        // so model output reaches the UI where it can be read and tuned.
        // Re-enable as hard gates once output quality is confirmed stable.
        #if DEBUG
        if let issue = guestNameCheck(text: fullText, allowedNames: packet.allowedGuestNames) {
            print("[STAFF_BRIEFING_VALIDATOR] soft_warn check=guest_name detail=\(issue)")
        }
        if let issue = tableCheck(text: fullText, allowedTables: packet.allowedTableLabels) {
            print("[STAFF_BRIEFING_VALIDATOR] soft_warn check=table_label detail=\(issue)")
        }
        if let issue = countGroundingCheck(text: fullText, packet: packet) {
            print("[STAFF_BRIEFING_VALIDATOR] soft_warn check=count_grounding detail=\(issue)")
        }
        if let issue = unsupportedStatusClaimCheck(text: lower, packet: packet) {
            print("[STAFF_BRIEFING_VALIDATOR] soft_warn check=status_claim detail=\(issue)")
        }
        let detail = "headline=\(parsed.headline.prefix(48)) sections=\(parsed.sections.map(\.id).joined(separator: ",")) words=\(words)"
        #else
        let detail: String? = nil
        #endif
        return StaffBriefingValidationResult(accepted: true, sanitized: parsed, rejectionReason: nil, debugDetail: detail)
    }

    // MARK: - Checks

    static func plainText(_ parsed: StaffBriefingOutputParser.Parsed) -> String {
        var parts: [String] = [parsed.headline]
        for section in parsed.sections {
            parts.append(contentsOf: section.paragraphs)
            parts.append(contentsOf: section.bullets)
        }
        parts.append(contentsOf: parsed.actionBullets)
        return parts.joined(separator: "\n")
    }

    // All lowercase. Any capitalized word whose lowercased form is in this set is NOT
    // treated as a possible guest name. The list is deliberately broad because the model
    // naturally starts sentences with articles, pronouns, and imperative verbs mid-text,
    // and we must not mistake those for hallucinated names.
    // Root cause of the first device false-positive: "The" in "…expected. The main thing…"
    // was at word index > 0, capitalized, and not in this set → rejected with unknown_guest_name.
    private static let commonOperationalWords: Set<String> = [
        // Weekdays and time references
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "today", "tonight", "tomorrow", "morning", "evening", "afternoon",
        "now", "soon", "next", "last", "first", "second", "before", "after",
        // Reservation and service nouns
        "arrivals", "arrival", "tables", "table", "seated", "seating",
        "party", "parties", "guest", "guests", "reservation", "reservations",
        "service", "floor", "review", "check", "open", "close", "cleanup",
        "nothing", "urgent", "quiet", "calm", "confirm", "confirmed", "confirmation",
        "reminder", "reminders", "allergy", "occasion", "setup", "deposit", "preorder",
        "no-show", "cancelled", "completed", "large", "attention", "follow-up",
        "overview", "headline", "section", "actions", "am", "pm",
        // Articles and determiners — most common false-positive source
        "the", "an", "this", "that", "these", "those",
        // Pronouns and existentials
        "it", "its", "they", "them", "their", "there", "here", "we", "our",
        // Derived contractions (apostrophe stripped by letter-filter: "here's"→"heres")
        "heres", "theres", "its",
        // Quantifiers
        "all", "both", "each", "some", "most", "more", "less", "fewer", "many", "no",
        // Common adverbs / connectors
        "also", "still", "already", "yet", "just", "only", "even", "never", "always",
        // Imperative verbs that start bullet-point sentences
        "pick", "send", "watch", "handle", "assign", "note", "cover", "wrap",
        "flag", "mark", "plan", "keep", "use", "get", "set", "call", "ask",
        "make", "move", "look", "push", "hold", "lead", "run", "add", "find",
        "focus", "remind", "alert",
        // Adjectives / nouns that commonly open sentences
        "main", "key", "total", "done", "ready", "pending", "missing", "running",
        "busy", "steady", "smooth", "clear", "safe", "good", "full", "short",
    ]

    private static func guestNameCheck(text: String, allowedNames: [String]) -> String? {
        guard !allowedNames.isEmpty else { return nil }
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet.letters.inverted) }
            .filter { $0.count >= 3 }   // raised from 2: 2-char words are never guest names
        let allowedFirst = Set(
            allowedNames.compactMap { $0.components(separatedBy: .whitespaces).first?.lowercased() }
        )
        for (index, word) in words.enumerated() {
            let lw = word.lowercased()
            guard !commonOperationalWords.contains(lw) else { continue }
            // Only flag when the word is mid-text (not the very first token of the full string).
            guard index > 0 else { continue }
            if word.first?.isUppercase == true, !allowedFirst.contains(lw) {
                let inFull = allowedNames.contains { $0.localizedCaseInsensitiveContains(word) }
                if !inFull {
                    return "Name '\(word)' not in allowed guest names."
                }
            }
        }
        return nil
    }

    private static func tableCheck(text: String, allowedTables: [String]) -> String? {
        guard !allowedTables.isEmpty else { return nil }
        let pattern = try? NSRegularExpression(pattern: #"\b([A-Z][0-9]{1,2})\b"#)
        let nsText = text as NSString
        guard let matches = pattern?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) else {
            return nil
        }
        for match in matches {
            let token = nsText.substring(with: match.range)
            let inAllowed = allowedTables.contains {
                $0.localizedCaseInsensitiveContains(token) || token.localizedCaseInsensitiveContains($0)
            }
            if !inAllowed {
                return "Table '\(token)' not in allowed table labels."
            }
        }
        return nil
    }

    private static func countGroundingCheck(text: String, packet: StaffBriefingPacket) -> String? {
        let sanitized = sanitizedForCountCheck(text)
        let pattern = try? NSRegularExpression(pattern: #"\b(\d+)\b"#)
        let nsText = sanitized as NSString
        guard let matches = pattern?.matches(in: sanitized, range: NSRange(location: 0, length: nsText.length)) else {
            return nil
        }
        let s = packet.statusCounts
        var maxAllowed = max(
            s.totalReservations, s.expectedGuests, s.activeCount,
            s.completedCount, s.noShowCount, s.cancelledCount, s.currentlySeatedGuests
        )
        if let preview = packet.tomorrowPreview {
            maxAllowed = max(maxAllowed, preview.reservationCount, preview.expectedGuests)
        }
        let ceiling = max(maxAllowed + 2, Int(Double(maxAllowed) * 1.5))
        for match in matches {
            let token = nsText.substring(with: match.range)
            if let n = Int(token), n > ceiling, n > 12 {
                return "Count \(n) exceeds packet maximum (\(maxAllowed))."
            }
        }
        return nil
    }

    /// Strips date (2026-07-01), clock-time (18:45, 6:45 PM), and numeric-range
    /// (30-60, 30–60) substrings before scanning for out-of-range counts, so
    /// service-time language never gets misread as an impossible reservation count.
    private static func sanitizedForCountCheck(_ text: String) -> String {
        var result = text
        result = replacingMatches(in: result, pattern: #"\b\d{4}-\d{2}-\d{2}\b"#)
        result = replacingMatches(in: result, pattern: #"\b\d{1,2}:\d{2}\s*(?:AM|PM|am|pm)?\b"#)
        result = replacingMatches(in: result, pattern: #"\b\d{1,4}[\u{2013}\-]\d{1,4}\b"#)
        return result
    }

    private static func replacingMatches(in text: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
    }

    private static func unsupportedStatusClaimCheck(text: String, packet: StaffBriefingPacket) -> String? {
        let s = packet.statusCounts
        if s.completedCount == 0, packet.truthCounts.walkInCompleted == 0,
           text.contains(" completed") {
            return "Claims completion when counts show none."
        }
        if s.noShowCount == 0, text.contains("no-show") || text.contains("no show") {
            return "Claims no-show when counts show none."
        }
        if s.seatedCount == 0, packet.mode != .closingRecap,
           text.contains(" seated") || text.contains("at the table") {
            return "Claims seated party when counts show none."
        }
        return nil
    }

    /// Matches real phone-number shapes only (3-3-4 NANP grouping, with or without a
    /// country code, or a bare 10-11 digit run). Deliberately does NOT match times
    /// (18:45, 03:52), ranges (30-60 minutes, 30–60 minutes), or dates (2026-07-01),
    /// because none of those form a 3-digit/3-digit/4-digit group. Uses literal
    /// space/dot/hyphen separators (not \s) so it can't accidentally bridge across
    /// newlines when multiple unrelated numbers appear in nearby sections.
    private static let phonePatterns: [String] = [
        #"(?:\+?\d{1,3}[ .\-]?)?\(?\d{3}\)?[ .\-]\d{3}[ .\-]\d{4}\b"#,
        #"\b\d{10,11}\b"#,
    ]

    private static func containsPhonePattern(_ text: String) -> Bool {
        let nsRange = NSRange(text.startIndex..., in: text)
        for pattern in phonePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            if regex.firstMatch(in: text, range: nsRange) != nil {
                return true
            }
        }
        return false
    }

    private static func containsEmailPattern(_ text: String) -> Bool {
        let pattern = try? NSRegularExpression(pattern: #"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}"#)
        return pattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func reject(_ reason: String, _ detail: String?) -> StaffBriefingValidationResult {
        #if DEBUG
        print("[STAFF_BRIEFING_TRACE] decision=validator_reject reason=\(reason) detail=\(detail ?? "none")")
        #endif
        return StaffBriefingValidationResult(accepted: false, sanitized: nil, rejectionReason: reason, debugDetail: detail)
    }
}
