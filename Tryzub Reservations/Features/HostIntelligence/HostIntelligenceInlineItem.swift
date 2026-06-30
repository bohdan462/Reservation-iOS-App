//
//  HostIntelligenceInlineItem.swift
//  Tryzub Reservations
//
//  Deterministic Host Board intelligence lane items.
//

import Foundation

enum HostIntelligenceInlineKind: String, Codable, CaseIterable {
  case nextGuest
  case returningGuest
  case guestNote
  case allergy
  case accessibility
  case occasion
  case noTable
  case tableSuggestion
  case busyTime
  case possibleCorrection
  case reminder
  case seatedTooLong
  case cleanup
  case serviceSummary
  case calm
}

enum HostIntelligenceInlineConfidence: String, Codable, CaseIterable {
  case confirmed
  case likely
  case uncertain
}

struct HostIntelligenceInlineItem: Identifiable, Equatable {
  let id: String
  let kind: HostIntelligenceInlineKind
  let priority: Int
  let title: String
  let detail: String
  let reservationID: Int?
  let action: HostSuggestedAction?
  let opensReview: Bool
  let evidence: [String]
  let confidence: HostIntelligenceInlineConfidence
  let suppressReason: String?
}

struct HostIntelligenceReminderInlineContext: Equatable {
  let dueCount: Int
  let skippedCount: Int
  let failedCount: Int
  let isSending: Bool
  let dailyLimitReached: Bool
  let leadHours: Int
}

/// Cached, display-ready input for the Host Board intelligence card. Building this
/// value may inspect reservation history; reading it from SwiftUI body is constant-time.
struct HostIntelligenceCardPresentation: Equatable {
  let key: String
  let items: [HostIntelligenceInlineItem]
  let visibleItems: [HostIntelligenceInlineItem]
  let headline: String?
  let primaryActionID: String?
  let attentionItems: [ManagerAttentionItem]
  let visibleCompactPrompts: [HostOperationalBriefingPrompt]
  let expandedPrompts: [HostOperationalBriefingPrompt]
  let hasCompactPrompts: Bool

  static let empty = HostIntelligenceCardPresentation(
    key: "empty",
    items: [],
    visibleItems: [],
    headline: nil,
    primaryActionID: nil,
    attentionItems: [],
    visibleCompactPrompts: [],
    expandedPrompts: [],
    hasCompactPrompts: false
  )

  static func build(
    key: String,
    snapshot: HostDecisionSnapshot,
    reservations: [ReservationRecord],
    knownReservations: [ReservationRecord],
    reminderContext: HostIntelligenceReminderInlineContext?,
    attentionPresentation: HostAttentionPresentation,
    briefingText: String,
    usesSeparatedPrompts: Bool,
    includesReviewItem: Bool
  ) -> HostIntelligenceCardPresentation {
    let started = ContinuousClock.now
    let items = HostIntelligenceInlineItemBuilder.build(
      snapshot: snapshot,
      reservations: reservations,
      knownReservations: knownReservations,
      reminderContext: reminderContext
    )
    let visibleItems = HostIntelligenceInlineItemBuilder.visibleItems(
      from: items,
      maxVisible: 4,
      includeMoreItem: includesReviewItem
    )
    let attentionItems = ManagerAttentionItemBuilder.build(
      from: snapshot,
      presentation: attentionPresentation,
      maxItems: 3,
      compactPresentation: true,
      briefingText: briefingText
    )
    let compactPrompts = usesSeparatedPrompts
      ? HostOperationalBriefingPromptBuilder.buildCompactPrompts(from: snapshot)
      : []
    let expandedPrompts = usesSeparatedPrompts
      ? HostOperationalBriefingPromptBuilder.buildExpandedPrompts(from: snapshot)
      : []
    let visibleCompactPrompts = attentionItems.isEmpty
      ? ManagerAttentionItemBuilder.nonRedundantPrompts(
          briefingText: briefingText,
          prompts: compactPrompts
        )
      : []
    let result = HostIntelligenceCardPresentation(
      key: key,
      items: items,
      visibleItems: visibleItems,
      headline: HostIntelligenceInlineItemBuilder.headline(
        snapshot: snapshot,
        reservations: reservations,
        items: items
      ),
      primaryActionID: visibleItems.first(where: isPrimaryInlineCandidate)?.id,
      attentionItems: attentionItems,
      visibleCompactPrompts: visibleCompactPrompts,
      expandedPrompts: expandedPrompts,
      hasCompactPrompts: !compactPrompts.isEmpty
    )
    #if DEBUG
    let durationMs = Int(started.duration(to: .now).pressureTraceTimeInterval * 1_000)
    print("[INTEL_PERF_TRACE] operation=Host inline presentation build reservations=\(reservations.count) knownReservations=\(knownReservations.count) items=\(items.count) durationMs=\(durationMs)")
    #endif
    return result
  }

