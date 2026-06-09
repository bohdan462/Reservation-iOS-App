//
//  HostIntelligenceEngine.swift
//  Tryzub Reservations
//
//  Deterministic, read-only Host Intelligence engine.
//  No network, SwiftData writes, UI, timers, or mutations.
//

import Foundation

struct HostIntelligenceEngine {

  private let briefingService = HostBriefingService()

  init() {}

  // MARK: - Public

  func evaluateHostDecisionSnapshot(input: HostEngineInput) -> HostDecisionSnapshot {
    let context = buildServiceDayContext(from: input)
    let slots = buildTimeSlots(context: context)
    let activeReservations = activeReservationsForAnalysis(context: context)
    let grouped = groupReservationsBySlot(
      reservations: activeReservations,
      slots: slots,
      settings: context.settings
    )

    let slotPressures = buildSlotPressures(
      context: context,
      slots: slots,
      grouped: grouped
    )

    let noTableReservations = findReservationsWithoutTables(
      reservations: activeReservations
    )
    let noTableDueSoon = findNoTableDueSoon(
      reservations: noTableReservations,
      now: context.now,
      settings: context.settings
    )

    var briefingFacts = slotPressures.flatMap(\.facts)
    var suggestedActions = slotPressures.flatMap(\.suggestedActions)
    var guestSignals: [HostGuestSignal] = []
    var tableSignals: [HostTableSignal] = []

    var guestMetrics = HostGuestIntelligenceSupport.GuestIntelligenceMetrics(
      allergyCount: 0,
      accessibilityCount: 0,
      previousServiceIssueCount: 0,
      noShowRiskCount: 0,
      cancellationRiskCount: 0,
      regularGuestCount: 0
    )

    if context.settings.includeGuestSignals {
      guestSignals = HostGuestIntelligenceSupport.buildGuestSignals(
        activeReservations: activeReservations,
        allDayReservations: context.reservations,
        allKnownReservations: context.allKnownReservations,
        settings: context.settings
      )
      briefingFacts.append(
        contentsOf: HostGuestIntelligenceSupport.buildGuestBriefingFacts(signals: guestSignals)
      )
      suggestedActions.append(
        contentsOf: HostGuestIntelligenceSupport.buildGuestSuggestedActions(signals: guestSignals)
      )
      guestMetrics = HostGuestIntelligenceSupport.metrics(from: guestSignals)
    }

    let seatedTimingSignals = analyzeSeatedTimingReliability(context: context)
    let longSeated = detectLongSeatedWarnings(context: context)
    tableSignals.append(contentsOf: longSeated.tableSignals)
    briefingFacts.append(contentsOf: longSeated.briefingFacts)

    let noTableFactsAndActions = noTableDueSoonFactsAndActions(
      reservations: noTableDueSoon,
      now: context.now,
      settings: context.settings
    )
    let tableIntelligence = analyzeTableIntelligence(
      context: context,
      noTableReservations: noTableReservations,
      activeReservations: activeReservations
    )
    briefingFacts.append(contentsOf: tableIntelligence.facts)
    suggestedActions.append(contentsOf: tableIntelligence.actions)
    tableSignals.append(contentsOf: tableIntelligence.signals)

    let cancellationIntelligence = HostCancellationIntelligenceSupport.analyze(
      activeReservations: activeReservations,
      allDayReservations: context.reservations,
      tableConfigs: context.tableConfigs,
      now: context.now,
      settings: context.settings
    )

    let filteredNoTable = filterSupersededNoTableOutputs(
      outputs: noTableFactsAndActions,
      overdueReservationIDs: cancellationIntelligence.overdueReservationIDs
    )

    briefingFacts = briefingFacts.filter { fact in
      !shouldReplaceWithOverdueFact(
        fact,
        overdueReservationIDs: cancellationIntelligence.overdueReservationIDs
      )
    }
    suggestedActions = suggestedActions.filter { action in
      !shouldReplaceWithOverdueAction(
        action,
        overdueReservationIDs: cancellationIntelligence.overdueReservationIDs
      )
    }
    tableSignals = tableSignals.filter { signal in
      !shouldReplaceWithOverdueTableSignal(
        signal,
        overdueReservationIDs: cancellationIntelligence.overdueReservationIDs
      )
    }

    briefingFacts.append(contentsOf: filteredNoTable.facts)
    suggestedActions.append(contentsOf: filteredNoTable.actions)
    tableSignals.append(contentsOf: filteredNoTable.tableSignals)

    briefingFacts.append(contentsOf: cancellationIntelligence.facts)
    suggestedActions.append(contentsOf: cancellationIntelligence.actions)
    tableSignals.append(contentsOf: cancellationIntelligence.tableSignals)

    let bookingIntelligence = HostBookingDecisionSupport.analyze(
      activeReservations: activeReservations,
      allDayReservations: context.reservations,
      slotPressures: slotPressures,
      guestSignals: guestSignals,
      tableConfigs: context.tableConfigs,
      availabilitySummary: context.availabilitySummary,
      restaurantSetup: context.restaurantSetup,
      now: context.now,
      selectedDate: context.selectedDate,
      settings: context.settings
    )
    briefingFacts.append(contentsOf: bookingIntelligence.facts)
    suggestedActions.append(contentsOf: bookingIntelligence.actions)
    appendNewReservationsAttentionFacts(
      activeReservations: activeReservations,
      existingFacts: briefingFacts,
      briefingFacts: &briefingFacts,
      suggestedActions: &suggestedActions
    )

    let analyticsIntelligence: HostAnalyticsIntelligenceResult
    if context.settings.includeAnalyticsSignals {
      analyticsIntelligence = HostAnalyticsIntelligenceSupport.analyze(
        slotPressures: slotPressures,
        analyticsSummary: context.analyticsSummary,
        selectedDate: context.selectedDate,
        now: context.now,
        settings: context.settings
      )
      briefingFacts.append(contentsOf: analyticsIntelligence.facts)
      suggestedActions.append(contentsOf: analyticsIntelligence.actions)
    } else {
      analyticsIntelligence = HostAnalyticsIntelligenceResult(
        facts: [],
        actions: [],
        metrics: HostAnalyticsMetrics(
          hasAnalytics: false,
          unusuallyBusySlotCount: 0,
          unusuallyLightSlotCount: 0,
          weekdayPressureSignalCount: 0,
          confidence: 0
        )
      )
    }

    let rankedFacts = briefingService.rankHostFacts(briefingFacts)
    let pressureScore = calculatePressureScore(
      slotPressures: slotPressures,
      briefingFacts: rankedFacts,
      noTableDueSoonCount: noTableDueSoon.filter {
        !cancellationIntelligence.overdueReservationIDs.contains($0.remoteID)
      }.count,
      allergySignalCount: guestMetrics.allergyCount,
      accessibilitySignalCount: guestMetrics.accessibilityCount,
      previousServiceIssueCount: guestMetrics.previousServiceIssueCount,
      noShowRiskCount: guestMetrics.noShowRiskCount,
      cancellationRiskCount: guestMetrics.cancellationRiskCount,
      tableCapacityMismatchCount: tableIntelligence.capacityMismatchCount,
      noSuitableTableCount: tableIntelligence.noSuitableTableCount,
      tableTurnRiskCount: tableIntelligence.turnRiskCount,
      tableFitAvailableCount: tableIntelligence.fitAvailableCount,
      overdueWarningOrCriticalCount: cancellationIntelligence.overdueFactCount,
      lateLargePartyCount: cancellationIntelligence.lateLargePartyCount,
      cancellationOpportunityCount: cancellationIntelligence.cancellationOpportunityCount,
      pastDueCompleteCount: cancellationIntelligence.pastDueCompleteCount,
      bookingManualReviewCriticalCount: bookingIntelligence.manualReviewCriticalCount,
      bookingSuggestAlternateCount: bookingIntelligence.suggestAlternateCount,
      bookingAutoConfirmCount: bookingIntelligence.autoConfirmCount,
      bookingRejectCount: bookingIntelligence.rejectCount,
      analyticsBusyWarningCount: analyticsIntelligence.facts.filter {
        $0.id.hasPrefix("analytics-busy-hour-") && $0.severity == .warning
      }.count,
      analyticsBusyCriticalCount: analyticsIntelligence.facts.filter {
        $0.id.hasPrefix("analytics-busy-hour-") && $0.severity == .critical
      }.count + analyticsIntelligence.facts.filter {
        $0.id.hasPrefix("analytics-weekday-") && $0.severity == .warning
      }.count
    )
    let serviceState = classifyServiceState(pressureScore: pressureScore)
    let templateBriefingText = briefingService.buildTemplateBriefingFallback(
      from: rankedFacts,
      serviceState: serviceState
    )
    let llmPacket = buildLLMPacket(
      facts: rankedFacts,
      serviceState: serviceState,
      pressureScore: pressureScore,
      generatedAt: context.now,
      settings: context.settings
    )

    return HostDecisionSnapshot(
      generatedAt: context.now,
      serviceState: serviceState,
      pressureScore: pressureScore,
      slotPressures: slotPressures,
      briefingFacts: rankedFacts,
      suggestedActions: deduplicatedActions(suggestedActions),
      guestSignals: guestSignals,
      tableSignals: tableSignals,
      seatedTimingSignals: seatedTimingSignals,
      bookingDecisions: bookingIntelligence.decisions,
      templateBriefingText: templateBriefingText,
      llmPacket: llmPacket
    )
  }

