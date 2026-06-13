//
//  HostAttentionGrouper.swift
//  Tryzub Reservations
//
//  Deterministic grouping layer for Host card presentation.
//

import Foundation

enum HostAttentionGrouper {

  static func build(
    from snapshot: HostDecisionSnapshot,
    selectedDateKey: String,
    floorTableSource: HostFloorTableSource
  ) -> HostAttentionPresentation {
    let plan = HostActionPresentationPolicy.plan(
      snapshot: snapshot,
      floorTableSource: floorTableSource
    )

    var primaryItems = plan.actionableGuestSignals.map { signal in
      item(
        for: signal,
        action: HostActionPresentationPolicy.matchingAction(
          for: signal,
          in: snapshot.suggestedActions
        )
      )
    }

    let guestReservationIDs = Set(primaryItems.flatMap(\.relatedReservationIDs))
    let operationalItems = plan.operationalActions
      .filter { action in
        Set(action.relatedReservationIDs).isDisjoint(with: guestReservationIDs)
      }
      .map(item(for:))

    primaryItems.append(contentsOf: operationalItems)
    primaryItems = primaryItems
      .stableItemDedupe()
      .sorted(by: itemSort)

    let secondaryContext = plan.returningGuestSignals
      .filter { signal in
        !guestReservationIDs.contains(signal.reservationID)
      }
      .prefix(2)
      .map(contextItem(for:))

    let visiblePrimaryItems = Array(primaryItems.prefix(3))
    let summary = summaryLine(
      actionableSignals: plan.actionableGuestSignals,
      returningSignals: plan.returningGuestSignals,
      primaryItems: visiblePrimaryItems
    )
    let headline = headlineLine(
      actionableSignals: plan.actionableGuestSignals,
      primaryItems: visiblePrimaryItems,
      secondaryContext: Array(secondaryContext),
      fallback: snapshot.templateBriefingText
    )
    let eligibleReason = modelEligibleReason(
      snapshot: snapshot,
      actionableSignals: plan.actionableGuestSignals,
      primaryItems: visiblePrimaryItems,
      floorTableSource: floorTableSource
    )

    let presentation = HostAttentionPresentation(
      headline: headline,
      summary: summary,
      primaryItems: visiblePrimaryItems,
      secondaryContext: Array(secondaryContext),
      primaryActions: visiblePrimaryItems.compactMap(\.sourceAction),
      suppressedItems: plan.suppressedItems,
      modelEligibleReason: eligibleReason,
      floorSourceLabel: floorTableSource.traceLabel
    )

    HostAttentionTrace.logGroup(
      date: selectedDateKey,
      presentation: presentation,
      groupCount: groupCount(
        actionableSignals: plan.actionableGuestSignals,
        returningSignals: plan.returningGuestSignals,
        operationalItems: operationalItems
      )
    )
    return presentation
  }

  // MARK: - Item Building

  private static func item(
    for signal: HostGuestSignal,
    action: HostSuggestedAction?
  ) -> HostAttentionPresentationItem {
    HostAttentionPresentationItem(
      id: "guest-group-\(signal.kind.rawValue)-\(signal.reservationID)",
      priority: priority(for: signal.severity),
      title: title(for: signal),
      detail: nil,
      actionTitle: HostActionPresentationPolicy.actionTitle(for: action),
      destinationHint: HostActionPresentationPolicy.destinationHint(for: action),
      relatedReservationIDs: [signal.reservationID],
      sourceAction: action
    )
  }

  private static func item(for action: HostSuggestedAction) -> HostAttentionPresentationItem {
    HostAttentionPresentationItem(
      id: action.id,
      priority: priority(for: action.severity),
      title: HostStaffLanguage.rewrite(action.title),
      detail: conciseDetail(action.reason, title: action.title),
      actionTitle: HostActionPresentationPolicy.actionTitle(for: action),
      destinationHint: HostActionPresentationPolicy.destinationHint(for: action),
      relatedReservationIDs: action.relatedReservationIDs,
      sourceAction: action
    )
  }

  private static func contextItem(for signal: HostGuestSignal) -> HostAttentionContextItem {
    HostAttentionContextItem(
      id: "guest-context-\(signal.reservationID)",
      title: returningContextLine(for: signal),
      detail: nil,
      relatedReservationIDs: [signal.reservationID]
    )
  }

  private static func title(for signal: HostGuestSignal) -> String {
    let name = firstName(signal.guestName)
    let message = signal.message.lowercased()
    switch signal.kind {
    case .allergy:
      return "Check \(name)'s allergy note"
    case .accessibility:
      return "Check \(name)'s accessibility note"
    case .seatingPreference:
      return "Check \(name)'s seating note"
    case .specialOccasion:
      if message.contains("birthday") {
        return "Check \(name)'s birthday note"
      }
      if message.contains("anniversary") {
        return "Check \(name)'s anniversary note"
      }
      return "Check \(name)'s occasion note"
    case .noteReminder:
      if signal.evidence.contains("dietaryNote") || message.contains("dietary") {
        return "Check \(name)'s dietary note"
      }
      return "Check \(name)'s guest note"
    case .previousServiceIssue:
      return "Flag \(name)'s service note"
    default:
      return "Check \(name)'s guest note"
    }
  }

  // MARK: - Copy

  private static func headlineLine(
    actionableSignals: [HostGuestSignal],
    primaryItems: [HostAttentionPresentationItem],
    secondaryContext: [HostAttentionContextItem],
    fallback: String
  ) -> String {
    if !actionableSignals.isEmpty {
      return "Guest notes to check"
    }
    if !primaryItems.isEmpty {
      return "Needs attention"
    }
    if !secondaryContext.isEmpty {
      return "Returning guest context"
    }
    let trimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? HostAttentionPresentation.empty.headline : trimmed
  }

