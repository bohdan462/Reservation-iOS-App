//
//  HostBookingDecisionSupport.swift
//  Tryzub Reservations
//
//  Deterministic booking decision recommendations for incoming reservations.
//  Read-only — staff confirm through existing reservation workflows.
//

import Foundation

struct HostBookingDecisionAnalysisResult {
  let decisions: [HostBookingDecisionResult]
  let facts: [HostBriefingFact]
  let actions: [HostSuggestedAction]
  let manualReviewCriticalCount: Int
  let suggestAlternateCount: Int
  let autoConfirmCount: Int
  let rejectCount: Int
}

enum HostBookingDecisionSupport {

  private static let maxBookingFacts = 5

  // MARK: - Public

  static func analyze(
    activeReservations: [ReservationRecord],
    allDayReservations: [ReservationRecord],
    slotPressures: [HostSlotPressure],
    guestSignals: [HostGuestSignal],
    tableConfigs: [RestaurantTableConfig],
    availabilitySummary: ReservationAvailabilitySummary?,
    restaurantSetup: RestaurantSetup?,
    now: Date,
    selectedDate: Date,
    settings: HostIntelligenceSettings
  ) -> HostBookingDecisionAnalysisResult {
    guard settings.enableBookingDecisioning else {
      return emptyResult
    }

    let candidates = bookingCandidates(from: activeReservations)
    guard !candidates.isEmpty else {
      return emptyResult
    }

    let blockedSlots = blockedSlotTimeSet(from: availabilitySummary)
    let pressureBySlot = slotPressureIndex(slotPressures)
    let signalsByReservation = guestSignalsByReservationID(guestSignals)

    var decisions: [HostBookingDecisionResult] = []
    var facts: [HostBriefingFact] = []
    var actions: [HostSuggestedAction] = []

    for reservation in candidates {
      let decision = decide(
        reservation: reservation,
        slotPressures: slotPressures,
        pressureBySlot: pressureBySlot,
        blockedSlots: blockedSlots,
        guestSignals: signalsByReservation[reservation.remoteID] ?? [],
        tableConfigs: tableConfigs,
        availabilitySummary: availabilitySummary,
        restaurantSetup: restaurantSetup,
        now: now,
        selectedDate: selectedDate,
        settings: settings
      )

      guard decision.decision != .noDecision else { continue }

      decisions.append(decision)

      if let fact = makeFact(for: decision, reservation: reservation, settings: settings) {
        facts.append(fact)
      }
      if let action = makeAction(for: decision, reservation: reservation, settings: settings) {
        actions.append(action)
      }
    }

    let rankedFacts = Array(rankFacts(facts).prefix(maxBookingFacts))
    let topReservationIDs = Set(rankedFacts.flatMap(\.relatedReservationIDs))
    let filteredDecisions = decisions.filter { decision in
      guard let reservationID = decision.reservationID else { return false }
      return topReservationIDs.contains(reservationID)
    }
    let alignedActions = deduplicatedActions(
      actions.filter { action in
        action.relatedReservationIDs.contains(where: topReservationIDs.contains)
      }
    )

    return HostBookingDecisionAnalysisResult(
      decisions: filteredDecisions,
      facts: rankedFacts,
      actions: alignedActions,
      manualReviewCriticalCount: decisions.filter {
        $0.decision == .manualReview && factSeverity(for: $0).rank <= HostSeverity.warning.rank
      }.count + decisions.filter { $0.decision == .reject }.count,
      suggestAlternateCount: decisions.filter { $0.decision == .suggestAlternateTime }.count,
      autoConfirmCount: decisions.filter { $0.decision == .autoConfirm }.count,
      rejectCount: decisions.filter { $0.decision == .reject }.count
    )
  }