  // MARK: - Service Day Context

  private struct ServiceDayContext {
    let now: Date
    let selectedDate: Date
    let reservations: [ReservationRecord]
    let availabilitySummary: ReservationAvailabilitySummary?
    let analyticsSummary: ReservationAnalyticsSummaryDTO?
    let restaurantSetup: RestaurantSetup?
    let localSeatedAtByReservationID: [Int: Date]
    let settings: HostIntelligenceSettings
    let tableConfigs: [RestaurantTableConfig]
    let allKnownReservations: [ReservationRecord]
  }

  private func buildServiceDayContext(from input: HostEngineInput) -> ServiceDayContext {
    let selectedDateKey = input.selectedDate.reservationDateString()
    let dayReservations = input.reservations.filter {
      $0.reservationDate == selectedDateKey && !$0.isHidden
    }

    return ServiceDayContext(
      now: input.now,
      selectedDate: input.selectedDate,
      reservations: dayReservations,
      availabilitySummary: input.availabilitySummary,
      analyticsSummary: input.analyticsSummary,
      restaurantSetup: input.restaurantSetup,
      localSeatedAtByReservationID: input.localSeatedAtByReservationID,
      settings: input.settings,
      tableConfigs: input.tableConfigs,
      allKnownReservations: input.allKnownReservations
    )
  }

  // MARK: - Time Slots

  private func buildTimeSlots(context: ServiceDayContext) -> [Date] {
    let end = context.now.addingTimeInterval(
      TimeInterval(context.settings.lookaheadMinutes * 60)
    )
    let selectedDateKey = context.selectedDate.reservationDateString()

    if let apiSlots = context.availabilitySummary?.slots.slots, !apiSlots.isEmpty {
      let parsed = apiSlots.compactMap { slot -> Date? in
        parseSlotDate(value: slot.value, dateKey: selectedDateKey)
      }
      let filtered = parsed
        .filter { $0 >= context.now && $0 <= end }
        .sorted()
      if !filtered.isEmpty {
        return filtered
      }
    }

    var slots: [Date] = []
    var current = roundDownToSlotInterval(
      context.now,
      intervalMinutes: context.settings.slotIntervalMinutes
    )
    while current <= end {
      slots.append(current)
      current = current.addingTimeInterval(
        TimeInterval(context.settings.slotIntervalMinutes * 60)
      )
    }
    return slots
  }

  // MARK: - Grouping

  private func groupReservationsBySlot(
    reservations: [ReservationRecord],
    slots: [Date],
    settings: HostIntelligenceSettings
  ) -> [Date: [ReservationRecord]] {
    guard !slots.isEmpty else { return [:] }

    let interval = TimeInterval(settings.slotIntervalMinutes * 60)
    var grouped = Dictionary(uniqueKeysWithValues: slots.map { ($0, [ReservationRecord]()) })

    for reservation in reservations {
      guard let serviceDate = reservation.serviceDateTime else { continue }
      guard let slot = slotBucket(for: serviceDate, slots: slots, interval: interval) else {
        continue
      }
      grouped[slot, default: []].append(reservation)
    }

    return grouped
  }

  // MARK: - Seated Counts & Projections

  private func calculateCurrentSeatedGuestCount(reservations: [ReservationRecord]) -> Int {
    reservations
      .filter { shouldCountReservationInAnalysis($0) && isSeatedReservation($0) }
      .reduce(0) { $0 + $1.partySize }
  }

  private func calculateProjectedSeatedGuestsAtSlot(
    slot: Date,
    reservations: [ReservationRecord],
    localSeatedAtByReservationID: [Int: Date],
    settings: HostIntelligenceSettings
  ) -> Int {
    let counted = reservations.filter(shouldCountReservationInAnalysis(_:))
    var projected = calculateCurrentSeatedGuestCount(reservations: counted)

    for reservation in counted where isSeatedReservation(reservation) {
      let turnMinutes = estimatedTurnMinutes(
        partySize: reservation.partySize,
        settings: settings
      )
      if let seatedAt = localSeatedAtByReservationID[reservation.remoteID] {
        let departure = seatedAt.addingTimeInterval(TimeInterval(turnMinutes * 60))
        if departure <= slot {
          projected -= reservation.partySize
        }
      }
    }

    for reservation in counted where isArrivingReservationForProjection(reservation) {
      guard let serviceDate = reservation.serviceDateTime, serviceDate <= slot else { continue }
      projected += reservation.partySize
    }

    return max(projected, 0)
  }

