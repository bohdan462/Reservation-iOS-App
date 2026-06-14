//
//  LocalModelNoteAnalyzer.swift
//  Tryzub Reservations
//
//  Phase 10 — Model-based note intelligence (sentiment + classification).
//
//  ADDITIVE, NOT AUTHORITATIVE. `NoteSignalAnalyzer` (deterministic keywords) is always the
//  baseline. This analyzer asks the on-device model to read the note for:
//    1. tone / sentiment (excited, neutral, concerned)
//    2. signal classification it may have missed (typed from a strict allowlist)
//
//  SAFETY DESIGN:
//  • The model only returns a TYPE (from an allowlist) + a short evidence quote + a tone.
//  • The app owns every staff-facing sentence — the model never writes the wording. This
//    makes it structurally impossible for the model to claim "deposit paid" or
//    "allergy confirmed": it can only say which category the note touches.
//  • Unknown/forbidden types are dropped. Evidence with PII markers is dropped.
//  • Gated on readiness; on any failure it returns [] and the deterministic baseline stands.
//
//  Source on every produced signal is `.localModel`.
//

import Foundation

actor LocalModelNoteAnalyzer {

    struct Input {
        let reservationID: String
        let guestNote: String?
        let staffNote: String?
    }

    /// Types the model is allowed to assign. Excludes any "verified/confirmed" fact types.
    private static let allowedTypes: [ReservationSignalType] = [
        .depositMentioned, .preorderMentioned, .banquetMentioned,
        .allergyOrDietary, .accessibility, .occasion, .guestPreference,
        .kitchenNote, .barNote, .serviceIssue, .guestCommunicationNeeded
    ]

    private static let maxNoteCharacters = 600

    /// Returns model-enriched signals, or [] if the model is unavailable / found nothing.
    func analyze(_ input: Input) async -> [ReservationSignal] {
        let combined = Self.combinedNote(guest: input.guestNote, staff: input.staffNote)
        guard !combined.isEmpty else { return [] }

        guard HostLocalModelRuntimeFactory.isRuntimeIntegrated,
              HostLocalModelReadinessProvider.currentReadiness().status == .ready else {
            return []
        }

        let prompt = Self.buildPrompt(note: combined)
        let runtime = HostLocalModelRuntimeFactory.makeRuntime()

        guard HostLocalModelInferenceTracker.begin(task: .noteAnalysis) else {
            ModelTaskTrace.blocked(task: .noteAnalysis, reason: "host_board_pending")
            return []
        }
        defer { HostLocalModelInferenceTracker.end(task: .noteAnalysis) }

        ModelTaskTrace.started(task: .noteAnalysis)

        let generated: String
        do {
            generated = try await runtime.generate(prompt: prompt, profile: .noteAnalysis)
        } catch {
            ModelTaskTrace.fallback(task: .noteAnalysis, reason: "inference_failed")
            return []
        }

        guard let payload = Self.parse(generated) else {
            ModelTaskTrace.fallback(task: .noteAnalysis, reason: "parse_failed")
            return []
        }

        let signals = Self.makeSignals(from: payload, reservationID: input.reservationID)
        ModelTaskTrace.completed(task: .noteAnalysis, detail: "signals=\(signals.count)")
        return signals
    }

    // MARK: - Prompt

    private static func combinedNote(guest: String?, staff: String?) -> String {
        let parts = [guest, staff]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = parts.joined(separator: " | ")
        return String(joined.prefix(maxNoteCharacters))
    }

    private static func buildPrompt(note: String) -> String {
        let typeList = allowedTypes.map { $0.rawValue }.joined(separator: ", ")
        return """
        Note to classify:
        \"\"\"
        \(note)
        \"\"\"

        Allowed signal types: \(typeList)

        Return one JSON object only. No markdown. No commentary. Keys:
        - sentiment: one of "positive", "neutral", "concerned"
        - sentimentReason: a short phrase (max 8 words) or null
        - signals: an array; each item is { "type": one allowed type, "evidence": a short quote (max 8 words) from the note }

        Rules:
        - Use only types from the allowed list.
        - Only include a signal the note clearly supports.
        - Never claim a deposit is paid or an allergy is confirmed.
        - If nothing is notable, return an empty signals array.

        Write the JSON now:
        """
    }

    // MARK: - Parsing

    private struct Payload: Decodable {
        struct Item: Decodable {
            let type: String
            let evidence: String?
        }
        let sentiment: String?
        let sentimentReason: String?
        let signals: [Item]?
    }

    private static func parse(_ text: String) -> Payload? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidates = [trimmed, extractJSONObject(from: trimmed)].compactMap { $0 }
        for candidate in candidates {
            if let data = candidate.data(using: .utf8),
               let payload = try? JSONDecoder().decode(Payload.self, from: data) {
                return payload
            }
        }
        return nil
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else { return nil }
        return String(text[start...end])
    }

    // MARK: - Signal construction (app owns all wording)

    private static func makeSignals(from payload: Payload, reservationID: String) -> [ReservationSignal] {
        var signals: [ReservationSignal] = []
        var usedTypes = Set<ReservationSignalType>()

        // Sentiment first — only surface a tone signal when it is actionable.
        if let sentimentSignal = sentimentSignal(
            from: payload.sentiment,
            reason: payload.sentimentReason,
            reservationID: reservationID
        ) {
            signals.append(sentimentSignal)
        }

        for item in payload.signals ?? [] {
            guard let type = ReservationSignalType(rawValue: item.type),
                  allowedTypes.contains(type),
                  !usedTypes.contains(type) else { continue }
            let wording = staffWording(for: type)
            signals.append(ReservationSignal(
                id: "\(reservationID)-model-\(type.rawValue)",
                reservationID: reservationID,
                type: type,
                title: wording.title,
                staffText: wording.staffText,
                evidence: sanitizedEvidence(item.evidence),
                confidence: .medium,
                source: .localModel,
                requiresReview: wording.requiresReview,
                priority: wording.priority
            ))
            usedTypes.insert(type)
        }

        return signals.sorted { $0.priority > $1.priority }
    }

    private static func sentimentSignal(
        from sentiment: String?,
        reason: String?,
        reservationID: String
    ) -> ReservationSignal? {
        guard let raw = sentiment?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        let cleanReason = sanitizedEvidence(reason)
        switch raw {
        case "concerned", "negative", "anxious", "upset":
            return ReservationSignal(
                id: "\(reservationID)-model-sentiment",
                reservationID: reservationID,
                type: .guestSentiment,
                title: "Guest may be concerned",
                staffText: "Read the note — the guest may have a concern.",
                evidence: cleanReason,
                confidence: .low,
                source: .localModel,
                requiresReview: true,
                priority: .medium
            )
        case "positive", "excited", "happy":
            return ReservationSignal(
                id: "\(reservationID)-model-sentiment",
                reservationID: reservationID,
                type: .guestSentiment,
                title: "Guest sounds excited",
                staffText: "The guest seems to be looking forward to this visit.",
                evidence: cleanReason,
                confidence: .low,
                source: .localModel,
                requiresReview: false,
                priority: .info
            )
        default:
            // neutral / unknown → no tone signal (avoids noise).
            return nil
        }
    }

    /// App-controlled, staff-safe wording per type. The model never writes these sentences.
    private static func staffWording(
        for type: ReservationSignalType
    ) -> (title: String, staffText: String, priority: SignalPriority, requiresReview: Bool) {
        switch type {
        case .depositMentioned:
            return ("Deposit mentioned", "Manager should verify deposit note.", .high, true)
        case .preorderMentioned:
            return ("Preorder mentioned", "Kitchen should review preorder note.", .high, true)
        case .banquetMentioned:
            return ("Banquet note", "Kitchen should review banquet details.", .high, true)
        case .allergyOrDietary:
            return ("Dietary or allergy note", "Check guest notes before seating.", .critical, true)
        case .accessibility:
            return ("Accessibility note", "Check setup before seating.", .high, true)
        case .occasion:
            return ("Occasion note", "Note the occasion before seating.", .medium, false)
        case .guestPreference:
            return ("Guest preference", "Note the seating preference.", .low, false)
        case .kitchenNote:
            return ("Kitchen note", "Tell the kitchen.", .medium, false)
        case .barNote:
            return ("Bar note", "Tell the bar.", .medium, false)
        case .serviceIssue:
            return ("Possible service issue", "Read the note and check with a manager.", .high, true)
        case .guestCommunicationNeeded:
            return ("Guest may need a reply", "Check whether the guest needs a response.", .medium, true)
        default:
            return ("Note signal", "Review this note.", .low, false)
        }
    }

    /// Evidence must be short and free of obvious PII markers (no emails / long digit runs).
    private static func sanitizedEvidence(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.contains("@") { return nil }
        let digitRun = raw.filter(\.isNumber)
        if digitRun.count >= 7 { return nil }
        return String(raw.prefix(60))
    }
}
