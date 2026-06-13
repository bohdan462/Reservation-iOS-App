//
//  HostAIProofTraces.swift
//  Tryzub Reservations
//
//  DEBUG-only proof traces for the Host Intelligence / local LLM safety pipeline.
//  These make it explicit from device logs whether the model was fed a bounded,
//  sanitized packet, whether the validator passed or blocked output, and which
//  facts/categories drove an AI-worthy decision. None of these emit raw guest
//  contact data or raw notes — only counts and stable tokens.
//

import Foundation
import OSLog

// MARK: - Facts

/// Emits the deterministic facts/categories the engine produced for a date, plus
/// whether guest signals and floor tables came from the backend or local fallback.
enum HostAIFactsTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "HostAI"
    )

    static func log(
        date: String,
        facts: Int,
        actions: Int,
        categories: [String],
        guestSignals: String,
        floorTables: String
    ) {
        guard isEnabled else { return }
        let cats = categories.isEmpty ? "none" : categories.joined(separator: ",")
        logger.debug(
            "[HOST_AI_FACTS_TRACE] date=\(date, privacy: .public) facts=\(facts, privacy: .public) actions=\(actions, privacy: .public) categories=\(cats, privacy: .public) guestSignals=\(guestSignals, privacy: .public) floorTables=\(floorTables, privacy: .public)"
        )
    }
}

// MARK: - Packet

/// Emits the sanitized packet summary actually handed to the model writer. The
/// containsRaw* flags are computed AFTER sanitization, so they must be false in a
/// healthy build; a true value is a red flag that sanitization regressed.
enum HostAIPacketTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "HostAI"
    )

    static func log(
        packetID: String,
        facts: Int,
        actions: Int,
        containsRawContact: Bool,
        containsRawNotes: Bool,
        source: String
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[HOST_AI_PACKET_TRACE] packetID=\(packetID, privacy: .public) facts=\(facts, privacy: .public) actions=\(actions, privacy: .public) containsRawContact=\(containsRawContact ? "true" : "false", privacy: .public) containsRawNotes=\(containsRawNotes ? "true" : "false", privacy: .public) source=\(source, privacy: .public)"
        )
    }

    /// Heuristic raw-contact detector used only to prove sanitization held. Detects
    /// email-like and long phone-like digit runs in the sanitized text.
    static func looksLikeRawContact(_ text: String) -> Bool {
        if text.range(of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        if text.range(of: #"\+?\d[\d\s().-]{8,}\d"#, options: [.regularExpression]) != nil {
            return true
        }
        return false
    }
}

// MARK: - Validator

/// Emits a single pass/blocked line per validation with a STABLE reason token,
/// independent of the human-readable validator message. Never weakens validation;
/// purely observational.
enum HostAIValidatorTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "HostAI"
    )

    static func pass(packetID: String) {
        guard isEnabled else { return }
        logger.debug("[HOST_AI_VALIDATOR] result=accepted packetID=\(packetID, privacy: .public)")
    }

    static func blocked(packetID: String, reason: String?) {
        guard isEnabled else { return }
        logger.debug("[HOST_AI_VALIDATOR] result=blocked packetID=\(packetID, privacy: .public) reason=\(classify(reason), privacy: .public)")
    }

    /// Maps a validator reason (human sentence or internal token) to a stable,
    /// log-safe token for device proof.
    static func classify(_ reason: String?) -> String {
        guard let reason = reason?.lowercased(), !reason.isEmpty else { return "unspecified" }

        // Already-tokenized operational reasons pass through.
        let knownTokens = [
            "announcement_tone", "manager_prefix", "second_person_guest_facing",
            "unsupported_table_available_claim",
            "unsupported_no_table_claim_for_seated_reservation",
            "unsupported_late_claim_for_seated_reservation",
            "unsupported_seated_claim_for_unseated_reservation",
            "unknown_guest_name"
        ]
        for token in knownTokens where reason == token {
            return token
        }

        if reason.contains("phone") { return "raw_contact" }
        if reason.contains("email") { return "raw_contact" }
        if reason.contains("table") { return "unsupported_table_claim" }
        if reason.contains("completed") || reason.contains("confirmed") || reason.contains("seated") {
            return "unsupported_status_claim"
        }
        if reason.contains("labeled") || reason.contains("unnatural") { return "leaked_labels" }
        if reason.contains("repeats") { return "repetition" }
        if reason.contains("exceeds") || reason.contains("characters") { return "too_long" }
        if reason.contains("one sentence") { return "multi_sentence" }
        if reason.contains("technical") { return "blocked_technical" }
        if reason.contains("calm fallback") || reason.contains("no facts") { return "unsupported_no_facts" }
        if reason.contains("headline is empty") { return "empty_headline" }
        if reason.contains("regular") || reason.contains("vip") || reason.contains("always") || reason.contains("never") {
            return "unsupported_guest_fact"
        }
        return "other"
    }
}

// MARK: - Test harness

/// Emits results of developer-only validator fixtures. Never shown in production UI.
enum HostAITestTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "HostAI"
    )

    static func log(scenario: String, result: String, detail: String? = nil) {
        guard isEnabled else { return }
        if let detail, !detail.isEmpty {
            logger.debug("[HOST_AI_TEST] scenario=\(scenario, privacy: .public) result=\(result, privacy: .public) \(detail, privacy: .public)")
        } else {
            logger.debug("[HOST_AI_TEST] scenario=\(scenario, privacy: .public) result=\(result, privacy: .public)")
        }
    }
}
