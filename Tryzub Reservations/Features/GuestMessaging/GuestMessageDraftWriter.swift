//
//  GuestMessageDraftWriter.swift
//  Tryzub Reservations
//

import Foundation

protocol GuestMessageDraftWriting {
    func draftMessage(from packet: GuestMessageDraftPacket) async -> GuestMessageDraft
}

struct TemplateGuestMessageDraftWriter: GuestMessageDraftWriting {
    func draftMessage(from packet: GuestMessageDraftPacket) async -> GuestMessageDraft {
        GuestMessageDraftTemplateWriter.draft(from: packet)
    }
}

actor LocalModelGuestMessageDraftWriter: GuestMessageDraftWriting {

    func draftMessage(from packet: GuestMessageDraftPacket) async -> GuestMessageDraft {
        let template = GuestMessageDraftTemplateWriter.draft(from: packet)

        guard HostLocalModelRuntimeFactory.isRuntimeIntegrated else {
            return template
        }

        let readiness = HostLocalModelReadinessProvider.currentReadiness()
        guard readiness.status == .ready else {
            return templateWithNote(
                template,
                note: "Local model is not ready; using template draft."
            )
        }

        let prompt = GuestMessageDraftPromptBuilder.buildPrompt(from: packet)
        let runtime = HostLocalModelRuntimeFactory.makeRuntime()

        HostLocalModelInferenceTracker.begin()
        defer { HostLocalModelInferenceTracker.end() }

        do {
            let generated = try await runtime.generateBriefing(prompt: prompt)
            guard let parsed = GuestMessageDraftOutputParser.parse(generated) else {
                return templateWithNote(template, note: "Could not parse model output; using template draft.")
            }

            switch GuestMessageDraftValidator.validate(parsed, packet: packet) {
            case .valid:
                return GuestMessageDraft(
                    emailSubject: parsed.emailSubject,
                    emailBody: parsed.emailBody,
                    shortMessageBody: parsed.shortMessageBody,
                    safetyNote: parsed.safetyNote,
                    blockedReason: nil,
                    source: .localModel
                )
            case .blocked(let reason):
                return templateWithNote(template, note: reason)
            }
        } catch {
            return templateWithNote(
                template,
                note: "Local model failed; using template draft."
            )
        }
    }

    private func templateWithNote(
        _ template: GuestMessageDraft,
        note: String
    ) -> GuestMessageDraft {
        GuestMessageDraft(
            emailSubject: template.emailSubject,
            emailBody: template.emailBody,
            shortMessageBody: template.shortMessageBody,
            safetyNote: note,
            blockedReason: nil,
            source: .template
        )
    }
}

enum GuestMessageDraftWriterFactory {
    static func make(useLocalModel: Bool) -> GuestMessageDraftWriting {
        if useLocalModel {
            return LocalModelGuestMessageDraftWriter()
        }
        return TemplateGuestMessageDraftWriter()
    }
}
