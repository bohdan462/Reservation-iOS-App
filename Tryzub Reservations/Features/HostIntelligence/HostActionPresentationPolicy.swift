//
//  HostActionPresentationPolicy.swift
//  Tryzub Reservations
//
//  Deterministic policy for promoting staff-useful Host rows and suppressing
//  low-value raw action rows.
//

import Foundation

struct HostActionPresentationPlan: Equatable {
  let actionableGuestSignals: [HostGuestSignal]
  let returningGuestSignals: [HostGuestSignal]
  let operationalActions: [HostSuggestedAction]
  let suppressedItems: [String]
  let suppressedSeenBeforeCount: Int
  let promotedNoteCount: Int
}

enum HostActionPresentationPolicy {

  static func plan(
    snapshot: HostDecisionSnapshot,
    floorTableSource: HostFloorTableSource
  ) -> HostActionPresentationPlan {
    let actionableSignals = snapshot.guestSignals
      .filter(isActionableGuestSignal)
      .stableGuestSignalDedupe()
      .sorted(by: signalSort)

    let returningSignals = snapshot.guestSignals
      .filter(isReturningContextSignal)
      .stableReturningSignalDedupe()
      .sorted(by: signalSort)

    var suppressed: [String] = []
    var suppressedSeenBefore = 0
    let operationalActions = snapshot.suggestedActions.filter { action in
      if isStandaloneSeenBeforeAction(action) {
        suppressedSeenBefore += 1
        suppressed.append("standalone Seen before action rows")
        return false
      }
      if isGuestSignalAction(action) {
        suppressed.append("raw guest signal action \(action.id)")
        return false
      }
      if !floorTableSource.supportsTableIntelligence, isTableDependent(action) {
        suppressed.append("table-dependent action while floor source is \(floorTableSource.traceLabel)")
        return false
      }
      return true
    }

    let promotedNotes = actionableSignals.filter { signal in
      switch signal.kind {
      case .allergy, .accessibility, .seatingPreference, .specialOccasion, .noteReminder,
           .previousServiceIssue:
        return true
      default:
        return false
      }
    }.count

    HostAttentionTrace.logActionPolicy(
      suppressedSeenBefore: suppressedSeenBefore,
      promotedNotes: promotedNotes
    )

    return HostActionPresentationPlan(
      actionableGuestSignals: actionableSignals,
      returningGuestSignals: returningSignals,
      operationalActions: operationalActions,
      suppressedItems: suppressed.stableUnique(),
      suppressedSeenBeforeCount: suppressedSeenBefore,
      promotedNoteCount: promotedNotes
    )
  }

  static func isActionableGuestSignal(_ signal: HostGuestSignal) -> Bool {
    switch signal.kind {
    case .allergy, .accessibility, .seatingPreference, .specialOccasion, .noteReminder,
         .previousServiceIssue:
      return true
    case .regularGuest, .importantGuest, .vip, .cancellationRisk, .noShowRisk,
         .manualCallIn, .possibleDuplicate, .unknown:
      return false
    }
  }

  static func isHighPriorityModelSignal(_ signal: HostGuestSignal) -> Bool {
    switch signal.kind {
    case .allergy, .accessibility, .seatingPreference:
      return true
    case .specialOccasion:
      return signal.message.localizedCaseInsensitiveContains("birthday")
        || signal.message.localizedCaseInsensitiveContains("anniversary")
    case .noteReminder:
      return signal.evidence.contains("dietaryNote")
        || signal.message.localizedCaseInsensitiveContains("dietary")
        || signal.message.localizedCaseInsensitiveContains("allergy")
    case .previousServiceIssue:
      return true
    default:
      return false
    }
  }