  static func findAlternateSlot(
    for reservation: ReservationRecord,
    slotPressures: [HostSlotPressure],
    availabilitySummary: ReservationAvailabilitySummary?,
    restaurantSetup: RestaurantSetup?,
    settings: HostIntelligenceSettings,
    now: Date,
    selectedDate: Date
  ) -> String? {
    guard settings.suggestAlternateTimesEnabled else { return nil }

    let requestedTime = normalizedSlotTime(reservation.reservationTime)
    let blockedSlots = blockedSlotTimeSet(from: availabilitySummary)
    let pressureBySlot = slotPressureIndex(slotPressures)
    let candidateSlots = candidateSlotTimes(
      availabilitySummary: availabilitySummary,
      slotPressures: slotPressures,
      restaurantSetup: restaurantSetup,
      selectedDate: selectedDate,
      settings: settings
    )

    let requestedDate = reservation.serviceDateTime
    let isLargeParty = reservation.partySize >= settings.largePartyThreshold

    func scoreSlot(_ slotTime: String) -> Int? {
      let normalized = normalizedSlotTime(slotTime)
      guard normalized != requestedTime else { return nil }
      guard !blockedSlots.contains(normalized) else { return nil }

      if let slotDate = parseSlotDate(slotTime: normalized, selectedDate: selectedDate),
         slotDate <= now {
        return nil
      }

      guard let pressure = pressureBySlot[normalized] else {
        return 50
      }

      if pressure.severity == .critical || pressure.severity == .busy {
        return nil
      }

      if isLargeParty, pressure.largePartyCount > 0 {
        return nil
      }

      switch pressure.severity {
      case .calm: return 100
      case .watch: return 70
      case .busy, .critical: return nil
      }
    }

    let scored = candidateSlots.compactMap { slot -> (String, Int, Date)? in
      guard let score = scoreSlot(slot),
            let date = parseSlotDate(slotTime: slot, selectedDate: selectedDate) else {
        return nil
      }
      return (slot, score, date)
    }

    guard !scored.isEmpty else { return nil }

    if let requestedDate {
      let after = scored
        .filter { $0.2 > requestedDate }
        .sorted { lhs, rhs in
          if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
          return lhs.2 < rhs.2
        }
      if let best = after.first {
        return displaySlotTime(best.0)
      }

      let before = scored
        .filter { $0.2 < requestedDate && $0.2 > now }
        .sorted { lhs, rhs in
          if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
          return lhs.2 > rhs.2
        }
      if let best = before.first {
        return displaySlotTime(best.0)
      }
    }

    let future = scored
      .filter { $0.2 > now }
      .sorted { lhs, rhs in
        if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
        return lhs.2 < rhs.2
      }
    return future.first.map { displaySlotTime($0.0) }
  }

  // MARK: - Decision Logic