  private struct CapacityBasis {
    let capacity: Int
    let usesTableInventory: Bool
  }

  private func effectiveCapacityBasis(
    settings: HostIntelligenceSettings,
    tableConfigs: [RestaurantTableConfig]
  ) -> CapacityBasis {
    let activeCapacity = tableConfigs
      .filter(\.isActive)
      .reduce(0) { $0 + $1.capacity }
    if activeCapacity > 0 {
      return CapacityBasis(capacity: activeCapacity, usesTableInventory: true)
    }
    return CapacityBasis(capacity: settings.restaurantCapacity, usesTableInventory: false)
  }

  private func calculateCapacityRatio(
    projectedGuests: Int,
    settings: HostIntelligenceSettings,
    tableConfigs: [RestaurantTableConfig]
  ) -> Double? {
    let basis = effectiveCapacityBasis(settings: settings, tableConfigs: tableConfigs)
    guard basis.capacity > 0 else { return nil }
    return Double(projectedGuests) / Double(basis.capacity)
  }

  private func classifyCapacityPressure(
    ratio: Double?,
    settings: HostIntelligenceSettings
  ) -> HostPressureSeverity {
    guard let ratio else { return .calm }

    if ratio >= settings.criticalCapacityRatio {
      return .critical
    }
    if ratio >= settings.comfortableCapacityRatio {
      return .busy
    }
    if ratio >= 0.70 {
      return .watch
    }
    return .calm
  }

  // MARK: - Slot Fact Detectors

  private func detectArrivalWave(
    slot: Date,
    reservations: [ReservationRecord],
    settings: HostIntelligenceSettings
  ) -> HostBriefingFact? {
    let count = reservations.count
    guard count > settings.maxReservationsPerSlot else { return nil }

    let guestCount = reservations.reduce(0) { $0 + $1.partySize }
    let timeLabel = displaySlotTime(slot)
    let ids = reservations.map(\.remoteID)

    return HostBriefingFact(
      id: "arrival-wave-\(slotTimeKey(slot))",
      severity: .warning,
      category: .arrivalWave,
      title: "Arrival wave",
      detail: "\(count) reservations are arriving around \(timeLabel).",
      evidence: [
        "reservations=\(count)",
        "guests=\(guestCount)",
        "threshold=\(settings.maxReservationsPerSlot)"
      ],
      relatedReservationIDs: ids,
      suggestedActionTitle: "Slow down new bookings around this time."
    )
  }

  private func detectLargePartyCollision(
    slot: Date,
    reservations: [ReservationRecord],
    settings: HostIntelligenceSettings
  ) -> HostBriefingFact? {
    let largeParties = reservations.filter { $0.partySize >= settings.largePartyThreshold }
    let largePartyCount = largeParties.count
    guard largePartyCount > settings.maxLargePartiesPerSlot else { return nil }

    let timeLabel = displaySlotTime(slot)
    let partySummaries = largeParties.map { "\($0.guestName) (\($0.partySize))" }
    let ids = largeParties.map(\.remoteID)

    return HostBriefingFact(
      id: "large-party-collision-\(slotTimeKey(slot))",
      severity: .critical,
      category: .largeParty,
      title: "Large-party collision",
      detail: "\(largePartyCount) large parties are arriving around \(timeLabel).",
      evidence: partySummaries + ["threshold=\(settings.maxLargePartiesPerSlot)"],
      relatedReservationIDs: ids,
      suggestedActionTitle: "Require manual review before accepting more bookings in this slot."
    )
  }

  private func detectCriticalSlot(
    slot: Date,
    reservations: [ReservationRecord],
    severity: HostPressureSeverity,
    reservationCount: Int,
    largePartyCount: Int,
    capacityRatio: Double?,
    settings: HostIntelligenceSettings
  ) -> HostSuggestedAction? {
    let tooManyReservations = reservationCount > settings.maxReservationsPerSlot
    let tooManyLargeParties = largePartyCount > settings.maxLargePartiesPerSlot
    let overCriticalCapacity = (capacityRatio ?? 0) >= settings.criticalCapacityRatio

    let isCritical = severity == .critical
      || tooManyReservations
      || tooManyLargeParties
      || overCriticalCapacity

    guard isCritical else { return nil }

    let timeLabel = displaySlotTime(slot)
    var reasons: [String] = []
    if tooManyReservations {
      reasons.append("\(reservationCount) reservations exceed the \(settings.maxReservationsPerSlot)-reservation limit")
    }
    if tooManyLargeParties {
      reasons.append("\(largePartyCount) large parties exceed the \(settings.maxLargePartiesPerSlot)-party limit")
    }
    if overCriticalCapacity, let capacityRatio {
      let percent = Int((capacityRatio * 100).rounded())
      reasons.append("projected capacity is about \(percent)%")
    }
    if severity == .critical, reasons.isEmpty {
      reasons.append("slot pressure is critical")
    }

    return HostSuggestedAction(
      id: "close-slot-\(slotTimeKey(slot))",
      severity: .critical,
      kind: .closeSlot,
      title: "Close \(timeLabel) slot",
      reason: reasons.joined(separator: "; ") + ".",
      relatedReservationIDs: reservations.map(\.remoteID),
      targetSlotTime: apiSlotTimeString(slot),
      targetTableName: nil,
      requiresStaffConfirmation: true
    )
  }

  // MARK: - Table Assignment

  private func findReservationsWithoutTables(
    reservations: [ReservationRecord]
  ) -> [ReservationRecord] {
    reservations.filter { $0.isOpenWork && !$0.hasTableAssignment }
  }

  private func findNoTableDueSoon(
    reservations: [ReservationRecord],
    now: Date,
    settings: HostIntelligenceSettings
  ) -> [ReservationRecord] {
    reservations.filter { reservation in
      guard let serviceDate = reservation.serviceDateTime else { return false }
      let minutesUntil = serviceDate.timeIntervalSince(now) / 60
      if minutesUntil < 0 {
        return abs(minutesUntil) <= Double(settings.noTableDueSoonMinutes)
      }
      return minutesUntil <= Double(settings.noTableDueSoonMinutes)
    }
  }

