//
//  HostOperationalBriefingPromptBuilder.swift
//  Tryzub Reservations
//
//  Deterministic grouped operational prompts from Host Intelligence facts.
//

import Foundation

enum HostOperationalBriefingPromptCategory: String, Codable, CaseIterable, Equatable {
  case reservationAttention
  case tablePlan
  case guestNotes
  case timing
  case booking
  case general

  var displayTitle: String {
    switch self {
    case .reservationAttention: return "Reservation attention"
    case .tablePlan: return "Table plan"
    case .guestNotes: return "Guest notes"
    case .timing: return "Timing"
    case .booking: return "Booking"
    case .general: return "Service status"
    }
  }
}

enum HostOperationalBriefingPromptSource: String, Equatable {
  case deterministic

  var displayName: String { "Deterministic" }
}

struct HostOperationalBriefingPrompt: Identifiable, Equatable {
  let id: String
  let title: String
  let body: String
  let category: HostOperationalBriefingPromptCategory
  let severity: HostSeverity
  let source: HostOperationalBriefingPromptSource
  let relatedReservationIDs: [Int]
}

enum HostOperationalBriefingPromptBuilder {
  private static let maxPrompts = 3

  private static let groupOrder: [HostOperationalBriefingPromptCategory] = [
    .tablePlan,
    .guestNotes,
    .timing,
    .reservationAttention,
    .booking
  ]

  private static let categoriesByGroup: [HostOperationalBriefingPromptCategory: Set<HostFactCategory>] = [
    .tablePlan: [.table, .capacity, .opportunity],
    .guestNotes: [.allergy, .preference, .note, .guest],
    .timing: [.arrivalWave, .overdue, .timing, .largeParty],
    .reservationAttention: [.duplicate, .cancellation, .sync],
    .booking: [.bookingDecision, .analytics]
  ]

  static func build(from snapshot: HostDecisionSnapshot) -> [HostOperationalBriefingPrompt] {
    let facts = snapshot.briefingFacts
    guard !facts.isEmpty else {
      guard snapshot.serviceState == .calm else { return [] }
      return [
        HostOperationalBriefingPrompt(
          id: "operational-general-calm",
          title: HostOperationalBriefingPromptCategory.general.displayTitle,
          body: snapshot.templateBriefingText,
          category: .general,
          severity: .info,
          source: .deterministic,
          relatedReservationIDs: []
        )
      ]
    }

    var prompts: [HostOperationalBriefingPrompt] = []
    var consumedFactIDs = Set<String>()

    for category in groupOrder {
      let matched = facts.filter { fact in
        guard !consumedFactIDs.contains(fact.id) else { return false }
        guard let allowed = categoriesByGroup[category] else { return false }
        return allowed.contains(fact.category)
      }
      guard !matched.isEmpty else { continue }

      matched.forEach { consumedFactIDs.insert($0.id) }
      if let prompt = buildPrompt(category: category, facts: matched) {
        prompts.append(prompt)
      }
      if prompts.count >= maxPrompts { break }
    }

    return Array(prompts.prefix(maxPrompts))
  }

  private static func buildPrompt(
    category: HostOperationalBriefingPromptCategory,
    facts: [HostBriefingFact]
  ) -> HostOperationalBriefingPrompt? {
    guard !facts.isEmpty else { return nil }

    let sentences = facts.prefix(2).compactMap { sentence(for: $0) }
    guard !sentences.isEmpty else { return nil }

    let severity = facts.map(\.severity).min(by: { $0.rank < $1.rank }) ?? .info
    let reservationIDs = Array(Set(facts.flatMap(\.relatedReservationIDs))).sorted()

    return HostOperationalBriefingPrompt(
      id: "operational-\(category.rawValue)",
      title: category.displayTitle,
      body: sentences.joined(separator: " "),
      category: category,
      severity: severity,
      source: .deterministic,
      relatedReservationIDs: reservationIDs
    )
  }

  private static func sentence(for fact: HostBriefingFact) -> String? {
    let detail = fact.detail.trimmingCharacters(in: .whitespacesAndNewlines)
    if !detail.isEmpty {
      return detail.hasSuffix(".") ? detail : "\(detail)."
    }

    let title = fact.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return nil }
    return title.hasSuffix(".") ? title : "\(title)."
  }
}
