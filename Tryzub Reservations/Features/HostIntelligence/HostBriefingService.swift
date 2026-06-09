//
//  HostBriefingService.swift
//  Tryzub Reservations
//
//  Template briefing and fact ranking for Host Intelligence.
//  Pure, deterministic, read-only.
//

import Foundation

struct HostBriefingService {

  // MARK: - Public

  func rankHostFacts(_ facts: [HostBriefingFact]) -> [HostBriefingFact] {
    facts.sorted { lhs, rhs in
      if lhs.severity.rank != rhs.severity.rank {
        return lhs.severity.rank < rhs.severity.rank
      }
      if categoryRank(lhs.category) != categoryRank(rhs.category) {
        return categoryRank(lhs.category) < categoryRank(rhs.category)
      }
      return lhs.title < rhs.title
    }
  }

  func buildTemplateBriefingFallback(
    from facts: [HostBriefingFact],
    serviceState: HostServiceState
  ) -> String {
    let ranked = rankHostFacts(facts)
    guard !ranked.isEmpty else {
      return stableMessage(for: serviceState)
    }

    let topFacts = ranked.prefix(3)
    var sentences: [String] = []

    for fact in topFacts {
      let detail = fact.detail.trimmingCharacters(in: .whitespacesAndNewlines)
      if !detail.isEmpty {
        sentences.append(detail.hasSuffix(".") ? detail : "\(detail).")
      }
      if let action = fact.suggestedActionTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
         !action.isEmpty
      {
        let actionSentence = action.hasSuffix(".") ? action : "\(action)."
        sentences.append(actionSentence)
      }
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