  private static func decide(
    reservation: ReservationRecord,
    slotPressures: [HostSlotPressure],
    pressureBySlot: [String: HostSlotPressure],
    blockedSlots: Set<String>,
    guestSignals: [HostGuestSignal],
    tableConfigs: [RestaurantTableConfig],
    availabilitySummary: ReservationAvailabilitySummary?,
    restaurantSetup: RestaurantSetup?,
    now: Date,
    selectedDate: Date,
    settings: HostIntelligenceSettings
  ) -> HostBookingDecisionResult {
    let requestedTime = reservation.displayTime
    let requestedSlot = normalizedSlotTime(reservation.reservationTime)
    let slotPressure = pressureBySlot[requestedSlot]
    let isBlocked = slotPressure?.isBlocked == true || blockedSlots.contains(requestedSlot)
    let hasTableInventory = !tableConfigs.isEmpty
    let tableFit = HostTableIntelligenceSupport.bestTableFitOptions(
      for: reservation,
      tableConfigs: tableConfigs,
      limit: 1
    )
    let hasTableFit = !hasTableInventory || !tableFit.isEmpty

    if let serviceDate = reservation.serviceDateTime, serviceDate < now {
      return makeResult(
        reservation: reservation,
        decision: .manualReview,
        requestedTime: requestedTime,
        suggestedTime: nil,
        confidence: 0.92,
        reason: "Requested time is already past.",
        evidence: ["requestedTime=\(requestedTime)", "status=\(reservation.statusValue.rawValue)"]
      )
    }

    if reservation.partySize >= settings.criticalPartyThreshold {
      return makeResult(
        reservation: reservation,
        decision: .manualReview,
        requestedTime: requestedTime,
        suggestedTime: nil,
        confidence: 0.95,
        reason: "Critical large party requires staff review.",
        evidence: ["partySize=\(reservation.partySize)", "threshold=\(settings.criticalPartyThreshold)"]
      )
    }

    if reservation.isManualOrCallIn || !reservation.hasUsableConfirmationEmail {
      return makeResult(
        reservation: reservation,
        decision: .manualReview,
        requestedTime: requestedTime,
        suggestedTime: nil,
        confidence: 0.9,
        reason: "Manual/call-in or no usable email; staff should review before confirmation.",
        evidence: [
          "manualOrCallIn=\(reservation.isManualOrCallIn)",
          "hasUsableEmail=\(reservation.hasUsableConfirmationEmail)"
        ]
      )
    }

    if let riskReason = guestRiskReason(signals: guestSignals) {
      return makeResult(
        reservation: reservation,
        decision: .manualReview,
        requestedTime: requestedTime,
        suggestedTime: nil,
        confidence: 0.88,
        reason: riskReason,
        evidence: guestSignals.map { "signal=\($0.kind.rawValue)" }
      )
    }

    if violatesLeadTime(
      reservation: reservation,
      restaurantSetup: restaurantSetup,
      now: now,
      selectedDate: selectedDate
    ) {
      let leadMinutes = restaurantSetup?.minimumLeadTimeMinutes ?? 0
      return makeResult(
        reservation: reservation,
        decision: .manualReview,
        requestedTime: requestedTime,
        suggestedTime: nil,
        confidence: 0.86,
        reason: "Requested time is inside minimum lead time window.",
        evidence: ["leadTimeMinutes=\(leadMinutes)"]
      )
    }

    if isBlocked {
      if let alternate = findAlternateSlot(
        for: reservation,
        slotPressures: slotPressures,
        availabilitySummary: availabilitySummary,
        restaurantSetup: restaurantSetup,
        settings: settings,
        now: now,
        selectedDate: selectedDate
      ) {
        return makeResult(
          reservation: reservation,
          decision: .suggestAlternateTime,
          requestedTime: requestedTime,
          suggestedTime: alternate,
          confidence: 0.84,
          reason: "Requested slot \(requestedTime) is blocked; \(alternate) is safer.",
          evidence: ["requestedSlotBlocked=true", "suggestedTime=\(alternate)"]
        )
      }

      if reservation.partySize >= settings.largePartyThreshold {
        return makeResult(
          reservation: reservation,
          decision: .reject,
          requestedTime: requestedTime,
          suggestedTime: nil,
          confidence: 0.9,
          reason: "Requested slot is blocked and no safer alternate time is available.",
          evidence: ["requestedSlotBlocked=true", "partySize=\(reservation.partySize)"]
        )
      }

      return makeResult(
        reservation: reservation,
        decision: .manualReview,
        requestedTime: requestedTime,
        suggestedTime: nil,
        confidence: 0.82,
        reason: "Requested slot is blocked.",
        evidence: ["requestedSlotBlocked=true"]
      )
    }

    if reservation.partySize >= settings.largePartyThreshold {
      let busy = slotPressure?.severity == .busy || slotPressure?.severity == .critical
      if busy || !hasTableFit,
         let alternate = findAlternateSlot(
           for: reservation,
           slotPressures: slotPressures,
           availabilitySummary: availabilitySummary,
           restaurantSetup: restaurantSetup,
           settings: settings,
           now: now,
           selectedDate: selectedDate
         ) {
        return makeResult(
          reservation: reservation,
          decision: .suggestAlternateTime,
          requestedTime: requestedTime,
          suggestedTime: alternate,
          confidence: 0.8,
          reason: "Large party at \(requestedTime) needs review; \(alternate) has less pressure.",
          evidence: [
            "partySize=\(reservation.partySize)",
            "slotSeverity=\(slotPressure?.severity.rawValue ?? "unknown")"
          ]
        )
      }

      return makeResult(
        reservation: reservation,
        decision: .manualReview,
        requestedTime: requestedTime,
        suggestedTime: nil,
        confidence: 0.9,
        reason: "Large party requires staff review before confirmation.",
        evidence: ["partySize=\(reservation.partySize)", "hasTableFit=\(hasTableFit)"]
      )
    }

    if !hasTableFit {
      return makeResult(
        reservation: reservation,
        decision: .manualReview,
        requestedTime: requestedTime,
        suggestedTime: nil,
        confidence: 0.85,
        reason: "No suitable table fit exists for this party size.",
        evidence: ["partySize=\(reservation.partySize)", "tableInventoryConfigured=true"]
      )
    }

    if slotPressure?.severity == .critical || slotPressure?.severity == .busy {
      if let alternate = findAlternateSlot(
        for: reservation,
        slotPressures: slotPressures,
        availabilitySummary: availabilitySummary,
        restaurantSetup: restaurantSetup,
        settings: settings,
        now: now,
        selectedDate: selectedDate
      ) {
        return makeResult(
          reservation: reservation,
          decision: .suggestAlternateTime,
          requestedTime: requestedTime,
          suggestedTime: alternate,
          confidence: 0.83,
          reason: "Party of \(reservation.partySize) requested \(requestedTime), but \(alternate) is safer.",
          evidence: [
            "slotSeverity=\(slotPressure?.severity.rawValue ?? "unknown")",
            "reservationCount=\(slotPressure?.reservationCount ?? 0)"
          ]
        )
      }

      return makeResult(
        reservation: reservation,
        decision: .manualReview,
        requestedTime: requestedTime,
        suggestedTime: nil,
        confidence: 0.87,
        reason: "\(requestedTime) is under heavy pressure and needs staff review.",
        evidence: [
          "slotSeverity=\(slotPressure?.severity.rawValue ?? "unknown")",
          "reservationCount=\(slotPressure?.reservationCount ?? 0)"
        ]
      )
    }

    if slotPressure?.severity == .watch,
       settings.suggestAlternateTimesEnabled,
       let alternate = findAlternateSlot(
         for: reservation,
         slotPressures: slotPressures,
         availabilitySummary: availabilitySummary,
         restaurantSetup: restaurantSetup,
         settings: settings,
         now: now,
         selectedDate: selectedDate
       ) {
      return makeResult(
        reservation: reservation,
        decision: .suggestAlternateTime,
        requestedTime: requestedTime,
        suggestedTime: alternate,
        confidence: 0.78,
        reason: "Party of \(reservation.partySize) requested \(requestedTime), but \(alternate) is calmer.",
        evidence: ["slotSeverity=watch", "suggestedTime=\(alternate)"]
      )
    }

    if canRecommendAutoConfirm(
      reservation: reservation,
      slotPressure: slotPressure,
      settings: settings,
      selectedDate: selectedDate
    ) {
      return makeResult(
        reservation: reservation,
        decision: .autoConfirm,
        requestedTime: requestedTime,
        suggestedTime: nil,
        confidence: 0.85,
        reason: "This request can be confirmed based on slot pressure and party size.",
        evidence: [
          "partySize=\(reservation.partySize)",
          "slotSeverity=\(slotPressure?.severity.rawValue ?? "calm")",
          "hasUsableEmail=true"
        ]
      )
    }

    return makeResult(
      reservation: reservation,
      decision: .noDecision,
      requestedTime: requestedTime,
      suggestedTime: nil,
      confidence: 0,
      reason: "",
      evidence: []
    )
  }

