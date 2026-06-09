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

  let settingsStore: HostIntelligenceSettingsStore
  let tableStore: HostTableConfigStore
  private let engine: HostIntelligenceEngine

  private var lastBriefingCacheKey: String?
  private var lastBriefingPacketFingerprint: String?
  private var lastBriefingGeneratedAt: Date?
  private var lastBriefingText: String?
  private var lastBriefingSource: HostBriefingWriterSource?
  private var lastBriefingFailureReason: String?

  init(
    settingsStore: HostIntelligenceSettingsStore? = nil,
    tableStore: HostTableConfigStore? = nil,
    engine: HostIntelligenceEngine = HostIntelligenceEngine()
  ) {
    self.settingsStore = settingsStore ?? HostIntelligenceSettingsStore()
    self.tableStore = tableStore ?? HostTableConfigStore()
    self.engine = engine
  }

  func evaluate(input: HostEngineInput) {
    guard settingsStore.settings.isEnabled else {
      decisionSnapshot = .empty
      clearBriefingCache()
      applyTemplateBriefing(from: .empty)
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
      allKnownReservations: input.allKnownReservations
    )

    decisionSnapshot = engine.evaluateHostDecisionSnapshot(input: enriched)
    applyTemplateBriefing(from: decisionSnapshot)
  }

  /// Presentation-only rewrite of the approved LLM packet. Does not change engine output.
  func refreshBriefing(hostBoardContext: HostBriefingHostBoardContext? = nil) async {
    let fallback = decisionSnapshot.templateBriefingText
    let settings = settingsStore.settings
    let packet = decisionSnapshot.llmPacket
    let fingerprint = packet.briefingFingerprint
    let settingsStamp = briefingSettingsStamp(settings)
    let cacheKey = briefingCacheKey(
      fingerprint: fingerprint,
      settingsStamp: settingsStamp,
      hostBoardContext: hostBoardContext,
      settings: settings,
      packet: packet
    )

    guard settings.isEnabled else {
      clearBriefingCache()
      applyTemplateBriefing(from: .empty)
      return
    }

    if cacheKey == lastBriefingCacheKey,
       let cachedText = lastBriefingText {
      briefingText = cachedText
      briefingSource = lastBriefingSource ?? .template
      briefingFailureReason = lastBriefingFailureReason
      HostIntelligenceDiagnostics.skipBriefing(reason: "same_packet")
      return
    }

    guard settings.useEnhancedBriefing else {
      storeBriefingResult(
        cacheKey: cacheKey,
        fingerprint: fingerprint,
        text: fallback,
        source: .template,
        failureReason: nil
      )
      return
    }

    if hostBoardContext != nil,
       HostBriefingHostBoardGate.shouldUseTemplateOnlyOnHostBoard(packet: packet) {
      HostIntelligenceDiagnostics.skipLocalModel(reason: "host_board_template_only")
      storeBriefingResult(
        cacheKey: cacheKey,
        fingerprint: fingerprint,
        text: fallback,
        source: .template,
        failureReason: nil
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
        failureReason: nil
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
      storeBriefingResult(
        cacheKey: cacheKey,
        fingerprint: fingerprint,
        text: result.text,
        source: result.source,
        failureReason: result.failedReason
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
        ?? "Briefing validation failed."
    )
  }

  func reset() {
    decisionSnapshot = .empty
    clearBriefingCache()
    applyTemplateBriefing(from: .empty)
  }

  private func applyTemplateBriefing(from snapshot: HostDecisionSnapshot) {
    briefingText = snapshot.templateBriefingText
    briefingSource = .template
    briefingFailureReason = nil
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
    packet: HostLLMPacket
  ) -> String {
    if let hostBoardContext {
      let localModelAllowed = HostBriefingHostBoardGate.shouldUseLocalModelOnHostBoard(
        settings: settings,
        context: hostBoardContext,
        packet: packet
      )
      return "\(fingerprint)|\(settingsStamp)|host|\(localModelAllowed)"
    }
    return "\(fingerprint)|\(settingsStamp)|manual"
  }

  private func storeBriefingResult(
    cacheKey: String,
    fingerprint: String,
    text: String,
    source: HostBriefingWriterSource,
    failureReason: String?
  ) {
    briefingText = text
    briefingSource = source
    briefingFailureReason = failureReason
    lastBriefingCacheKey = cacheKey
    lastBriefingPacketFingerprint = fingerprint
    lastBriefingGeneratedAt = Date()
    lastBriefingText = text
    lastBriefingSource = source
    lastBriefingFailureReason = failureReason
  }

  private func clearBriefingCache() {
    lastBriefingCacheKey = nil
    lastBriefingPacketFingerprint = nil
    lastBriefingGeneratedAt = nil
    lastBriefingText = nil
    lastBriefingSource = nil
    lastBriefingFailureReason = nil
  }

  var settings: HostIntelligenceSettings {
    settingsStore.settings
  }
}
