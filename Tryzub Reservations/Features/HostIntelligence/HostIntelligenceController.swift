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
  /// LOCAL-FIRST-OPS-4A — unified per-date staff intelligence snapshot.
  /// Populated by updateServiceIntelligenceSnapshot(_:); never built in body.
  @Published private(set) var serviceIntelligenceSnapshot: HostServiceIntelligenceSnapshot = .empty
  @Published private(set) var serviceBriefingPacket: HostServiceBriefingPacket = .empty
  /// 4E — validated packet narrative (template or local-model wording).
  /// Built by refreshServiceBriefingNarrative; never built by GlobalServiceIntelligenceView.
  @Published private(set) var serviceBriefingNarrative: HostServiceBriefingNarrative = .empty
  @Published private(set) var serviceIntelligenceSourceFingerprint: String = ""

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
  private var latestEvaluatedServiceIntelSourceFingerprint = ""
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
  private var lastServiceIntelSnapshotFingerprint: String = ""
  private var lastServiceBriefingPacketFingerprint: String = ""
  private var lastNarrativeCacheKey: String = ""
  private var narrativeRefreshGeneration = 0

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

  // MARK: - Date transition readiness API

  /// The date key for which the controller has completed a local evaluate pass.
  var evaluatedSelectedDateKey: String { latestSelectedDateKey }

  /// True when the controller has completed a local evaluate pass for the given date.
  /// HostBoardView uses this to guard card rebuild and enrichment tasks.
  func isEvaluatedForSelectedDate(_ dateKey: String) -> Bool {
    latestSelectedDateKey == dateKey && localEvaluationComplete
  }

  static func serviceIntelligenceSourceFingerprint(
    dateKey: String,
    reservations: [ReservationRecord]
  ) -> String {
    let reservationStamp = reservations
      .filter { $0.reservationDate == dateKey && !$0.isHidden }
      .sorted {
        if $0.remoteID != $1.remoteID { return $0.remoteID < $1.remoteID }
        return $0.id.uuidString < $1.id.uuidString
      }
      .map { reservation -> String in
        let noteHash = HostAttentionStableDigest.hexDigest(
          "\(reservation.guestNotes ?? "")|\(reservation.staffNotes ?? "")"
        )
        return [
          reservation.id.uuidString,
          String(reservation.remoteID),
          reservation.reservationDate,
          reservation.reservationTime,
          String(reservation.partySize),
          reservation.status,
          reservation.tableName ?? "",
          noteHash,
          reservation.confirmedAt ?? "none",
          reservation.confirmationEmailSentAt ?? "none",
          reservation.reminderEmailSentAt ?? "none",
          reservation.rowVersion
        ].joined(separator: ":")
      }
      .joined(separator: "|")
    return HostAttentionStableDigest.hexDigest("\(dateKey)||\(reservationStamp)")
  }

  func isServiceIntelligenceSnapshotCurrent(
    dateKey: String,
    sourceFingerprint: String
  ) -> Bool {
    let current = sourceFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
    guard serviceIntelligenceSnapshot.dateKey == dateKey,
          !current.isEmpty,
          serviceIntelligenceSourceFingerprint == current else {
      #if DEBUG
      print("[SERVICE_INTEL_LIFECYCLE_TRACE] event=snapshot_source_stale date=\(dateKey) stored=\(serviceIntelligenceSourceFingerprint.isEmpty ? "none" : serviceIntelligenceSourceFingerprint) current=\(current.isEmpty ? "none" : current)")
      #endif
      return false
    }
    #if DEBUG
    print("[SERVICE_INTEL_LIFECYCLE_TRACE] event=snapshot_source_current date=\(dateKey) fingerprint=\(String(current.prefix(16)))")
    #endif
    return true
  }

  func isServiceBriefingPacketCurrent(
    dateKey: String,
    sourceFingerprint: String
  ) -> Bool {
    let current = sourceFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
    guard serviceBriefingPacket.dateKey == dateKey,
          serviceBriefingPacket.inputFingerprint != "empty",
          !current.isEmpty,
          serviceIntelligenceSourceFingerprint == current else {
      #if DEBUG
      print("[SERVICE_BRIEFING_PACKET_TRACE] decision=skip reason=stale_source date=\(dateKey)")
      #endif
      return false
    }
    return true
  }

  /// Synchronously clears old-date publishable state when the view's selected date
  /// changes before the debounced evaluate task runs. Mirrors the dateChanged clearing
  /// block inside evaluate(), but callable immediately from onChange(of: selectedDateKey).
  /// Safe/idempotent: no-op when called with the already-evaluated date.
  func beginSelectedDateTransition(to newSelectedDateKey: String) {
    guard newSelectedDateKey != latestSelectedDateKey else { return }
    let previousDateKey = latestSelectedDateKey
    briefingRefreshGeneration += 1
    clearAttentionPreservation()
    clearValidModelBriefingCache()
    decisionSnapshot = .empty
    attentionPresentation = .empty
    applyTemplateBriefing(from: .empty, presentation: .empty)
    localEvaluationComplete = false
    isEnrichmentLoading = false
    latestEvaluatedServiceIntelSourceFingerprint = ""
    clearStaffBriefingState()
    clearServiceIntelligenceSnapshotForDateTransition(
      oldDateKey: previousDateKey,
      newDateKey: newSelectedDateKey
    )
    #if DEBUG
    print("[HOST_CARD_STALE_GUARD_TRACE] event=date_transition_begin from=\(previousDateKey) to=\(newSelectedDateKey)")
    #endif
  }

  /// LOCAL-FIRST-OPS-4A/4B — Build or skip unified per-date intelligence snapshot.
  ///
  /// Called from HostBoardView.rebuildServiceBriefing() after serviceBriefingState
  /// is set (so serviceMode is accurate). Guards:
  ///  1. Requires controller to have completed a local evaluate pass for the selected
  ///     date (same safety pattern as the Host card task). Prevents building from an
  ///     .empty HostDecisionSnapshot right after a date switch.
  ///  2. Skip-gated by FNV-1a fingerprint of all meaningful inputs.
  /// Emits [SERVICE_INTEL_SNAPSHOT_TRACE] on build and skip.
  func updateServiceIntelligenceSnapshot(
    _ input: HostServiceIntelligenceSnapshotBuilder.Input,
    sourceFingerprint: String
  ) {
    // Guard 1: evaluate must have completed for this date.
    guard isEvaluatedForSelectedDate(input.dateKey) else {
      #if DEBUG
      print("[SERVICE_INTEL_SNAPSHOT_TRACE] decision=skip reason=awaiting_evaluate date=\(input.dateKey)")
      #endif
      return
    }
    // Guard 2: fingerprint skip if inputs unchanged.
    let fingerprint = HostServiceIntelligenceSnapshotBuilder.inputFingerprint(input)
    let normalizedSourceFingerprint = sourceFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedSourceFingerprint.isEmpty,
          normalizedSourceFingerprint == latestEvaluatedServiceIntelSourceFingerprint else {
      #if DEBUG
      print("[SERVICE_INTEL_SNAPSHOT_TRACE] decision=skip reason=source_awaiting_evaluate date=\(input.dateKey)")
      #endif
      return
    }
    let sourceFingerprintChanged = normalizedSourceFingerprint != serviceIntelligenceSourceFingerprint
    guard fingerprint != lastServiceIntelSnapshotFingerprint || sourceFingerprintChanged else {
      #if DEBUG
      print("[SERVICE_INTEL_SNAPSHOT_TRACE] decision=skip reason=fingerprint_unchanged date=\(input.dateKey)")
      #endif
      return
    }
    lastServiceIntelSnapshotFingerprint = fingerprint
    if serviceIntelligenceSourceFingerprint != normalizedSourceFingerprint {
      serviceIntelligenceSourceFingerprint = normalizedSourceFingerprint
    }
    serviceIntelligenceSnapshot = HostServiceIntelligenceSnapshotBuilder.build(input)
  }

  func updateServiceBriefingPacket(
    _ input: HostServiceBriefingPacketBuilder.Input
  ) {
    guard isEvaluatedForSelectedDate(input.dateKey) else {
      #if DEBUG
      print("[SERVICE_BRIEFING_PACKET_TRACE] decision=skip reason=awaiting_evaluate date=\(input.dateKey) facts=0 compact=\"\"")
      #endif
      return
    }
    let normalizedSourceFingerprint = input.sourceFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedSourceFingerprint.isEmpty,
          normalizedSourceFingerprint == serviceIntelligenceSourceFingerprint else {
      #if DEBUG
      print("[SERVICE_BRIEFING_PACKET_TRACE] decision=skip reason=source_not_current date=\(input.dateKey) facts=0 compact=\"\"")
      #endif
      return
    }
    guard serviceIntelligenceSnapshot.dateKey == input.dateKey,
          serviceIntelligenceSnapshot.inputFingerprint != "empty",
          serviceIntelligenceSnapshot.inputFingerprint == input.serviceSnapshot.inputFingerprint else {
      #if DEBUG
      print("[SERVICE_BRIEFING_PACKET_TRACE] decision=skip reason=snapshot_not_current date=\(input.dateKey) facts=0 compact=\"\"")
      #endif
      return
    }
    let fingerprint = HostServiceBriefingPacketBuilder.inputFingerprint(input)
    guard fingerprint != lastServiceBriefingPacketFingerprint else {
      #if DEBUG
      print("[SERVICE_BRIEFING_PACKET_TRACE] decision=skip reason=fingerprint_unchanged date=\(input.dateKey) facts=\(serviceBriefingPacket.facts.count) compact=\"\(serviceBriefingPacket.compactLine)\"")
      #endif
      return
    }

    let packet = HostServiceBriefingPacketBuilder.build(input)
    lastServiceBriefingPacketFingerprint = packet.inputFingerprint
    serviceBriefingPacket = packet
    #if DEBUG
    print("[SERVICE_BRIEFING_PACKET_TRACE] decision=build date=\(packet.dateKey) facts=\(packet.facts.count) compact=\"\(packet.compactLine)\"")
    #endif
  }

  // MARK: - 4E Packet narrative

  /// Returns true when the cached narrative is current for the given packet fingerprint and date.
  func isServiceBriefingNarrativeCurrent(dateKey: String, packetFingerprint: String) -> Bool {
    serviceBriefingNarrative.isCurrent(dateKey: dateKey, packetFingerprint: packetFingerprint)
  }

  /// Builds a cache key for the narrative pass.
  private func narrativeCacheKey(
    packet: HostServiceBriefingPacket,
    sourceFingerprint: String,
    settings: HostIntelligenceSettings
  ) -> String {
    [
      packet.inputFingerprint,
      sourceFingerprint,
      HostServiceBriefingNarrativePromptBuilder.promptVersion,
      settings.useEnhancedBriefing ? "1" : "0",
      settings.enhancedBriefingProvider.rawValue,
      settings.useLocalModelOnHostBoard ? "1" : "0",
    ].joined(separator: "|")
  }

  /// 4E async narrative refresh. Called from HostBoardView after updateServiceBriefingPacket
  /// builds a new packet. Global SI must never call this.
  func refreshServiceBriefingNarrative(
    packet: HostServiceBriefingPacket,
    sourceFingerprint: String,
    serviceDateLabel: String?,
    gateContext: HostServiceBriefingNarrativeGate.Context
  ) async {
    narrativeRefreshGeneration += 1
    let generation = narrativeRefreshGeneration
    let settings = settingsStore.settings

    // Cache check — skip if nothing changed
    let cacheKey = narrativeCacheKey(
      packet: packet,
      sourceFingerprint: sourceFingerprint,
      settings: settings
    )
    guard cacheKey != lastNarrativeCacheKey else {
      #if DEBUG
      print("[SERVICE_BRIEFING_NARRATIVE_TRACE] decision=skip reason=cache_hit date=\(packet.dateKey) fingerprint=\(packet.inputFingerprint.prefix(12))")
      #endif
      return
    }

    let writerInput = HostServiceBriefingNarrativeWriter.Input(
      packet: packet,
      sourceFingerprint: sourceFingerprint,
      settings: settings,
      gateContext: gateContext,
      serviceDateLabel: serviceDateLabel
    )

    let result = await HostServiceBriefingNarrativeWriter.write(writerInput)

    // Stale-generation guard (date or packet may have changed while model was running)
    guard generation == narrativeRefreshGeneration,
          result.dateKey == latestSelectedDateKey,
          result.packetFingerprint == serviceBriefingPacket.inputFingerprint else {
      #if DEBUG
      print("[SERVICE_BRIEFING_NARRATIVE_TRACE] decision=skip reason=stale_result date=\(result.dateKey) expected=\(latestSelectedDateKey)")
      #endif
      return
    }

    lastNarrativeCacheKey = cacheKey
    serviceBriefingNarrative = result
    #if DEBUG
    print("[SERVICE_BRIEFING_NARRATIVE_TRACE] decision=stored source=\(result.source.rawValue) date=\(result.dateKey) fingerprint=\(result.packetFingerprint.prefix(12)) compact=\"\(result.compactLine.prefix(60))\"")
    #endif
  }

  // MARK: - 4F On-demand staff briefing

  /// UI-facing state for the on-demand staff briefing surface. Only mutated by
  /// requestStaffBriefing; never auto-generated on packet rebuild.
  @Published private(set) var staffBriefingDisplayState: StaffBriefingDisplayState = .none
  /// Last generated result (any mode). Retained across date transitions only until cleared.
  @Published private(set) var staffBriefingLastResult: StaffBriefingResult?

  private var staffBriefingCache: [StaffBriefingCacheKey: StaffBriefingResult] = [:]
  private var staffBriefingRefreshGeneration = 0

  /// Human-readable label for the best available model profile (diagnostics only).
  var staffBriefingModelProfileLabel: String {
    HostLocalModelFileLocator.bestAvailableProfile().rawValue
  }

  private func staffBriefingCacheKey(
    mode: StaffBriefingMode,
    dateKey: String,
    packetFingerprint: String,
    sourceFingerprint: String
  ) -> StaffBriefingCacheKey {
    StaffBriefingCacheKey(
      mode: mode,
      dateKey: dateKey,
      packetFingerprint: packetFingerprint,
      sourceFingerprint: sourceFingerprint,
      promptVersion: StaffBriefingPromptBuilder.promptVersion,
      settingsStamp: briefingSettingsStamp(runtimeSettings)
    )
  }

  /// Pure lookup used by the UI to decide what to show without triggering generation.
  /// Cache hit → .current; same mode/date but changed inputs → .stale; otherwise .none.
  func staffBriefingDisplayState(
    for mode: StaffBriefingMode,
    dateKey: String,
    packetFingerprint: String,
    sourceFingerprint: String
  ) -> StaffBriefingDisplayState {
    if staffBriefingDisplayState.isGenerating,
       case .generating(let activeMode) = staffBriefingDisplayState,
       activeMode == mode {
      return staffBriefingDisplayState
    }
    let key = staffBriefingCacheKey(
      mode: mode,
      dateKey: dateKey,
      packetFingerprint: packetFingerprint,
      sourceFingerprint: sourceFingerprint
    )
    if let hit = staffBriefingCache[key] {
      return .current(hit)
    }
    if let stale = staleStaffBriefingResult(mode: mode, dateKey: dateKey, currentKey: key) {
      return .stale(stale, reason: "inputs_changed")
    }
    return .none
  }

  /// Finds a prior result for the same mode + date whose fingerprint/settings differ.
  private func staleStaffBriefingResult(
    mode: StaffBriefingMode,
    dateKey: String,
    currentKey: StaffBriefingCacheKey
  ) -> StaffBriefingResult? {
    staffBriefingCache
      .filter { $0.key.mode == mode && $0.key.dateKey == dateKey && $0.key != currentKey }
      .sorted { $0.value.generatedAt > $1.value.generatedAt }
      .first?
      .value
  }

  /// On-demand full staff briefing generation. MUST only be called from an explicit
  /// user action (never on packet rebuild). Uses the current packet/snapshot state
  /// plus caller-supplied deterministic reservation summaries for counts/tomorrow.
  func requestStaffBriefing(
    mode: StaffBriefingMode,
    dateKey requestedDateKey: String? = nil,
    serviceMode requestedServiceMode: ServiceMode? = nil,
    sourceFingerprint requestedSourceFingerprint: String? = nil,
    dayReservations: [ReservationRecord] = [],
    tomorrowReservations: [ReservationRecord] = [],
    businessSummaryLines: [String] = [],
    serviceDateLabel: String? = nil,
    largePartyThreshold: Int = 7,
    forceRefresh: Bool = false
  ) async {
    let storedPacket = serviceBriefingPacket
    let normalizedDateKey = requestedDateKey?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let dateKey = normalizedDateKey.isEmpty
      ? (latestSelectedDateKey.isEmpty ? storedPacket.dateKey : latestSelectedDateKey)
      : normalizedDateKey
    let normalizedSourceFingerprint = requestedSourceFingerprint?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let sourceFingerprint = normalizedSourceFingerprint.isEmpty
      ? serviceIntelligenceSourceFingerprint
      : normalizedSourceFingerprint
    let packet = storedPacket.dateKey == dateKey || storedPacket.inputFingerprint == "empty"
      ? storedPacket
      : .empty
    let serviceMode = requestedServiceMode
      ?? (packet.inputFingerprint == "empty" ? serviceModeFallback(for: mode) : packet.serviceMode)
    let hasExplicitDateKey = !normalizedDateKey.isEmpty

    #if DEBUG
    print("[STAFF_BRIEFING_TRACE] decision=request mode=\(mode.rawValue) date=\(dateKey) force=\(forceRefresh)")
    #endif

    let cacheKey = staffBriefingCacheKey(
      mode: mode,
      dateKey: dateKey,
      packetFingerprint: packet.inputFingerprint,
      sourceFingerprint: sourceFingerprint
    )

    if !forceRefresh, let cached = staffBriefingCache[cacheKey] {
      staffBriefingLastResult = cached
      staffBriefingDisplayState = .current(cached)
      #if DEBUG
      print("[STAFF_BRIEFING_TRACE] decision=cache_hit mode=\(mode.rawValue) source=\(cached.source.rawValue)")
      #endif
      return
    }

    #if DEBUG
    if staleStaffBriefingResult(mode: mode, dateKey: dateKey, currentKey: cacheKey) != nil {
      print("[STAFF_BRIEFING_TRACE] decision=stale mode=\(mode.rawValue) reason=regenerating")
    }
    #endif
    staffBriefingDisplayState = .generating(mode: mode)

    staffBriefingRefreshGeneration += 1
    let generation = staffBriefingRefreshGeneration

    let builtPacket = StaffBriefingPacketBuilder.build(
      StaffBriefingPacketBuilder.Input(
        mode: mode,
        dateKey: dateKey,
        now: Date(),
        serviceMode: serviceMode,
        sourceFingerprint: sourceFingerprint,
        servicePacket: packet,
        dayReservations: dayReservations,
        tomorrowReservations: tomorrowReservations,
        businessSummaryLines: businessSummaryLines,
        largePartyThreshold: largePartyThreshold
      )
    )

    let writerInput = StaffBriefingWriter.Input(
      packet: builtPacket,
      settings: runtimeSettings,
      gateContext: StaffBriefingGate.Context(
        isLocalModelInferenceActive: HostLocalModelInferenceTracker.isActive
      ),
      serviceDateLabel: serviceDateLabel,
      cacheKey: cacheKey
    )

    let result = await StaffBriefingWriter.write(writerInput)

    // Discard results that finished after a date change or a newer request superseded us.
    guard generation == staffBriefingRefreshGeneration,
          hasExplicitDateKey || cacheKey.dateKey == latestSelectedDateKey || latestSelectedDateKey.isEmpty else {
      #if DEBUG
      print("[STAFF_BRIEFING_TRACE] decision=discard_stale_result mode=\(mode.rawValue) date=\(cacheKey.dateKey) expected=\(latestSelectedDateKey)")
      #endif
      return
    }

    staffBriefingCache[cacheKey] = result
    staffBriefingLastResult = result
    staffBriefingDisplayState = .current(result)
    #if DEBUG
    if result.source == .localModel {
      print("[STAFF_BRIEFING_TRACE] decision=model_accept mode=\(mode.rawValue) words=\(result.wordCount)")
    } else {
      print("[STAFF_BRIEFING_TRACE] decision=fallback mode=\(mode.rawValue) source=\(result.source.rawValue) reason=\(result.failedReason ?? "template")")
    }
    #endif
  }

  /// Clears staff briefing state (date transition / reset). Bumps the generation
  /// token so any in-flight generation is discarded on completion.
  private func clearStaffBriefingState() {
    staffBriefingRefreshGeneration += 1
    staffBriefingCache.removeAll()
    staffBriefingLastResult = nil
    staffBriefingDisplayState = .none
  }

  private func serviceModeFallback(for mode: StaffBriefingMode) -> ServiceMode {
    switch mode {
    case .preService:  return .beforeService
    case .liveService: return .duringService
    case .closingRecap: return .afterCloseFinished
    }
  }

  func evaluate(
    input: HostEngineInput,
    stability: HostEvaluationStabilityContext,
    bookingLoadReport: BookingLoadReport? = nil
  ) {
    latestStabilityContext = stability
    let selectedDateKey = input.selectedDate.reservationDateString()
    let evaluatedSourceFingerprint = HostIntelligenceController.serviceIntelligenceSourceFingerprint(
      dateKey: selectedDateKey,
      reservations: input.reservations
    )
    let dateChanged = !latestSelectedDateKey.isEmpty && latestSelectedDateKey != selectedDateKey
    if dateChanged {
      let previousDateKey = latestSelectedDateKey
      briefingRefreshGeneration += 1
      clearAttentionPreservation()
      clearValidModelBriefingCache()
      decisionSnapshot = .empty
      attentionPresentation = .empty
      applyTemplateBriefing(from: .empty, presentation: .empty)
      localEvaluationComplete = false
      isEnrichmentLoading = false
      latestEvaluatedServiceIntelSourceFingerprint = ""
      clearServiceIntelligenceSnapshotForDateTransition(
        oldDateKey: previousDateKey,
        newDateKey: selectedDateKey
      )
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
      latestEvaluatedServiceIntelSourceFingerprint = evaluatedSourceFingerprint
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
    latestEvaluatedServiceIntelSourceFingerprint = evaluatedSourceFingerprint
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
  ///
  /// - Parameter allowLocalModelNarrative: When false, skips the legacy ManagerNarrativeWriter
  ///   local model branch. Pass false for live Service Intelligence paths where packet narrative
  ///   owns the wording to prevent two simultaneous local model calls.
  func refreshBriefing(
    hostBoardContext: HostBriefingHostBoardContext? = nil,
    bookingLoadReport: BookingLoadReport? = nil,
    allowLocalModelNarrative: Bool = true
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
      // 4E-3: Skip legacy ManagerNarrativeWriter model when packet narrative owns SI wording.
      // allowLocalModelNarrative is false for live Host paths where serviceBriefingNarrative
      // takes over, preventing two simultaneous local model calls.
      guard allowLocalModelNarrative else {
        #if DEBUG
        print("[HOST_AI] legacy_model_skipped reason=packet_service_briefing_narrative_active date=\(latestSelectedDateKey)")
        #endif
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
    // If the model is mid-generation during a full reset, discard any in-flight
    // result (bump the generation guard) and log the cancellation. The llama
    // runtime itself is not force-killed, but its output can no longer reach UI.
    if HostLocalModelInferenceTracker.isActive {
      briefingRefreshGeneration += 1
      HostAILifecycleTrace.modelCancelled(reason: "full_reset")
    }
    decisionSnapshot = .empty
    attentionPresentation = .empty
    clearAttentionPreservation()
    clearBriefingCache()
    applyTemplateBriefing(from: .empty, presentation: .empty)
    renderState = .evaluating
    localEvaluationComplete = false
    isEnrichmentLoading = false
    serviceIntelligenceSnapshot = .empty
    serviceBriefingPacket = .empty
    serviceBriefingNarrative = .empty
    serviceIntelligenceSourceFingerprint = ""
    lastServiceIntelSnapshotFingerprint = ""
    lastServiceBriefingPacketFingerprint = ""
    lastNarrativeCacheKey = ""
    narrativeRefreshGeneration += 1
    clearStaffBriefingState()
    latestEvaluatedServiceIntelSourceFingerprint = ""
    latestSelectedDateKey = ""
  }

  /// Clears transient Host presentation/loading state when the Host Board is hidden,
  /// while preserving the canonical service-day snapshot and evaluated-date marker
  /// for other surfaces such as More → Service Intelligence.
  func resetVolatilePresentation(reason: String) {
    if HostLocalModelInferenceTracker.isActive {
      briefingRefreshGeneration += 1
      HostAILifecycleTrace.modelCancelled(reason: reason)
    }
    isEnrichmentLoading = false
    renderState = localEvaluationComplete ? .ready : .evaluating
    #if DEBUG
    let snapshotDate = serviceIntelligenceSnapshot.dateKey.isEmpty
      ? "none"
      : serviceIntelligenceSnapshot.dateKey
    let hasSnapshot = serviceIntelligenceSnapshot.inputFingerprint != "empty"
    print(
      "[SERVICE_INTEL_LIFECYCLE_TRACE] event=preserve_snapshot_on_hide " +
      "date=\(latestSelectedDateKey.isEmpty ? "none" : latestSelectedDateKey) " +
      "snapshotDate=\(snapshotDate) hasSnapshot=\(hasSnapshot) reason=\(reason)"
    )
    let packetDate = serviceBriefingPacket.dateKey.isEmpty ? "none" : serviceBriefingPacket.dateKey
    let hasPacket = serviceBriefingPacket.inputFingerprint != "empty"
    print(
      "[SERVICE_BRIEFING_PACKET_TRACE] decision=preserve reason=view_hidden " +
      "date=\(latestSelectedDateKey.isEmpty ? "none" : latestSelectedDateKey) " +
      "packetDate=\(packetDate) hasPacket=\(hasPacket)"
    )
    // 4E: narrative is preserved on hide (packet preserved → narrative remains current)
    print("[SERVICE_BRIEFING_NARRATIVE_TRACE] decision=preserve reason=view_hidden date=\(latestSelectedDateKey.isEmpty ? "none" : latestSelectedDateKey) hasNarrative=\(serviceBriefingNarrative.hasUsableCopy)")
    #endif
  }

  private func clearServiceIntelligenceSnapshotForDateTransition(
    oldDateKey: String,
    newDateKey: String
  ) {
    let hadSnapshot = serviceIntelligenceSnapshot.inputFingerprint != "empty"
      && !serviceIntelligenceSnapshot.dateKey.isEmpty
    let hadPacket = serviceBriefingPacket.inputFingerprint != "empty"
      && !serviceBriefingPacket.dateKey.isEmpty
    let hadNarrative = serviceBriefingNarrative.hasUsableCopy
    serviceIntelligenceSnapshot = .empty
    serviceBriefingPacket = .empty
    serviceBriefingNarrative = .empty
    serviceIntelligenceSourceFingerprint = ""
    lastServiceIntelSnapshotFingerprint = ""
    lastServiceBriefingPacketFingerprint = ""
    lastNarrativeCacheKey = ""
    narrativeRefreshGeneration += 1
    latestEvaluatedServiceIntelSourceFingerprint = ""
    #if DEBUG
    if hadSnapshot {
      print("[SERVICE_INTEL_LIFECYCLE_TRACE] event=clear_snapshot_on_date_transition old=\(oldDateKey.isEmpty ? "none" : oldDateKey) new=\(newDateKey)")
    }
    if hadPacket {
      print("[SERVICE_BRIEFING_PACKET_TRACE] decision=clear reason=date_transition old=\(oldDateKey.isEmpty ? "none" : oldDateKey) new=\(newDateKey)")
    }
    if hadNarrative {
      print("[SERVICE_BRIEFING_NARRATIVE_TRACE] decision=clear reason=date_transition old=\(oldDateKey.isEmpty ? "none" : oldDateKey) new=\(newDateKey)")
    }
    #endif
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
