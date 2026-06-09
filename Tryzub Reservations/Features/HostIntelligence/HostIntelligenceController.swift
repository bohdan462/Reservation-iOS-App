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
  func refreshBriefing() async {
    let fallback = decisionSnapshot.templateBriefingText
    let settings = settingsStore.settings

    guard settings.isEnabled else {
      applyTemplateBriefing(from: .empty)
      return
    }

    guard settings.useEnhancedBriefing else {
      applyTemplateBriefing(from: decisionSnapshot)
      return
    }

    let writer = HostBriefingWriterFactory.writer(for: settings.enhancedBriefingProvider)
    let result = await writer.writeBriefing(
      packet: decisionSnapshot.llmPacket,
      fallbackText: fallback
    )

    let validation = HostBriefingWriterValidator.validationResult(
      result.text,
      packet: decisionSnapshot.llmPacket,
      fallbackText: fallback
    )

    if validation.isValid {
      briefingText = result.text
      briefingSource = result.source
      briefingFailureReason = result.failedReason
      return
    }

    briefingText = fallback
    briefingSource = .failedFallback
    briefingFailureReason = validation.reason
      ?? result.failedReason
      ?? "Briefing validation failed."
  }

  func reset() {
    decisionSnapshot = .empty
    applyTemplateBriefing(from: .empty)
  }

  private func applyTemplateBriefing(from snapshot: HostDecisionSnapshot) {
    briefingText = snapshot.templateBriefingText
    briefingSource = .template
    briefingFailureReason = nil
  }

  var settings: HostIntelligenceSettings {
    settingsStore.settings
  }
}
