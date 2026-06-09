//
//  HostBriefingService.swift
//  Tryzub Reservations
//
//  Template briefing and fact ranking for Host Intelligence.
//  Pure, deterministic, read-only.
//

import Foundation

struct HostBriefingService {

  private let maxTemplateFacts = 3

  // MARK: - Public

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

    let sentences = selected.compactMap { fact -> String? in
      let detail = fact.detail.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !detail.isEmpty else { return nil }
      return detail.hasSuffix(".") ? detail : "\(detail)."
    }

    let briefing = sentences.joined(separator: " ")
    return briefing.isEmpty ? stableMessage(for: serviceState) : briefing
  }

  func makeLLMFact(from fact: HostBriefingFact) -> HostLLMFact {
    HostLLMFact(
      severity: fact.severity,
      category: fact.category,
      title: fact.title,
      detail: fact.detail,
      evidence: fact.evidence,
      suggestedAction: fact.suggestedActionTitle
    )
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
      return "Service looks stable right now."
    case .building:
      return "Service is building. No urgent issues right now."
    case .busy:
      return "Service is busy. Review the top alerts before seating the next party."
    case .critical:
      return "Service is under heavy pressure. Address critical alerts first."
    }
  }

  private func isReturningGuestFact(_ fact: HostBriefingFact) -> Bool {
    guard fact.category == .guest else { return false }
    if fact.title == "Returning guest" || fact.title == "Regular guest" {
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
