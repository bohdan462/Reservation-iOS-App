//
//  HostBriefingService.swift
//  Tryzub Reservations
//
//  Template briefing and fact ranking for Host Intelligence.
//  Pure, deterministic, read-only.
//

import Foundation

struct HostBriefingService {

  private let maxTemplateFacts = 2
  private let maxTemplateSentences = 2

  // MARK: - Public

  func rankSuggestedActions(
    _ actions: [HostSuggestedAction],
    reservations: [ReservationRecord],
    now: Date,
    settings: HostIntelligenceSettings
  ) -> [HostSuggestedAction] {
    let lookup = Dictionary(uniqueKeysWithValues: reservations.map { ($0.remoteID, $0) })

    return actions.sorted { lhs, rhs in
      let lhsScore = actionPriorityScore(
        lhs,
        lookup: lookup,
        now: now,
        settings: settings
      )
      let rhsScore = actionPriorityScore(
        rhs,
        lookup: lookup,
        now: now,
        settings: settings
      )
      if lhsScore != rhsScore {
        return lhsScore > rhsScore
      }
      if lhs.severity.rank != rhs.severity.rank {
        return lhs.severity.rank < rhs.severity.rank
      }
      return lhs.title < rhs.title
    }
  }

  func rankHostFacts(_ facts: [HostBriefingFact]) -> [HostBriefingFact] {
    facts.sorted { lhs, rhs in
      if lhs.severity.rank != rhs.severity.rank {
        return lhs.severity.rank < rhs.severity.rank
      }
      let lhsCategoryRank = effectiveCategoryRank(for: lhs)
      let rhsCategoryRank = effectiveCategoryRank(for: rhs)
      if lhsCategoryRank != rhsCategoryRank {
        return lhsCategoryRank < rhsCategoryRank
      }
      return lhs.title < rhs.title
    }
  }

  func buildTemplateBriefingFallback(
    from facts: [HostBriefingFact],
    serviceState: HostServiceState
  ) -> String {
    let ranked = rankHostFacts(facts)
    let selected = selectTemplateFacts(from: ranked, maxCount: maxTemplateFacts)
    guard !selected.isEmpty else {
      return stableMessage(for: serviceState)
    }

    var sentences: [String] = []
    for fact in selected {
      guard sentences.count < maxTemplateSentences else { break }
      guard let sentence = templateSentence(for: fact) else { continue }
      if !sentences.contains(where: { HostStaffLanguage.areSameStaffMeaning($0, sentence) }) {
        sentences.append(sentence)
      }
    }

    if sentences.count < maxTemplateSentences,
       let fact = selected.first,
       let checkSentence = templateGenericCheckSentence(for: fact),
       !sentences.contains(where: { HostStaffLanguage.areSameStaffMeaning($0, checkSentence) }) {
      sentences.append(checkSentence)
    }

    if sentences.count < maxTemplateSentences,
       let actionSentence = templateActionSentence(for: selected.first, existing: sentences),
       !sentences.contains(where: { HostStaffLanguage.areSameStaffMeaning($0, actionSentence) }) {
      sentences.append(actionSentence)
    }

    let briefing = sentences.prefix(maxTemplateSentences).joined(separator: " ")
    return briefing.isEmpty ? stableMessage(for: serviceState) : briefing
  }

  func makeLLMFact(from fact: HostBriefingFact) -> HostLLMFact? {
    guard !GuestHistorySemantics.containsInventedOccasionNoteLanguage(
      title: fact.title,
      detail: fact.detail
    ) else {
      return nil
    }

    let category = sanitizedCategory(for: fact)
    return HostLLMFact(
      severity: fact.severity,
      category: category,
      title: fact.title,
      detail: fact.detail,
      evidence: fact.evidence,
      suggestedAction: fact.suggestedActionTitle
    )
  }

  private func sanitizedCategory(for fact: HostBriefingFact) -> HostFactCategory {
    if fact.category == .note,
       isReturningGuestFact(fact) || fact.title == "Seen before" {
      return .guest
    }
    return fact.category
  }

  // MARK: - Template Selection

  private func selectTemplateFacts(
    from ranked: [HostBriefingFact],
    maxCount: Int
  ) -> [HostBriefingFact] {
    var selected: [HostBriefingFact] = []
    var lowRiskByReservation: [Int: HostBriefingFact] = [:]
    var returningReservationIDs = Set<Int>()
    var returningGuestNames = Set<String>()

    for fact in ranked {
      guard selected.count < maxCount else { break }

      if isReturningGuestFact(fact) {
        let reservationIDs = fact.relatedReservationIDs
        if reservationIDs.contains(where: returningReservationIDs.contains) {
          continue
        }
        if let guestName = guestName(fromReturningFact: fact) {
          let nameKey = guestName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
          if returningGuestNames.contains(nameKey) {
            continue
          }
          returningGuestNames.insert(nameKey)
        }
        reservationIDs.forEach { returningReservationIDs.insert($0) }
      }

      if let reservationID = fact.relatedReservationIDs.first,
         fact.relatedReservationIDs.count == 1,
         collapsesPerReservationLowRisk(fact) {
        if let existing = lowRiskByReservation[reservationID] {
          if templateFactPriority(fact) >= templateFactPriority(existing) {
            continue
          }
          selected.removeAll { $0.id == existing.id }
        }
        lowRiskByReservation[reservationID] = fact
      }

      selected.append(fact)
    }

    return selected
  }

  private func collapsesPerReservationLowRisk(_ fact: HostBriefingFact) -> Bool {
    switch fact.category {
    case .preference, .guest, .note:
      return true
    default:
      return false
    }
  }

