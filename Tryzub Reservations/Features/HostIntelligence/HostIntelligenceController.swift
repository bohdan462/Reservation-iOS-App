//
//  HostIntelligenceController.swift
//  Tryzub Reservations
//
//  Read-only coordinator for Host Intelligence evaluation.
//

import Foundation

@MainActor
final class HostIntelligenceController: ObservableObject {

  @Published private(set) var decisionSnapshot: HostDecisionSnapshot = .empty
  @Published private(set) var briefingText: String = HostDecisionSnapshot.empty.templateBriefingText
  @Published private(set) var briefingSource: HostBriefingWriterSource = .template
  @Published private(set) var briefingFailureReason: String?
  @Published private(set) var managerNarrative: ManagerNarrative = .empty
  @Published private(set) var renderState: HostIntelligenceRenderState = .evaluating
  @Published private(set) var localEvaluationComplete = false
  @Published private(set) var isEnrichmentLoading = false

  let settingsStore: HostIntelligenceSettingsStore
  let tableStore: HostTableConfigStore
  private let engine: HostIntelligenceEngine

  private var lastAttentionSnapshot: HostDecisionSnapshot?
  private var lastAttentionNarrative: ManagerNarrative?
  private var lastAttentionBriefingText: String?
  private var lastAttentionSelectedDateKey = ""
  private var latestStabilityContext = HostEvaluationStabilityContext()
  private var latestTraceCandidate: HostCardTraceNoTableCandidate?
  private var latestSelectedDateKey = ""

  private var lastBriefingCacheKey: String?
  private var lastBriefingPacketFingerprint: String?
  private var lastBriefingGeneratedAt: Date?
  private var lastBriefingText: String?
  private var lastBriefingSource: HostBriefingWriterSource?
  private var lastBriefingFailureReason: String?
  private var lastManagerNarrative: ManagerNarrative?

  init(
    settingsStore: HostIntelligenceSettingsStore? = nil,
    tableStore: HostTableConfigStore? = nil,
    engine: HostIntelligenceEngine = HostIntelligenceEngine()
  ) {
    self.settingsStore = settingsStore ?? HostIntelligenceSettingsStore()
    self.tableStore = tableStore ?? HostTableConfigStore()
    self.engine = engine
  }

  var displaySnapshot: HostDecisionSnapshot {
    if shouldPreservePreviousAttentionCard,
       let lastAttentionSnapshot {
      return lastAttentionSnapshot
    }
    return decisionSnapshot
  }

  var displayManagerNarrative: ManagerNarrative {
    if shouldShowLoadingNarrative {
      return .loading
    }
    if shouldPreservePreviousAttentionCard,
       let lastAttentionNarrative {
      return lastAttentionNarrative
    }
    return managerNarrative
  }

  var displayBriefingText: String {
    if shouldShowLoadingNarrative {
      return ManagerNarrative.loading.compactBriefingText
    }
    if shouldPreservePreviousAttentionCard,
       let lastAttentionBriefingText {
      return lastAttentionBriefingText
    }
    return briefingText
  }

  var isRefreshingAttentionCard: Bool {
    isEnrichmentLoading
      && localEvaluationComplete
      && (decisionSnapshot.hasAttentionContent || displaySnapshot.hasAttentionContent)
  }

  var hostCardDisplayMode: String {
    if !localEvaluationComplete {
      return "loading"
    }
    if isEnrichmentLoading {
      return decisionSnapshot.hasAttentionContent ? "local_ready_refreshing" : "refreshing"
    }
    return decisionSnapshot.hasAttentionContent ? "local_ready" : "stable_empty"
  }

