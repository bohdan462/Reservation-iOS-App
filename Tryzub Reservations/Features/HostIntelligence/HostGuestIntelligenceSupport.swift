//
//  HostGuestIntelligenceSupport.swift
//  Tryzub Reservations
//
//  Deterministic guest memory signals for Host Intelligence.
//

import Foundation

enum HostGuestIntelligenceSupport {

  private static let insightsController = GuestInsightsController()

  struct GuestIntelligenceMetrics {
    let allergyCount: Int
    let accessibilityCount: Int
    let previousServiceIssueCount: Int
    let noShowRiskCount: Int
    let cancellationRiskCount: Int
    let regularGuestCount: Int
  }

  // MARK: - Public

  static func buildGuestSignals(
    activeReservations: [ReservationRecord],
    allDayReservations: [ReservationRecord],
    allKnownReservations: [ReservationRecord],
    settings: HostIntelligenceSettings
  ) -> [HostGuestSignal] {
    guard settings.includeGuestSignals else { return [] }

    let historyPool = historyReservations(
      allKnown: allKnownReservations,
      dayReservations: allDayReservations
    )

    var signals: [HostGuestSignal] = []
    var seenKeys = Set<String>()

    for reservation in activeReservations {
      let report = insightsController.analyze(
        selected: reservation,
        allReservations: historyPool
      )

      appendUnique(&signals, &seenKeys, allergySignal(for: reservation))
      appendUnique(&signals, &seenKeys, regularGuestSignal(for: reservation, report: report))
      appendUnique(&signals, &seenKeys, importantGuestSignal(for: reservation, report: report))
      appendUnique(&signals, &seenKeys, contentsOf: seatingPreferenceSignals(for: reservation))
      appendUnique(&signals, &seenKeys, contentsOf: accessibilitySignals(for: reservation))
      appendUnique(&signals, &seenKeys, contentsOf: specialOccasionSignals(for: reservation))
      appendUnique(&signals, &seenKeys, cancellationRiskSignal(for: reservation, report: report))
      appendUnique(&signals, &seenKeys, noShowRiskSignal(for: reservation, report: report))
      appendUnique(&signals, &seenKeys, previousServiceIssueSignal(for: reservation))
      appendUnique(&signals, &seenKeys, manualCallInSignal(for: reservation, report: report))
      appendUnique(&signals, &seenKeys, possibleDuplicateSignal(for: reservation, report: report))
    }

    return signals
  }

  static func buildGuestBriefingFacts(
    signals: [HostGuestSignal]
  ) -> [HostBriefingFact] {
    var facts: [HostBriefingFact] = []

    let individualKinds: Set<HostGuestSignalKind> = [
      .allergy, .accessibility, .previousServiceIssue, .noShowRisk,
      .cancellationRisk, .possibleDuplicate, .importantGuest, .manualCallIn, .specialOccasion
    ]

    for signal in signals where individualKinds.contains(signal.kind) {
      facts.append(fact(from: signal))
    }

    facts.append(contentsOf: groupedFacts(
      signals: signals.filter { $0.kind == .regularGuest },
      id: "regular-guests-group",
      title: "Regular guests today",
      singularTitle: "Regular guest today",
      detailPrefix: "regular guests are coming today",
      category: .guest,
      severity: .watch,
      suggestedActionTitle: "Recognize returning guests at arrival."
    ))

    facts.append(contentsOf: groupedFacts(
      signals: signals.filter { $0.kind == .seatingPreference },
      id: "seating-preference-group",
      title: "Seating preferences",
      singularTitle: "Seating preference",
      detailPrefix: "guests have seating preferences today",
      category: .preference,
      severity: .watch,
      suggestedActionTitle: "Review seating notes before assigning tables."
    ))

    return facts
  }

