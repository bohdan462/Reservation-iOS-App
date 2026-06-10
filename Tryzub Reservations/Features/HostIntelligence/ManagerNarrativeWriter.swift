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
      let skipReason = HostBriefingHostBoardGate.hasOperationalTension(packet: hostPacket)
        ? "host_board_template_only"
        : "independent_simple_facts"
      HostAILifecycleTrace.modelSkipped(reason: skipReason)
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
      HostAILifecycleTrace.modelSkipped(reason: skipReason.rawValue)
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
    let packetKey = hostPacket.briefingFingerprint
    let inferenceStarted = ContinuousClock.now
    let themes = HostBriefingHostBoardGate.operationalCategories(for: hostPacket)
      .map(\.traceLabel)
      .sorted()

    do {
      HostAILifecycleTrace.modelStarted(
        packetKey: packetKey,
        promptChars: prompt.count,
        promptTokens: HostAILifecycleTrace.estimatedPromptTokens(for: prompt),
        facts: narrativePacket.headlineFacts.count,
        actions: narrativePacket.availableActions.count,
        themes: themes,
        visibleSurface: narrativePacket.surface.rawValue
      )
      let generated = try await runtime.generateBriefing(prompt: prompt)
      let inferenceDurationMs = Int(
        inferenceStarted.duration(to: .now).pressureTraceTimeInterval * 1000
      )
      HostAILifecycleTrace.modelCompleted(
        durationMs: inferenceDurationMs,
        outputChars: generated.count
      )
      HostBoardModelDecisionTrace.recordModelDuration(inferenceDurationMs)
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

      let validationStarted = ContinuousClock.now
      let validation = ManagerNarrativeValidator.validationResult(
        parsed,
        packet: narrativePacket,
        hostPacket: hostPacket,
        fallback: fallback
      )
      let validationDurationMs = Int(
        validationStarted.duration(to: .now).pressureTraceTimeInterval * 1000
      )
      HostAILifecycleTrace.validationCompleted(
        durationMs: validationDurationMs,
        result: validation.isValid ? "valid" : "rejected",
        reason: validation.isValid ? nil : validation.reason
      )

      if validation.isValid {
        HostLocalModelWarmthTracker.markWarm()
        if usedRepair {
          HostIntelligenceDiagnostics.repairedOutputUsed(labelsRemoved: true)
        } else {
          HostIntelligenceDiagnostics.modelOutputUsed(source: "local_model")
        }
        HostAILifecycleTrace.modelOutputUsed(
          source: usedRepair ? "repairedLocalModel" : "localModel",
          durationMs: inferenceDurationMs + validationDurationMs
        )
        HostBoardModelDecisionTrace.recordRejectionReason(nil)
        return parsed
      }

      let rejectionReason = validation.reason ?? "validation_failed"
      HostIntelligenceDiagnostics.modelOutputRejected(reason: rejectionReason)
      HostAILifecycleTrace.modelOutputRejected(reason: rejectionReason)
      HostAILifecycleTrace.templateFallbackUsed(reason: rejectionReason)
      HostBoardModelDecisionTrace.recordRejectionReason(rejectionReason)
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
    var candidate = generated.trimmingCharacters(in: .whitespacesAndNewlines)
    var usedPrefixRepair = false

    if let stripped = ManagerNarrativeValidator.stripRolePrefixIfNeeded(candidate) {
      candidate = stripped.text
      usedPrefixRepair = stripped.stripped
    }

    if ManagerNarrativeValidator.containsLeakedModelLabels(in: candidate),
       let repaired = ManagerNarrativeValidator.repairStaffCopy(candidate),
       !ManagerNarrativeValidator.containsLeakedModelLabels(in: repaired) {
      return NormalizedModelOutput(text: repaired, usedRepair: true, failureReason: nil)
    }

    if usedPrefixRepair, !ManagerNarrativeValidator.containsLeakedModelLabels(in: candidate) {
      return NormalizedModelOutput(text: candidate, usedRepair: true, failureReason: nil)
    }

    if ManagerNarrativeValidator.containsLeakedModelLabels(in: candidate) {
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

    return NormalizedModelOutput(text: candidate, usedRepair: usedPrefixRepair, failureReason: nil)
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
