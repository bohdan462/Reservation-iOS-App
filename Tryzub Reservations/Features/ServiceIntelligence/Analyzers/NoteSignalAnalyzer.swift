//
//  NoteSignalAnalyzer.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 6 (Note intelligence).
//
//  PURE + DETERMINISTIC. No model, no I/O.
//
//  Scans a single reservation's note text (guest note + staff note) and converts
//  what it finds into typed ReservationSignals with honest confidence and wording.
//
//  Rules:
//  * A vague note produces `.depositMentioned`, never `.depositVerified`.
//  * Allergy/dietary findings always have `requiresReview = true`.
//  * Signals never claim more than the text literally shows.
//  * "reviewNote" evidence is the first matching snippet (≤ 60 chars) — never raw PII.
//  * If nothing is found, returns an empty array: silence is the correct output.
//
//  Emits [SERVICE_NOTE_ANALYZER_TRACE] on every analysis run.
//

import Foundation

enum NoteSignalAnalyzer {

    struct Input {
        let reservationID: String
        let guestNote: String?
        let staffNote: String?
    }

    static func analyze(_ input: Input) -> [ReservationSignal] {
        let allSources: [(String, SignalSource)] = [
            (input.guestNote ?? "", .guestNote),
            (input.staffNote ?? "", .staffNote)
        ]
        .filter { !$0.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !allSources.isEmpty else {
            NoteSignalTrace.analyzed(
                reservationID: input.reservationID,
                signals: 0,
                fallback: false
            )
            return []
        }

        var signals: [ReservationSignal] = []
        var usedTypes = Set<ReservationSignalType>()

        for (text, source) in allSources {
            let normalized = text.lowercased()

            // Deposit / payment
            if !usedTypes.contains(.depositMentioned),
               let evidence = firstMatch(in: normalized, keywords: depositKeywords) {
                signals.append(ReservationSignal(
                    id: "\(input.reservationID)-deposit",
                    reservationID: input.reservationID,
                    type: .depositMentioned,
                    title: "Deposit mentioned",
                    staffText: "Manager should verify deposit note.",
                    evidence: trimEvidence(evidence, from: text),
                    confidence: .medium,
                    source: source,
                    requiresReview: true,
                    priority: .high
                ))
                usedTypes.insert(.depositMentioned)
            }

            // Preorder
            if !usedTypes.contains(.preorderMentioned),
               let evidence = firstMatch(in: normalized, keywords: preorderKeywords) {
                signals.append(ReservationSignal(
                    id: "\(input.reservationID)-preorder",
                    reservationID: input.reservationID,
                    type: .preorderMentioned,
                    title: "Preorder mentioned",
                    staffText: "Kitchen should review preorder note.",
                    evidence: trimEvidence(evidence, from: text),
                    confidence: .medium,
                    source: source,
                    requiresReview: true,
                    priority: .high
                ))
                usedTypes.insert(.preorderMentioned)
            }

            // Banquet
            if !usedTypes.contains(.banquetMentioned),
               let evidence = firstMatch(in: normalized, keywords: banquetKeywords) {
                signals.append(ReservationSignal(
                    id: "\(input.reservationID)-banquet",
                    reservationID: input.reservationID,
                    type: .banquetMentioned,
                    title: "Banquet note",
                    staffText: "Kitchen should review group details.",
                    evidence: trimEvidence(evidence, from: text),
                    confidence: .medium,
                    source: source,
                    requiresReview: true,
                    priority: .high
                ))
                usedTypes.insert(.banquetMentioned)
            }

            // Allergy / dietary
            if !usedTypes.contains(.allergyOrDietary),
               let evidence = firstMatch(in: normalized, keywords: dietaryKeywords) {
                signals.append(ReservationSignal(
                    id: "\(input.reservationID)-dietary",
                    reservationID: input.reservationID,
                    type: .allergyOrDietary,
                    title: "Dietary or allergy note",
                    staffText: "Check guest notes before seating.",
                    evidence: trimEvidence(evidence, from: text),
                    confidence: .medium,
                    source: source,
                    requiresReview: true,
                    priority: .critical
                ))
                usedTypes.insert(.allergyOrDietary)
            }

            // Accessibility
            if !usedTypes.contains(.accessibility),
               let evidence = firstMatch(in: normalized, keywords: accessibilityKeywords) {
                signals.append(ReservationSignal(
                    id: "\(input.reservationID)-access",
                    reservationID: input.reservationID,
                    type: .accessibility,
                    title: "Accessibility note",
                    staffText: "Check setup before seating.",
                    evidence: trimEvidence(evidence, from: text),
                    confidence: .medium,
                    source: source,
                    requiresReview: true,
                    priority: .high
                ))
                usedTypes.insert(.accessibility)
            }

            // Occasion
            if !usedTypes.contains(.occasion),
               let evidence = firstMatch(in: normalized, keywords: occasionKeywords) {
                signals.append(ReservationSignal(
                    id: "\(input.reservationID)-occasion",
                    reservationID: input.reservationID,
                    type: .occasion,
                    title: "Occasion note",
                    staffText: "Mention the occasion before seating.",
                    evidence: trimEvidence(evidence, from: text),
                    confidence: .medium,
                    source: source,
                    requiresReview: false,
                    priority: .medium
                ))
                usedTypes.insert(.occasion)
            }

            // Guest question / reply needed. A question is operationally useful, but
            // not automatically a concern.
            if !usedTypes.contains(.guestCommunicationNeeded),
               looksLikeGuestQuestion(normalized) {
                signals.append(ReservationSignal(
                    id: "\(input.reservationID)-guest-reply",
                    reservationID: input.reservationID,
                    type: .guestCommunicationNeeded,
                    title: "Guest may expect a reply",
                    staffText: "Review the note before confirming or seating.",
                    evidence: trimQuestionEvidence(from: text),
                    confidence: .medium,
                    source: source,
                    requiresReview: true,
                    priority: .medium
                ))
                usedTypes.insert(.guestCommunicationNeeded)
            }

            // Guest preference (seating, location)
            if !usedTypes.contains(.guestPreference),
               let evidence = firstMatch(in: normalized, keywords: preferenceKeywords) {
                signals.append(ReservationSignal(
                    id: "\(input.reservationID)-pref",
                    reservationID: input.reservationID,
                    type: .guestPreference,
                    title: "Guest preference",
                    staffText: "Note the seating preference.",
                    evidence: trimEvidence(evidence, from: text),
                    confidence: .medium,
                    source: source,
                    requiresReview: false,
                    priority: .low
                ))
                usedTypes.insert(.guestPreference)
            }

            // Kitchen note (food request, not preorder/banquet)
            if !usedTypes.contains(.kitchenNote),
               let evidence = firstMatch(in: normalized, keywords: kitchenKeywords) {
                signals.append(ReservationSignal(
                    id: "\(input.reservationID)-kitchen",
                    reservationID: input.reservationID,
                    type: .kitchenNote,
                    title: "Kitchen note",
                    staffText: "Tell the kitchen.",
                    evidence: trimEvidence(evidence, from: text),
                    confidence: .medium,
                    source: source,
                    requiresReview: false,
                    priority: .medium
                ))
                usedTypes.insert(.kitchenNote)
            }

            // Bar note
            if !usedTypes.contains(.barNote),
               let evidence = firstMatch(in: normalized, keywords: barKeywords) {
                signals.append(ReservationSignal(
                    id: "\(input.reservationID)-bar",
                    reservationID: input.reservationID,
                    type: .barNote,
                    title: "Bar note",
                    staffText: "Tell the bar.",
                    evidence: trimEvidence(evidence, from: text),
                    confidence: .medium,
                    source: source,
                    requiresReview: false,
                    priority: .medium
                ))
                usedTypes.insert(.barNote)
            }
        }

        let sorted = signals.sorted { $0.priority > $1.priority }

        NoteSignalTrace.analyzed(
            reservationID: input.reservationID,
            signals: sorted.count,
            fallback: false
        )
        for signal in sorted {
            NoteSignalTrace.signal(
                reservationID: input.reservationID,
                type: signal.type.rawValue,
                confidence: signal.confidence.rawValue,
                source: signal.source.rawValue,
                requiresReview: signal.requiresReview
            )
        }

        return sorted
    }

    // MARK: - Keyword dictionaries

    private static let depositKeywords = [
        "deposit", "paid", "payment", "cash", "venmo", "zelle", "credit card",
        "e-transfer", "prepaid", "hold fee"
    ]

    private static let preorderKeywords = [
        "preorder", "pre-order", "pre order", "preordered", "chicken kyiv",
        "honey cake", "tasting menu", "menu package", "set menu", "order ahead",
        "food order", "pre-paid dinner"
    ]

    private static let banquetKeywords = [
        "banquet", "private event", "full buyout", "buyout", "private dining",
        "party package", "full room", "event package"
    ]

    private static let dietaryKeywords = [
        "allerg", "vegan", "vegetarian", "gluten", "dairy", "nut allergy",
        "halal", "kosher", "lactose", "celiac", "coeliac", "shellfish",
        "peanut", "tree nut", "soy allerg", "egg allerg", "fish allerg",
        "no meat", "no pork", "plant-based", "dairy-free", "gluten-free",
        "nut-free", "veg only"
    ]

    private static let accessibilityKeywords = [
        "wheelchair", "accessible", "accessibility", "high chair", "highchair",
        "mobility", "walker", "cane", "disabled", "stroller", "pram",
        "booster seat", "baby seat", "low table"
    ]

    private static let occasionKeywords = [
        "birthday", "anniversary", "engagement", "proposal", "wedding",
        "graduation", "celebration", "bachelorette", "bachelor", "farewell",
        "retirement", "promotion", "special occasion", "surprise"
    ]

    private static let preferenceKeywords = [
        "booth", "window seat", "quiet table", "outside", "patio", "corner",
        "not near kitchen", "near bar", "back room", "private area",
        "high top", "regular spot", "usual table", "prefers"
    ]

    private static let kitchenKeywords = [
        "cake", "candle", "special plating", "fresh flowers on table",
        "bring out dessert", "custom dish", "late arrival", "split portion",
        "allergy plate"
    ]

    private static let barKeywords = [
        "champagne", "prosecco", "bottle service", "flight", "cocktail",
        "wine pairing", "whiskey", "open bar", "drinks package"
    ]

    private static let questionLeadIns = [
        "why", "what", "when", "where", "who", "how", "can you", "could you",
        "please reply", "please confirm", "let me know", "call me", "text me"
    ]

    // MARK: - Helpers

    /// Returns the keyword that matched, or nil.
    private static func firstMatch(in normalized: String, keywords: [String]) -> String? {
        keywords.first { normalized.contains($0) }
    }

    private static func looksLikeGuestQuestion(_ normalized: String) -> Bool {
        if normalized.contains("?") { return true }
        return questionLeadIns.contains { normalized.contains($0) }
    }

    /// Short evidence snippet: up to 60 chars from the source text around the keyword.
    private static func trimEvidence(_ keyword: String, from source: String) -> String? {
        let lower = source.lowercased()
        guard let range = lower.range(of: keyword) else {
            return String(source.prefix(60))
        }
        let start = lower.distance(from: lower.startIndex, to: range.lowerBound)
        let snippetStart = max(0, start - 10)
        let snippet = String(source.dropFirst(snippetStart).prefix(60))
        return snippet.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimQuestionEvidence(from source: String) -> String? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let questionMark = trimmed.firstIndex(of: "?") {
            let prefix = trimmed[...questionMark]
            return String(prefix.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(trimmed.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