  static func buildGuestSuggestedActions(
    signals: [HostGuestSignal]
  ) -> [HostSuggestedAction] {
    signals.compactMap { signal in
      switch signal.kind {
      case .allergy:
        return suggestedAction(
          id: "guest-action-allergy-\(signal.reservationID)",
          signal: signal,
          kind: .alertServer,
          title: "Review allergy notes for \(signal.guestName)",
          reason: signal.message
        )
      case .accessibility:
        return suggestedAction(
          id: "guest-action-accessibility-\(signal.reservationID)",
          signal: signal,
          kind: .assignTable,
          title: "Plan accessible seating for \(signal.guestName)",
          reason: signal.message
        )
      case .seatingPreference:
        return suggestedAction(
          id: "guest-action-seating-\(signal.reservationID)",
          signal: signal,
          kind: .assignTable,
          title: "Review seating preference for \(signal.guestName)",
          reason: signal.message
        )
      case .previousServiceIssue:
        return suggestedAction(
          id: "guest-action-service-issue-\(signal.reservationID)",
          signal: signal,
          kind: .alertServer,
          title: "Alert server about \(signal.guestName)",
          reason: signal.message
        )
      case .noShowRisk, .cancellationRisk:
        return suggestedAction(
          id: "guest-action-risk-\(signal.kind.rawValue)-\(signal.reservationID)",
          signal: signal,
          kind: .reviewReservation,
          title: "Review booking risk for \(signal.guestName)",
          reason: signal.message
        )
      case .possibleDuplicate:
        return suggestedAction(
          id: "guest-action-duplicate-\(signal.reservationID)",
          signal: signal,
          kind: .reviewReservation,
          title: "Review possible same guest for \(signal.guestName)",
          reason: signal.message
        )
      case .manualCallIn:
        return suggestedAction(
          id: "guest-action-callin-\(signal.reservationID)",
          signal: signal,
          kind: .reviewReservation,
          title: "Review call-in details for \(signal.guestName)",
          reason: signal.message
        )
      case .specialOccasion:
        return suggestedAction(
          id: "guest-action-occasion-\(signal.reservationID)",
          signal: signal,
          kind: .alertServer,
          title: "Note special occasion for \(signal.guestName)",
          reason: signal.message
        )
      case .regularGuest, .vip, .importantGuest, .noteReminder, .unknown:
        return nil
      }
    }
  }

  static func metrics(from signals: [HostGuestSignal]) -> GuestIntelligenceMetrics {
    GuestIntelligenceMetrics(
      allergyCount: signals.filter { $0.kind == .allergy }.count,
      accessibilityCount: signals.filter { $0.kind == .accessibility }.count,
      previousServiceIssueCount: signals.filter { $0.kind == .previousServiceIssue }.count,
      noShowRiskCount: signals.filter { $0.kind == .noShowRisk }.count,
      cancellationRiskCount: signals.filter { $0.kind == .cancellationRisk }.count,
      regularGuestCount: signals.filter { $0.kind == .regularGuest || $0.kind == .importantGuest }.count
    )
  }

  // MARK: - History Pool

  private static func historyReservations(
    allKnown: [ReservationRecord],
    dayReservations: [ReservationRecord]
  ) -> [ReservationRecord] {
    if !allKnown.isEmpty {
      return allKnown
    }
    // Guest memory only — historical pressure uses backend aggregate analytics, not local cache breadth.
    return dayReservations
  }

  // MARK: - Per-Guest Signals

  private static func allergySignal(for reservation: ReservationRecord) -> HostGuestSignal? {
    let combined = combinedNotes(for: reservation)
    guard !combined.isEmpty else { return nil }

    let matched = matchedKeywords(in: combined, keywords: allergyKeywords, negations: allergyNegationPhrases)
    guard !matched.isEmpty else { return nil }

    return HostGuestSignal(
      id: "guest-allergy-\(reservation.remoteID)",
      reservationID: reservation.remoteID,
      guestName: reservation.guestName,
      kind: .allergy,
      severity: .critical,
      message: "\(reservation.guestName) has allergy-related notes.",
      evidence: matched
    )
  }

  private static func regularGuestSignal(
    for reservation: ReservationRecord,
    report: GuestInsightReport
  ) -> HostGuestSignal? {
    guard report.regularityLevel.rank >= GuestRegularityLevel.becomingRegular.rank else {
      return nil
    }

    var evidence = [
      "regularGuest",
      "visitCount=\(report.summary.totalMatchedReservations)",
      "regularity=\(report.regularityLevel.displayName)"
    ]
    if report.hasReliableContactIdentity {
      evidence.append(report.primaryPhone != nil ? "matchedByPhone" : "matchedByEmail")
    }

    return HostGuestSignal(
      id: "guest-regular-\(reservation.remoteID)",
      reservationID: reservation.remoteID,
      guestName: reservation.guestName,
      kind: .regularGuest,
      severity: .info,
      message: "\(reservation.guestName) is a returning guest.",
      evidence: evidence
    )
  }