  func evaluate(
    input: HostEngineInput,
    stability: HostEvaluationStabilityContext
  ) {
    latestStabilityContext = stability
    let selectedDateKey = input.selectedDate.reservationDateString()
    let dateChanged = !latestSelectedDateKey.isEmpty && latestSelectedDateKey != selectedDateKey
    if dateChanged {
      clearAttentionPreservation()
      decisionSnapshot = .empty
      applyTemplateBriefing(from: .empty)
      localEvaluationComplete = false
      isEnrichmentLoading = false
    }
    latestSelectedDateKey = selectedDateKey
    latestTraceCandidate = HostCardTrace.noTableSoonCandidate(
      in: input.reservations,
      selectedDate: input.selectedDate,
      now: input.now
    )
    renderState = .evaluating

    guard settingsStore.settings.isEnabled else {
      decisionSnapshot = .empty
      clearAttentionPreservation()
      clearBriefingCache()
      applyTemplateBriefing(from: .empty)
      localEvaluationComplete = true
      renderState = .ready
      traceEvaluation(snapshot: .empty, preservedPrevious: false, emptyAllowed: true)
      return
    }

    let enriched = HostEngineInput(
      now: input.now,
      selectedDate: input.selectedDate,
      reservations: input.reservations,
      availabilitySummary: input.availabilitySummary,
      analyticsSummary: input.analyticsSummary,
      restaurantSetup: input.restaurantSetup,
      localSeatedAtByReservationID: input.localSeatedAtByReservationID,
      settings: settingsStore.settings,
      tableConfigs: input.tableConfigs,
      allKnownReservations: input.allKnownReservations,
      guestIntelligenceSummariesByReservationID: input.guestIntelligenceSummariesByReservationID
    )

    let candidate = engine.evaluateHostDecisionSnapshot(input: enriched)
    let shouldBlockEmptyReplacement = !stability.allowsEmptyReplacement
      && !candidate.hasAttentionContent
      && lastAttentionSnapshot?.hasAttentionContent == true
      && lastAttentionSelectedDateKey == selectedDateKey

    if shouldBlockEmptyReplacement {
      localEvaluationComplete = true
      traceEvaluation(
        snapshot: candidate,
        preservedPrevious: true,
        emptyAllowed: false,
        dateChanged: dateChanged,
        enrichmentLoading: stability.isEnrichmentLoading
      )
      renderState = stability.allowsEmptyReplacement ? .ready : .evaluating
      return
    }

    decisionSnapshot = candidate
    applyTemplateBriefing(from: candidate)

    if candidate.hasAttentionContent {
      lastAttentionSnapshot = candidate
      lastAttentionNarrative = managerNarrative
      lastAttentionBriefingText = briefingText
      lastAttentionSelectedDateKey = selectedDateKey
    } else if stability.allowsEmptyReplacement {
      clearAttentionPreservation()
    }

    localEvaluationComplete = true
    renderState = .ready
    traceEvaluation(
      snapshot: candidate,
      preservedPrevious: false,
      emptyAllowed: stability.allowsEmptyReplacement,
      dateChanged: dateChanged,
      enrichmentLoading: stability.isEnrichmentLoading
    )
  }

