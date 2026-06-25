//
//  HostIntelligenceController.swift
//  Tryzub Reservations
//
//  Read-only coordinator for Host Intelligence evaluation.
//

import Foundation

enum HostAIRetryTrace {
  static func retry(packet: String, previousSkip: String) {
    #if DEBUG
    print("[HOST_AI_RETRY_TRACE] packet=\(packet) previousSkip=\(previousSkip) retry=true")
    #endif
  }

  static func final(packet: String, source: String) {
    #if DEBUG
    print("[HOST_AI_RETRY_TRACE] packet=\(packet) final=true source=\(source)")
    #endif
  }
}

@MainActor
final class HostIntelligenceController: ObservableObject {

  @Published private(set) var decisionSnapshot: HostDecisionSnapshot = .empty
  @Published private(set) var attentionPresentation: HostAttentionPresentation = .empty
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

  /// When false, briefing and on-device wording use production-safe template defaults.
  private(set) var canViewDeveloperDiagnostics = false

  func updateDeveloperDiagnosticsAccess(_ canView: Bool) {
    guard canViewDeveloperDiagnostics != canView else { return }
    canViewDeveloperDiagnostics = canView
    clearBriefingCache()
  }

  private var lastAttentionSnapshot: HostDecisionSnapshot?
  private var lastAttentionPresentation: HostAttentionPresentation?
  private var lastAttentionNarrative: ManagerNarrative?
  private var lastAttentionBriefingText: String?
  private var lastAttentionSelectedDateKey = ""
  private var latestStabilityContext = HostEvaluationStabilityContext()
  private var latestTraceCandidate: HostCardTraceNoTableCandidate?
  private var latestSelectedDateKey = ""
  private var latestFloorTableSource: HostFloorTableSource = .pendingBackend

  private var lastBriefingCacheKey: String?
  private var lastBriefingPacketFingerprint: String?
  private var lastBriefingGeneratedAt: Date?
  private var lastBriefingText: String?
  private var lastBriefingSource: HostBriefingWriterSource?
  private var lastBriefingFailureReason: String?
  private var lastManagerNarrative: ManagerNarrative?
  private var briefingRefreshGeneration = 0
  private var lastValidModelBriefingCacheKey: String?
  private var lastValidModelNarrative: ManagerNarrative?
  private var lastValidModelBriefingText: String?
  private var lastVisibleSourceLabel: String?
  private var lastRetryableBriefingCacheKey: String?
  private var lastRetryableBriefingPacketFingerprint: String?
  private var lastRetryableBriefingSkipReason: HostBriefingHostBoardGate.SkipReason?

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