  private static func importantGuestSignal(
    for reservation: ReservationRecord,
    report: GuestInsightReport
  ) -> HostGuestSignal? {
    guard report.regularityLevel == .frequentRegular else { return nil }

    return HostGuestSignal(
      id: "guest-important-\(reservation.remoteID)",
      reservationID: reservation.remoteID,
      guestName: reservation.guestName,
      kind: .importantGuest,
      severity: .watch,
      message: "\(reservation.guestName) is a frequent regular guest.",
      evidence: [
        "frequentRegular",
        "visitCount=\(report.summary.totalMatchedReservations)"
      ]
    )
  }

  private static func seatingPreferenceSignals(
    for reservation: ReservationRecord
  ) -> [HostGuestSignal] {
    keywordSignals(
      for: reservation,
      keywords: seatingPreferenceKeywords,
      kind: .seatingPreference,
      severity: .watch,
      messagePrefix: "has a seating preference"
    )
  }

  private static func accessibilitySignals(
    for reservation: ReservationRecord
  ) -> [HostGuestSignal] {
    keywordSignals(
      for: reservation,
      keywords: accessibilityKeywords,
      kind: .accessibility,
      severity: .warning,
      messagePrefix: "has accessibility needs noted"
    )
  }

  private static func specialOccasionSignals(
    for reservation: ReservationRecord
  ) -> [HostGuestSignal] {
    keywordSignals(
      for: reservation,
      keywords: specialOccasionKeywords,
      kind: .specialOccasion,
      severity: .watch,
      messagePrefix: "has a special occasion noted"
    )
  }

  private static func cancellationRiskSignal(
    for reservation: ReservationRecord,
    report: GuestInsightReport
  ) -> HostGuestSignal? {
    let cancelledCount = report.matchedReservations.filter {
      $0.status == .cancelled
    }.count
    guard cancelledCount >= 3 else { return nil }

    return HostGuestSignal(
      id: "guest-cancel-risk-\(reservation.remoteID)",
      reservationID: reservation.remoteID,
      guestName: reservation.guestName,
      kind: .cancellationRisk,
      severity: .watch,
      message: "\(reservation.guestName) has prior cancellations in guest memory.",
      evidence: ["cancelledCount=\(cancelledCount)"]
    )
  }

  private static func noShowRiskSignal(
    for reservation: ReservationRecord,
    report: GuestInsightReport
  ) -> HostGuestSignal? {
    let noShowCount = report.matchedReservations.filter {
      $0.status == .noShow
    }.count
    guard noShowCount >= 2 else { return nil }

    return HostGuestSignal(
      id: "guest-noshow-risk-\(reservation.remoteID)",
      reservationID: reservation.remoteID,
      guestName: reservation.guestName,
      kind: .noShowRisk,
      severity: .warning,
      message: "\(reservation.guestName) has prior no-shows in guest memory.",
      evidence: ["noShowCount=\(noShowCount)"]
    )
  }

  private static func previousServiceIssueSignal(
    for reservation: ReservationRecord
  ) -> HostGuestSignal? {
    let staffNotes = (reservation.staffNotes ?? "").lowercased()
    guard !staffNotes.isEmpty else { return nil }

    let matched = serviceIssueKeywords.filter { staffNotes.contains($0) }
    guard !matched.isEmpty else { return nil }

    return HostGuestSignal(
      id: "guest-service-issue-\(reservation.remoteID)",
      reservationID: reservation.remoteID,
      guestName: reservation.guestName,
      kind: .previousServiceIssue,
      severity: .warning,
      message: "\(reservation.guestName) has prior service-issue notes.",
      evidence: matched
    )
  }

  private static func manualCallInSignal(
    for reservation: ReservationRecord,
    report: GuestInsightReport
  ) -> HostGuestSignal? {
    guard report.isLikelyManualGuest || reservation.isManualOrCallIn else { return nil }

    var evidence = ["manualCallIn"]
    if !reservation.hasUsableConfirmationEmail {
      evidence.append("placeholderEmail")
    }

    return HostGuestSignal(
      id: "guest-callin-\(reservation.remoteID)",
      reservationID: reservation.remoteID,
      guestName: reservation.guestName,
      kind: .manualCallIn,
      severity: .info,
      message: "\(reservation.guestName) is a manual call-in reservation.",
      evidence: evidence
    )
  }