  // MARK: - Facts & Actions

  private static func makeFact(
    for decision: HostBookingDecisionResult,
    reservation: ReservationRecord,
    settings: HostIntelligenceSettings
  ) -> HostBriefingFact? {
    switch decision.decision {
    case .noDecision:
      return nil
    case .autoConfirm:
      guard settings.autoConfirmRecommendationsEnabled else { return nil }
      let detail =
        "\(reservation.guestName), party of \(reservation.partySize), requested \(decision.requestedTime ?? reservation.displayTime). \(decision.reason)"
      return HostBriefingFact(
        id: factID(for: decision) ?? "booking-fact-\(reservation.remoteID)",
        severity: .info,
        category: .bookingDecision,
        title: "Auto-confirm candidate",
        detail: detail,
        evidence: decision.evidence,
        relatedReservationIDs: [reservation.remoteID],
        suggestedActionTitle: "Review auto-confirm candidate."
      )
    case .suggestAlternateTime:
      let detail =
        "\(reservation.guestName), party of \(reservation.partySize), requested \(decision.requestedTime ?? reservation.displayTime), but \(decision.suggestedTime ?? "another time") is safer."
      return HostBriefingFact(
        id: factID(for: decision) ?? "booking-fact-\(reservation.remoteID)",
        severity: .watch,
        category: .bookingDecision,
        title: "Suggest alternate time",
        detail: detail,
        evidence: decision.evidence,
        relatedReservationIDs: [reservation.remoteID],
        suggestedActionTitle: "Review alternate time with guest."
      )
    case .manualReview:
      let category: HostFactCategory =
        reservation.partySize >= settings.largePartyThreshold ? .largeParty : .bookingDecision
      return HostBriefingFact(
        id: factID(for: decision) ?? "booking-fact-\(reservation.remoteID)",
        severity: factSeverity(for: decision),
        category: category,
        title: "Booking needs review",
        detail: "\(reservation.guestName), party of \(reservation.partySize). \(decision.reason)",
        evidence: decision.evidence,
        relatedReservationIDs: [reservation.remoteID],
        suggestedActionTitle: "Review before confirming."
      )
    case .reject:
      return HostBriefingFact(
        id: factID(for: decision) ?? "booking-fact-\(reservation.remoteID)",
        severity: .critical,
        category: .bookingDecision,
        title: "No safe booking option",
        detail: "\(reservation.guestName), party of \(reservation.partySize). \(decision.reason)",
        evidence: decision.evidence,
        relatedReservationIDs: [reservation.remoteID],
        suggestedActionTitle: "Review whether to reject or reschedule."
      )
    }
  }