  private static func isPrimaryInlineCandidate(_ item: HostIntelligenceInlineItem) -> Bool {
    switch item.kind {
    case .allergy, .accessibility, .guestNote, .noTable, .possibleCorrection, .serviceSummary, .cleanup, .seatedTooLong:
      return true
    case .reminder:
      return item.priority <= 26
    case .busyTime:
      return item.priority <= 30
    case .nextGuest, .returningGuest, .occasion, .tableSuggestion, .calm:
      return false
    }
  }
}

enum HostIntelligenceInlineItemBuilder {
  static func build(
    snapshot: HostDecisionSnapshot,
    reservations: [ReservationRecord],
    knownReservations: [ReservationRecord],
    reminderContext: HostIntelligenceReminderInlineContext?
  ) -> [HostIntelligenceInlineItem] {
    var items: [HostIntelligenceInlineItem] = []

    if let serviceSummary = serviceSummaryItem(snapshot: snapshot, reservations: reservations) {
      items.append(serviceSummary)
    }

    items.append(contentsOf: guestCareItems(snapshot: snapshot))
    items.append(contentsOf: noTableItems(snapshot: snapshot, reservations: reservations))
    items.append(contentsOf: seatedTooLongItems(snapshot: snapshot))

    if let reminder = reminderItem(reminderContext) {
      items.append(reminder)
    }

    items.append(contentsOf: possibleCorrectionItems(snapshot: snapshot))
    items.append(contentsOf: busyTimeItems(snapshot: snapshot))
    items.append(contentsOf: returningGuestItems(
      snapshot: snapshot,
      reservations: reservations,
      knownReservationsCount: knownReservations.count
    ))

    if let next = nextGuestItem(reservations: reservations, now: snapshot.generatedAt),
       !items.contains(where: { $0.reservationID == next.reservationID && $0.priority < next.priority }) {
      items.append(next)
    }

    return items
      .stableDedupe()
      .sorted(by: itemSort)
  }

  static func visibleItems(
    from items: [HostIntelligenceInlineItem],
    maxVisible: Int = 4,
    includeMoreItem: Bool = true
  ) -> [HostIntelligenceInlineItem] {
    guard items.count > maxVisible, includeMoreItem, maxVisible > 1 else {
      return Array(items.prefix(maxVisible))
    }
    return Array(items.prefix(maxVisible - 1)) + [
      HostIntelligenceInlineItem(
        id: "inline-more-review",
        kind: .calm,
        priority: 90,
        title: "More",
        detail: "Review",
        reservationID: nil,
        action: nil,
        opensReview: true,
        evidence: ["visibleItems=\(items.count)"],
        confidence: .confirmed,
        suppressReason: nil
      )
    ]
  }