  private func templateFactPriority(_ fact: HostBriefingFact) -> Int {
    switch fact.category {
    case .allergy: return 0
    case .preference: return 1
    case .guest:
      return isReturningGuestFact(fact) ? 2 : 3
    case .note: return 4
    case .bookingDecision: return 5
    default: return 100
    }
  }

  // MARK: - Private

  private func stableMessage(for serviceState: HostServiceState) -> String {
    switch serviceState {
    case .calm:
      return "Nothing needs attention right now."
    case .building:
      return "More guests are arriving soon. Watch the next seating window."
    case .busy:
      return "The floor is getting busy. Check tables still open and upcoming arrivals."
    case .critical:
      return "Service is very busy. Start with the most urgent items."
    }
  }

  private func templateSentence(for fact: HostBriefingFact) -> String? {
    let title = HostStaffLanguage.rewrite(fact.title)
    let detail = HostStaffLanguage.rewrite(fact.detail)

    if !title.isEmpty, !HostStaffLanguage.isGenericCheckLine(title) {
      if detail.isEmpty || HostStaffLanguage.isGenericCheckLine(detail) {
        return punctuate(title)
      }
    }

    if !detail.isEmpty, !HostStaffLanguage.isGenericCheckLine(detail) {
      return punctuate(detail)
    }

    if !title.isEmpty {
      return punctuate(title)
    }
    return nil
  }

  private func templateGenericCheckSentence(for fact: HostBriefingFact) -> String? {
    let detail = HostStaffLanguage.rewrite(fact.detail)
    if !detail.isEmpty, HostStaffLanguage.isGenericCheckLine(detail) {
      return punctuate(detail)
    }

    let action = HostStaffLanguage.rewrite(fact.suggestedActionTitle ?? "")
    if !action.isEmpty, HostStaffLanguage.isGenericCheckLine(action) {
      return punctuate(action)
    }
    return nil
  }

  private func templateActionSentence(
    for fact: HostBriefingFact?,
    existing sentences: [String]
  ) -> String? {
    guard let fact else { return nil }
    let action = HostStaffLanguage.rewrite(fact.suggestedActionTitle ?? "")
    guard !action.isEmpty, !HostStaffLanguage.isGenericCheckLine(action) else {
      return nil
    }

    let corpus = ([fact.detail, fact.title] + sentences)
      .map { HostStaffLanguage.rewrite($0) }
    if corpus.contains(where: { HostStaffLanguage.areSameStaffMeaning($0, action) }) {
      return nil
    }

    return punctuate(action)
  }

  private func punctuate(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    return trimmed.hasSuffix(".") ? trimmed : "\(trimmed)."
  }

  private func isNearDuplicateSentence(_ lhs: String, _ rhs: String) -> Bool {
    normalizeSentence(lhs) == normalizeSentence(rhs)
  }

  private func normalizeSentence(_ text: String) -> String {
    text
      .lowercased()
      .replacingOccurrences(of: #"[^\w\s]"#, with: "", options: .regularExpression)
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }

  private func isReturningGuestFact(_ fact: HostBriefingFact) -> Bool {
    guard fact.category == .guest else { return false }
    if fact.title == "Seen before" || fact.title == "Returning guest" || fact.title == "Regular guest" {
      return true
    }
    return fact.evidence.contains { $0 == "returningGuest" || $0.hasPrefix("returningGuest") }
  }

  private func guestName(fromReturningFact fact: HostBriefingFact) -> String? {
    let detail = fact.detail.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !detail.isEmpty else { return nil }
    if let range = detail.range(of: " is returning") {
      return String(detail[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let range = detail.range(of: " has been seen before") {
      return String(detail[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let range = detail.range(of: " is a frequent returning guest") {
      return String(detail[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let range = detail.range(of: " has been seen before") {
      return String(detail[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return nil
  }

  private func effectiveCategoryRank(for fact: HostBriefingFact) -> Int {
    if isReturningGuestFact(fact) {
      return 9
    }
    return categoryRank(fact.category)
  }

  private func actionPriorityScore(
    _ action: HostSuggestedAction,
    lookup: [Int: ReservationRecord],
    now: Date,
    settings: HostIntelligenceSettings
  ) -> Int {
    var score = max(0, 4 - action.severity.rank) * 20

    switch action.kind {
    case .reviewReservation, .confirmReservation, .suggestAlternateTime:
      score += 10
    case .assignTable, .holdTable:
      score += 8
    default:
      break
    }

    for reservationID in action.relatedReservationIDs {
      guard let reservation = lookup[reservationID] else { continue }

      if reservation.statusValue == .new || reservation.statusValue == .needsReview {
        score += 45
      }
      if !reservation.hasTableAssignment {
        score += 40
      }
      if reservation.partySize >= settings.largePartyThreshold {
        score += 25
      }
      if reservation.statusValue == .confirmed, reservation.hasTableAssignment {
        score -= 70
      }

      switch reservation.operationalTimingState(now: now) {
      case .overdue, .dueNow:
        score += 55
      case .dueSoon:
        score += 40
      case .normal:
        score += 5
      case .none:
        break
      }
    }

    return score
  }

  private func categoryRank(_ category: HostFactCategory) -> Int {
    switch category {
    case .largeParty: return 0
    case .capacity: return 1
    case .table: return 2
    case .overdue: return 3
    case .opportunity: return 4
    case .cancellation: return 5
    case .allergy: return 6
    case .arrivalWave: return 7
    case .preference: return 8
    case .duplicate: return 9
    case .timing: return 10
    case .bookingDecision: return 11
    case .analytics: return 12
    case .guest: return 13
    case .note: return 14
    case .sync: return 15
    case .unknown: return 16
    }
  }
}
