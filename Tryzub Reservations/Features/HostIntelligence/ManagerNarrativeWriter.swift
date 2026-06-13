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

enum HostModelPacketTrace {
  static func log(
    task: String,
    grouped: Bool,
    facts: Int,
    actions: Int,
    fingerprint: String,
    themes: [String]
  ) {
    #if DEBUG
    print(
      "[HOST_MODEL_PACKET_TRACE] task=\(task) grouped=\(grouped) facts=\(facts) actions=\(actions) themes=\(themes.joined(separator: ",")) fingerprint=\(fingerprint)"
    )
    #endif
  }
}

enum HostAIValidatorRepairTrace {
  static func log(reason: String, repaired: Bool) {
    #if DEBUG
    print("[HOST_AI_VALIDATOR_REPAIR_TRACE] reason=\(reason) repaired=\(repaired)")
    #endif
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

    let groupedEligible = narrativePacket.groupedPresentation
      && narrativePacket.modelEligibleReason != nil
    if !groupedEligible,
       HostBriefingHostBoardGate.shouldUseTemplateOnlyOnHostBoard(packet: hostPacket)
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
        packet: hostPacket,
        modelEligibleReason: narrativePacket.modelEligibleReason
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

    // Resolve the best available wording profile. For the iPad/demo build this is
    // betterLocal3B when bundled. Falls back to smallFastLocal if 3B is absent, and
    // to template if neither is available (handled by the readiness check below).
    let resolvedWordingProfile = HostLocalModelFileLocator.bestAvailableProfile()
    HostProductionTrace.localModelProfile(
      requested: .betterLocal3B,
      resolved: resolvedWordingProfile,
      reason: "manager_narrative"
    )

    let readiness = HostLocalModelReadinessProvider.currentReadiness(profile: resolvedWordingProfile)
    switch readiness.status {
    case .runtimeMissing, .modelMissing, .unavailable:
      HostAILifecycleTrace.modelUnavailable(reason: "\(readiness.status)")
      HostAILifecycleTrace.fallbackUsed(reason: "model_unavailable")
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
    let packetKey = narrativePacket.presentationFingerprint ?? hostPacket.briefingFingerprint

    // Proof trace: the sanitized packet handed to the writer. containsRaw* are
    // computed on the already-sanitized prompt, so they must be false in a healthy
    // build (a true value means sanitization regressed).
    let promptLower = prompt.lowercased()
    HostAIPacketTrace.log(
      packetID: packetKey,
      facts: narrativePacket.headlineFacts.count,
      actions: narrativePacket.availableActions.count,
      containsRawContact: HostAIPacketTrace.looksLikeRawContact(prompt),
      containsRawNotes: promptLower.contains("guest_key") || promptLower.contains("payload") || promptLower.contains("source="),
      source: narrativePacket.surface.rawValue
    )
    HostModelPacketTrace.log(
      task: "managerNarrative",
      grouped: narrativePacket.groupedPresentation,
      facts: narrativePacket.headlineFacts.count,
      actions: narrativePacket.availableActions.count,
      fingerprint: packetKey,
      themes: narrativePacket.presentationThemes
    )
    let inferenceStarted = ContinuousClock.now
    let themes = narrativePacket.presentationThemes.isEmpty
      ? HostBriefingHostBoardGate.operationalCategories(for: hostPacket)
        .map(\.traceLabel)
        .sorted()
      : narrativePacket.presentationThemes

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
      // Use the managerNarrative task profile: larger token budget and better system
      // prompt tuned for 2-sentence operational briefings from the 3B model.
      let generated = try await runtime.generate(prompt: prompt, profile: .managerNarrative)
      let inferenceDurationMs = Int(
        inferenceStarted.duration(to: .now).pressureTraceTimeInterval * 1000
      )
      HostAILifecycleTrace.modelCompleted(
        durationMs: inferenceDurationMs,
        outputChars: generated.count
      )
      HostProductionTrace.localModelGeneration(
        surface: narrativePacket.surface.rawValue,
        profile: resolvedWordingProfile,
        status: "success",
        durationMs: inferenceDurationMs
      )
      HostBoardModelDecisionTrace.recordModelDuration(inferenceDurationMs)
      let normalizedResult = normalizeModelOutput(generated)
      guard let normalized = normalizedResult.text else {
        return fallbackWithReason(
          fallback,
          reason: normalizedResult.failureReason ?? "rejected labeled or unnatural staff output"
        )
      }
      var usedRepair = normalizedResult.usedRepair

      ManagerNarrativeWriterDiagnostics.recordSuccess(raw: normalized)

      var parsed = ManagerNarrativeOutputParser.parse(normalized)
      parsed = ManagerNarrative(
        headline: parsed.headline,
        whyItMatters: parsed.whyItMatters,
        checkNext: parsed.checkNext,
        source: usedRepair ? .repairedLocalModel : .localModel,
        failedReason: nil
      )

      let validationStarted = ContinuousClock.now
      var validation = ManagerNarrativeValidator.validationResult(
        parsed,
        packet: narrativePacket,
        hostPacket: hostPacket,
        fallback: fallback
      )
      if !validation.isValid,
         validation.reason == ManagerNarrativeValidator.unknownGuestNameReason {
        if let repaired = ManagerNarrativeValidator.repairUnknownGuestNames(
          in: parsed,
          packet: narrativePacket
        ) {
          let repairedValidation = ManagerNarrativeValidator.validationResult(
            repaired,
            packet: narrativePacket,
            hostPacket: hostPacket,
            fallback: fallback
          )
          HostAIValidatorRepairTrace.log(
            reason: "unknown_name",
            repaired: repairedValidation.isValid
          )
          if repairedValidation.isValid {
            parsed = repaired
            validation = repairedValidation
            usedRepair = true
            ManagerNarrativeWriterDiagnostics.recordSuccess(raw: repaired.compactBriefingText)
          }
        } else {
          HostAIValidatorRepairTrace.log(reason: "unknown_name", repaired: false)
        }
      }
      let validationDurationMs = Int(
        validationStarted.duration(to: .now).pressureTraceTimeInterval * 1000
      )
      HostAILifecycleTrace.validationCompleted(
        durationMs: validationDurationMs,
        result: validation.isValid ? "valid" : "rejected",
        reason: validation.isValid ? nil : validation.reason
      )
      if validation.isValid {
        HostAIValidatorTrace.pass(packetID: packetKey)
      } else {
        HostAIValidatorTrace.blocked(packetID: packetKey, reason: validation.reason)
      }

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
        HostProductionTrace.hostManagerSummary(
          source: resolvedWordingProfile.traceName,
          clusterCount: narrativePacket.availableActions.count,
          headlineLength: parsed.headline.count,
          whyLength: parsed.whyItMatters?.count ?? 0,
          checkLength: parsed.checkNext?.count ?? 0,
          sentenceCount: ManagerNarrativeValidator.sentenceCount(in: parsed),
          richContext: narrativePacket.headlineFacts.count >= 2
            || (narrativePacket.arrivalPressureFacts?.peakGuestCount ?? 0) > 0,
          pressureLevel: narrativePacket.arrivalPressureFacts?.pressureLevel,
          peakWindow: narrativePacket.arrivalPressureFacts?.peakWindow,
          blocked: nil
        )
        return parsed
      }

      let rejectionReason = validation.reason ?? "validation_failed"
      HostIntelligenceDiagnostics.modelOutputRejected(reason: rejectionReason)
      HostAILifecycleTrace.modelOutputRejected(reason: rejectionReason)
      HostAILifecycleTrace.templateFallbackUsed(reason: rejectionReason)
      HostAILifecycleTrace.fallbackUsed(reason: "validator_blocked")
      HostBoardModelDecisionTrace.recordRejectionReason(rejectionReason)
      ManagerNarrativeWriterDiagnostics.recordFailure(
        raw: generated,
        reason: validation.reason
      )
      HostProductionTrace.localModelGeneration(
        surface: narrativePacket.surface.rawValue,
        profile: resolvedWordingProfile,
        status: "blocked",
        durationMs: inferenceDurationMs
      )
      HostProductionTrace.hostManagerSummary(
        source: "template",
        clusterCount: narrativePacket.availableActions.count,
        headlineLength: fallback.headline.count,
        whyLength: fallback.whyItMatters?.count ?? 0,
        checkLength: fallback.checkNext?.count ?? 0,
        sentenceCount: ManagerNarrativeValidator.sentenceCount(in: fallback),
        richContext: false,
        pressureLevel: narrativePacket.arrivalPressureFacts?.pressureLevel,
        peakWindow: narrativePacket.arrivalPressureFacts?.peakWindow,
        blocked: rejectionReason
      )
      return fallbackWithReason(fallback, reason: validation.reason)
    } catch {
      ManagerNarrativeWriterDiagnostics.recordFailure(
        raw: nil,
        reason: error.localizedDescription
      )
      HostProductionTrace.localModelGeneration(
        surface: narrativePacket.surface.rawValue,
        profile: resolvedWordingProfile,
        status: "fallback",
        durationMs: 0
      )
      HostProductionTrace.hostManagerSummary(
        source: "template",
        clusterCount: narrativePacket.availableActions.count,
        headlineLength: fallback.headline.count,
        whyLength: fallback.whyItMatters?.count ?? 0,
        checkLength: fallback.checkNext?.count ?? 0,
        sentenceCount: ManagerNarrativeValidator.sentenceCount(in: fallback),
        richContext: false,
        pressureLevel: narrativePacket.arrivalPressureFacts?.pressureLevel,
        peakWindow: narrativePacket.arrivalPressureFacts?.peakWindow,
        blocked: error.localizedDescription
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