  static func headline(
    snapshot: HostDecisionSnapshot,
    reservations: [ReservationRecord],
    items: [HostIntelligenceInlineItem]
  ) -> String? {
    if serviceSummaryItem(snapshot: snapshot, reservations: reservations) != nil,
       let headline = serviceSummaryHeadline(reservations: reservations) {
      return headline
    }

    if let allergy = items.first(where: { $0.kind == .allergy }) {
      let name = allergy.detail.components(separatedBy: " · ").first ?? "guest"
      return "Check \(name) before seating."
    }

    if items.contains(where: { $0.kind == .possibleCorrection }) {
      return "Possible correction needs a quick check."
    }

    if let noTable = items.first(where: { $0.kind == .noTable }),
       let reservation = reservations.first(where: { $0.remoteID == noTable.reservationID }) {
      return "\(firstName(reservation.guestName)) is next at \(reservation.displayTime) · \(guestCountText(reservation.partySize))."
    }

    if let busy = busySlotPressures(snapshot).first {
      return "\(displaySlotTime(busy.slotTime)) is busy · \(busy.guestCount) guests arriving."
    }

    if let next = nextReservation(reservations: reservations, now: snapshot.generatedAt) {
      return "Next: \(firstName(next.guestName)) at \(next.displayTime) · \(guestCountText(next.partySize))."
    }

    if snapshot.serviceGrounding.isQuietService {
      return punctuate(snapshot.serviceGrounding.deterministicSummary)
    }

    return nil
  }

  private static func guestCareItems(snapshot: HostDecisionSnapshot) -> [HostIntelligenceInlineItem] {
    snapshot.guestSignals.compactMap { signal in
      switch signal.kind {
      case .allergy:
        return guestSignalItem(signal, kind: .allergy, priority: 10, title: "Allergy", actionKind: .alertServer)
      case .accessibility:
        return guestSignalItem(signal, kind: .accessibility, priority: 11, title: "Access", actionKind: .alertServer)
      case .previousServiceIssue:
        return guestSignalItem(signal, kind: .guestNote, priority: 12, title: "Service note", actionKind: .alertServer)
      case .noteReminder:
        return guestSignalItem(signal, kind: .guestNote, priority: 13, title: "Note", actionKind: .alertServer)
      case .seatingPreference:
        return guestSignalItem(signal, kind: .guestNote, priority: 16, title: "Preference", actionKind: .alertServer)
      case .specialOccasion:
        return guestSignalItem(signal, kind: .occasion, priority: 42, title: "Occasion", actionKind: .reviewReservation)
      default:
        return nil
      }
    }
  }

  private static func possibleCorrectionItems(snapshot: HostDecisionSnapshot) -> [HostIntelligenceInlineItem] {
    snapshot.guestSignals
      .filter { $0.kind == .possibleDuplicate }
      .map { signal in
        let action = action(
          id: "inline-correction-\(signal.reservationID)",
          kind: .reviewReservation,
          severity: signal.severity,
          title: "Possible correction",
          reason: "Same phone/email on another active booking today",
          reservationID: signal.reservationID
        )
        return HostIntelligenceInlineItem(
          id: "correction-\(signal.reservationID)",
          kind: .possibleCorrection,
          priority: 30,
          title: "Correction",
          detail: "Same phone/email today",
          reservationID: signal.reservationID,
          action: action,
          opensReview: false,
          evidence: signal.evidence,
          confidence: .likely,
          suppressReason: nil
        )
      }
  }