  private func noTableDueSoonFactsAndActions(
    reservations: [ReservationRecord],
    now: Date,
    settings: HostIntelligenceSettings
  ) -> (facts: [HostBriefingFact], actions: [HostSuggestedAction], tableSignals: [HostTableSignal]) {
    var facts: [HostBriefingFact] = []
    var actions: [HostSuggestedAction] = []
    var tableSignals: [HostTableSignal] = []

    for reservation in reservations {
      let timing = reservation.operationalTimingState(now: now)
      let severity: HostSeverity
      switch timing {
      case .overdue, .dueNow:
        severity = .critical
      case .dueSoon:
        severity = .warning
      case .normal, .none:
        severity = .watch
      }

      let timeLabel = reservation.displayTime
      facts.append(
        HostBriefingFact(
          id: "no-table-due-soon-\(reservation.remoteID)",
          severity: severity,
          category: .table,
          title: "No table assigned",
          detail: "\(reservation.guestName) at \(timeLabel) has no table assigned.",
          evidence: [
            "partySize=\(reservation.partySize)",
            "dueWindowMinutes=\(settings.noTableDueSoonMinutes)"
          ],
          relatedReservationIDs: [reservation.remoteID],
          suggestedActionTitle: "Review table plan before they arrive."
        )
      )

      actions.append(
        HostSuggestedAction(
          id: "assign-table-\(reservation.remoteID)",
          severity: severity,
          kind: .reviewReservation,
          title: "Review table plan for \(reservation.guestName)",
          reason: "Reservation at \(timeLabel) has no table assigned.",
          relatedReservationIDs: [reservation.remoteID],
          targetSlotTime: reservation.reservationTime,
          targetTableName: nil,
          requiresStaffConfirmation: true
        )
      )

      tableSignals.append(
        HostTableSignal(
          id: "no-table-\(reservation.remoteID)",
          tableName: nil,
          kind: .noTableAssigned,
          severity: severity,
          title: "No table assigned",
          detail: "\(reservation.guestName) at \(timeLabel) needs a table.",
          relatedReservationIDs: [reservation.remoteID],
          evidence: ["dueWindowMinutes=\(settings.noTableDueSoonMinutes)"]
        )
      )
    }

    return (facts, actions, tableSignals)
  }

  // MARK: - Seated Timing

  private func analyzeSeatedTimingReliability(
    context: ServiceDayContext
  ) -> [HostSeatedTimingSignal] {
    let seated = context.reservations.filter { $0.statusValue == .seated }

    return seated.map { reservation in
      if let seatedAt = context.localSeatedAtByReservationID[reservation.remoteID] {
        let elapsed = Int(context.now.timeIntervalSince(seatedAt) / 60)
        return HostSeatedTimingSignal(
          id: "seated-timing-\(reservation.remoteID)",
          reservationID: reservation.remoteID,
          guestName: reservation.guestName,
          reliability: .localTimestamp,
          seatedAtDescription: ReservationFormatters.shortTime.string(from: seatedAt),
          elapsedMinutes: max(elapsed, 0),
          message: "Seated timing is based on a local timestamp.",
          confidence: 0.9
        )
      }

      return HostSeatedTimingSignal(
        id: "seated-timing-\(reservation.remoteID)",
        reservationID: reservation.remoteID,
        guestName: reservation.guestName,
        reliability: .unknown,
        seatedAtDescription: nil,
        elapsedMinutes: nil,
        message: "Seated timing is unknown without a local timestamp.",
        confidence: 0.2
      )
    }
  }

  private func detectLongSeatedWarnings(
    context: ServiceDayContext
  ) -> (tableSignals: [HostTableSignal], briefingFacts: [HostBriefingFact]) {
    var tableSignals: [HostTableSignal] = []
    var briefingFacts: [HostBriefingFact] = []

    for reservation in context.reservations where reservation.statusValue == .seated {
      guard let seatedAt = context.localSeatedAtByReservationID[reservation.remoteID] else {
        continue
      }

      let elapsedMinutes = Int(context.now.timeIntervalSince(seatedAt) / 60)
      guard elapsedMinutes >= context.settings.longSeatedWarningMinutes else { continue }

      let tableName = reservation.assignedTableName
      tableSignals.append(
        HostTableSignal(
          id: "long-seated-\(reservation.remoteID)",
          tableName: tableName,
          kind: .longSeated,
          severity: .warning,
          title: "Long-seated table",
          detail: "\(reservation.guestName) has been seated for \(elapsedMinutes) minutes.",
          relatedReservationIDs: [reservation.remoteID],
          evidence: [
            "elapsedMinutes=\(elapsedMinutes)",
            "threshold=\(context.settings.longSeatedWarningMinutes)"
          ]
        )
      )

      briefingFacts.append(
        HostBriefingFact(
          id: "long-seated-fact-\(reservation.remoteID)",
          severity: .warning,
          category: .timing,
          title: "Long-seated party",
          detail: "\(reservation.guestName) has been seated for \(elapsedMinutes) minutes.",
          evidence: [
            "elapsedMinutes=\(elapsedMinutes)",
            "threshold=\(context.settings.longSeatedWarningMinutes)"
          ],
          relatedReservationIDs: [reservation.remoteID],
          suggestedActionTitle: "Check whether the table can turn."
        )
      )
    }

    return (tableSignals, briefingFacts)
  }

  // MARK: - Slot Pressures