  private static func makeAction(
    for decision: HostBookingDecisionResult,
    reservation: ReservationRecord,
    settings: HostIntelligenceSettings
  ) -> HostSuggestedAction? {
    switch decision.decision {
    case .noDecision:
      return nil
    case .autoConfirm:
      guard settings.autoConfirmRecommendationsEnabled else { return nil }
      return HostSuggestedAction(
        id: "booking-action-confirm-\(reservation.remoteID)",
        severity: .info,
        kind: .confirmReservation,
        title: "Review auto-confirm candidate for \(reservation.guestName)",
        reason: decision.reason,
        relatedReservationIDs: [reservation.remoteID],
        targetSlotTime: reservation.reservationTime,
        targetTableName: reservation.assignedTableName,
        requiresStaffConfirmation: true
      )
    case .suggestAlternateTime:
      return HostSuggestedAction(
        id: "booking-action-alternate-\(reservation.remoteID)",
        severity: .watch,
        kind: .suggestAlternateTime,
        title: "Suggest \(decision.suggestedTime ?? "alternate time")",
        reason: decision.reason,
        relatedReservationIDs: [reservation.remoteID],
        targetSlotTime: decision.suggestedTime,
        targetTableName: nil,
        requiresStaffConfirmation: true
      )
    case .manualReview, .reject:
      return HostSuggestedAction(
        id: "booking-action-review-\(reservation.remoteID)",
        severity: factSeverity(for: decision),
        kind: .reviewReservation,
        title: "Review booking for \(reservation.guestName)",
        reason: decision.reason,
        relatedReservationIDs: [reservation.remoteID],
        targetSlotTime: reservation.reservationTime,
        targetTableName: reservation.assignedTableName,
        requiresStaffConfirmation: true
      )
    }
  }