  private static func noTableItems(
    snapshot: HostDecisionSnapshot,
    reservations: [ReservationRecord]
  ) -> [HostIntelligenceInlineItem] {
    var byID: [Int: ReservationRecord] = [:]
    for reservation in reservations {
      byID[reservation.remoteID] = reservation
    }
    let signalItems = snapshot.tableSignals
      .filter { $0.kind == .noTableAssigned }
      .compactMap { signal -> HostIntelligenceInlineItem? in
        guard let id = signal.relatedReservationIDs.first,
              let reservation = byID[id],
              reservation.isOpenWork,
              !reservation.hasTableAssignment,
              !reservation.isHidden else {
          return nil
        }
        return noTableItem(for: reservation, evidence: signal.evidence)
      }

    let fallbackItems = reservations
      .filter { $0.isOpenWork && !$0.hasTableAssignment && !$0.isHidden }
      .map { noTableItem(for: $0, evidence: ["reservation.hasTableAssignment=false"]) }

    let deduped = (signalItems + fallbackItems).stableDedupe()
    guard deduped.count > 1 else { return deduped }
    return [
      HostIntelligenceInlineItem(
        id: "no-table-summary-\(deduped.count)",
        kind: .noTable,
        priority: 20,
        title: "\(deduped.count) no tables",
        detail: "\(deduped.count) bookings",
        reservationID: nil,
        action: nil,
        opensReview: true,
        evidence: deduped.flatMap(\.evidence).stableUnique(),
        confidence: .confirmed,
        suppressReason: nil
      )
    ]
  }

  private static func seatedTooLongItems(snapshot: HostDecisionSnapshot) -> [HostIntelligenceInlineItem] {
    snapshot.seatedTimingSignals.compactMap { signal in
      guard signal.elapsedMinutes ?? 0 >= 60 else { return nil }
      let action = action(
        id: "inline-seated-\(signal.reservationID)",
        kind: .completeReservation,
        severity: .watch,
        title: "Check table",
        reason: signal.message,
        reservationID: signal.reservationID
      )
      return HostIntelligenceInlineItem(
        id: "seated-long-\(signal.reservationID)",
        kind: .seatedTooLong,
        priority: 24,
        title: "Check table",
        detail: "\(firstName(signal.guestName)) · seated \(durationText(minutes: signal.elapsedMinutes))",
        reservationID: signal.reservationID,
        action: action,
        opensReview: false,
        evidence: ["elapsedMinutes=\(signal.elapsedMinutes ?? 0)", "reliability=\(signal.reliability.rawValue)"],
        confidence: signal.reliability == .unknown ? .uncertain : .likely,
        suppressReason: nil
      )
    }
  }

  private static func busyTimeItems(snapshot: HostDecisionSnapshot) -> [HostIntelligenceInlineItem] {
    busySlotPressures(snapshot).map { pressure in
      let noTablePart = pressure.noTableCount > 0
        ? " · \(pressure.noTableCount) no \(pressure.noTableCount == 1 ? "table" : "tables")"
        : ""
      let largePart = pressure.largePartyCount > 0
        ? " · \(pressure.largePartyCount) large \(pressure.largePartyCount == 1 ? "party" : "parties")"
        : ""
      let closeSlot = pressure.suggestedActions.first(where: { $0.kind == .closeSlot })
      return HostIntelligenceInlineItem(
        id: "busy-\(pressure.id)",
        kind: .busyTime,
        priority: 32,
        title: "\(displaySlotTime(pressure.slotTime)) busy",
        detail: "\(pressure.reservationCount) bookings · \(pressure.guestCount) guests\(noTablePart)\(largePart)",
        reservationID: nil,
        action: closeSlot,
        opensReview: true,
        evidence: [
          "slotTime=\(pressure.slotTime)",
          "reservations=\(pressure.reservationCount)",
          "guests=\(pressure.guestCount)",
          "noTable=\(pressure.noTableCount)"
        ],
        confidence: .confirmed,
        suppressReason: nil
      )
    }
  }