  private func buildSlotPressures(
    context: ServiceDayContext,
    slots: [Date],
    grouped: [Date: [ReservationRecord]]
  ) -> [HostSlotPressure] {
    let blockedSlotTimes = blockedSlotTimeSet(context: context)

    return slots.map { slot in
      let reservations = grouped[slot] ?? []
      let reservationCount = reservations.count
      let guestCount = reservations.reduce(0) { $0 + $1.partySize }
      let largePartyCount = reservations.filter {
        $0.partySize >= context.settings.largePartyThreshold
      }.count
      let noTableCount = reservations.filter {
        $0.isOpenWork && !$0.hasTableAssignment
      }.count
      let projected = calculateProjectedSeatedGuestsAtSlot(
        slot: slot,
        reservations: context.reservations,
        localSeatedAtByReservationID: context.localSeatedAtByReservationID,
        settings: context.settings
      )
      let capacityBasis = effectiveCapacityBasis(
        settings: context.settings,
        tableConfigs: context.tableConfigs
      )
      let capacityRatio = calculateCapacityRatio(
        projectedGuests: projected,
        settings: context.settings,
        tableConfigs: context.tableConfigs
      )
      let severity = classifyCapacityPressure(
        ratio: capacityRatio,
        settings: context.settings
      )

      var facts: [HostBriefingFact] = []
      if let arrivalWave = detectArrivalWave(
        slot: slot,
        reservations: reservations,
        settings: context.settings
      ) {
        facts.append(arrivalWave)
      }
      if let largePartyCollision = detectLargePartyCollision(
        slot: slot,
        reservations: reservations,
        settings: context.settings
      ) {
        facts.append(largePartyCollision)
      }
      if let ratio = capacityRatio,
         ratio >= context.settings.comfortableCapacityRatio
      {
        facts.append(
          HostBriefingFact(
            id: "capacity-pressure-\(slotTimeKey(slot))",
            severity: ratio >= context.settings.criticalCapacityRatio ? .critical : .warning,
            category: .capacity,
            title: "Capacity pressure",
            detail: "Projected seated guests around \(displaySlotTime(slot)) are about \(Int((ratio * 100).rounded()))% of capacity.",
            evidence: capacityPressureEvidence(
              projectedGuests: projected,
              basis: capacityBasis
            ),
            relatedReservationIDs: reservations.map(\.remoteID),
            suggestedActionTitle: "Watch walk-ins and table turns around this time."
          )
        )
      }

      var suggestedActions: [HostSuggestedAction] = []
      if let closeSlot = detectCriticalSlot(
        slot: slot,
        reservations: reservations,
        severity: severity,
        reservationCount: reservationCount,
        largePartyCount: largePartyCount,
        capacityRatio: capacityRatio,
        settings: context.settings
      ) {
        suggestedActions.append(closeSlot)
      }

      let slotSeverity = elevatedSlotSeverity(
        base: severity,
        facts: facts,
        isBlocked: blockedSlotTimes.contains(normalizedSlotTime(slot))
      )

      return HostSlotPressure(
        id: "slot-pressure-\(slotTimeKey(slot))",
        slotTime: apiSlotTimeString(slot),
        reservationCount: reservationCount,
        guestCount: guestCount,
        largePartyCount: largePartyCount,
        noTableCount: noTableCount,
        projectedSeatedGuestCount: projected,
        capacityRatio: capacityRatio,
        isBlocked: blockedSlotTimes.contains(normalizedSlotTime(slot)),
        severity: slotSeverity,
        facts: facts,
        suggestedActions: suggestedActions
      )
    }
  }

  // MARK: - Table Intelligence

  private struct TableIntelligenceResult {
    let facts: [HostBriefingFact]
    let actions: [HostSuggestedAction]
    let signals: [HostTableSignal]
    let capacityMismatchCount: Int
    let noSuitableTableCount: Int
    let turnRiskCount: Int
    let fitAvailableCount: Int
  }

  private func analyzeTableIntelligence(
    context: ServiceDayContext,
    noTableReservations: [ReservationRecord],
    activeReservations: [ReservationRecord]
  ) -> TableIntelligenceResult {
    guard !context.tableConfigs.isEmpty else {
      return TableIntelligenceResult(
        facts: [],
        actions: [],
        signals: [],
        capacityMismatchCount: 0,
        noSuitableTableCount: 0,
        turnRiskCount: 0,
        fitAvailableCount: 0
      )
    }

    let fit = detectNoTableFitRecommendations(
      reservations: noTableReservations,
      context: context
    )
    let mismatch = detectAssignedTableCapacityMismatch(
      reservations: activeReservations,
      context: context
    )
    let largeParty = detectLargePartyWithoutFit(
      reservations: activeReservations,
      context: context
    )
    let turnRisk = detectTableTurnRisk(
      context: context
    )

    return TableIntelligenceResult(
      facts: fit.facts + mismatch.facts + largeParty.facts + turnRisk.facts,
      actions: fit.actions + mismatch.actions + largeParty.actions + turnRisk.actions,
      signals: fit.signals + mismatch.signals + largeParty.signals + turnRisk.signals,
      capacityMismatchCount: mismatch.count,
      noSuitableTableCount: fit.noSuitableCount + largeParty.count,
      turnRiskCount: turnRisk.count,
      fitAvailableCount: fit.fitAvailableCount
    )
  }

  private func detectNoTableFitRecommendations(
    reservations: [ReservationRecord],
    context: ServiceDayContext
  ) -> (
    facts: [HostBriefingFact],
    actions: [HostSuggestedAction],
    signals: [HostTableSignal],
    fitAvailableCount: Int,
    noSuitableCount: Int
  ) {
    var facts: [HostBriefingFact] = []
    var actions: [HostSuggestedAction] = []
    var signals: [HostTableSignal] = []
    var fitAvailableCount = 0
    var noSuitableCount = 0

    let largePartyThreshold = context.settings.largePartyThreshold

    for reservation in reservations {
      let partySize = reservation.partySize
      guard HostTableIntelligenceSupport.shouldSurfaceNoTableFitAdvice(
        partySize: partySize,
        largePartyThreshold: largePartyThreshold
      ) else {
        continue
      }

      let options = HostTableIntelligenceSupport.bestTableFitOptions(
        for: reservation,
        tableConfigs: context.tableConfigs,
        limit: 1
      )

      if let best = options.first {
        fitAvailableCount += 1
        let guestName = reservation.guestName
        let detail: String
        let suggestedActionTitle: String
        let actionTitle: String
        let factTitle: String

        if best.isCombination {
          factTitle = "Combined table plan may be needed"
          detail = "Party of \(partySize) for \(guestName) may need a combined table plan."
          suggestedActionTitle = "Review combined table option."
          actionTitle = "Review combined table option"
        } else {
          factTitle = "Large party needs table planning"
          detail = "Party of \(partySize) for \(guestName) needs table planning."
          suggestedActionTitle = "Review table plan for \(guestName)."
          actionTitle = "Review table plan for \(guestName)"
        }

        facts.append(
          HostBriefingFact(
            id: "table-fit-\(reservation.remoteID)",
            severity: .watch,
            category: .largeParty,
            title: factTitle,
            detail: detail,
            evidence: [
              "partySize=\(partySize)",
              "fitQuality=\(best.fitQuality.rawValue)",
              "combination=\(best.isCombination)"
            ],
            relatedReservationIDs: [reservation.remoteID],
            suggestedActionTitle: suggestedActionTitle
          )
        )

        actions.append(
          HostSuggestedAction(
            id: "table-fit-action-\(reservation.remoteID)",
            severity: .watch,
            kind: .reviewReservation,
            title: actionTitle,
            reason: detail,
            relatedReservationIDs: [reservation.remoteID],
            targetSlotTime: reservation.reservationTime,
            targetTableName: nil,
            requiresStaffConfirmation: true
          )
        )

        signals.append(
          HostTableSignal(
            id: "table-fit-signal-\(reservation.remoteID)",
            tableName: nil,
            kind: .noTableAssigned,
            severity: .watch,
            title: factTitle,
            detail: detail,
            relatedReservationIDs: [reservation.remoteID],
            evidence: ["combination=\(best.isCombination)"]
          )
        )
      } else {
        noSuitableCount += 1
        let severity: HostSeverity = partySize >= context.settings.criticalPartyThreshold
          ? .critical
          : .warning
        let guestName = reservation.guestName
        let detail =
          "Party of \(partySize) for \(guestName) has no configured single-table or pair fit."

        facts.append(
          HostBriefingFact(
            id: "no-table-fit-\(reservation.remoteID)",
            severity: severity,
            category: .largeParty,
            title: "No suitable table",
            detail: detail,
            evidence: ["partySize=\(partySize)"],
            relatedReservationIDs: [reservation.remoteID],
            suggestedActionTitle: "Review table plan for \(guestName)."
          )
        )

        actions.append(
          HostSuggestedAction(
            id: "no-table-fit-action-\(reservation.remoteID)",
            severity: severity,
            kind: .reviewReservation,
            title: "Review table plan for \(guestName)",
            reason: detail,
            relatedReservationIDs: [reservation.remoteID],
            targetSlotTime: reservation.reservationTime,
            targetTableName: nil,
            requiresStaffConfirmation: true
          )
        )
      }
    }

    return (facts, actions, signals, fitAvailableCount, noSuitableCount)
  }

