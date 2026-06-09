//
//  ManagerNarrativeWriter.swift
//  Tryzub Reservations
//
//  Controlled staff-facing narrative writer. Wording only — facts/actions are fixed upstream.
//

import Foundation

enum ManagerNarrativeWriterDiagnostics {
  private static let lock = NSLock()
  private static let maxStoredOutputLength = 800
  nonisolated(unsafe) private static var _lastRawOutput: String?
  nonisolated(unsafe) private static var _lastValidationFailureReason: String?

  static var lastRawOutput: String? {
    lock.lock()
    defer { lock.unlock() }
    return _lastRawOutput
  }

  static var lastValidationFailureReason: String? {
    lock.lock()
    defer { lock.unlock() }
    return _lastValidationFailureReason
  }

  static func recordSuccess(raw: String) {
    lock.lock()
    defer { lock.unlock() }
    _lastRawOutput = truncated(raw)
    _lastValidationFailureReason = nil
  }

  static func recordFailure(raw: String?, reason: String?) {
    lock.lock()
    defer { lock.unlock() }
    _lastRawOutput = raw.map(truncated)
    _lastValidationFailureReason = reason
  }

  private static func truncated(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > maxStoredOutputLength else { return trimmed }
    return String(trimmed.prefix(maxStoredOutputLength))
  }
}

struct ManagerNarrativeWriter {

  func write(
    narrativePacket: ManagerNarrativePacket,
    hostPacket: HostLLMPacket,
    fallback: ManagerNarrative
  ) async -> ManagerNarrative {
    if hostPacket.topFacts.isEmpty {
      ManagerNarrativeWriterDiagnostics.recordSuccess(raw: fallback.compactBriefingText)
      return fallback
    }

    if HostBriefingHostBoardGate.shouldUseTemplateOnlyOnHostBoard(packet: hostPacket)
      || LocalModelHostBriefingWriter.shouldUseTemplateForLowRiskSingleFact(hostPacket) {
      ManagerNarrativeWriterDiagnostics.recordSuccess(raw: fallback.compactBriefingText)
      return fallback
    }

    HostBriefingWriterDiagnostics.prepareForInference()
    HostLocalModelInferenceTracker.begin()
    defer { HostLocalModelInferenceTracker.end() }

    let readiness = HostLocalModelReadinessProvider.currentReadiness()
    switch readiness.status {
    case .runtimeMissing, .modelMissing, .unavailable:
      ManagerNarrativeWriterDiagnostics.recordFailure(
        raw: nil,
        reason: readiness.detail
      )
      return fallbackWithReason(fallback, reason: readiness.detail)
    case .ready:
      break
    }

    let prompt = ManagerNarrativePromptBuilder.buildPrompt(from: narrativePacket)
    let runtime = HostLocalModelRuntimeFactory.makeRuntime()

    do {
      let generated = try await runtime.generateBriefing(prompt: prompt)
      ManagerNarrativeWriterDiagnostics.recordSuccess(raw: generated)

      var parsed = ManagerNarrativeOutputParser.parse(generated)
      parsed = ManagerNarrative(
        headline: parsed.headline,
        whyItMatters: parsed.whyItMatters,
        checkNext: parsed.checkNext,
        source: .localModel,
        failedReason: nil
      )

      let validation = ManagerNarrativeValidator.validationResult(
        parsed,
        packet: narrativePacket,
        hostPacket: hostPacket,
        fallback: fallback
      )

      if validation.isValid {
        return parsed
      }

      ManagerNarrativeWriterDiagnostics.recordFailure(
        raw: generated,
        reason: validation.reason
      )
      return fallbackWithReason(fallback, reason: validation.reason)
    } catch {
      ManagerNarrativeWriterDiagnostics.recordFailure(
        raw: nil,
        reason: error.localizedDescription
      )
      return fallbackWithReason(fallback, reason: error.localizedDescription)
    }
  }

  private func fallbackWithReason(
    _ fallback: ManagerNarrative,
    reason: String?
  ) -> ManagerNarrative {
    ManagerNarrative(
      headline: fallback.headline,
      whyItMatters: fallback.whyItMatters,
      checkNext: fallback.checkNext,
      source: .failedFallback,
      failedReason: reason
    )
  }
}