  private static func returningGuestItems(
    snapshot: HostDecisionSnapshot,
    reservations: [ReservationRecord],
    knownReservationsCount: Int
  ) -> [HostIntelligenceInlineItem] {
    guard !reservations.isEmpty else { return [] }

    let started = ContinuousClock.now
    let dayReservationIDs = Set(
      reservations.filter { $0.isExpectedGuest && !$0.isHidden }.map(\.remoteID)
    )
    guard !dayReservationIDs.isEmpty else { return [] }

    let signals = snapshot.guestSignals.filter { signal in
      dayReservationIDs.contains(signal.reservationID)
        && (signal.kind == .regularGuest || signal.kind == .importantGuest)
    }
    var seenReservationIDs = Set<Int>()
    let items: [HostIntelligenceInlineItem] = signals
      .sorted { lhs, rhs in
        if lhs.kind == rhs.kind { return lhs.reservationID < rhs.reservationID }
        return lhs.kind == .importantGuest
      }
      .compactMap { signal -> HostIntelligenceInlineItem? in
        guard seenReservationIDs.insert(signal.reservationID).inserted else { return nil }
        let isFrequent = signal.kind == .importantGuest
        let title = isFrequent ? "Likely regular" : "Seen before"
        let lastVisitText = lastVisitDisplay(from: signal.evidence)
          .map { "last \($0)" } ?? "history found"
        let action = action(
          id: "inline-returning-\(signal.reservationID)",
          kind: .reviewReservation,
          severity: signal.severity,
          title: title,
          reason: signal.message,
          reservationID: signal.reservationID
        )
        return HostIntelligenceInlineItem(
          id: "returning-\(signal.reservationID)",
          kind: .returningGuest,
          priority: 45,
          title: title,
          detail: "\(firstName(signal.guestName)) · \(lastVisitText)",
          reservationID: signal.reservationID,
          action: action,
          opensReview: false,
          evidence: signal.evidence,
          confidence: isFrequent ? .likely : .confirmed,
          suppressReason: nil
        )
      }
    #if DEBUG
    let durationMs = Int(started.duration(to: .now).pressureTraceTimeInterval * 1_000)
    print("[INTEL_PERF_TRACE] operation=Host inline returning scan skipped reason=using_snapshot_guest_signals knownReservations=\(knownReservationsCount) dayReservations=\(reservations.count) acceptedReturning=\(items.count) durationMs=\(durationMs)")
    #endif
    return items
  }

  private static func lastVisitDisplay(from evidence: [String]) -> String? {
    for item in evidence {
      guard item.hasPrefix("lastVisit=") else { continue }
      let value = String(item.dropFirst("lastVisit=".count))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty { return value }
    }
    return nil
  }

  private static func reminderItem(_ context: HostIntelligenceReminderInlineContext?) -> HostIntelligenceInlineItem? {
    guard let context else { return nil }
    if context.isSending {
      return reminderItem(id: "reminder-sending", priority: 25, title: "Sending reminders", detail: "In progress", evidence: ["isSending=true"])
    }
    if context.dailyLimitReached {
      return reminderItem(id: "reminder-limit", priority: 25, title: "Reminder limit", detail: "Reached today", evidence: ["dailyLimitReached=true"])
    }
    if context.dueCount > 0 {
      return reminderItem(id: "reminder-due", priority: 26, title: "\(context.dueCount) reminders", detail: "not sent", evidence: ["eligible=\(context.dueCount)"])
    }
    if context.failedCount > 0 {
      return reminderItem(id: "reminder-failed", priority: 25, title: "\(context.failedCount) reminders", detail: "need check", evidence: ["failed=\(context.failedCount)"])
    }
    if context.skippedCount > 0 {
      return reminderItem(id: "reminder-skipped", priority: 46, title: "No reminders", detail: "inside \(context.leadHours)h cutoff", evidence: ["skipped=\(context.skippedCount)", "leadHours=\(context.leadHours)"])
    }
    return nil
  }

  private static func reminderItem(
    id: String,
    priority: Int,
    title: String,
    detail: String,
    evidence: [String]
  ) -> HostIntelligenceInlineItem {
    HostIntelligenceInlineItem(
      id: id,
      kind: .reminder,
      priority: priority,
      title: title,
      detail: detail,
      reservationID: nil,
      action: nil,
      opensReview: true,
      evidence: evidence,
      confidence: .confirmed,
      suppressReason: nil
    )
  }

