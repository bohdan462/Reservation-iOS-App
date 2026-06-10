//
//  HostAILifecycleTrace.swift
//  Tryzub Reservations
//
//  DEBUG-only high-level local model lifecycle tracing.
//

import Foundation
import OSLog

enum HostAILifecycleTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "HostAI"
    )

    static func modelStarted(
        packetKey: String,
        promptChars: Int,
        promptTokens: Int,
        facts: Int,
        actions: Int,
        themes: [String],
        selectedDate: String? = nil,
        visibleSurface: String? = nil
    ) {
        guard isEnabled else { return }
        var parts = [
            "event=model_started",
            "packetKey=\(packetKey)",
            "promptChars=\(promptChars)",
            "promptTokens=\(promptTokens)",
            "facts=\(facts)",
            "actions=\(actions)",
            "themes=\(themes.joined(separator: ","))"
        ]
        if let selectedDate, !selectedDate.isEmpty {
            parts.append("selectedDate=\(selectedDate)")
        }
        if let visibleSurface, !visibleSurface.isEmpty {
            parts.append("surface=\(visibleSurface)")
        }
        emit(parts.joined(separator: " "))
    }

    static func modelCompleted(durationMs: Int, outputChars: Int) {
        guard isEnabled else { return }
        emit("event=model_completed duration=\(durationMs)ms outputChars=\(outputChars)")
    }

    static func validationCompleted(durationMs: Int, result: String, reason: String? = nil) {
        guard isEnabled else { return }
        if let reason, !reason.isEmpty, result != "valid" {
            emit("event=validation_completed duration=\(durationMs)ms result=\(result) reason=\(reason)")
        } else {
            emit("event=validation_completed duration=\(durationMs)ms result=\(result)")
        }
    }

    static func modelOutputUsed(source: String, durationMs: Int) {
        guard isEnabled else { return }
        emit("event=model_output_used source=\(source) duration=\(durationMs)ms")
    }

    static func modelOutputRejected(reason: String) {
        guard isEnabled else { return }
        emit("event=model_output_rejected reason=\(reason)")
    }

    static func modelSkipped(reason: String) {
        guard isEnabled else { return }
        emit("event=model_skipped reason=\(reason)")
    }

    static func templateFallbackUsed(reason: String) {
        guard isEnabled else { return }
        emit("event=template_fallback_used reason=\(reason)")
    }

    static func visibleSourceChanged(from: String, to: String, reason: String) {
        guard isEnabled else { return }
        emit("event=visible_source_changed from=\(from) to=\(to) reason=\(reason)")
    }

    static func modelResultIgnored(reason: String) {
        guard isEnabled else { return }
        emit("event=model_result_ignored reason=\(reason)")
    }

    static func estimatedPromptTokens(for prompt: String) -> Int {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return max(1, trimmed.count / 4)
    }

    private static func emit(_ body: String) {
        logger.debug("[HOST_AI_LIFECYCLE] \(body, privacy: .public)")
    }
}

enum HostLlamaLogSettings {
    #if DEBUG
    nonisolated(unsafe) static var verboseModelLogs = false
    #else
    static let verboseModelLogs = false
    #endif
}
