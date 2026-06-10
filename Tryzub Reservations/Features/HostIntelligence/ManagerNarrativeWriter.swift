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

  @MainActor
  func write(
    narrativePacket: ManagerNarrativePacket,
    hostPacket: HostLLMPacket,
    fallback: ManagerNarrative,
    hostBoardContext: HostBriefingHostBoardContext? = nil,
    settings: HostIntelligenceSettings? = nil
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

    if let hostBoardContext, let settings,
       let skipReason = HostBriefingHostBoardGate.localModelSkipReason(
        settings: settings,
        context: hostBoardContext,
        packet: hostPacket
       ) {
      HostIntelligenceDiagnostics.skipLocalModel(reason: skipReason.rawValue)
      ManagerNarrativeWriterDiagnostics.recordFailure(
        raw: nil,
        reason: skipReason.rawValue
      )
      return fallbackWithReason(fallback, reason: skipReason.rawValue)
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
      let normalizedResult = normalizeModelOutput(generated)
      guard let normalized = normalizedResult.text else {
        return fallbackWithReason(
          fallback,
          reason: normalizedResult.failureReason ?? "rejected labeled or unnatural staff output"
        )
      }
      let usedRepair = normalizedResult.usedRepair

      ManagerNarrativeWriterDiagnostics.recordSuccess(raw: normalized)

      var parsed = ManagerNarrativeOutputParser.parse(normalized)
      parsed = ManagerNarrative(
        headline: parsed.headline,
        whyItMatters: parsed.whyItMatters,
        checkNext: nil,
        source: usedRepair ? .repairedLocalModel : .localModel,
        failedReason: nil
      )

      let validation = ManagerNarrativeValidator.validationResult(
        parsed,
        packet: narrativePacket,
        hostPacket: hostPacket,
        fallback: fallback
      )

      if validation.isValid {
        HostLocalModelWarmthTracker.markWarm()
        if usedRepair {
          HostIntelligenceDiagnostics.repairedOutputUsed(labelsRemoved: true)
        } else {
          HostIntelligenceDiagnostics.modelOutputUsed(source: "local_model")
        }
        return parsed
      }

      HostIntelligenceDiagnostics.modelOutputRejected(
        reason: validation.reason ?? "validation_failed"
      )
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

  private struct NormalizedModelOutput {
    let text: String?
    let usedRepair: Bool
    let failureReason: String?
  }

  private func normalizeModelOutput(_ generated: String) -> NormalizedModelOutput {
    if ManagerNarrativeValidator.containsLeakedModelLabels(in: generated),
       let repaired = ManagerNarrativeValidator.repairStaffCopy(generated),
       !ManagerNarrativeValidator.containsLeakedModelLabels(in: repaired) {
      return NormalizedModelOutput(text: repaired, usedRepair: true, failureReason: nil)
    }

    if ManagerNarrativeValidator.containsLeakedModelLabels(in: generated) {
      HostIntelligenceDiagnostics.modelOutputRejected(reason: "raw_labels")
      ManagerNarrativeWriterDiagnostics.recordFailure(
        raw: generated,
        reason: "Narrative contains labeled or unnatural staff output."
      )
      return NormalizedModelOutput(
        text: nil,
        usedRepair: false,
        failureReason: "Narrative contains labeled or unnatural staff output."
      )
    }

    return NormalizedModelOutput(text: generated, usedRepair: false, failureReason: nil)
  }

  private func fallbackWithReason(
    _ fallback: ManagerNarrative,
    reason: String?
  ) -> ManagerNarrative {
    if let reason, !reason.isEmpty {
      HostIntelligenceDiagnostics.localModelFallback(reason: reason)
    }
    return ManagerNarrative(
      headline: fallback.headline,
      whyItMatters: fallback.whyItMatters,
      checkNext: fallback.checkNext,
      source: .failedFallback,
      failedReason: reason
    )
  }
}
