//
//  ManagerAttentionItem.swift
//  Tryzub Reservations
//
//  Presentation-only “needs attention” rows for manager UI.
//  Derived from existing Host facts/actions — no network, mutation, or model calls.
//

import Foundation

enum ManagerAttentionPriority: Int, Comparable, Equatable {
  case critical
  case high
  case normal

  static func < (lhs: ManagerAttentionPriority, rhs: ManagerAttentionPriority) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

enum ManagerAttentionDestinationHint: Equatable {
  case reservation
  case tablePlan
  case guestNote
  case newBookings
  case schedule
  case none
}

struct ManagerAttentionItem: Identifiable, Equatable {
  let id: String
  let priority: ManagerAttentionPriority
  let title: String
  let detail: String?
  let actionTitle: String
  let destinationHint: ManagerAttentionDestinationHint
  let relatedReservationIDs: [Int]
  let sourceAction: HostSuggestedAction?
}

enum ManagerAttentionItemBuilder {

  static func build(from snapshot: HostDecisionSnapshot, maxItems: Int = 3) -> [ManagerAttentionItem] {
    Array(
      snapshot.suggestedActions
        .prefix(maxItems)
        .map { staffItem(from: $0) }
    )
  }

  static func nonRedundantPrompts(
    briefingText: String,
    prompts: [HostOperationalBriefingPrompt]
  ) -> [HostOperationalBriefingPrompt] {
    let normalizedBriefing = briefingText
      .lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedBriefing.isEmpty else { return prompts }

    return prompts.filter { prompt in
      let body = prompt.body
        .lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !body.isEmpty else { return false }
      if normalizedBriefing.contains(body) { return false }

      let overlapPhrases = [
        "still need tables",
        "still needs a table",
        "nothing needs attention",
        "busiest time",
        "table plan"
      ]
      if overlapPhrases.contains(where: { normalizedBriefing.contains($0) && body.contains($0) }) {
        return false
      }
      return true
    }
  }

  // MARK: - Private

  private static func staffItem(from action: HostSuggestedAction) -> ManagerAttentionItem {
    ManagerAttentionItem(
      id: action.id,
      priority: priority(for: action.severity),
      title: staffTitle(for: action),
      detail: staffDetail(for: action),
      actionTitle: staffTapLabel(for: action.kind),
      destinationHint: destinationHint(for: action.kind),
      relatedReservationIDs: action.relatedReservationIDs,
      sourceAction: action
    )
  }

  static func tapLabel(for action: HostSuggestedAction) -> String {
    staffTapLabel(for: action.kind)
  }

  private static func priority(for severity: HostSeverity) -> ManagerAttentionPriority {
    switch severity {
    case .critical: return .critical
    case .warning: return .high
    case .watch, .info: return .normal
    }
  }

  private static func staffTitle(for action: HostSuggestedAction) -> String {
    let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
    if !title.isEmpty { return title }
    return staffTapLabel(for: action.kind)
  }

  private static func staffDetail(for action: HostSuggestedAction) -> String? {
    let reason = action.reason.trimmingCharacters(in: .whitespacesAndNewlines)
    return reason.isEmpty ? nil : reason
  }

  private static func staffTapLabel(for kind: HostActionKind) -> String {
    switch kind {
    case .assignTable, .holdTable, .releaseTable:
      return "Check table plan"
    case .alertServer:
      return "Check guest note"
    case .reviewReservation, .reviewCancellationOpportunity:
      return "Check reservation"
    case .confirmReservation:
      return "Confirm details"
    case .suggestAlternateTime:
      return "Check time options"
    case .seatReservation:
      return "Check seating"
    case .completeReservation:
      return "Check completion"
    case .markNoShow:
      return "Check no-show"
    case .closeSlot:
      return "Check open times"
    case .generateEmailDraft:
      return "Draft message"
    case .generateGuestManageLink:
      return "Check guest link"
    case .noAction:
      return "Check details"
    }
  }

  private static func destinationHint(for kind: HostActionKind) -> ManagerAttentionDestinationHint {
    switch kind {
    case .assignTable, .holdTable, .releaseTable:
      return .tablePlan
    case .alertServer:
      return .guestNote
    case .closeSlot:
      return .schedule
    case .generateEmailDraft, .generateGuestManageLink:
      return .reservation
    case .reviewReservation, .reviewCancellationOpportunity,
         .confirmReservation, .suggestAlternateTime, .seatReservation,
         .completeReservation, .markNoShow:
      return .reservation
    case .noAction:
      return .none
    }
  }
}
