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

  static func build(
    from snapshot: HostDecisionSnapshot,
    presentation: HostAttentionPresentation? = nil,
    maxItems: Int = 3,
    compactPresentation: Bool = false,
    briefingText: String = ""
  ) -> [ManagerAttentionItem] {
    if let presentation, presentation.hasVisibleContent {
      return Array(presentation.primaryItems.prefix(maxItems)).map { item in
        ManagerAttentionItem(
          id: item.id,
          priority: item.priority,
          title: item.title,
          detail: item.detail,
          actionTitle: item.actionTitle,
          destinationHint: item.destinationHint,
          relatedReservationIDs: item.relatedReservationIDs,
          sourceAction: item.sourceAction
        )
      }
    }

    let actions = Array(snapshot.suggestedActions.prefix(maxItems))
    return actions.map { action in
      staffItem(
        from: action,
        among: actions,
        compactPresentation: compactPresentation,
        briefingText: briefingText
      )
    }
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
        "floor plan"
      ]
      if overlapPhrases.contains(where: { normalizedBriefing.contains($0) && body.contains($0) }) {
        return false
      }
      return true
    }
  }

  // MARK: - Private

  private static func staffItem(
    from action: HostSuggestedAction,
    among actions: [HostSuggestedAction],
    compactPresentation: Bool,
    briefingText: String
  ) -> ManagerAttentionItem {
    ManagerAttentionItem(
      id: action.id,
      priority: priority(for: action.severity),
      title: staffTitle(for: action),
      detail: staffDetail(
        for: action,
        among: actions,
        compactPresentation: compactPresentation,
        briefingText: briefingText
      ),
      actionTitle: tapLabel(for: action),
      destinationHint: destinationHint(for: action.kind),
      relatedReservationIDs: action.relatedReservationIDs,
      sourceAction: action
    )
  }

  static func tapLabel(for action: HostSuggestedAction) -> String {
    if action.id.hasPrefix("unresolved-late-cleanup-action-") {
      return "Resolve booking"
    }
    return HostIntelligenceActionLabelPolicy.label(for: action)
  }

  private static func priority(for severity: HostSeverity) -> ManagerAttentionPriority {
    switch severity {
    case .critical: return .critical
    case .warning: return .high
    case .watch, .info: return .normal
    }
  }

  private static func staffTitle(for action: HostSuggestedAction) -> String {
    let title = HostStaffLanguage.rewrite(action.title)
    if !title.isEmpty { return title }
    return HostIntelligenceActionLabelPolicy.label(for: action)
  }

  private static func staffDetail(
    for action: HostSuggestedAction,
    among actions: [HostSuggestedAction],
    compactPresentation: Bool,
    briefingText: String
  ) -> String? {
    let reason = HostStaffLanguage.rewrite(action.reason)
    guard !reason.isEmpty else { return nil }

    if compactPresentation,
       shouldHideCompactDetail(
         for: action,
         reason: reason,
         among: actions,
         briefingText: briefingText
       ) {
      return nil
    }

    return reason
  }

  private static func shouldHideCompactDetail(
    for action: HostSuggestedAction,
    reason: String,
    among actions: [HostSuggestedAction],
    briefingText: String
  ) -> Bool {
    let normalizedReason = reason.lowercased()
    let normalizedBriefing = briefingText.lowercased()

    if normalizedBriefing.contains(normalizedReason) {
      return true
    }

    if normalizedBriefing.contains("look safe to confirm"),
       action.kind == .confirmReservation {
      return true
    }

    if normalizedBriefing.contains("coming up soon"),
       action.kind == .reviewReservation,
       normalizedReason.contains("coming up soon") {
      return true
    }

    if normalizedBriefing.contains("still needs a table")
        || normalizedBriefing.contains("needs a table") {
      if normalizedReason.contains("still needs a table")
          || normalizedReason.contains("needs a table") {
        return true
      }
      if action.kind == .assignTable {
        return false
      }
    }

    if action.kind == .assignTable,
       normalizedReason.contains("·"),
       normalizedBriefing.contains("table") {
      return false
    }

    let matchingReasonCount = actions.filter {
      HostStaffLanguage.rewrite($0.reason).lowercased() == normalizedReason
    }.count
    if matchingReasonCount >= 2 {
      return true
    }

    if action.kind == .confirmReservation,
       actions.filter({ $0.kind == .confirmReservation }).count >= 2,
       normalizedReason.contains("time looks manageable") {
      return true
    }

    return false
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
