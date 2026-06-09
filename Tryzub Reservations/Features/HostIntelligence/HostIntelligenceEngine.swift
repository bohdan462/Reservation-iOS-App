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

    if context.settings.includeGuestSignals {
      guestSignals = extractAllergySignals(reservations: activeReservations)
      briefingFacts.append(contentsOf: allergyBriefingFacts(from: guestSignals))
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
    briefingFacts.append(contentsOf: noTableFactsAndActions.facts)
    suggestedActions.append(contentsOf: noTableFactsAndActions.actions)
    tableSignals.append(contentsOf: noTableFactsAndActions.tableSignals)

    let rankedFacts = briefingService.rankHostFacts(briefingFacts)
    let pressureScore = calculatePressureScore(
      slotPressures: slotPressures,
      briefingFacts: rankedFacts,
      noTableDueSoonCount: noTableDueSoon.count,
      allergySignalCount: guestSignals.filter { $0.kind == .allergy }.count
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
      bookingDecisions: [],
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
      settings: input.settings
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

  private func calculateCapacityRatio(
    projectedGuests: Int,
    settings: HostIntelligenceSettings
  ) -> Double? {
    guard settings.restaurantCapacity > 0 else { return nil }
    return Double(projectedGuests) / Double(settings.restaurantCapacity)
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
          suggestedActionTitle: "Assign a table before they arrive."
        )
      )

      actions.append(
        HostSuggestedAction(
          id: "assign-table-\(reservation.remoteID)",
          severity: severity,
          kind: .assignTable,
          title: "Assign table for \(reservation.guestName)",
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

  // MARK: - Guest Signals

  private func extractAllergySignals(
    reservations: [ReservationRecord]
  ) -> [HostGuestSignal] {
    reservations.compactMap { reservation in
      let guestNotes = reservation.guestNotes ?? ""
      let staffNotes = reservation.staffNotes ?? ""
      let combined = "\(guestNotes) \(staffNotes)".lowercased()
      guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

      let matched = matchedAllergyKeywords(in: combined)
      guard !matched.isEmpty else { return nil }

      return HostGuestSignal(
        id: "allergy-\(reservation.remoteID)",
        reservationID: reservation.remoteID,
        guestName: reservation.guestName,
        kind: .allergy,
        severity: .critical,
        message: "\(reservation.guestName) has allergy-related notes.",
        evidence: matched
      )
    }
  }

  private func allergyBriefingFacts(from signals: [HostGuestSignal]) -> [HostBriefingFact] {
    signals.map { signal in
      HostBriefingFact(
        id: "allergy-fact-\(signal.reservationID)",
        severity: .critical,
        category: .allergy,
        title: "Allergy note",
        detail: signal.message,
        evidence: signal.evidence,
        relatedReservationIDs: [signal.reservationID],
        suggestedActionTitle: "Review allergy notes before seating."
      )
    }
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
      let capacityRatio = calculateCapacityRatio(
        projectedGuests: projected,
        settings: context.settings
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
            evidence: [
              "projectedGuests=\(projected)",
              "capacity=\(context.settings.restaurantCapacity)"
            ],
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

  // MARK: - Scoring & Classification

  private func calculatePressureScore(
    slotPressures: [HostSlotPressure],
    briefingFacts: [HostBriefingFact],
    noTableDueSoonCount: Int,
    allergySignalCount: Int
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

  private let allergyKeywords = [
    "allergy", "allergic", "shellfish", "shrimp", "crab", "lobster",
    "nuts", "peanut", "gluten", "dairy", "celiac"
  ]

  private let allergyNegationPhrases = [
    "no allergy", "no allergies", "not allergic", "no shellfish allergy"
  ]

  private func matchedAllergyKeywords(in text: String) -> [String] {
    allergyKeywords.filter { keyword in
      guard text.contains(keyword) else { return false }
      return !isNegatedAllergyKeyword(keyword, in: text)
    }
  }

  private func isNegatedAllergyKeyword(_ keyword: String, in text: String) -> Bool {
    if allergyNegationPhrases.contains(where: { phrase in
      text.contains(phrase) && (phrase.contains(keyword) || keyword == "allergy" || keyword == "allergic")
    }) {
      return true
    }

    guard let range = text.range(of: keyword) else { return false }
    let prefix = text[..<range.lowerBound].suffix(8)
    return prefix.hasSuffix("no ") || prefix.hasSuffix("not ")
  }
}