  private func detectAssignedTableCapacityMismatch(
    reservations: [ReservationRecord],
    context: ServiceDayContext
  ) -> (
    facts: [HostBriefingFact],
    actions: [HostSuggestedAction],
    signals: [HostTableSignal],
    count: Int
  ) {
    var facts: [HostBriefingFact] = []
    var actions: [HostSuggestedAction] = []
    var signals: [HostTableSignal] = []
    var count = 0

    for reservation in reservations where reservation.isOpenWork && reservation.hasTableAssignment {
      guard let mismatch = HostTableIntelligenceSupport.assignedTableCapacityMismatch(
        for: reservation,
        tableConfigs: context.tableConfigs
      ) else {
        continue
      }

      count += 1
      let tableLabel = HostTableIntelligenceSupport.displayTableNames(
        mismatch.tables.map(\.name)
      )
      let totalCapacity = mismatch.totalCapacity
      let detail = "Assigned table may be too small for party of \(reservation.partySize) at \(tableLabel) (seats \(totalCapacity))."

      facts.append(
        HostBriefingFact(
          id: "table-mismatch-\(reservation.remoteID)",
          severity: .critical,
          category: .table,
          title: "Assigned table may be too small",
          detail: detail,
          evidence: [
            "partySize=\(reservation.partySize)",
            "tableCapacity=\(totalCapacity)"
          ],
          relatedReservationIDs: [reservation.remoteID],
          suggestedActionTitle: "Review table assignment."
        )
      )

      actions.append(
        HostSuggestedAction(
          id: "table-mismatch-action-\(reservation.remoteID)",
          severity: .critical,
          kind: .reviewReservation,
          title: "Review table assignment for \(reservation.guestName)",
          reason: detail,
          relatedReservationIDs: [reservation.remoteID],
          targetSlotTime: reservation.reservationTime,
          targetTableName: tableLabel,
          requiresStaffConfirmation: true
        )
      )

      signals.append(
        HostTableSignal(
          id: "table-mismatch-signal-\(reservation.remoteID)",
          tableName: tableLabel,
          kind: .tableCapacityMismatch,
          severity: .critical,
          title: "Assigned table too small",
          detail: detail,
          relatedReservationIDs: [reservation.remoteID],
          evidence: ["tableCapacity=\(totalCapacity)"]
        )
      )
    }

    return (facts, actions, signals, count)
  }

  private func detectLargePartyWithoutFit(
    reservations: [ReservationRecord],
    context: ServiceDayContext
  ) -> (
    facts: [HostBriefingFact],
    actions: [HostSuggestedAction],
    signals: [HostTableSignal],
    count: Int
  ) {
    var facts: [HostBriefingFact] = []
    var actions: [HostSuggestedAction] = []
    var signals: [HostTableSignal] = []
    var count = 0

    for reservation in reservations where reservation.isExpectedGuest {
      guard reservation.partySize >= context.settings.largePartyThreshold else { continue }
      if reservation.isOpenWork && !reservation.hasTableAssignment {
        continue
      }
      let options = HostTableIntelligenceSupport.bestTableFitOptions(
        for: reservation,
        tableConfigs: context.tableConfigs,
        limit: 1
      )
      guard options.isEmpty else { continue }

      count += 1
      let severity: HostSeverity = reservation.partySize >= context.settings.criticalPartyThreshold
        ? .critical
        : .warning
      let detail = "Party of \(reservation.partySize) for \(reservation.guestName) has no configured single-table or pair fit."

      facts.append(
        HostBriefingFact(
          id: "large-party-no-fit-\(reservation.remoteID)",
          severity: severity,
          category: .largeParty,
          title: "Large party without table fit",
          detail: detail,
          evidence: ["partySize=\(reservation.partySize)"],
          relatedReservationIDs: [reservation.remoteID],
          suggestedActionTitle: "Plan combined seating before confirming more bookings."
        )
      )

      actions.append(
        HostSuggestedAction(
          id: "large-party-no-fit-action-\(reservation.remoteID)",
          severity: severity,
          kind: .reviewReservation,
          title: "Plan seating for \(reservation.guestName)",
          reason: detail,
          relatedReservationIDs: [reservation.remoteID],
          targetSlotTime: reservation.reservationTime,
          targetTableName: nil,
          requiresStaffConfirmation: true
        )
      )

      signals.append(
        HostTableSignal(
          id: "large-party-no-fit-signal-\(reservation.remoteID)",
          tableName: reservation.assignedTableName,
          kind: .tableCapacityMismatch,
          severity: severity,
          title: "Large party without table fit",
          detail: detail,
          relatedReservationIDs: [reservation.remoteID],
          evidence: ["partySize=\(reservation.partySize)"]
        )
      )
    }

    return (facts, actions, signals, count)
  }

