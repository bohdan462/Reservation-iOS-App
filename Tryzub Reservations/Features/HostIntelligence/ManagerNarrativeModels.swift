//
//  ManagerNarrativeModels.swift
//  Tryzub Reservations
//
//  Presentation-only manager narrative shapes. Facts and actions come from
//  deterministic Host engine output — never raw reservation records or notes.
//

import Foundation

enum ManagerNarrativeSurface: String, Codable, Equatable, CaseIterable {
  case hostHome
  case businessAnalytics
  case newBookings
}

struct ManagerNarrativeFact: Codable, Equatable {
  let priority: String
  let title: String
  let detail: String?
}

struct ManagerNarrativeAction: Codable, Equatable {
  let id: String
  let title: String
  let destinationHint: String
}

struct ManagerNarrativePacket: Codable, Equatable {
  let surface: ManagerNarrativeSurface
  let generatedAtDescription: String
  let serviceState: String
  let headlineFacts: [ManagerNarrativeFact]
  let availableActions: [ManagerNarrativeAction]
  let writingRules: [String]
}

struct ManagerNarrative: Equatable {
  enum Source: Equatable {
    case template
    case localModel
    case failedFallback
  }

  let headline: String
  let whyItMatters: String?
  let checkNext: String?
  let source: Source
  let failedReason: String?

  static let empty = ManagerNarrative(
    headline: "Nothing needs attention right now.",
    whyItMatters: nil,
    checkNext: nil,
    source: .template,
    failedReason: nil
  )

  var compactBriefingText: String {
    [headline, whyItMatters, checkNext]
      .compactMap { line in
        let trimmed = line?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
      }
      .joined(separator: " ")
  }

  var hasStructuredDetail: Bool {
    let why = whyItMatters?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let check = checkNext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return !why.isEmpty || !check.isEmpty
  }
}

// MARK: - Packet Builder

enum ManagerNarrativePacketBuilder {

  static func buildHostHome(from snapshot: HostDecisionSnapshot) -> ManagerNarrativePacket {
    let facts = snapshot.llmPacket.topFacts.compactMap { fact -> ManagerNarrativeFact? in
      guard let title = ManagerNarrativePacketSanitizer.staffSafeLine(fact.title) else {
        return nil
      }
      return ManagerNarrativeFact(
        priority: fact.severity.rawValue,
        title: title,
        detail: ManagerNarrativePacketSanitizer.staffSafeOptionalLine(fact.detail.nilIfBlank)
      )
    }

    let actions = ManagerAttentionItemBuilder
      .build(from: snapshot, maxItems: 3)
      .compactMap { item -> ManagerNarrativeAction? in
        guard let title = ManagerNarrativePacketSanitizer.staffSafeLine(item.title) else {
          return nil
        }
        return ManagerNarrativeAction(
          id: item.id,
          title: title,
          destinationHint: destinationHintLabel(item.destinationHint)
        )
      }

    let generatedAt = ManagerNarrativePacketSanitizer.staffSafeLine(
      snapshot.llmPacket.generatedAtDescription
    ) ?? ""

    return ManagerNarrativePacket(
      surface: .hostHome,
      generatedAtDescription: generatedAt,
      serviceState: snapshot.serviceState.rawValue,
      headlineFacts: facts,
      availableActions: actions,
      writingRules: ManagerNarrativeWritingRules.standard
    )
  }

  /// Future phase — safe aggregate metrics only, no raw backend JSON.
  static func buildBusinessAnalyticsPrototype(
    summaryLine: String,
    secondaryLines: [String]
  ) -> ManagerNarrativePacket {
    ManagerNarrativePacket(
      surface: .businessAnalytics,
      generatedAtDescription: "",
      serviceState: "summary",
      headlineFacts: [ManagerNarrativeFact(priority: "info", title: summaryLine, detail: nil)]
        + secondaryLines.map {
          ManagerNarrativeFact(priority: "info", title: $0, detail: nil)
        },
      availableActions: [],
      writingRules: ManagerNarrativeWritingRules.standard
    )
  }

  private static func destinationHintLabel(_ hint: ManagerAttentionDestinationHint) -> String {
    switch hint {
    case .reservation: return "reservation"
    case .tablePlan: return "table plan"
    case .guestNote: return "guest note"
    case .newBookings: return "new bookings"
    case .schedule: return "schedule"
    case .none: return "none"
    }
  }
}

// MARK: - Template Builder

enum ManagerNarrativeTemplateBuilder {

  static func build(from snapshot: HostDecisionSnapshot) -> ManagerNarrative {
    let headline = snapshot.templateBriefingText
    let ranked = HostBriefingService().rankHostFacts(snapshot.briefingFacts)

    let whyItMatters = whyLine(from: ranked, snapshot: snapshot)
    let checkNext = checkLine(from: snapshot)

    return ManagerNarrative(
      headline: headline,
      whyItMatters: whyItMatters,
      checkNext: checkNext,
      source: .template,
      failedReason: nil
    )
  }

  private static func whyLine(
    from rankedFacts: [HostBriefingFact],
    snapshot: HostDecisionSnapshot
  ) -> String? {
    if rankedFacts.count >= 2 {
      let fact = rankedFacts[1]
      if let detail = ManagerNarrativePacketSanitizer.staffSafeLine(fact.detail),
         !isNearDuplicate(detail, headline: snapshot.templateBriefingText) {
        return punctuate(detail)
      }
      if let title = ManagerNarrativePacketSanitizer.staffSafeLine(fact.title),
         !isNearDuplicate(title, headline: snapshot.templateBriefingText) {
        return punctuate(title)
      }
    }

    if let pressure = snapshot.slotPressures.first(where: {
      $0.severity == .busy || $0.severity == .critical
    }) {
      let time = displaySlotTime(pressure.slotTime)
      let line = "Seating pressure builds around \(time)."
      if !isNearDuplicate(line, headline: snapshot.templateBriefingText) {
        return line
      }
    }

    return nil
  }

  private static func checkLine(from snapshot: HostDecisionSnapshot) -> String? {
    guard let action = snapshot.suggestedActions.first else { return nil }
    return ManagerAttentionItemBuilder.tapLabel(for: action)
  }

  private static func displaySlotTime(_ value: String) -> String {
    if let date = ReservationFormatters.apiTime.date(from: value) {
      return ReservationFormatters.shortTime.string(from: date)
    }
    return String(value.prefix(5))
  }

  private static func punctuate(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return trimmed }
    if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
      return trimmed
    }
    return "\(trimmed)."
  }

  private static func isNearDuplicate(_ candidate: String, headline: String) -> Bool {
    let lhs = candidate.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let rhs = headline.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !lhs.isEmpty, !rhs.isEmpty else { return false }
    return rhs.contains(lhs) || lhs.contains(rhs)
  }
}

enum ManagerNarrativeWritingRules {
  static let standard: [String] = [
    "Use simple restaurant staff language.",
    "Write so a busy host understands in five seconds.",
    "Use only provided facts and actions.",
    "Do not invent guests, tables, times, counts, allergies, notes, or actions.",
    "Do not say anything was confirmed, sent, assigned, cancelled, or changed.",
    "Do not mention AI or local model.",
    "Use at most 3 short lines: what matters, why it matters, what staff can check next."
  ]
}

private extension String {
  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
