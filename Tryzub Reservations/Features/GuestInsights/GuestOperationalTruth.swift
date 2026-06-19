//
//  GuestOperationalTruth.swift
//  Tryzub Reservations
//
//  Shared operational truth for prior visits, regularity, and correction evidence.
//

import Foundation

enum GuestOperationalTruth {
  enum Source: String {
    case backend
    case local
    case mixed
    case unknown
  }

  enum Confidence: String {
    case exact
    case strong
    case possible
    case unknown
  }

  enum Regularity: String {
    case firstTime
    case seenBefore
    case regular
    case unknown
  }

  struct Evaluation {
    let seenBefore: Bool
    let regularity: Regularity
    let localValidPastVisitCount: Int
    let cleanVisitCount: Int
    let matchedVisitCount: Int
    let lastVisitDate: Date?
    let lastVisitDisplay: String?
    let source: Source
    let confidence: Confidence
    let finalLabel: String
    let backendLastVisitCandidate: String?
    let rejectedReason: String?
    let rejectedFutureBackendDate: Bool
    let classificationRegular: Bool
    let classificationAccepted: Bool
    let classificationRejectedReason: String?
  }

  struct LocalSnapshot: Sendable {
    let validPastVisitCount: Int
    let lastVisitDisplay: String?
  }

  static func evaluate(
    surface: String,
    selected: ReservationRecord,
    localReport: GuestInsightReport?,
    summary: GuestIntelligenceSummaryDTO?,
    profilePack: GuestIntelligenceProfilePackDTO? = nil
  ) -> Evaluation {
    #if DEBUG
    if localReport != nil {
      print("[INTEL_TRUTH_TRACE] surface=\(surface) reservationID=\(selected.remoteID) source=legacyLocalReport ignoredForStaffTruth=true")
    }
    #endif
    return evaluate(
      surface: surface,
      reservationID: selected.remoteID,
      selectedDate: selected.reservationDate,
      selectedTime: selected.reservationTime,
      localValidPastVisitCount: 0,
      localLastVisit: nil,
      hasConflictingLocalEvidence: localReport != nil,
      summary: summary,
      profilePack: profilePack
    )
  }

  static func evaluate(
    surface: String,
    selected: ReservationRecord,
    reservationPool: [ReservationRecord],
    summary: GuestIntelligenceSummaryDTO?,
    profilePack: GuestIntelligenceProfilePackDTO? = nil
  ) -> Evaluation {
    let started = ContinuousClock.now
    let localSnapshot = localTruthSnapshot(
      selected: selected,
      reservationPool: reservationPool
    )
    let result = evaluate(
      surface: surface,
      reservationID: selected.remoteID,
      selectedDate: selected.reservationDate,
      selectedTime: selected.reservationTime,
      localValidPastVisitCount: localSnapshot.validPastVisitCount,
      localLastVisit: localSnapshot.lastVisitDisplay.map { (date: nil, display: $0) },
      hasConflictingLocalEvidence: possibleCorrection(
        reservation: selected,
        peers: reservationPool
      ),
      summary: summary,
      profilePack: profilePack
    )
    perfTrace(
      operation: "GuestOperationalTruth build",
      reservationID: selected.remoteID,
      candidateCount: reservationPool.count,
      duration: started.duration(to: .now)
    )
    return result
  }

  static func validPastVisit(
    _ candidate: ReservationRecord,
    selected: ReservationRecord
  ) -> Bool {
    validPastVisitRejection(candidate, selected: selected) == nil
  }

