//
//  HostIntelligenceActionLabelPolicy.swift
//  Tryzub Reservations
//
//  Staff-facing labels for read-only Host Intelligence actions.
//

import Foundation

enum HostIntelligenceActionLabelPolicy {
  static func label(for action: HostSuggestedAction?) -> String {
    guard let action else { return "Review" }
    if isPossibleCorrection(action) {
      return "Review correction"
    }

    switch action.kind {
    case .alertServer:
      return "Check note"
    case .assignTable:
      return "Assign table"
    case .closeSlot:
      return "Review busy time"
    case .completeReservation, .seatReservation:
      return "Check table"
    case .reviewReservation, .reviewCancellationOpportunity,
         .confirmReservation, .suggestAlternateTime, .markNoShow:
      return "Review booking"
    case .holdTable, .releaseTable:
      return "Check table"
    case .generateEmailDraft, .generateGuestManageLink:
      return "Review"
    case .noAction:
      return "Review"
    }
  }

  static func reviewTitle(for action: HostSuggestedAction) -> String {
    if isPossibleCorrection(action) {
      return "Possible correction"
    }
    if action.kind == .closeSlot {
      return "Busy time"
    }
    if action.kind == .assignTable {
      return "Still needs a table"
    }
    let title = HostStaffLanguage.rewrite(action.title)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? label(for: action) : title
  }

  static func primaryAction(
    from presentation: HostAttentionPresentation,
    snapshot: HostDecisionSnapshot
  ) -> HostSuggestedAction? {
    let presentationCandidates = presentation.primaryActions.isEmpty
      ? presentation.primaryItems.compactMap(\.sourceAction)
      : presentation.primaryActions
    let candidates = presentationCandidates.isEmpty
      ? snapshot.suggestedActions
      : presentationCandidates

    return candidates
      .filter(isUsefulPrimaryAction)
      .sorted(by: primaryActionSort)
      .first
  }

  static func isUsefulPrimaryAction(_ action: HostSuggestedAction) -> Bool {
    guard action.kind != .noAction else { return false }
    return !isReturningGuestContext(action)
  }

  static func isPossibleCorrection(_ action: HostSuggestedAction) -> Bool {
    let text = "\(action.id) \(action.title) \(action.reason)"
      .lowercased()
    return text.contains("correction")
      || text.contains("duplicate")
      || text.contains("same guest")
  }

  private static func primaryActionSort(_ lhs: HostSuggestedAction, _ rhs: HostSuggestedAction) -> Bool {
    let leftRank = primaryRank(lhs)
    let rightRank = primaryRank(rhs)
    if leftRank != rightRank { return leftRank < rightRank }
    if lhs.severity.rank != rhs.severity.rank { return lhs.severity.rank < rhs.severity.rank }
    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
  }

  private static func primaryRank(_ action: HostSuggestedAction) -> Int {
    switch action.kind {
    case .alertServer:
      return 0
    case .reviewReservation where isPossibleCorrection(action):
      return 1
    case .assignTable:
      return 2
    case .closeSlot:
      return 3
    case .reviewReservation where isLargePartyOrReview(action):
      return 4
    case .reviewReservation, .reviewCancellationOpportunity:
      return 5
    case .completeReservation, .seatReservation, .holdTable, .releaseTable:
      return 6
    case .confirmReservation, .suggestAlternateTime, .markNoShow:
      return 7
    case .generateEmailDraft, .generateGuestManageLink:
      return 8
    case .noAction:
      return 99
    }
  }

  private static func isLargePartyOrReview(_ action: HostSuggestedAction) -> Bool {
    let text = "\(action.title) \(action.reason)".lowercased()
    return text.contains("large")
      || text.contains("party")
      || text.contains("review")
  }

  private static func isReturningGuestContext(_ action: HostSuggestedAction) -> Bool {
    let text = "\(action.id) \(action.title) \(action.reason)".lowercased()
    return text.contains("returning")
      || text.contains("seen before")
      || text.contains("visited before")
      || text.contains("regular guest")
  }
}