  static func destinationHint(for action: HostSuggestedAction?) -> ManagerAttentionDestinationHint {
    guard let action else { return .reservation }
    switch action.kind {
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

  static func actionTitle(for action: HostSuggestedAction?) -> String {
    guard let action else { return "Check details" }
    switch action.kind {
    case .assignTable, .holdTable, .releaseTable:
      return "Check floor plan"
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

  static func matchingAction(
    for signal: HostGuestSignal,
    in actions: [HostSuggestedAction]
  ) -> HostSuggestedAction? {
    actions.first { action in
      guard action.relatedReservationIDs.contains(signal.reservationID) else { return false }
      switch signal.kind {
      case .allergy:
        return action.id.hasPrefix("guest-action-allergy-")
      case .accessibility:
        return action.id.hasPrefix("guest-action-accessibility-")
      case .seatingPreference:
        return action.id.hasPrefix("guest-action-seating-")
      case .specialOccasion:
        return action.id.hasPrefix("guest-action-occasion-")
      case .noteReminder:
        return action.id.hasPrefix("guest-action-note-")
      case .previousServiceIssue:
        return action.id.hasPrefix("guest-action-service-issue-")
      default:
        return false
      }
    }
  }

  private static func isReturningContextSignal(_ signal: HostGuestSignal) -> Bool {
    switch signal.kind {
    case .regularGuest, .importantGuest, .vip:
      return true
    default:
      return false
    }
  }

  private static func isStandaloneSeenBeforeAction(_ action: HostSuggestedAction) -> Bool {
    action.id.hasPrefix("guest-action-returning-")
      || HostStaffLanguage.rewrite(action.title).localizedCaseInsensitiveContains("seen before")
  }

  private static func isGuestSignalAction(_ action: HostSuggestedAction) -> Bool {
    action.id.hasPrefix("guest-action-")
  }

  private static func isTableDependent(_ action: HostSuggestedAction) -> Bool {
    if action.kind == .assignTable || action.kind == .holdTable || action.kind == .releaseTable {
      return true
    }
    let corpus = "\(action.title) \(action.reason) \(action.targetTableName ?? "")".lowercased()
    return corpus.contains("table")
      || corpus.contains("floor plan")
      || corpus.contains("capacity")
      || corpus.contains("joined")
  }

  private static func signalSort(_ lhs: HostGuestSignal, _ rhs: HostGuestSignal) -> Bool {
    if lhs.severity.rank != rhs.severity.rank {
      return lhs.severity.rank < rhs.severity.rank
    }
    let left = signalKindRank(lhs.kind)
    let right = signalKindRank(rhs.kind)
    if left != right { return left < right }
    return lhs.guestName.localizedCaseInsensitiveCompare(rhs.guestName) == .orderedAscending
  }

  private static func signalKindRank(_ kind: HostGuestSignalKind) -> Int {
    switch kind {
    case .allergy: return 0
    case .accessibility: return 1
    case .seatingPreference: return 2
    case .specialOccasion: return 3
    case .noteReminder: return 4
    case .previousServiceIssue: return 5
    case .importantGuest: return 6
    case .regularGuest: return 7
    case .vip: return 8
    case .cancellationRisk, .noShowRisk: return 9
    case .manualCallIn, .possibleDuplicate: return 10
    case .unknown: return 11
    }
  }
}

private extension Array where Element == HostGuestSignal {
  func stableGuestSignalDedupe() -> [HostGuestSignal] {
    var seen = Set<String>()
    var result: [HostGuestSignal] = []
    for signal in self {
      let key = "\(signal.reservationID)|\(signal.kind.rawValue)"
      guard !seen.contains(key) else { continue }
      seen.insert(key)
      result.append(signal)
    }
    return result
  }

  func stableReturningSignalDedupe() -> [HostGuestSignal] {
    var seenIDs = Set<Int>()
    var seenNames = Set<String>()
    var result: [HostGuestSignal] = []
    for signal in self {
      let nameKey = signal.guestName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
      guard !seenIDs.contains(signal.reservationID), !seenNames.contains(nameKey) else { continue }
      seenIDs.insert(signal.reservationID)
      seenNames.insert(nameKey)
      result.append(signal)
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