  static func validPastVisits(
    selected: ReservationRecord,
    reservationPool: [ReservationRecord],
    emitTrace: Bool = true
  ) -> [ReservationRecord] {
    let resolver = GuestIdentityResolver()
    let selectedIdentity = resolver.identity(for: selected)
    let identityMatches = reservationPool.filter { candidate in
      if candidate.remoteID == selected.remoteID { return true }
      guard let match = resolver.match(
        candidate,
        against: selectedIdentity,
        selectedID: selected.remoteID
      ) else { return false }
      return match.confidence == .exact || match.confidence == .strong
    }
    let deduped = GuestReservationIntentDeduper()
      .collapse(identityMatches + [selected], keeping: selected.remoteID)
      .records
    let keptIDs = Set(deduped.map(\.remoteID))
    for candidate in identityMatches where !keptIDs.contains(candidate.remoteID) && emitTrace {
      guestTruthTrace(
        reservationID: selected.remoteID,
        candidate: candidate,
        counted: false,
        rejectedReason: "duplicate_intent_collapsed"
      )
    }

    var rejectedCounts: [String: Int] = [:]
    let accepted = deduped.filter { candidate in
      let rejectedReason = validPastVisitRejection(candidate, selected: selected)
      if let rejectedReason {
        rejectedCounts[rejectedReason, default: 0] += 1
        if emitTrace && (rejectedReason == "superseded" || rejectedReason == "not_before_selected_service") {
          guestTruthTrace(
            reservationID: selected.remoteID,
            candidate: candidate,
            counted: false,
            rejectedReason: rejectedReason
          )
        }
      }
      return validPastVisit(candidate, selected: selected)
    }
    if emitTrace {
      guestTruthSummaryTrace(
        reservationID: selected.remoteID,
        candidateCount: identityMatches.count,
        acceptedCount: accepted.count,
        rejectedCounts: rejectedCounts
      )
    }
    return accepted
  }

  static func localTruthSnapshot(
    selected: ReservationRecord,
    reservationPool: [ReservationRecord],
    emitTrace: Bool = true
  ) -> LocalSnapshot {
    let visits = validPastVisits(
      selected: selected,
      reservationPool: reservationPool,
      emitTrace: emitTrace
    )
    let lastVisit = lastRealVisit(
      selected: selected,
      reservationPool: reservationPool,
      prefilteredVisits: visits
    )
    return LocalSnapshot(
      validPastVisitCount: visits.count,
      lastVisitDisplay: lastVisit?.displayDate
    )
  }

  static func validHistoricalVisits(
    _ reservationPool: [ReservationRecord],
    referenceDate: Date = Date()
  ) -> [ReservationRecord] {
    GuestReservationIntentDeduper().collapse(reservationPool).records.filter { candidate in
      guard !candidate.isHidden, (candidate.supersededById ?? 0) <= 0 else { return false }
      guard isCleanStatus(candidate.statusValue) else { return false }
      guard let serviceDate = serviceDateTime(
        date: candidate.reservationDate,
        time: candidate.reservationTime
      ) else { return false }
      return serviceDate < referenceDate
    }
  }

  static func lastRealVisit(
    selected: ReservationRecord,
    reservationPool: [ReservationRecord],
    prefilteredVisits: [ReservationRecord]? = nil
  ) -> ReservationRecord? {
    (prefilteredVisits ?? validPastVisits(selected: selected, reservationPool: reservationPool))
      .max { serviceSortKey($0) < serviceSortKey($1) }
  }

  static func regularity(forPastVisitCount count: Int) -> Regularity {
    if count >= 3 { return .regular }
    if count >= 1 { return .seenBefore }
    return .firstTime
  }

  static func possibleCorrection(
    reservation: ReservationRecord,
    peers: [ReservationRecord]
  ) -> Bool {
    guard isActiveCorrectionCandidate(reservation) else { return false }
    let resolver = GuestIdentityResolver()
    let selectedIdentity = resolver.identity(for: reservation)

    return peers.contains { peer in
      guard peer.remoteID != reservation.remoteID,
            peer.reservationDate == reservation.reservationDate,
            isActiveCorrectionCandidate(peer) else {
        return false
      }
      let peerIdentity = resolver.identity(for: peer)
      if let phone = selectedIdentity.fullPhoneDigits, phone == peerIdentity.fullPhoneDigits {
        return true
      }
      if let email = selectedIdentity.usefulEmail, email == peerIdentity.usefulEmail {
        return true
      }
      guard let match = resolver.match(
        peer,
        against: selectedIdentity,
        selectedID: reservation.remoteID
      ) else { return false }
      return match.confidence == .exact || match.confidence == .strong
    }
  }

  static func serviceIntelTrace(
    guestLabel: String,
    truth: Evaluation,
    finalBadge: String?
  ) {
    #if DEBUG
    let badge = finalBadge ?? "none"
    print("[SERVICE_INTEL_TRACE] guest=\(guestLabel) cleanVisitCount=\(truth.cleanVisitCount) matchedVisitCount=\(truth.matchedVisitCount) finalSeenBefore=\(truth.seenBefore) finalBadge=\(badge) source=\(truth.source.rawValue)")
    #endif
  }

