//
//  HostServiceBriefingNarrativeWriter.swift
//  Tryzub Reservations
//
//  4E narrative writer for Service Intelligence.
//  Input: HostServiceBriefingPacket (facts only).
//  Output: HostServiceBriefingNarrative (template or validated model prose).
//
//  Responsibilities:
//  - Always builds template fallback first from existing template writer.
//  - Applies gate; returns template if model should not run.
//  - Calls runtime with structured fact prompt if gate passes.
//  - Validates output; falls back to template on any failure.
//  - Never touches HostLLMPacket, HostDecisionSnapshot, or raw reservation fields.
//

import Foundation

// MARK: - Writer

enum HostServiceBriefingNarrativeWriter {

    // MARK: - Entry point

    struct Input {
        let packet: HostServiceBriefingPacket
        let sourceFingerprint: String
        let settings: HostIntelligenceSettings
        let gateContext: HostServiceBriefingNarrativeGate.Context
        let serviceDateLabel: String?
    }

    /// Synchronous template-only write (always safe, always fast).
    static func writeTemplate(_ input: Input) -> HostServiceBriefingNarrative {
        let presentation = HostServiceBriefingTemplateWriter.presentation(
            for: input.packet.facts,
            dateKey: input.packet.dateKey,
            serviceMode: input.packet.serviceMode,
            truthCounts: input.packet.truthCounts,
            now: Date()
        )
        #if DEBUG
        print("[SERVICE_BRIEFING_NARRATIVE_TRACE] decision=template reason=template_path date=\(input.packet.dateKey) fingerprint=\(input.packet.inputFingerprint.prefix(12))")
        #endif
        return HostServiceBriefingNarrative(
            compactLine: presentation.compactLine,
            sectionLinesByID: sectionLinesByID(from: presentation.sections),
            source: .template,
            failedReason: nil,
            dateKey: input.packet.dateKey,
            packetFingerprint: input.packet.inputFingerprint,
            sourceFingerprint: input.sourceFingerprint,
            promptVersion: HostServiceBriefingNarrativePromptBuilder.promptVersion,
            createdAt: Date()
        )
    }

    /// Async write: applies gate, attempts model if allowed, falls back to template.
    static func write(_ input: Input) async -> HostServiceBriefingNarrative {
        let packet = input.packet
        let templateFallback = writeTemplate(input)

        // Gate: check if model should run
        if let skipReason = HostServiceBriefingNarrativeGate.skipReason(
            settings: input.settings,
            packet: packet,
            context: input.gateContext
        ) {
            #if DEBUG
            print("[SERVICE_BRIEFING_NARRATIVE_TRACE] decision=skip reason=\(skipReason.rawValue) date=\(packet.dateKey) fingerprint=\(packet.inputFingerprint.prefix(12))")
            #endif
            return templateFallback
        }

        // Build prompt from facts only
        let prompt = HostServiceBriefingNarrativePromptBuilder.build(
            HostServiceBriefingNarrativePromptBuilder.Input(
                packet: packet,
                serviceDateLabel: input.serviceDateLabel
            )
        )

        #if DEBUG
        print("[SERVICE_BRIEFING_NARRATIVE_TRACE] decision=model_start date=\(packet.dateKey) fingerprint=\(packet.inputFingerprint.prefix(12))")
        #endif

        // Run model
        let runtime = HostLocalModelRuntimeFactory.makeRuntime()
        let rawOutput: String
        do {
            rawOutput = try await runtime.generate(
                prompt: prompt,
                profile: .serviceBriefingNarrative
            )
        } catch {
            let reason = (error as? HostLocalModelRuntimeError)?.localizedDescription ?? error.localizedDescription
            #if DEBUG
            print("[SERVICE_BRIEFING_NARRATIVE_TRACE] decision=fallback reason=model_error detail=\(reason)")
            #endif
            return fallbackNarrative(from: templateFallback, reason: "model_error")
        }

        // Parse
        guard let parsed = ServiceBriefingNarrativeOutputParser.parse(rawOutput) else {
            #if DEBUG
            print("[SERVICE_BRIEFING_NARRATIVE_TRACE] decision=fallback reason=parse_failed")
            #endif
            return fallbackNarrative(from: templateFallback, reason: "parse_failed")
        }

        // Validate
        let validation = HostServiceBriefingNarrativeValidator.validate(
            parsed: parsed,
            packet: packet
        )
        guard validation.accepted, let cleanCompact = validation.sanitizedCompactLine else {
            #if DEBUG
            print("[SERVICE_BRIEFING_NARRATIVE_TRACE] decision=fallback reason=validator_rejected detail=\(validation.rejectionReason ?? "unknown")")
            #endif
            return fallbackNarrative(from: templateFallback, reason: "validator_rejected:\(validation.rejectionReason ?? "unknown")")
        }

        #if DEBUG
        print("[SERVICE_BRIEFING_NARRATIVE_TRACE] decision=model_accept date=\(packet.dateKey) fingerprint=\(packet.inputFingerprint.prefix(12)) compact=\"\(cleanCompact.prefix(60))\"")
        #endif

        return HostServiceBriefingNarrative(
            compactLine: cleanCompact,
            sectionLinesByID: validation.acceptedSectionLinesByID,
            source: .localModel,
            failedReason: nil,
            dateKey: packet.dateKey,
            packetFingerprint: packet.inputFingerprint,
            sourceFingerprint: input.sourceFingerprint,
            promptVersion: HostServiceBriefingNarrativePromptBuilder.promptVersion,
            createdAt: Date()
        )
    }

    // MARK: - Helpers

    private static func fallbackNarrative(
        from template: HostServiceBriefingNarrative,
        reason: String
    ) -> HostServiceBriefingNarrative {
        HostServiceBriefingNarrative(
            compactLine: template.compactLine,
            sectionLinesByID: template.sectionLinesByID,
            source: .fallback,
            failedReason: reason,
            dateKey: template.dateKey,
            packetFingerprint: template.packetFingerprint,
            sourceFingerprint: template.sourceFingerprint,
            promptVersion: template.promptVersion,
            createdAt: Date()
        )
    }

    private static func sectionLinesByID(from sections: [BriefingSection]) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0.lines) })
    }
}