  // MARK: - Helpers

  private static var emptyResult: HostBookingDecisionAnalysisResult {
    HostBookingDecisionAnalysisResult(
      decisions: [],
      facts: [],
      actions: [],
      manualReviewCriticalCount: 0,
      suggestAlternateCount: 0,
      autoConfirmCount: 0,
      rejectCount: 0
    )
  }

  private static func bookingCandidates(from activeReservations: [ReservationRecord]) -> [ReservationRecord] {
    activeReservations
      .filter { reservation in
        !reservation.isHidden
          && (reservation.statusValue == .new || reservation.statusValue == .needsReview)
      }
      .sorted { lhs, rhs in
        let lhsDate = lhs.serviceDateTime ?? .distantFuture
        let rhsDate = rhs.serviceDateTime ?? .distantFuture
        return lhsDate < rhsDate
      }
  }

  private static func canRecommendAutoConfirm(
    reservation: ReservationRecord,
    slotPressure: HostSlotPressure?,
    settings: HostIntelligenceSettings,
    selectedDate: Date
  ) -> Bool {
    guard settings.autoConfirmRecommendationsEnabled else { return false }
    guard reservation.statusValue == .new || reservation.statusValue == .needsReview else { return false }
    guard reservation.partySize <= settings.maxPartySizeForAutoConfirm else { return false }
    guard reservation.hasUsableConfirmationEmail, !reservation.isManualOrCallIn else { return false }

    if settings.autoConfirmWeekdaysOnly {
      let weekday = Calendar.current.component(.weekday, from: selectedDate)
      if weekday == 1 || weekday == 7 { return false }
    }

    let severity = slotPressure?.severity ?? .calm
    guard severity == .calm || severity == .watch else { return false }
    guard slotPressure?.isBlocked != true else { return false }

    return 0.85 >= settings.minimumConfidenceForAutoConfirm
  }

  private static func violatesLeadTime(
    reservation: ReservationRecord,
    restaurantSetup: RestaurantSetup?,
    now: Date,
    selectedDate: Date
  ) -> Bool {
    guard let leadMinutes = restaurantSetup?.minimumLeadTimeMinutes, leadMinutes > 0,
          let serviceDate = reservation.serviceDateTime else {
      return false
    }

    let calendar = Calendar.current
    guard calendar.isDate(selectedDate, inSameDayAs: now),
          calendar.isDate(serviceDate, inSameDayAs: now) else {
      return false
    }

    return serviceDate.timeIntervalSince(now) < TimeInterval(leadMinutes * 60)
  }

  private static func guestRiskReason(signals: [HostGuestSignal]) -> String? {
    let riskKinds: Set<HostGuestSignalKind> = [
      .allergy, .accessibility, .previousServiceIssue, .possibleDuplicate
    ]
    guard let match = signals.first(where: { riskKinds.contains($0.kind) }) else {
      return nil
    }

    switch match.kind {
    case .allergy:
      return "Allergy signal requires staff review before confirmation."
    case .accessibility:
      return "Accessibility needs require staff review before confirmation."
    case .previousServiceIssue:
      return "Previous service issue requires staff review before confirmation."
    case .possibleDuplicate:
      return "Possible duplicate booking requires staff review."
    default:
      return "Guest risk signal requires staff review."
    }
  }

  private static func guestSignalsByReservationID(
    _ signals: [HostGuestSignal]
  ) -> [Int: [HostGuestSignal]] {
    Dictionary(grouping: signals, by: \.reservationID)
  }