  /// Presentation-only rewrite of the approved LLM packet. Does not change engine output.
  func refreshBriefing(hostBoardContext: HostBriefingHostBoardContext? = nil) async {
    let preserveLocalPresentation = localEvaluationComplete
      && (decisionSnapshot.hasAttentionContent || !decisionSnapshot.briefingFacts.isEmpty)
    if preserveLocalPresentation {
      isEnrichmentLoading = true
    } else {
      renderState = .evaluating
    }
    defer {
      isEnrichmentLoading = false
      if latestStabilityContext.allowsEmptyReplacement || displaySnapshot.hasAttentionContent {
        renderState = .ready
      }
    }

    let fallback = decisionSnapshot.templateBriefingText
    let settings = settingsStore.settings
    let packet = decisionSnapshot.llmPacket
    let fingerprint = packet.briefingFingerprint
    let settingsStamp = briefingSettingsStamp(settings)
    let actionStamp = narrativeActionStamp(from: decisionSnapshot)
    let cacheKey = briefingCacheKey(
      fingerprint: fingerprint,
      settingsStamp: settingsStamp,
      hostBoardContext: hostBoardContext,
      settings: settings,
      packet: packet,
      actionStamp: actionStamp
    )

    guard settings.isEnabled else {
      clearBriefingCache()
      applyTemplateBriefing(from: .empty)
      return
    }

    let templateNarrative = ManagerNarrativeTemplateBuilder.build(from: decisionSnapshot)

    if cacheKey == lastBriefingCacheKey,
       let cachedText = lastBriefingText {
      briefingText = cachedText
      briefingSource = lastBriefingSource ?? .template
      briefingFailureReason = lastBriefingFailureReason
      managerNarrative = lastManagerNarrative ?? templateNarrative
      HostIntelligenceDiagnostics.skipBriefing(reason: "same_packet")
      return
    }

    guard settings.useEnhancedBriefing else {
      storeBriefingResult(
        cacheKey: cacheKey,
        fingerprint: fingerprint,
        text: fallback,
        source: .template,
        failureReason: nil,
        narrative: templateNarrative
      )
      return
    }

    if let hostBoardContext {
      recordHostBoardGateDecision(
        context: hostBoardContext,
        settings: settings,
        packet: packet
      )
    }

    if hostBoardContext != nil,
       HostBriefingHostBoardGate.shouldUseTemplateOnlyOnHostBoard(packet: packet) {
      HostIntelligenceDiagnostics.skipLocalModel(reason: HostBriefingHostBoardGate.SkipReason.host_board_template_only.rawValue)
      storeBriefingResult(
        cacheKey: cacheKey,
        fingerprint: fingerprint,
        text: fallback,
        source: .template,
        failureReason: nil,
        narrative: templateNarrative,
        visibleSource: "template"
      )
      return
    }

    let provider = resolvedBriefingProvider(
      settings: settings,
      hostBoardContext: hostBoardContext,
      packet: packet
    )

    if provider == .template {
      storeBriefingResult(
        cacheKey: cacheKey,
        fingerprint: fingerprint,
        text: fallback,
        source: .template,
        failureReason: nil,
        narrative: templateNarrative
      )
      return
    }

    if let hostBoardContext, provider == .localModel {
      HostIntelligenceDiagnostics.localModelAttempted(surface: "host_home")
      let narrativePacket = ManagerNarrativePacketBuilder.buildHostHome(from: decisionSnapshot)
      let narrativeResult = await ManagerNarrativeWriter().write(
        narrativePacket: narrativePacket,
        hostPacket: packet,
        fallback: templateNarrative,
        hostBoardContext: hostBoardContext,
        settings: settings
      )
      let briefingSource = mapBriefingSource(narrativeResult.source)
      storeBriefingResult(
        cacheKey: cacheKey,
        fingerprint: fingerprint,
        text: narrativeResult.compactBriefingText,
        source: briefingSource,
        failureReason: narrativeResult.failedReason,
        narrative: narrativeResult,
        templateFallback: templateNarrative,
        visibleSource: visibleSourceLabel(for: briefingSource),
        modelRunAt: briefingSource == .localModel || briefingSource == .repairedLocalModel
          ? Date()
          : nil
      )
      return
    }

    let writer = HostBriefingWriterFactory.writer(for: provider)
    let result = await writer.writeBriefing(
      packet: packet,
      fallbackText: fallback
    )

    let validation = HostBriefingWriterValidator.validationResult(
      result.text,
      packet: packet,
      fallbackText: fallback
    )

    if validation.isValid {
      let narrative = ManagerNarrative(
        headline: result.text,
        whyItMatters: templateNarrative.whyItMatters,
        checkNext: templateNarrative.checkNext,
        source: mapNarrativeSource(result.source),
        failedReason: result.failedReason
      )
      storeBriefingResult(
        cacheKey: cacheKey,
        fingerprint: fingerprint,
        text: result.text,
        source: result.source,
        failureReason: result.failedReason,
        narrative: narrative
      )
      return
    }

    storeBriefingResult(
      cacheKey: cacheKey,
      fingerprint: fingerprint,
      text: fallback,
      source: .failedFallback,
      failureReason: validation.reason
        ?? result.failedReason
        ?? "Briefing validation failed.",
      narrative: templateNarrative
    )
  }