  private static func possibleDuplicateSignal(
    for reservation: ReservationRecord,
    report: GuestInsightReport
  ) -> HostGuestSignal? {
    if let superseded = reservation.supersededById, superseded > 0 {
      return HostGuestSignal(
        id: "guest-duplicate-superseded-\(reservation.remoteID)",
        reservationID: reservation.remoteID,
        guestName: reservation.guestName,
        kind: .possibleDuplicate,
        severity: .watch,
        message: "\(reservation.guestName) may be a duplicate or corrected booking.",
        evidence: ["supersededById=\(superseded)"]
      )
    }

    let staffNotes = (reservation.staffNotes ?? "").lowercased()
    if staffNotes.contains("possible duplicate") || staffNotes.contains("correction") {
      return HostGuestSignal(
        id: "guest-duplicate-note-\(reservation.remoteID)",
        reservationID: reservation.remoteID,
        guestName: reservation.guestName,
        kind: .possibleDuplicate,
        severity: .watch,
        message: "\(reservation.guestName) may need duplicate review.",
        evidence: ["staffNoteFlag=duplicateOrCorrection"]
      )
    }

    if report.collapsedDuplicateReservationCount > 0 {
      return HostGuestSignal(
        id: "guest-duplicate-intent-\(reservation.remoteID)",
        reservationID: reservation.remoteID,
        guestName: reservation.guestName,
        kind: .possibleDuplicate,
        severity: .watch,
        message: "\(reservation.guestName) may have duplicate booking copies in cache.",
        evidence: ["collapsedDuplicateIntent"]
      )
    }

    if let identityMatch = report.possibleMatches.first {
      var evidence = identityMatch.matchReasons
      if evidence.isEmpty {
        evidence = ["possibleIdentityMatch"]
      }
      return HostGuestSignal(
        id: "guest-duplicate-identity-\(reservation.remoteID)",
        reservationID: reservation.remoteID,
        guestName: reservation.guestName,
        kind: .possibleDuplicate,
        severity: .watch,
        message: "Possible same guest for \(reservation.guestName). Review only; nothing is merged.",
        evidence: evidence
      )
    }

    return nil
  }

  // MARK: - Facts / Actions Helpers

  private static func fact(from signal: HostGuestSignal) -> HostBriefingFact {
    HostBriefingFact(
      id: "guest-fact-\(signal.kind.rawValue)-\(signal.reservationID)",
      severity: signal.severity,
      category: category(for: signal.kind),
      title: title(for: signal.kind),
      detail: signal.message,
      evidence: signal.evidence,
      relatedReservationIDs: [signal.reservationID],
      suggestedActionTitle: suggestedActionTitle(for: signal.kind)
    )
  }

  private static func groupedFacts(
    signals: [HostGuestSignal],
    id: String,
    title: String,
    singularTitle: String,
    detailPrefix: String,
    category: HostFactCategory,
    severity: HostSeverity,
    suggestedActionTitle: String?
  ) -> [HostBriefingFact] {
    guard !signals.isEmpty else { return [] }

    if signals.count == 1, let signal = signals.first {
      return [fact(from: signal)]
    }

    return [
      HostBriefingFact(
        id: id,
        severity: severity,
        category: category,
        title: title,
        detail: "\(signals.count) \(detailPrefix).",
        evidence: ["count=\(signals.count)"],
        relatedReservationIDs: signals.map(\.reservationID),
        suggestedActionTitle: suggestedActionTitle
      )
    ]
  }

  private static func suggestedAction(
    id: String,
    signal: HostGuestSignal,
    kind: HostActionKind,
    title: String,
    reason: String
  ) -> HostSuggestedAction {
    HostSuggestedAction(
      id: id,
      severity: signal.severity,
      kind: kind,
      title: title,
      reason: reason,
      relatedReservationIDs: [signal.reservationID],
      targetSlotTime: nil,
      targetTableName: nil,
      requiresStaffConfirmation: true
    )
  }

  private static func category(for kind: HostGuestSignalKind) -> HostFactCategory {
    switch kind {
    case .allergy: return .allergy
    case .regularGuest, .vip, .importantGuest, .manualCallIn: return .guest
    case .specialOccasion: return .guest
    case .seatingPreference: return .preference
    case .accessibility: return .guest
    case .cancellationRisk, .noShowRisk: return .guest
    case .previousServiceIssue: return .note
    case .possibleDuplicate: return .duplicate
    case .noteReminder: return .note
    case .unknown: return .unknown
    }
  }