  static func isActiveCorrectionCandidate(_ reservation: ReservationRecord) -> Bool {
    guard !reservation.isHidden, (reservation.supersededById ?? 0) <= 0 else { return false }
    switch reservation.statusValue {
    case .new, .needsReview, .confirmed, .seated:
      return true
    case .completed, .cancelled, .noShow:
      return false
    }
  }

  static func acceptedBackendLastVisit(
    _ raw: String?,
    selectedDate: String,
    selectedTime: String
  ) -> Date? {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
      return nil
    }
    if raw.count >= 10 {
      let candidateDateKey = String(raw.prefix(10))
      // Date-only server history cannot prove that a same-day row precedes this reservation.
      guard candidateDateKey < selectedDate else { return nil }
    }
    return parseBackendDate(raw)
  }

  static func acceptedBackendLastVisit(
    _ raw: String?,
    referenceDate: Date
  ) -> Date? {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
      return nil
    }
    if raw.count >= 10 {
      let candidateDateKey = String(raw.prefix(10))
      guard candidateDateKey < referenceDate.reservationDateString() else { return nil }
    }
    guard let parsed = parseBackendDate(raw), parsed < referenceDate else { return nil }
    return parsed
  }

  private static func evaluate(
    surface: String,
    reservationID: Int,
    selectedDate: String,
    selectedTime: String,
    localValidPastVisitCount: Int,
    localLastVisit: (date: Date?, display: String)?,
    hasConflictingLocalEvidence: Bool,
    summary: GuestIntelligenceSummaryDTO?,
    profilePack: GuestIntelligenceProfilePackDTO?
  ) -> Evaluation {
    let resolvedSummary = profilePack?.resolvedSummary ?? summary
    let identity = backendConfidence(summary: resolvedSummary, profilePack: profilePack)
    let reliableIdentity = identity == .exact || identity == .strong
    let cleanCount = reliableIdentity ? max(0, resolvedSummary?.cleanVisitCount ?? 0) : 0
    let profilePriorCount = reliableIdentity
      ? max(0, profilePack?.history?.priorVisitCount ?? profilePack?.visitAnalytics?.priorVisitCount ?? 0)
      : 0
    let reliableBackendCount = max(cleanCount, profilePriorCount)
    let matchedCount = max(0, resolvedSummary?.matchedVisitCount ?? 0)
    let classification = resolvedSummary?.classification ?? .unknown
    let classificationRegular = classification == .regular || classification == .frequentRegular
    let classificationRejectedReason: String? = {
      guard classificationRegular else { return "not_regular_classification" }
      guard reliableIdentity else { return "identity_not_exact_or_strong" }
      guard resolvedSummary?.possibleDuplicate != true else { return "possible_duplicate" }
      guard !hasConflictingLocalEvidence else { return "local_correction_conflict" }
      guard reliableBackendCount >= 3 else { return "insufficient_clean_visit_evidence" }
      return nil
    }()
    let classificationAccepted = classificationRegular && classificationRejectedReason == nil
    // Classification corroborates count-backed wording only. It never creates visit
    // history or regularity when clean/local visit evidence is absent.
    let seenBefore = reliableBackendCount > 0 || localValidPastVisitCount > 0
    let combinedCount = max(reliableBackendCount, localValidPastVisitCount)
    let regularity = regularity(forPastVisitCount: combinedCount)

    let backendCandidate = profilePack?.history?.lastSeenDate ?? resolvedSummary?.lastVisitDate
    let backendLast = acceptedBackendLastVisit(
      backendCandidate,
      selectedDate: selectedDate,
      selectedTime: selectedTime
    )
    let rejectedFutureBackendDate = backendCandidate?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      && backendLast == nil
    let chosenDate: Date?
    let chosenDisplay: String?
    if let backendLast, seenBefore {
      chosenDate = backendLast
      chosenDisplay = ReservationFormatters.mediumDate.string(from: backendLast)
    } else {
      chosenDate = localLastVisit?.date
      chosenDisplay = localLastVisit?.display
    }

    let source: Source
    if reliableBackendCount > 0 {
      source = localValidPastVisitCount > 0 ? .mixed : .backend
    } else if localValidPastVisitCount > 0 {
      source = .local
    } else {
      source = .unknown
    }
    let weakHistory = !seenBefore && (matchedCount > 0
      || profilePack?.history?.seenBefore == true
      || profilePack?.hostProfilePacket?.seenBefore == true
      || (classificationRegular && reliableIdentity
        && resolvedSummary?.possibleDuplicate != true
        && !hasConflictingLocalEvidence))
    let finalLabel: String
    if regularity == .regular {
      finalLabel = "Regular"
    } else if seenBefore, let chosenDisplay {
      finalLabel = "Seen before · Last visit \(chosenDisplay)"
    } else if seenBefore {
      finalLabel = "Seen before"
    } else if weakHistory {
      finalLabel = "Guest history found"
    } else {
      finalLabel = "First time"
    }
    let rejectedReason = rejectedFutureBackendDate ? "backend_last_visit_not_before_selected_service" : nil

    let result = Evaluation(
      seenBefore: seenBefore,
      regularity: regularity,
      localValidPastVisitCount: localValidPastVisitCount,
      cleanVisitCount: reliableBackendCount,
      matchedVisitCount: matchedCount,
      lastVisitDate: chosenDate,
      lastVisitDisplay: chosenDisplay,
      source: source,
      confidence: seenBefore ? (reliableIdentity ? identity : .strong) : (weakHistory ? .possible : .unknown),
      finalLabel: finalLabel,
      backendLastVisitCandidate: backendCandidate,
      rejectedReason: rejectedReason,
      rejectedFutureBackendDate: rejectedFutureBackendDate,
      classificationRegular: classificationRegular,
      classificationAccepted: classificationAccepted,
      classificationRejectedReason: classificationRejectedReason
    )
    intelTruthTrace(surface: surface, reservationID: reservationID, date: selectedDate, result: result)
    if surface == "guest_detail" || surface == "guest_insights" {
      guestDetailTrace(
        reservationID: reservationID,
        selectedDate: selectedDate,
        selectedTime: selectedTime,
        backendCandidate: backendCandidate,
        localCandidate: localLastVisit?.display,
        chosen: chosenDisplay,
        rejectedFutureBackendDate: rejectedFutureBackendDate
      )
    }
    return result
  }

  private static func validPastVisitRejection(
    _ candidate: ReservationRecord,
    selected: ReservationRecord
  ) -> String? {
    if candidate.remoteID == selected.remoteID { return "current_reservation" }
    if candidate.isHidden { return "hidden" }
    if (candidate.supersededById ?? 0) > 0 { return "superseded" }
    if !isCleanStatus(candidate.statusValue) { return "status_\(candidate.statusValue.rawValue)" }
    if !isStrictlyBefore(
      date: candidate.reservationDate,
      time: candidate.reservationTime,
      referenceDate: selected.reservationDate,
      referenceTime: selected.reservationTime
    ) { return "not_before_selected_service" }
    return nil
  }

  private static func isCleanStatus(_ status: ReservationStatus) -> Bool {
    status == .confirmed || status == .seated || status == .completed
  }

  private static func isStrictlyBefore(
    date: String,
    time: String,
    referenceDate: String,
    referenceTime: String
  ) -> Bool {
    serviceSortKey(date: date, time: time) < serviceSortKey(date: referenceDate, time: referenceTime)
  }

  private static func serviceSortKey(_ reservation: ReservationRecord) -> String {
    serviceSortKey(date: reservation.reservationDate, time: reservation.reservationTime)
  }

  private static func serviceSortKey(date: String, time: String) -> String {
    "\(date) \(time)"
  }

  private static func serviceDateTime(date: String, time: String) -> Date? {
    ReservationFormatters.serverDateMinute.date(from: "\(date) \(String(time.prefix(5)))")
  }

  private static func parseBackendDate(_ raw: String) -> Date? {
    if let date = ISO8601DateFormatter().date(from: raw) { return date }
    if raw.count >= 10 {
      return ReservationFormatters.reservationDateKey.date(from: String(raw.prefix(10)))
    }
    return nil
  }

  private static func backendConfidence(
    summary: GuestIntelligenceSummaryDTO?,
    profilePack: GuestIntelligenceProfilePackDTO?
  ) -> Confidence {
    if let summary {
      switch summary.identityConfidence {
      case .exact: return .exact
      case .strong: return .strong
      case .possible, .weak: return .possible
      case .unknown: break
      }
    }
    let raw = profilePack?.hostProfilePacket?.identityConfidence?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if raw == "exact" { return .exact }
    if raw == "strong" { return .strong }
    if raw == "possible" || raw == "weak" { return .possible }
    return .unknown
  }

  private static func intelTruthTrace(
    surface: String,
    reservationID: Int,
    date: String,
    result: Evaluation
  ) {
    #if DEBUG
    let candidate = result.backendLastVisitCandidate ?? "nil"
    let accepted = result.lastVisitDisplay ?? "nil"
    let reason = result.rejectedReason ?? "none"
    let classificationReason = result.classificationRejectedReason ?? "none"
    print("[INTEL_TRUTH_TRACE] surface=\(surface) reservationID=\(reservationID) date=\(date) source=\(result.source.rawValue) cleanVisitCount=\(result.cleanVisitCount) matchedVisitCount=\(result.matchedVisitCount) localValidPastVisitCount=\(result.localValidPastVisitCount) classificationRegular=\(result.classificationRegular) classificationAccepted=\(result.classificationAccepted) classificationRejectedReason=\(classificationReason) lastVisitCandidate=\(candidate) lastVisitAccepted=\(accepted) rejectedReason=\(reason) finalLabel=\(result.finalLabel) confidence=\(result.confidence.rawValue)")
    #endif
  }

  private static func guestTruthTrace(
    reservationID: Int,
    candidate: ReservationRecord,
    counted: Bool,
    rejectedReason: String?
  ) {
    #if DEBUG
    let superseded = candidate.supersededById.map(String.init) ?? "nil"
    let reason = rejectedReason ?? "none"
    print("[GUEST_TRUTH_TRACE] reservationID=\(reservationID) candidateID=\(candidate.remoteID) candidateDate=\(candidate.reservationDate)T\(candidate.reservationTime) status=\(candidate.statusValue.rawValue) isHidden=\(candidate.isHidden) supersededById=\(superseded) counted=\(counted) rejectedReason=\(reason)")
    #endif
  }

  private static func guestTruthSummaryTrace(
    reservationID: Int,
    candidateCount: Int,
    acceptedCount: Int,
    rejectedCounts: [String: Int]
  ) {
    #if DEBUG
    let rejected = rejectedCounts.keys.sorted().map {
      "\($0):\(rejectedCounts[$0] ?? 0)"
    }.joined(separator: ",")
    print("[GUEST_TRUTH_TRACE] reservationID=\(reservationID) candidateCount=\(candidateCount) acceptedCount=\(acceptedCount) rejectedCounts=\(rejected.isEmpty ? "none" : rejected)")
    #endif
  }

  private static func guestDetailTrace(
    reservationID: Int,
    selectedDate: String,
    selectedTime: String,
    backendCandidate: String?,
    localCandidate: String?,
    chosen: String?,
    rejectedFutureBackendDate: Bool
  ) {
    #if DEBUG
    let backend = backendCandidate ?? "nil"
    let local = localCandidate ?? "nil"
    let selected = chosen ?? "nil"
    let rejected = rejectedFutureBackendDate ? "yes" : "no"
    print("[GUEST_DETAIL_TRACE] selectedReservationID=\(reservationID) selectedServiceDateTime=\(selectedDate)T\(selectedTime) backendLastVisitCandidate=\(backend) localLastVisitCandidate=\(local) chosenLastVisit=\(selected) rejectedFutureBackendDate=\(rejected)")
    #endif
  }

  private static func perfTrace(
    operation: String,
    reservationID: Int,
    candidateCount: Int,
    duration: Duration
  ) {
    #if DEBUG
    let milliseconds = Int(duration.pressureTraceTimeInterval * 1_000)
    print("[INTEL_PERF_TRACE] operation=\(operation) reservationID=\(reservationID) candidateCount=\(candidateCount) durationMs=\(milliseconds)")
    #endif
  }
}

extension GuestOperationalTruth.Regularity {
  var guestLevel: GuestRegularityLevel {
    switch self {
    case .firstTime, .unknown: return .firstTime
    case .seenBefore: return .seenBefore
    case .regular: return .regular
    }
  }
}