  func reset() {
    decisionSnapshot = .empty
    clearAttentionPreservation()
    clearBriefingCache()
    applyTemplateBriefing(from: .empty)
    renderState = .evaluating
    localEvaluationComplete = false
    isEnrichmentLoading = false
  }

  private func applyTemplateBriefing(from snapshot: HostDecisionSnapshot) {
    let narrative = ManagerNarrativeTemplateBuilder.build(from: snapshot)
    briefingText = snapshot.templateBriefingText
    briefingSource = .template
    briefingFailureReason = nil
    managerNarrative = narrative
  }

  private var shouldPreservePreviousAttentionCard: Bool {
    renderState == .evaluating
      && !decisionSnapshot.hasAttentionContent
      && lastAttentionSnapshot?.hasAttentionContent == true
      && !lastAttentionSelectedDateKey.isEmpty
      && lastAttentionSelectedDateKey == latestSelectedDateKey
  }

  private var shouldShowLoadingNarrative: Bool {
    guard !localEvaluationComplete else { return false }
    guard renderState == .evaluating else { return false }
    if shouldPreservePreviousAttentionCard {
      return false
    }
    if decisionSnapshot.hasAttentionContent || displaySnapshot.hasAttentionContent {
      return false
    }
    return managerNarrative.headline == ManagerNarrative.empty.headline
  }

  private func clearAttentionPreservation() {
    lastAttentionSnapshot = nil
    lastAttentionNarrative = nil
    lastAttentionBriefingText = nil
    lastAttentionSelectedDateKey = ""
  }

  private func traceEvaluation(
    snapshot: HostDecisionSnapshot,
    preservedPrevious: Bool,
    emptyAllowed: Bool,
    dateChanged: Bool = false,
    enrichmentLoading: Bool = false
  ) {
    HostCardTrace.log(
      selectedDate: latestSelectedDateKey,
      lastAttentionSelectedDate: lastAttentionSelectedDateKey.isEmpty ? nil : lastAttentionSelectedDateKey,
      preserveAllowed: shouldPreservePreviousAttentionCard,
      dateChanged: dateChanged,
      localEvaluationComplete: localEvaluationComplete,
      enrichmentLoading: enrichmentLoading,
      display: hostCardDisplayMode,
      factCount: snapshot.briefingFacts.count,
      actionCount: snapshot.suggestedActions.count,
      renderState: renderState,
      emptyAllowed: emptyAllowed,
      preservedPrevious: preservedPrevious,
      noTableSoonCandidate: latestTraceCandidate
    )
  }

  private func resolvedBriefingProvider(
    settings: HostIntelligenceSettings,
    hostBoardContext: HostBriefingHostBoardContext?,
    packet: HostLLMPacket
  ) -> HostBriefingProviderKind {
    let requested = settings.enhancedBriefingProvider

    if let hostBoardContext {
      if requested == .localModel,
         let skipReason = HostBriefingHostBoardGate.localModelSkipReason(
          settings: settings,
          context: hostBoardContext,
          packet: packet
         ) {
        HostIntelligenceDiagnostics.skipLocalModel(reason: skipReason.rawValue)
      }

      return HostBriefingWriterFactory.effectiveProvider(
        requested: requested,
        settings: settings,
        forHostBoard: true,
        hostBoardAllowsLocalModel: HostBriefingHostBoardGate.shouldUseLocalModelOnHostBoard(
          settings: settings,
          context: hostBoardContext,
          packet: packet
        )
      )
    }

    return HostBriefingWriterFactory.effectiveProvider(
      requested: requested,
      settings: settings,
      forHostBoard: false
    )
  }

  private func briefingSettingsStamp(_ settings: HostIntelligenceSettings) -> String {
    "\(settings.useEnhancedBriefing)-\(settings.enhancedBriefingProvider.rawValue)-\(settings.useLocalModelOnHostBoard)"
  }