  private static func title(for kind: HostGuestSignalKind) -> String {
    switch kind {
    case .allergy: return "Allergy note"
    case .regularGuest: return "Regular guest"
    case .vip, .importantGuest: return "Important guest"
    case .specialOccasion: return "Special occasion"
    case .seatingPreference: return "Seating preference"
    case .accessibility: return "Accessibility need"
    case .cancellationRisk: return "Cancellation risk"
    case .noShowRisk: return "No-show risk"
    case .previousServiceIssue: return "Prior service issue"
    case .manualCallIn: return "Manual call-in"
    case .possibleDuplicate: return "Possible same guest"
    case .noteReminder: return "Note reminder"
    case .unknown: return "Guest note"
    }
  }

  private static func suggestedActionTitle(for kind: HostGuestSignalKind) -> String? {
    switch kind {
    case .allergy: return "Review allergy notes before seating."
    case .accessibility: return "Plan accessible seating."
    case .seatingPreference: return "Review seating preference before assigning."
    case .previousServiceIssue: return "Alert the server before seating."
    case .noShowRisk, .cancellationRisk: return "Review before confirming."
    case .possibleDuplicate: return "Review possible same guest before confirming."
    case .manualCallIn: return "Confirm contact details manually."
    case .specialOccasion: return "Mention the occasion at arrival."
    default: return nil
    }
  }

  // MARK: - Keyword Helpers

  private static func keywordSignals(
    for reservation: ReservationRecord,
    keywords: [String],
    kind: HostGuestSignalKind,
    severity: HostSeverity,
    messagePrefix: String
  ) -> [HostGuestSignal] {
    let combined = combinedNotes(for: reservation)
    guard !combined.isEmpty else { return [] }

    let matched = matchedKeywords(in: combined, keywords: keywords, negations: [])
    guard !matched.isEmpty else { return [] }

    return [
      HostGuestSignal(
        id: "guest-\(kind.rawValue)-\(reservation.remoteID)",
        reservationID: reservation.remoteID,
        guestName: reservation.guestName,
        kind: kind,
        severity: severity,
        message: "\(reservation.guestName) \(messagePrefix).",
        evidence: matched
      )
    ]
  }

  private static func combinedNotes(for reservation: ReservationRecord) -> String {
    "\(reservation.guestNotes ?? "") \(reservation.staffNotes ?? "")"
      .lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func matchedKeywords(
    in text: String,
    keywords: [String],
    negations: [String]
  ) -> [String] {
    keywords.filter { keyword in
      guard text.contains(keyword) else { return false }
      return !isNegated(keyword: keyword, in: text, negations: negations)
    }
  }

  private static func isNegated(
    keyword: String,
    in text: String,
    negations: [String]
  ) -> Bool {
    if negations.contains(where: { phrase in
      text.contains(phrase) && (phrase.contains(keyword) || keyword == "allergy" || keyword == "allergic")
    }) {
      return true
    }

    guard let range = text.range(of: keyword) else { return false }
    let prefix = text[..<range.lowerBound].suffix(8)
    return prefix.hasSuffix("no ") || prefix.hasSuffix("not ")
  }

  private static func appendUnique(
    _ signals: inout [HostGuestSignal],
    _ seenKeys: inout Set<String>,
    _ signal: HostGuestSignal?
  ) {
    guard let signal else { return }
    let key = "\(signal.kind.rawValue)-\(signal.reservationID)"
    guard !seenKeys.contains(key) else { return }
    seenKeys.insert(key)
    signals.append(signal)
  }

  private static func appendUnique(
    _ signals: inout [HostGuestSignal],
    _ seenKeys: inout Set<String>,
    contentsOf newSignals: [HostGuestSignal]
  ) {
    for signal in newSignals {
      appendUnique(&signals, &seenKeys, signal)
    }
  }

  private static let allergyKeywords = [
    "allergy", "allergic", "shellfish", "shrimp", "crab", "lobster",
    "nuts", "peanut", "gluten", "dairy", "celiac"
  ]

  private static let allergyNegationPhrases = [
    "no allergy", "no allergies", "not allergic", "no shellfish allergy"
  ]

  private static let seatingPreferenceKeywords = [
    "quiet", "booth", "patio", "window", "away from bar", "high chair",
    "kids", "stroller", "corner", "bar seating"
  ]

  private static let accessibilityKeywords = [
    "wheelchair", "walker", "accessible", "accessibility", "no stairs", "low table"
  ]

  private static let specialOccasionKeywords = [
    "birthday", "anniversary", "celebration", "engagement", "date night"
  ]

  private static let serviceIssueKeywords = [
    "issue", "complained", "complaint", "unhappy", "remake",
    "manager", "problem", "bad experience", "service issue"
  ]
}
