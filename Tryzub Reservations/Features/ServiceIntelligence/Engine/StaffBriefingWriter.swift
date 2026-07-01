//
//  StaffBriefingWriter.swift
//  Tryzub Reservations
//
//  4F-1 — Orchestrates on-demand staff briefing generation.
//
//  - Always builds a deterministic template result first (guaranteed fallback).
//  - Applies the gate; returns the template result if the model may not run.
//  - Otherwise builds the full prompt, runs the local model under the
//    `.staffBriefing` profile, parses + validates, and returns the model result.
//  - On any failure (error / parse / validation / timeout) returns a fallback
//    result carrying the template content and a reason.
//
//  MUST NOT auto-run. Only HostIntelligenceController.requestStaffBriefing calls this.
//

import Foundation

enum StaffBriefingWriter {

    struct Input {
        let packet: StaffBriefingPacket
        let settings: HostIntelligenceSettings
        let gateContext: StaffBriefingGate.Context
        let serviceDateLabel: String?
        let cacheKey: StaffBriefingCacheKey
    }

    // MARK: - Template (always safe)

    static func writeTemplate(_ input: Input, source: StaffBriefingSource = .template, failedReason: String? = nil) -> StaffBriefingResult {
        let content = StaffBriefingTemplateWriter.build(input.packet)
        return makeResult(
            mode: input.packet.mode,
            content: content,
            source: source,
            failedReason: failedReason,
            cacheKey: input.cacheKey
        )
    }

    // MARK: - Full generation

    static func write(_ input: Input) async -> StaffBriefingResult {
        let templateResult = writeTemplate(input)

        if let skip = StaffBriefingGate.skipReason(
            settings: input.settings,
            packet: input.packet,
            context: input.gateContext
        ) {
            #if DEBUG
            print("[STAFF_BRIEFING_TRACE] decision=fallback mode=\(input.packet.mode.rawValue) reason=gate_\(skip.rawValue)")
            #endif
            // Gate skip = model intentionally not used → template (not a failure fallback).
            return templateResult
        }

        let prompt = StaffBriefingPromptBuilder.build(input.packet, serviceDateLabel: input.serviceDateLabel)

        #if DEBUG
        print("[STAFF_BRIEFING_TRACE] decision=model_start mode=\(input.packet.mode.rawValue) date=\(input.packet.dateKey) fingerprint=\(input.packet.inputFingerprint.prefix(12))")
        #endif

        HostLocalModelInferenceTracker.begin(task: .staffBriefing)
        defer { HostLocalModelInferenceTracker.end(task: .staffBriefing) }

        let runtime = HostLocalModelRuntimeFactory.makeRuntime()
        let rawOutput: String
        do {
            rawOutput = try await runtime.generate(prompt: prompt, profile: .staffBriefing)
        } catch {
            let reason = (error as? HostLocalModelRuntimeError)?.localizedDescription ?? error.localizedDescription
            #if DEBUG
            print("[STAFF_BRIEFING_TRACE] decision=fallback mode=\(input.packet.mode.rawValue) reason=model_error detail=\(reason)")
            #endif
            return fallback(from: templateResult, reason: "model_error")
        }

        guard let parsed = StaffBriefingOutputParser.parse(rawOutput) else {
            #if DEBUG
            print("[STAFF_BRIEFING_TRACE] decision=fallback mode=\(input.packet.mode.rawValue) reason=parse_failed")
            #endif
            return fallback(from: templateResult, reason: "parse_failed")
        }

        let validation = StaffBriefingValidator.validate(parsed: parsed, packet: input.packet)
        guard validation.accepted, let clean = validation.sanitized else {
            let reason = validation.rejectionReason ?? "unknown"
            #if DEBUG
            print("[STAFF_BRIEFING_TRACE] decision=fallback mode=\(input.packet.mode.rawValue) reason=validator_\(reason)")
            #endif
            return fallback(from: templateResult, reason: "validator_\(reason)")
        }

        let content = StaffBriefingTemplateWriter.Content(
            headline: clean.headline,
            sections: clean.sections,
            actionBullets: clean.actionBullets
        )
        #if DEBUG
        print("[STAFF_BRIEFING_TRACE] decision=model_accept mode=\(input.packet.mode.rawValue) date=\(input.packet.dateKey) sections=\(clean.sections.count)")
        #endif
        return makeResult(
            mode: input.packet.mode,
            content: content,
            source: .localModel,
            failedReason: nil,
            cacheKey: input.cacheKey
        )
    }

    // MARK: - Helpers

    private static func fallback(from template: StaffBriefingResult, reason: String) -> StaffBriefingResult {
        StaffBriefingResult(
            mode: template.mode,
            headline: template.headline,
            sections: template.sections,
            actionBullets: template.actionBullets,
            source: .fallback,
            generatedAt: Date(),
            cacheKey: template.cacheKey,
            failedReason: reason,
            wordCount: template.wordCount
        )
    }

    private static func makeResult(
        mode: StaffBriefingMode,
        content: StaffBriefingTemplateWriter.Content,
        source: StaffBriefingSource,
        failedReason: String?,
        cacheKey: StaffBriefingCacheKey
    ) -> StaffBriefingResult {
        let plain = ([content.headline]
            + content.sections.flatMap { $0.paragraphs + $0.bullets }
            + content.actionBullets).joined(separator: "\n")
        return StaffBriefingResult(
            mode: mode,
            headline: content.headline,
            sections: content.sections,
            actionBullets: content.actionBullets,
            source: source,
            generatedAt: Date(),
            cacheKey: cacheKey,
            failedReason: failedReason,
            wordCount: StaffBriefingResult.wordCount(of: plain)
        )
    }
}