  private func briefingCacheKey(
    fingerprint: String,
    settingsStamp: String,
    hostBoardContext: HostBriefingHostBoardContext?,
    settings: HostIntelligenceSettings,
    packet: HostLLMPacket,
    actionStamp: String
  ) -> String {
    if let hostBoardContext {
      let localModelAllowed = HostBriefingHostBoardGate.shouldUseLocalModelOnHostBoard(
        settings: settings,
        context: hostBoardContext,
        packet: packet
      )
      return "\(fingerprint)|\(settingsStamp)|host|\(localModelAllowed)|\(actionStamp)"
    }
    return "\(fingerprint)|\(settingsStamp)|manual|\(actionStamp)"
  }

  private func narrativeActionStamp(from snapshot: HostDecisionSnapshot) -> String {
    snapshot.suggestedActions
      .prefix(3)
      .map { "\($0.kind.rawValue):\($0.title)" }
      .joined(separator: ";")
  }

  private func recordHostBoardGateDecision(
    context: HostBriefingHostBoardContext,
    settings: HostIntelligenceSettings,
    packet: HostLLMPacket
  ) {
    let skipReason = HostBriefingHostBoardGate.localModelSkipReason(
      settings: settings,
      context: context,
      packet: packet
    )
    HostBoardModelDecisionTrace.record(
      allowed: skipReason == nil,
      skipReason: skipReason,
      packet: packet,
      enrichmentLoading: context.isEnrichmentLoading
    )
  }

  private func visibleSourceLabel(for source: HostBriefingWriterSource) -> String {
    switch source {
    case .template: return "template"
    case .localModel: return "localModel"
    case .repairedLocalModel: return "repairedLocalModel"
    case .failedFallback: return "template"
    case .localPlaceholder: return "template"
    }
  }

  private func storeBriefingResult(
    cacheKey: String,
    fingerprint: String,
    text: String,
    source: HostBriefingWriterSource,
    failureReason: String?,
    narrative: ManagerNarrative,
    templateFallback: ManagerNarrative? = nil,
    visibleSource: String? = nil,
    modelRunAt: Date? = nil
  ) {
    if narrative.source == .localModel,
       ManagerNarrativeValidator.containsLeakedModelLabels(in: narrative)
        || ManagerNarrativeValidator.containsLeakedModelLabels(in: text) {
      HostIntelligenceDiagnostics.localModelFallback(
        reason: "rejected labeled or unnatural staff output"
      )
      if let templateFallback {
        briefingText = templateFallback.compactBriefingText
        briefingSource = .template
        briefingFailureReason = nil
        managerNarrative = templateFallback
      }
      return
    }

    briefingText = text
    briefingSource = source
    briefingFailureReason = failureReason
    managerNarrative = narrative
    if let visibleSource {
      HostBoardModelDecisionTrace.recordVisibleSource(visibleSource, modelRunAt: modelRunAt)
    }
    if decisionSnapshot.hasAttentionContent {
      lastAttentionNarrative = narrative
      lastAttentionBriefingText = text
    }
    lastBriefingCacheKey = cacheKey
    lastBriefingPacketFingerprint = fingerprint
    lastBriefingGeneratedAt = Date()
    lastBriefingText = text
    lastBriefingSource = source
    lastBriefingFailureReason = failureReason
    lastManagerNarrative = narrative
  }

  private func clearBriefingCache() {
    lastBriefingCacheKey = nil
    lastBriefingPacketFingerprint = nil
    lastBriefingGeneratedAt = nil
    lastBriefingText = nil
    lastBriefingSource = nil
    lastBriefingFailureReason = nil
    lastManagerNarrative = nil
    managerNarrative = .empty
  }

  private func mapBriefingSource(_ source: ManagerNarrative.Source) -> HostBriefingWriterSource {
    switch source {
    case .template: return .template
    case .localModel: return .localModel
    case .repairedLocalModel: return .repairedLocalModel
    case .failedFallback: return .failedFallback
    }
  }

  private func mapNarrativeSource(_ source: HostBriefingWriterSource) -> ManagerNarrative.Source {
    switch source {
    case .template: return .template
    case .localPlaceholder: return .template
    case .localModel: return .localModel
    case .repairedLocalModel: return .repairedLocalModel
    case .failedFallback: return .failedFallback
    }
  }

  var settings: HostIntelligenceSettings {
    settingsStore.settings
  }
}