  private func detectTableTurnRisk(
    context: ServiceDayContext
  ) -> (
    facts: [HostBriefingFact],
    actions: [HostSuggestedAction],
    signals: [HostTableSignal],
    count: Int
  ) {
    var facts: [HostBriefingFact] = []
    var actions: [HostSuggestedAction] = []
    var signals: [HostTableSignal] = []
    var count = 0

    let seated = context.reservations.filter { $0.statusValue == .seated }

    for reservation in seated {
      guard let tableName = reservation.assignedTableName else { continue }
      guard let seatedAt = context.localSeatedAtByReservationID[reservation.remoteID] else {
        continue
      }

      let turnMinutes = estimatedTurnMinutes(
        partySize: reservation.partySize,
        settings: context.settings
      )
      let estimatedRelease = seatedAt.addingTimeInterval(TimeInterval(turnMinutes * 60))
      let normalizedTable = HostTableIntelligenceSupport.normalizeTableName(tableName)

      let upcomingOnTable = context.reservations
        .filter { other in
          guard other.remoteID != reservation.remoteID else { return false }
          guard other.isOpenWork else { return false }
          guard let otherTable = other.assignedTableName else { return false }
          guard HostTableIntelligenceSupport.normalizeTableName(otherTable) == normalizedTable else {
            return false
          }
          guard let serviceDate = other.serviceDateTime else { return false }
          return serviceDate > context.now
        }
        .sorted {
          ($0.serviceDateTime ?? .distantFuture) < ($1.serviceDateTime ?? .distantFuture)
        }

      guard let nextReservation = upcomingOnTable.first,
            let nextServiceDate = nextReservation.serviceDateTime else {
        continue
      }

      guard estimatedRelease > nextServiceDate else { continue }

      count += 1
      let nextTime = nextReservation.displayTime
      let detail = "\(tableName) may not turn before the \(nextTime) reservation."

      facts.append(
        HostBriefingFact(
          id: "table-turn-risk-\(reservation.remoteID)-\(nextReservation.remoteID)",
          severity: .warning,
          category: .table,
          title: "Table turn risk",
          detail: detail,
          evidence: [
            "estimatedReleaseMinutes=\(turnMinutes)",
            "nextReservationID=\(nextReservation.remoteID)"
          ],
          relatedReservationIDs: [reservation.remoteID, nextReservation.remoteID],
          suggestedActionTitle: "Check table before seating the next party."
        )
      )

      actions.append(
        HostSuggestedAction(
          id: "table-turn-risk-action-\(reservation.remoteID)-\(nextReservation.remoteID)",
          severity: .warning,
          kind: .alertServer,
          title: "Check \(tableName) turn",
          reason: detail,
          relatedReservationIDs: [reservation.remoteID, nextReservation.remoteID],
          targetSlotTime: nextReservation.reservationTime,
          targetTableName: tableName,
          requiresStaffConfirmation: true
        )
      )

      signals.append(
        HostTableSignal(
          id: "table-turn-risk-signal-\(reservation.remoteID)-\(nextReservation.remoteID)",
          tableName: tableName,
          kind: .tableTurnRisk,
          severity: .warning,
          title: "Table turn risk",
          detail: detail,
          relatedReservationIDs: [reservation.remoteID, nextReservation.remoteID],
          evidence: ["nextTime=\(nextTime)"]
        )
      )
    }

    return (facts, actions, signals, count)
  }

  // MARK: - Scoring & Classification

  private func filterSupersededNoTableOutputs(
    outputs: (facts: [HostBriefingFact], actions: [HostSuggestedAction], tableSignals: [HostTableSignal]),
    overdueReservationIDs: Set<Int>
  ) -> (facts: [HostBriefingFact], actions: [HostSuggestedAction], tableSignals: [HostTableSignal]) {
    let facts = outputs.facts.filter { fact in
      !fact.relatedReservationIDs.contains(where: overdueReservationIDs.contains)
    }
    let actions = outputs.actions.filter { action in
      !action.relatedReservationIDs.contains(where: overdueReservationIDs.contains)
    }
    let tableSignals = outputs.tableSignals.filter { signal in
      !signal.relatedReservationIDs.contains(where: overdueReservationIDs.contains)
    }
    return (facts, actions, tableSignals)
  }

  private func shouldReplaceWithOverdueFact(
    _ fact: HostBriefingFact,
    overdueReservationIDs: Set<Int>
  ) -> Bool {
    guard fact.id.hasPrefix("no-table-due-soon-") else { return false }
    return fact.relatedReservationIDs.contains(where: overdueReservationIDs.contains)
  }

  private func shouldReplaceWithOverdueAction(
    _ action: HostSuggestedAction,
    overdueReservationIDs: Set<Int>
  ) -> Bool {
    guard action.id.hasPrefix("assign-table-") else { return false }
    return action.relatedReservationIDs.contains(where: overdueReservationIDs.contains)
  }

  private func shouldReplaceWithOverdueTableSignal(
    _ signal: HostTableSignal,
    overdueReservationIDs: Set<Int>
  ) -> Bool {
    guard signal.id.hasPrefix("no-table-") else { return false }
    return signal.relatedReservationIDs.contains(where: overdueReservationIDs.contains)
  }

  private func calculatePressureScore(
    slotPressures: [HostSlotPressure],
    briefingFacts: [HostBriefingFact],
    noTableDueSoonCount: Int,
    allergySignalCount: Int,
    accessibilitySignalCount: Int,
    previousServiceIssueCount: Int,
    noShowRiskCount: Int,
    cancellationRiskCount: Int,
    tableCapacityMismatchCount: Int,
    noSuitableTableCount: Int,
    tableTurnRiskCount: Int,
    tableFitAvailableCount: Int,
    overdueWarningOrCriticalCount: Int,
    lateLargePartyCount: Int,
    cancellationOpportunityCount: Int,
    pastDueCompleteCount: Int,
    bookingManualReviewCriticalCount: Int,
    bookingSuggestAlternateCount: Int,
    bookingAutoConfirmCount: Int,
    bookingRejectCount: Int,
    analyticsBusyWarningCount: Int,
    analyticsBusyCriticalCount: Int
  ) -> Double {
    let maxRatio = slotPressures.compactMap(\.capacityRatio).max() ?? 0
    let criticalSlotCount = slotPressures.filter { $0.severity == .critical }.count
    let warningFactCount = briefingFacts.filter { $0.severity == .warning }.count
    let criticalFactCount = briefingFacts.filter { $0.severity == .critical }.count

    let raw =
      maxRatio * 40
      + Double(criticalSlotCount) * 15
      + Double(warningFactCount) * 6
      + Double(criticalFactCount) * 10
      + Double(noTableDueSoonCount) * 5
      + Double(allergySignalCount) * 5
      + Double(accessibilitySignalCount) * 4
      + Double(previousServiceIssueCount) * 5
      + Double(noShowRiskCount) * 4
      + Double(cancellationRiskCount) * 3
      + Double(tableCapacityMismatchCount) * 12
      + Double(noSuitableTableCount) * 10
      + Double(tableTurnRiskCount) * 8
      + Double(tableFitAvailableCount) * 2
      + Double(overdueWarningOrCriticalCount) * 6
      + Double(lateLargePartyCount) * 8
      + Double(cancellationOpportunityCount) * 1
      + Double(pastDueCompleteCount) * 2
      + Double(bookingManualReviewCriticalCount) * 6
      + Double(bookingSuggestAlternateCount) * 4
      + Double(bookingAutoConfirmCount) * 1
      + Double(bookingRejectCount) * 8
      + Double(analyticsBusyWarningCount) * 4
      + Double(analyticsBusyCriticalCount) * 6

    return min(max(raw, 0), 100)
  }

  private func classifyServiceState(pressureScore: Double) -> HostServiceState {
    if pressureScore >= 75 { return .critical }
    if pressureScore >= 50 { return .busy }
    if pressureScore >= 25 { return .building }
    return .calm
  }