  private static func summaryLine(
    actionableSignals: [HostGuestSignal],
    returningSignals: [HostGuestSignal],
    primaryItems: [HostAttentionPresentationItem]
  ) -> String? {
    var lines = actionableSignals
      .prefix(2)
      .compactMap(summarySentence(for:))

    if let returning = returningSignals.first(where: { signal in
      !primaryItems.flatMap(\.relatedReservationIDs).contains(signal.reservationID)
    }) {
      lines.append(returningContextLine(for: returning))
    }

    let summary = lines
      .map(punctuate)
      .stableUnique()
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return summary.isEmpty ? nil : summary
  }

  private static func summarySentence(for signal: HostGuestSignal) -> String? {
    let name = firstName(signal.guestName)
    let message = HostStaffLanguage.rewrite(signal.message)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty else { return nil }

    switch signal.kind {
    case .specialOccasion:
      let lower = message.lowercased()
      if lower.contains("birthday") {
        return "\(name) has a birthday note"
      }
      if lower.contains("anniversary") {
        return "\(name) has an anniversary note"
      }
      return message
    default:
      return message
    }
  }

  private static func returningContextLine(for signal: HostGuestSignal) -> String {
    "\(firstName(signal.guestName)) has visited before"
  }

  private static func conciseDetail(_ value: String, title: String) -> String? {
    let detail = HostStaffLanguage.rewrite(value)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !detail.isEmpty else { return nil }
    if HostStaffLanguage.areSameStaffMeaning(detail, title) {
      return nil
    }
    return detail
  }

  // MARK: - Eligibility

  private static func modelEligibleReason(
    snapshot: HostDecisionSnapshot,
    actionableSignals: [HostGuestSignal],
    primaryItems: [HostAttentionPresentationItem],
    floorTableSource: HostFloorTableSource
  ) -> String? {
    let meaningfulCount = primaryItems.count
    if meaningfulCount >= 2 {
      return "grouped_staff_facts_\(meaningfulCount)"
    }

    if let highPriority = actionableSignals.first(where: HostActionPresentationPolicy.isHighPriorityModelSignal) {
      return "high_priority_\(highPriority.kind.rawValue)"
    }

    if floorTableSource.supportsTableIntelligence,
       hasHighPriorityTableFact(snapshot) {
      return "high_priority_table"
    }

    if hasArrivalWaveFact(snapshot) {
      return "arrival_wave"
    }

    return nil
  }

  private static func hasHighPriorityTableFact(_ snapshot: HostDecisionSnapshot) -> Bool {
    snapshot.briefingFacts.contains { fact in
      switch fact.category {
      case .table, .capacity, .largeParty:
        let text = "\(fact.title) \(fact.detail)".lowercased()
        return text.contains("mismatch")
          || text.contains("no table")
          || text.contains("still need")
          || text.contains("capacity")
      default:
        return false
      }
    }
  }

  private static func hasArrivalWaveFact(_ snapshot: HostDecisionSnapshot) -> Bool {
    if let pressure = snapshot.arrivalPressureFacts {
      return pressure.peakReservationCount > 0
        && pressure.pressureLevel != ArrivalPressureLevel.calm.displayName
    }
    return snapshot.briefingFacts.contains { $0.category == .arrivalWave }
  }

  // MARK: - Helpers

  private static func priority(for severity: HostSeverity) -> ManagerAttentionPriority {
    switch severity {
    case .critical: return .critical
    case .warning: return .high
    case .watch, .info: return .normal
    }
  }

  private static func itemSort(
    _ lhs: HostAttentionPresentationItem,
    _ rhs: HostAttentionPresentationItem
  ) -> Bool {
    if lhs.priority != rhs.priority {
      return lhs.priority < rhs.priority
    }
    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
  }

  private static func groupCount(
    actionableSignals: [HostGuestSignal],
    returningSignals: [HostGuestSignal],
    operationalItems: [HostAttentionPresentationItem]
  ) -> Int {
    (actionableSignals.isEmpty ? 0 : 1)
      + (returningSignals.isEmpty ? 0 : 1)
      + operationalItems.count
  }

  private static func firstName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "Guest" }
    return trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? trimmed
  }

  private static func punctuate(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return trimmed }
    if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
      return trimmed
    }
    return "\(trimmed)."
  }
}

enum HostAttentionTrace {
  static func logGroup(
    date: String,
    presentation: HostAttentionPresentation,
    groupCount: Int
  ) {
    #if DEBUG
    print(
      "[HOST_ATTENTION_GROUP_TRACE] date=\(date) groups=\(groupCount) primary=\(presentation.primaryItems.count) context=\(presentation.secondaryContext.count) suppressed=\(presentation.suppressedItems.count)"
    )
    #endif
  }

  static func logActionPolicy(
    suppressedSeenBefore: Int,
    promotedNotes: Int
  ) {
    #if DEBUG
    print(
      "[HOST_ACTION_POLICY_TRACE] suppressedSeenBefore=\(suppressedSeenBefore) promotedNotes=\(promotedNotes)"
    )
    #endif
  }
}

private extension Array where Element == HostAttentionPresentationItem {
  func stableItemDedupe() -> [HostAttentionPresentationItem] {
    var seen = Set<String>()
    var result: [HostAttentionPresentationItem] = []
    for item in self {
      let reservationKey = item.relatedReservationIDs.map(String.init).joined(separator: ",")
      let key = "\(reservationKey)|\(item.title.lowercased())"
      guard !seen.contains(key) else { continue }
      seen.insert(key)
      result.append(item)
    }
    return result
  }
}

private extension Array where Element == String {
  func stableUnique() -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in self {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
      seen.insert(trimmed)
      result.append(trimmed)
    }
    return result
  }
}