  private static func nextGuestItem(
    reservations: [ReservationRecord],
    now: Date
  ) -> HostIntelligenceInlineItem? {
    guard let reservation = nextReservation(reservations: reservations, now: now) else { return nil }
    let action = action(
      id: "inline-next-\(reservation.remoteID)",
      kind: .reviewReservation,
      severity: .info,
      title: "Open reservation",
      reason: "\(reservation.guestName) is next at \(reservation.displayTime)",
      reservationID: reservation.remoteID
    )
    return HostIntelligenceInlineItem(
      id: "next-\(reservation.remoteID)",
      kind: .nextGuest,
      priority: 40,
      title: "Next",
      detail: "\(firstName(reservation.guestName)) · \(reservation.displayTime)",
      reservationID: reservation.remoteID,
      action: action,
      opensReview: false,
      evidence: ["reservationTime=\(reservation.reservationTime)", "partySize=\(reservation.partySize)"],
      confidence: .confirmed,
      suppressReason: nil
    )
  }

  private static func serviceSummaryItem(
    snapshot: HostDecisionSnapshot,
    reservations: [ReservationRecord]
  ) -> HostIntelligenceInlineItem? {
    let visible = reservations.filter { !$0.isHidden }
    guard !visible.isEmpty, visible.allSatisfy({ !$0.isExpectedGuest }) else { return nil }
    let guests = visible
      .filter { $0.statusValue != .cancelled && $0.statusValue != .noShow }
      .reduce(0) { $0 + max(0, $1.partySize) }
    return HostIntelligenceInlineItem(
      id: "service-summary",
      kind: .serviceSummary,
      priority: 18,
      title: "Generate service summary",
      detail: "Review shift",
      reservationID: nil,
      action: nil,
      opensReview: true,
      evidence: ["visibleReservations=\(visible.count)", "expectedGuests=\(guests)", "serviceState=\(snapshot.serviceState.rawValue)"],
      confidence: .confirmed,
      suppressReason: nil
    )
  }

  private static func serviceSummaryHeadline(reservations: [ReservationRecord]) -> String? {
    let visible = reservations.filter { !$0.isHidden }
    guard !visible.isEmpty, visible.allSatisfy({ !$0.isExpectedGuest }) else { return nil }
    let guests = visible
      .filter { $0.statusValue != .cancelled && $0.statusValue != .noShow }
      .reduce(0) { $0 + max(0, $1.partySize) }
    return "Service is done. \(visible.count) reservations, \(guests) expected guests."
  }

  private static func noTableItem(for reservation: ReservationRecord, evidence: [String]) -> HostIntelligenceInlineItem {
    let action = action(
      id: "inline-no-table-\(reservation.remoteID)",
      kind: .assignTable,
      severity: .warning,
      title: "No table",
      reason: "\(reservation.guestName) · \(reservation.displayTime) · \(guestCountText(reservation.partySize))",
      reservationID: reservation.remoteID,
      targetSlotTime: reservation.reservationTime
    )
    return HostIntelligenceInlineItem(
      id: "no-table-\(reservation.remoteID)",
      kind: .noTable,
      priority: 20,
      title: "No table",
      detail: "\(firstName(reservation.guestName)) · \(reservation.displayTime)",
      reservationID: reservation.remoteID,
      action: action,
      opensReview: false,
      evidence: evidence,
      confidence: .confirmed,
      suppressReason: nil
    )
  }

  private static func guestSignalItem(
    _ signal: HostGuestSignal,
    kind: HostIntelligenceInlineKind,
    priority: Int,
    title: String,
    actionKind: HostActionKind
  ) -> HostIntelligenceInlineItem {
    let action = action(
      id: "inline-guest-\(signal.kind.rawValue)-\(signal.reservationID)",
      kind: actionKind,
      severity: signal.severity,
      title: title,
      reason: signal.message,
      reservationID: signal.reservationID
    )
    return HostIntelligenceInlineItem(
      id: "\(kind.rawValue)-\(signal.reservationID)",
      kind: kind,
      priority: priority,
      title: title,
      detail: firstName(signal.guestName),
      reservationID: signal.reservationID,
      action: action,
      opensReview: false,
      evidence: signal.evidence,
      confidence: signal.severity == .info ? .likely : .confirmed,
      suppressReason: nil
    )
  }