  private func buildLLMPacket(
    facts: [HostBriefingFact],
    serviceState: HostServiceState,
    pressureScore: Double,
    generatedAt: Date,
    settings: HostIntelligenceSettings
  ) -> HostLLMPacket {
    guard settings.includeLLMPacket else {
      return .empty
    }

    let topFacts = briefingService.rankHostFacts(facts).prefix(5).map {
      briefingService.makeLLMFact(from: $0)
    }
    let empty = HostLLMPacket.empty

    return HostLLMPacket(
      generatedAtDescription: ReservationFormatters.shortTime.string(from: generatedAt),
      serviceState: serviceState,
      pressureScore: pressureScore,
      topFacts: topFacts,
      forbiddenBehaviors: empty.forbiddenBehaviors,
      writingRules: empty.writingRules
    )
  }

  // MARK: - Helpers

  private func capacityPressureEvidence(
    projectedGuests: Int,
    basis: CapacityBasis
  ) -> [String] {
    if basis.usesTableInventory {
      return [
        "projectedGuests=\(projectedGuests)",
        "tableInventoryCapacity=\(basis.capacity)"
      ]
    }
    return [
      "projectedGuests=\(projectedGuests)",
      "settingsCapacity=\(basis.capacity)"
    ]
  }

  private func activeReservationsForAnalysis(context: ServiceDayContext) -> [ReservationRecord] {
    context.reservations.filter(shouldCountReservationInAnalysis(_:))
  }

  private func isSeatedReservation(_ reservation: ReservationRecord) -> Bool {
    reservation.statusValue == .seated
  }

  /// Future/open arrivals only. Seated parties are already in the seated baseline.
  private func isArrivingReservationForProjection(_ reservation: ReservationRecord) -> Bool {
    switch reservation.statusValue {
    case .new, .needsReview, .confirmed:
      return true
    case .seated, .completed, .cancelled, .noShow:
      return false
    }
  }

  private func shouldCountReservationInAnalysis(_ reservation: ReservationRecord) -> Bool {
    !reservation.isHidden && reservation.isExpectedGuest
  }

  private func appendNewReservationsAttentionFacts(
    activeReservations: [ReservationRecord],
    existingFacts: [HostBriefingFact],
    briefingFacts: inout [HostBriefingFact],
    suggestedActions: inout [HostSuggestedAction]
  ) {
    let pending = activeReservations.filter {
      $0.statusValue == .new || $0.statusValue == .needsReview
    }
    guard !pending.isEmpty else { return }
    guard !existingFacts.contains(where: { $0.id == "new-reservations-attention" }) else { return }

    let coveredIDs = Set(
      existingFacts
        .filter { $0.category == .bookingDecision }
        .flatMap(\.relatedReservationIDs)
    )
    let uncovered = pending.filter { !coveredIDs.contains($0.remoteID) }
    guard !uncovered.isEmpty else { return }

    let count = pending.count
    let detail = count == 1
      ? "One new reservation is waiting for staff review."
      : "\(count) new reservations are waiting for staff review."

    briefingFacts.append(
      HostBriefingFact(
        id: "new-reservations-attention",
        severity: .watch,
        category: .bookingDecision,
        title: "New reservations",
        detail: detail,
        evidence: [
          "new=\(pending.filter { $0.statusValue == .new }.count)",
          "needsReview=\(pending.filter { $0.statusValue == .needsReview }.count)"
        ],
        relatedReservationIDs: pending.map(\.remoteID),
        suggestedActionTitle: nil
      )
    )

    suggestedActions.append(
      HostSuggestedAction(
        id: "review-new-reservations",
        severity: .watch,
        kind: .reviewReservation,
        title: "Open New bookings",
        reason: detail,
        relatedReservationIDs: pending.map(\.remoteID),
        targetSlotTime: nil,
        targetTableName: nil,
        requiresStaffConfirmation: true
      )
    )
  }

  private func deduplicatedActions(_ actions: [HostSuggestedAction]) -> [HostSuggestedAction] {
    var seen = Set<String>()
    return actions.filter { action in
      if seen.contains(action.id) { return false }
      seen.insert(action.id)
      return true
    }
  }

  private func elevatedSlotSeverity(
    base: HostPressureSeverity,
    facts: [HostBriefingFact],
    isBlocked: Bool
  ) -> HostPressureSeverity {
    if facts.contains(where: { $0.severity == .critical }) || isBlocked {
      return .critical
    }
    if base == .busy || facts.contains(where: { $0.severity == .warning }) {
      return .busy
    }
    if base == .watch {
      return .watch
    }
    return base
  }

  private func estimatedTurnMinutes(
    partySize: Int,
    settings: HostIntelligenceSettings
  ) -> Int {
    if partySize <= 2 { return 75 }
    if partySize >= settings.largePartyThreshold { return 120 }
    return 90
  }

  private func blockedSlotTimeSet(context: ServiceDayContext) -> Set<String> {
    guard let blocked = context.availabilitySummary?.blockedSlots else { return [] }
    return Set(blocked.map { normalizedSlotTimeString($0.slotTime) })
  }

  private func slotBucket(
    for serviceDate: Date,
    slots: [Date],
    interval: TimeInterval
  ) -> Date? {
    for slot in slots where serviceDate >= slot && serviceDate < slot.addingTimeInterval(interval) {
      return slot
    }
    return nil
  }

  private func roundDownToSlotInterval(_ date: Date, intervalMinutes: Int) -> Date {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    guard let minute = components.minute else { return date }
    let roundedMinute = (minute / intervalMinutes) * intervalMinutes
    var adjusted = components
    adjusted.second = 0
    adjusted.minute = roundedMinute
    return calendar.date(from: adjusted) ?? date
  }

  private func parseSlotDate(value: String, dateKey: String) -> Date? {
    if let date = ReservationFormatters.serverDateTime.date(from: "\(dateKey) \(value)") {
      return date
    }
    let shortTime = value.count >= 5 ? String(value.prefix(5)) : value
    return ReservationFormatters.serverDateMinute.date(from: "\(dateKey) \(shortTime)")
  }

  private func displaySlotTime(_ date: Date) -> String {
    ReservationFormatters.shortTime.string(from: date)
  }

  private func apiSlotTimeString(_ date: Date) -> String {
    ReservationFormatters.apiTime.string(from: date)
  }

  private func slotTimeKey(_ date: Date) -> String {
    apiSlotTimeString(date).replacingOccurrences(of: ":", with: "")
  }

  private func normalizedSlotTime(_ date: Date) -> String {
    normalizedSlotTimeString(apiSlotTimeString(date))
  }

  private func normalizedSlotTimeString(_ value: String) -> String {
    value.count >= 5 ? String(value.prefix(5)) : value
  }
}