  var displayAttentionPresentation: HostAttentionPresentation {
    if shouldPreservePreviousAttentionCard,
       let lastAttentionPresentation {
      return lastAttentionPresentation
    }
    return attentionPresentation
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
    stability: HostEvaluationStabilityContext,
    bookingLoadReport: BookingLoadReport? = nil
  ) {
    latestStabilityContext = stability
    let selectedDateKey = input.selectedDate.reservationDateString()
    let dateChanged = !latestSelectedDateKey.isEmpty && latestSelectedDateKey != selectedDateKey
    if dateChanged {
      briefingRefreshGeneration += 1
      clearAttentionPreservation()
      clearValidModelBriefingCache()
      decisionSnapshot = .empty
      attentionPresentation = .empty
      applyTemplateBriefing(from: .empty, presentation: .empty)
      localEvaluationComplete = false
      isEnrichmentLoading = false
    }
    latestSelectedDateKey = selectedDateKey
    latestFloorTableSource = input.floorTableSource
    latestTraceCandidate = HostCardTrace.noTableSoonCandidate(
      in: input.reservations,
      selectedDate: input.selectedDate,
      now: input.now
    )
    renderState = .evaluating

    guard settingsStore.settings.isEnabled else {
      decisionSnapshot = .empty
      attentionPresentation = .empty
      clearAttentionPreservation()
      clearBriefingCache()
      applyTemplateBriefing(from: .empty, presentation: .empty)
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
      backendFloorTables: input.backendFloorTables,
      effectiveTableAssignments: input.effectiveTableAssignments,
      floorTableSource: input.floorTableSource,
      guestIntelligenceSummariesByReservationID: input.guestIntelligenceSummariesByReservationID,
      guestProfilePacksByReservationID: input.guestProfilePacksByReservationID
    )

    let guestSignalMode = input.guestIntelligenceSummariesByReservationID.isEmpty
      && input.guestProfilePacksByReservationID.isEmpty
      ? "local_bounded"
      : "server"
    let candidate = UIPressureTrace.measure(
      phase: "host_engine_evaluate",
      extra: "dayReservations=\(input.reservations.count) historyPoolUsed=\(input.allKnownReservations.count) guestSignals=\(guestSignalMode)"
    ) {
      engine.evaluateHostDecisionSnapshot(input: enriched)
    }
    let candidatePresentation = HostAttentionGrouper.build(
      from: candidate,
      selectedDateKey: selectedDateKey,
      floorTableSource: input.floorTableSource,
      bookingLoadReport: bookingLoadReport
    )

    HostAIFactsTrace.log(
      date: selectedDateKey,
      facts: candidate.briefingFacts.count,
      actions: candidate.suggestedActions.count,
      categories: HostBriefingHostBoardGate.operationalCategories(for: candidate.llmPacket).map(\.traceLabel).sorted(),
      guestSignals: guestSignalMode,
      floorTables: input.floorTableSource.traceLabel
    )

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
    attentionPresentation = candidatePresentation
    applyTemplateBriefing(from: candidate, presentation: candidatePresentation)

    if candidate.hasAttentionContent {
      lastAttentionSnapshot = candidate
      lastAttentionPresentation = candidatePresentation
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
  func refreshBriefing(
    hostBoardContext: HostBriefingHostBoardContext? = nil,
    bookingLoadReport: BookingLoadReport? = nil
  ) async {
    briefingRefreshGeneration += 1
    let refreshGeneration = briefingRefreshGeneration
    let refreshDateKey = latestSelectedDateKey

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

    let currentPresentation: HostAttentionPresentation
    if let bookingLoadReport {
      currentPresentation = HostAttentionGrouper.build(
        from: decisionSnapshot,
        selectedDateKey: latestSelectedDateKey,
        floorTableSource: latestFloorTableSource,
        bookingLoadReport: bookingLoadReport
      )
      attentionPresentation = currentPresentation
    } else {
      currentPresentation = attentionPresentation
    }
    let templateNarrative = ManagerNarrativeTemplateBuilder.build(
      from: decisionSnapshot,
      presentation: currentPresentation
    )
    let fallback = templateNarrative.compactBriefingText
    let settings = runtimeSettings
    let packet = decisionSnapshot.llmPacket
    let fingerprint = hostBriefingFingerprint(
      packet: packet,
      presentation: currentPresentation,
      hostBoardContext: hostBoardContext
    )
    let settingsStamp = briefingSettingsStamp(settings)
    let actionStamp = narrativeActionStamp(
      from: decisionSnapshot,
      presentation: currentPresentation
    )
    let cacheKey = briefingCacheKey(
      fingerprint: fingerprint,
      settingsStamp: settingsStamp,
      hostBoardContext: hostBoardContext,
      settings: settings,
      packet: packet,
      actionStamp: actionStamp,
      presentation: currentPresentation
    )

    guard settings.isEnabled else {
      clearBriefingCache()
      applyTemplateBriefing(from: .empty, presentation: .empty)
      return
    }

    let protectsHostModelSlot = shouldProtectHostBoardModelSlot(
      settings: settings,
      hostBoardContext: hostBoardContext,
      packet: packet,
      presentation: currentPresentation
    )
    if protectsHostModelSlot {
      HostLocalModelInferenceTracker.beginHostBoardPending()
    }
    defer {
      if protectsHostModelSlot {
        HostLocalModelInferenceTracker.endHostBoardPending()
      }
    }

    let hostBoardSkipReason = hostBoardContext.map { context in
      HostBriefingHostBoardGate.localModelSkipReason(
        settings: settings,
        context: context,
        packet: packet,
        modelEligibleReason: currentPresentation.modelEligibleReason
      )
    } ?? nil
    if let hostBoardContext {
      HostBoardModelDecisionTrace.record(
        allowed: hostBoardSkipReason == nil,
        skipReason: hostBoardSkipReason,
        packet: packet,
        enrichmentLoading: hostBoardContext.isEnrichmentLoading,
        modelEligibleReason: currentPresentation.modelEligibleReason
      )
    }
    let retryingDeferredSkip = shouldRetryDeferredHostBriefing(
      cacheKey: cacheKey,
      fingerprint: fingerprint,
      currentSkipReason: hostBoardSkipReason
    )
    if retryingDeferredSkip,
       let previousSkip = lastRetryableBriefingSkipReason {
      HostAIRetryTrace.retry(packet: fingerprint, previousSkip: previousSkip.rawValue)
      clearRetryableHostBriefingSkip()
    }

    if let hostBoardSkipReason,
       isRetryableHostBoardSkip(hostBoardSkipReason) {
      recordRetryableHostBriefingSkip(
        cacheKey: cacheKey,
        fingerprint: fingerprint,
        reason: hostBoardSkipReason
      )
      HostIntelligenceDiagnostics.skipLocalModel(reason: hostBoardSkipReason.rawValue)
      HostAILifecycleTrace.modelSkipped(reason: hostBoardSkipReason.rawValue)
      applyRetryableTemplateBriefing(
        fallback: fallback,
        templateNarrative: templateNarrative,
        reason: hostBoardSkipReason.rawValue
      )
      return
    }

    if cacheKey == lastBriefingCacheKey,
       let cachedText = lastBriefingText,
       !retryingDeferredSkip {
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

    if hostBoardContext != nil,
       currentPresentation.modelEligibleReason == nil,
       HostBriefingHostBoardGate.shouldUseTemplateOnlyOnHostBoard(packet: packet) {
      let skipReason = HostBriefingHostBoardGate.hasOperationalTension(packet: packet)
        ? HostBriefingHostBoardGate.SkipReason.host_board_template_only.rawValue
        : "independent_simple_facts"
      HostIntelligenceDiagnostics.skipLocalModel(reason: skipReason)
      HostAILifecycleTrace.modelSkipped(reason: skipReason)
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
      packet: packet,
      presentation: currentPresentation
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
      let narrativePacket = ManagerNarrativePacketBuilder.buildHostHome(
        from: decisionSnapshot,
        presentation: currentPresentation,
        selectedDateKey: latestSelectedDateKey,
        floorSourceLabel: currentPresentation.floorSourceLabel
      )
      let narrativeResult = await ManagerNarrativeWriter().write(
        narrativePacket: narrativePacket,
        hostPacket: packet,
        fallback: templateNarrative,
        hostBoardContext: hostBoardContext,
        settings: settings
      )
      guard !Task.isCancelled else {
        HostAILifecycleTrace.modelCancelled(reason: "task_cancelled")
        return
      }
      guard refreshGeneration == briefingRefreshGeneration,
            refreshDateKey == latestSelectedDateKey else {
        HostAILifecycleTrace.modelResultIgnored(reason: "date_changed")
        HostAILifecycleTrace.modelCancelled(reason: "date_changed")
        return
      }

      if let retryableReason = retryableHostBoardSkipReason(rawValue: narrativeResult.failedReason) {
        recordRetryableHostBriefingSkip(
          cacheKey: cacheKey,
          fingerprint: fingerprint,
          reason: retryableReason
        )
        applyRetryableTemplateBriefing(
          fallback: fallback,
          templateNarrative: templateNarrative,
          reason: retryableReason.rawValue
        )
        return
      }

      let briefingSource = mapBriefingSource(narrativeResult.source)
      if briefingSource == .localModel || briefingSource == .repairedLocalModel {
        lastValidModelBriefingCacheKey = cacheKey
        lastValidModelNarrative = narrativeResult
        lastValidModelBriefingText = narrativeResult.compactBriefingText
        storeBriefingResult(
          cacheKey: cacheKey,
          fingerprint: fingerprint,
          text: narrativeResult.compactBriefingText,
          source: briefingSource,
          failureReason: nil,
          narrative: narrativeResult,
          templateFallback: templateNarrative,
          visibleSource: visibleSourceLabel(for: briefingSource),
          modelRunAt: Date()
        )
        return
      }

      if cacheKey == lastValidModelBriefingCacheKey,
         let previousNarrative = lastValidModelNarrative,
         let previousText = lastValidModelBriefingText {
        let previousSource = mapBriefingSource(previousNarrative.source)
        storeBriefingResult(
          cacheKey: cacheKey,
          fingerprint: fingerprint,
          text: previousText,
          source: previousSource,
          failureReason: narrativeResult.failedReason,
          narrative: previousNarrative,
          templateFallback: templateNarrative,
          visibleSource: visibleSourceLabel(for: previousSource),
          modelRunAt: Date()
        )
        return
      }

      storeBriefingResult(
        cacheKey: cacheKey,
        fingerprint: fingerprint,
        text: narrativeResult.compactBriefingText,
        source: briefingSource,
        failureReason: narrativeResult.failedReason,
        narrative: narrativeResult,
        templateFallback: templateNarrative,
        visibleSource: visibleSourceLabel(for: briefingSource),
        modelRunAt: nil
      )
      return
    }

    let writer = HostBriefingWriterFactory.writer(for: provider)
    let result = await writer.writeBriefing(
      packet: packet,
      fallbackText: fallback
    )
    guard !Task.isCancelled else {
      HostAILifecycleTrace.modelCancelled(reason: "task_cancelled")
      return
    }

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
    // If the model is mid-generation when the Host Board is hidden, discard any
    // in-flight result (bump the generation guard) and log the cancellation. The
    // llama runtime itself is not force-killed, but its output can no longer reach UI.
    if HostLocalModelInferenceTracker.isActive {
      briefingRefreshGeneration += 1
      HostAILifecycleTrace.modelCancelled(reason: "view_hidden")
    }
    decisionSnapshot = .empty
    attentionPresentation = .empty
    clearAttentionPreservation()
    clearBriefingCache()
    applyTemplateBriefing(from: .empty, presentation: .empty)
    renderState = .evaluating
    localEvaluationComplete = false
    isEnrichmentLoading = false
  }

  private func applyTemplateBriefing(
    from snapshot: HostDecisionSnapshot,
    presentation: HostAttentionPresentation? = nil
  ) {
    let activePresentation = presentation ?? attentionPresentation
    let narrative = ManagerNarrativeTemplateBuilder.build(
      from: snapshot,
      presentation: activePresentation
    )
    briefingText = activePresentation.hasVisibleContent
      ? narrative.compactBriefingText
      : snapshot.templateBriefingText
    briefingSource = .template
    briefingFailureReason = nil
    managerNarrative = narrative
  }

  private func applyRetryableTemplateBriefing(
    fallback: String,
    templateNarrative: ManagerNarrative,
    reason: String
  ) {
    briefingText = fallback
    briefingSource = .template
    briefingFailureReason = reason
    managerNarrative = templateNarrative
    if decisionSnapshot.hasAttentionContent {
      lastAttentionNarrative = templateNarrative
      lastAttentionBriefingText = fallback
    }
  }

  private func shouldProtectHostBoardModelSlot(
    settings: HostIntelligenceSettings,
    hostBoardContext: HostBriefingHostBoardContext?,
    packet: HostLLMPacket,
    presentation: HostAttentionPresentation
  ) -> Bool {
    guard hostBoardContext != nil else { return false }
    guard settings.isEnabled,
          settings.useEnhancedBriefing,
          settings.enhancedBriefingProvider == .localModel,
          settings.useLocalModelOnHostBoard else {
      return false
    }
    guard packet.hasMeaningfulBriefingFacts else { return false }
    return presentation.modelEligibleReason != nil
  }

  private func isRetryableHostBoardSkip(
    _ reason: HostBriefingHostBoardGate.SkipReason
  ) -> Bool {
    switch reason {
    case .date_navigation, .enrichment_loading, .local_model_in_flight:
      return true
    case .host_board_gate_off, .host_board_template_only, .model_not_ready,
         .startup_in_flight, .reservation_refresh_in_flight, .stabilization_delay,
         .no_meaningful_facts:
      return false
    }
  }

  private func retryableHostBoardSkipReason(
    rawValue: String?
  ) -> HostBriefingHostBoardGate.SkipReason? {
    guard let rawValue,
          let reason = HostBriefingHostBoardGate.SkipReason(rawValue: rawValue),
          isRetryableHostBoardSkip(reason) else {
      return nil
    }
    return reason
  }

  private func recordRetryableHostBriefingSkip(
    cacheKey: String,
    fingerprint: String,
    reason: HostBriefingHostBoardGate.SkipReason
  ) {
    lastRetryableBriefingCacheKey = cacheKey
    lastRetryableBriefingPacketFingerprint = fingerprint
    lastRetryableBriefingSkipReason = reason
  }

  private func shouldRetryDeferredHostBriefing(
    cacheKey: String,
    fingerprint: String,
    currentSkipReason: HostBriefingHostBoardGate.SkipReason?
  ) -> Bool {
    guard currentSkipReason == nil else { return false }
    guard lastRetryableBriefingCacheKey == cacheKey
            || lastRetryableBriefingPacketFingerprint == fingerprint else {
      return false
    }
    return lastRetryableBriefingSkipReason != nil
  }

  private func clearRetryableHostBriefingSkip() {
    lastRetryableBriefingCacheKey = nil
    lastRetryableBriefingPacketFingerprint = nil
    lastRetryableBriefingSkipReason = nil
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
    lastAttentionPresentation = nil
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
    packet: HostLLMPacket,
    presentation: HostAttentionPresentation
  ) -> HostBriefingProviderKind {
    let requested = settings.enhancedBriefingProvider

    if let hostBoardContext {
      if requested == .localModel,
         let skipReason = HostBriefingHostBoardGate.localModelSkipReason(
          settings: settings,
          context: hostBoardContext,
          packet: packet,
          modelEligibleReason: presentation.modelEligibleReason
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
          packet: packet,
          modelEligibleReason: presentation.modelEligibleReason
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

  private func hostBriefingFingerprint(
    packet: HostLLMPacket,
    presentation: HostAttentionPresentation,
    hostBoardContext: HostBriefingHostBoardContext?
  ) -> String {
    let selectedDate = nonBlank(hostBoardContext?.selectedDateKey) ?? latestSelectedDateKey
    let floorSource = nonBlank(hostBoardContext?.floorSourceLabel)
      ?? presentation.floorSourceLabel
    let layout = nonBlank(hostBoardContext?.layoutFingerprint) ?? "layout-unknown"
    let guestGeneration = nonBlank(hostBoardContext?.guestIntelligenceGeneration) ?? "guest-unknown"
    let enrichmentState = hostBoardContext?.enrichmentCompletionState ?? "manual"

    return HostAttentionStableDigest.hexDigest(
      [
        "date=\(selectedDate)",
        "floor=\(floorSource)",
        "layout=\(layout)",
        "guest=\(guestGeneration)",
        "grouped=\(presentation.presentationFingerprint)",
        "actions=\(presentation.primaryActionsFingerprint)",
        "enrichment=\(enrichmentState)",
        "packet=\(packet.briefingFingerprint)"
      ].joined(separator: "|")
    )
  }

  private func nonBlank(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  private func briefingCacheKey(
    fingerprint: String,
    settingsStamp: String,
    hostBoardContext: HostBriefingHostBoardContext?,
    settings: HostIntelligenceSettings,
    packet: HostLLMPacket,
    actionStamp: String,
    presentation: HostAttentionPresentation
  ) -> String {
    if let hostBoardContext {
      let localModelAllowed = HostBriefingHostBoardGate.shouldUseLocalModelOnHostBoard(
        settings: settings,
        context: hostBoardContext,
        packet: packet,
        modelEligibleReason: presentation.modelEligibleReason
      )
      return "\(fingerprint)|\(settingsStamp)|host|\(localModelAllowed)|\(actionStamp)"
    }
    return "\(fingerprint)|\(settingsStamp)|manual|\(actionStamp)"
  }

  private func narrativeActionStamp(
    from snapshot: HostDecisionSnapshot,
    presentation: HostAttentionPresentation
  ) -> String {
    if presentation.hasVisibleContent {
      return presentation.primaryActionsFingerprint
    }
    return HostAttentionStableDigest.hexDigest(
      snapshot.suggestedActions
        .prefix(3)
        .map { "\($0.kind.rawValue):\($0.title)" }
        .joined(separator: ";")
    )
  }

  private func recordHostBoardGateDecision(
    context: HostBriefingHostBoardContext,
    settings: HostIntelligenceSettings,
    packet: HostLLMPacket,
    presentation: HostAttentionPresentation
  ) {
    let skipReason = HostBriefingHostBoardGate.localModelSkipReason(
      settings: settings,
      context: context,
      packet: packet,
      modelEligibleReason: presentation.modelEligibleReason
    )
    HostBoardModelDecisionTrace.record(
      allowed: skipReason == nil,
      skipReason: skipReason,
      packet: packet,
      enrichmentLoading: context.isEnrichmentLoading,
      modelEligibleReason: presentation.modelEligibleReason
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
      if let lastVisibleSourceLabel,
         lastVisibleSourceLabel != visibleSource {
        let changeReason = cacheKey == lastBriefingCacheKey ? "revalidation" : "packet_changed"
        HostAILifecycleTrace.visibleSourceChanged(
          from: lastVisibleSourceLabel,
          to: visibleSource,
          reason: changeReason
        )
      }
      lastVisibleSourceLabel = visibleSource
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
    clearRetryableHostBriefingSkip()
    HostAIRetryTrace.final(packet: fingerprint, source: retryFinalSourceLabel(for: source))
  }

  private func retryFinalSourceLabel(for source: HostBriefingWriterSource) -> String {
    switch source {
    case .localModel, .repairedLocalModel:
      return "localModel"
    case .template, .failedFallback, .localPlaceholder:
      return "fallback"
    }
  }

  private func clearValidModelBriefingCache() {
    lastValidModelBriefingCacheKey = nil
    lastValidModelNarrative = nil
    lastValidModelBriefingText = nil
    lastVisibleSourceLabel = nil
  }

  private func clearBriefingCache() {
    clearValidModelBriefingCache()
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

  private var runtimeSettings: HostIntelligenceSettings {
    settingsStore.settings.effectiveForRole(
      canViewDeveloperDiagnostics: canViewDeveloperDiagnostics
    )
  }
}