  private static func blockedSlotTimeSet(
    from availabilitySummary: ReservationAvailabilitySummary?
  ) -> Set<String> {
    guard let blocked = availabilitySummary?.blockedSlots else { return [] }
    return Set(blocked.map { normalizedSlotTime($0.slotTime) })
  }

  private static func slotPressureIndex(
    _ pressures: [HostSlotPressure]
  ) -> [String: HostSlotPressure] {
    Dictionary(uniqueKeysWithValues: pressures.map { (normalizedSlotTime($0.slotTime), $0) })
  }

  private static func candidateSlotTimes(
    availabilitySummary: ReservationAvailabilitySummary?,
    slotPressures: [HostSlotPressure],
    restaurantSetup: RestaurantSetup?,
    selectedDate: Date,
    settings: HostIntelligenceSettings
  ) -> [String] {
    if let slots = availabilitySummary?.slots.slots, !slots.isEmpty {
      return slots.map(\.value)
    }

    if let setup = restaurantSetup,
       let availability = availabilitySummary?.availability {
      let generated = setup.suggestedTimes(
        for: selectedDate,
        applyLeadTime: false,
        openTime: availability.openTime,
        closeTime: availability.closeTime,
        slotIntervalMinutes: settings.slotIntervalMinutes
      )
      if !generated.isEmpty {
        return generated.map { ReservationFormatters.apiTime.string(from: $0) }
      }
    }

    return slotPressures.map(\.slotTime)
  }

  private static func parseSlotDate(
    slotTime: String,
    selectedDate: Date
  ) -> Date? {
    let dateKey = selectedDate.reservationDateString()
    let normalized = normalizedSlotTime(slotTime)
    if let date = ReservationFormatters.serverDateTime.date(from: "\(dateKey) \(normalized)") {
      return date
    }
    return ReservationFormatters.serverDateMinute.date(from: "\(dateKey) \(normalized)")
  }

  private static func displaySlotTime(_ slotTime: String) -> String {
    let normalized = normalizedSlotTime(slotTime)
    if let date = ReservationFormatters.apiTime.date(from: normalized) {
      return ReservationFormatters.shortTime.string(from: date)
    }
    return normalized
  }

  private static func normalizedSlotTime(_ value: String) -> String {
    value.count >= 5 ? String(value.prefix(5)) : value
  }

  private static func makeResult(
    reservation: ReservationRecord,
    decision: HostBookingDecisionKind,
    requestedTime: String?,
    suggestedTime: String?,
    confidence: Double,
    reason: String,
    evidence: [String]
  ) -> HostBookingDecisionResult {
    HostBookingDecisionResult(
      id: "booking-decision-\(reservation.remoteID)",
      reservationID: reservation.remoteID,
      decision: decision,
      requestedTime: requestedTime,
      suggestedTime: suggestedTime,
      confidence: confidence,
      reason: reason,
      evidence: evidence,
      requiresStaffConfirmation: true
    )
  }

  private static func factID(for decision: HostBookingDecisionResult) -> String? {
    guard let reservationID = decision.reservationID else { return nil }
    return "booking-fact-\(reservationID)"
  }

  private static func factSeverity(for decision: HostBookingDecisionResult) -> HostSeverity {
    switch decision.decision {
    case .reject: return .critical
    case .manualReview:
      if decision.confidence >= 0.9 { return .warning }
      return .watch
    case .suggestAlternateTime: return .watch
    case .autoConfirm: return .info
    case .noDecision: return .info
    }
  }

  private static func rankFacts(_ facts: [HostBriefingFact]) -> [HostBriefingFact] {
    facts.sorted { lhs, rhs in
      if lhs.severity.rank != rhs.severity.rank {
        return lhs.severity.rank < rhs.severity.rank
      }
      return lhs.title < rhs.title
    }
  }

  private static func deduplicatedActions(_ actions: [HostSuggestedAction]) -> [HostSuggestedAction] {
    var seen = Set<String>()
    return actions.filter { action in
      if seen.contains(action.id) { return false }
      seen.insert(action.id)
      return true
    }
  }
}