  private static func action(
    id: String,
    kind: HostActionKind,
    severity: HostSeverity,
    title: String,
    reason: String,
    reservationID: Int,
    targetSlotTime: String? = nil
  ) -> HostSuggestedAction {
    HostSuggestedAction(
      id: id,
      severity: severity,
      kind: kind,
      title: title,
      reason: reason,
      relatedReservationIDs: [reservationID],
      targetSlotTime: targetSlotTime,
      targetTableName: nil,
      requiresStaffConfirmation: true
    )
  }

  private static func nextReservation(reservations: [ReservationRecord], now: Date) -> ReservationRecord? {
    let active = reservations
      .filter { $0.isExpectedGuest && !$0.isHidden }
      .sorted {
        if $0.reservationTime == $1.reservationTime {
          return $0.guestName.localizedCaseInsensitiveCompare($1.guestName) == .orderedAscending
        }
        return $0.reservationTime < $1.reservationTime
      }
    guard !active.isEmpty else { return nil }
    return active.first { reservation in
      guard reservation.reservationDate == Date.reservationDateString(),
            let serviceDate = reservation.serviceDateTime else {
        return true
      }
      return serviceDate >= now.addingTimeInterval(-10 * 60)
    } ?? active.first
  }

  private static func busySlotPressures(_ snapshot: HostDecisionSnapshot) -> [HostSlotPressure] {
    snapshot.slotPressures
      .filter { pressure in
        pressure.severity == .busy
          || pressure.severity == .critical
          || pressure.noTableCount > 0
          || pressure.largePartyCount > 0
      }
      .sorted {
        if pressureRank($0.severity) != pressureRank($1.severity) {
          return pressureRank($0.severity) < pressureRank($1.severity)
        }
        if $0.guestCount != $1.guestCount {
          return $0.guestCount > $1.guestCount
        }
        return $0.slotTime < $1.slotTime
      }
  }

  private static func itemSort(_ lhs: HostIntelligenceInlineItem, _ rhs: HostIntelligenceInlineItem) -> Bool {
    if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
    if lhs.confidence != rhs.confidence {
      return confidenceRank(lhs.confidence) < confidenceRank(rhs.confidence)
    }
    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
  }

  private static func confidenceRank(_ confidence: HostIntelligenceInlineConfidence) -> Int {
    switch confidence {
    case .confirmed: return 0
    case .likely: return 1
    case .uncertain: return 2
    }
  }

  private static func pressureRank(_ severity: HostPressureSeverity) -> Int {
    switch severity {
    case .critical: return 0
    case .busy: return 1
    case .watch: return 2
    case .calm: return 3
    }
  }

  private static func firstName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "Guest" }
    return trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? trimmed
  }

  private static func guestCountText(_ count: Int) -> String {
    "\(count) \(count == 1 ? "guest" : "guests")"
  }

  private static func durationText(minutes: Int?) -> String {
    let minutes = max(0, minutes ?? 0)
    if minutes >= 60 {
      return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }
    return "\(minutes)m"
  }

  private static func displaySlotTime(_ value: String) -> String {
    if let date = ReservationFormatters.apiTime.date(from: value) {
      return ReservationFormatters.shortTime.string(from: date)
    }
    return String(value.prefix(5))
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

private extension Array where Element == HostIntelligenceInlineItem {
  func stableDedupe() -> [HostIntelligenceInlineItem] {
    var seen = Set<String>()
    var result: [HostIntelligenceInlineItem] = []
    for item in self {
      let key = "\(item.kind.rawValue)|\(item.reservationID.map(String.init) ?? "none")|\(item.title.lowercased())|\(item.detail.lowercased())"
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
      guard !seen.contains(value) else { continue }
      seen.insert(value)
      result.append(value)
    }
    return result
  }
}
