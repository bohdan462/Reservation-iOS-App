//
//  HostOperationalBriefingPromptBuilder.swift
//  Tryzub Reservations
//
//  Deterministic grouped operational prompts from Host Intelligence snapshot data.
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

enum HostOperationalBriefingPromptMode: Equatable {
  case compact
  case expanded
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
  private static let expandedCategoryOrder: [HostOperationalBriefingPromptCategory] = [
    .reservationAttention,
    .tablePlan,
    .guestNotes,
    .timing,
    .booking
  ]

  private static let factCategoriesByGroup: [HostOperationalBriefingPromptCategory: Set<HostFactCategory>] = [
    .reservationAttention: [.duplicate, .sync, .cancellation],
    .tablePlan: [.table, .capacity, .opportunity],
    .guestNotes: [.allergy, .preference, .note, .guest],
    .timing: [.arrivalWave, .overdue, .timing, .largeParty],
    .booking: [.bookingDecision, .analytics]
  ]

  static func build(from snapshot: HostDecisionSnapshot) -> [HostOperationalBriefingPrompt] {
    buildExpandedPrompts(from: snapshot)
  }

  static func buildCompactPrompts(from snapshot: HostDecisionSnapshot) -> [HostOperationalBriefingPrompt] {
    build(snapshot: snapshot, mode: .compact)
  }

  static func buildExpandedPrompts(from snapshot: HostDecisionSnapshot) -> [HostOperationalBriefingPrompt] {
    build(snapshot: snapshot, mode: .expanded)
  }

  static func build(
    snapshot: HostDecisionSnapshot,
    mode: HostOperationalBriefingPromptMode
  ) -> [HostOperationalBriefingPrompt] {
    let candidates = expandedCategoryOrder.compactMap { category in
      buildCategoryPrompt(category: category, snapshot: snapshot, mode: mode)
    }

    guard !candidates.isEmpty else { return [] }

    switch mode {
    case .expanded:
      return Array(candidates.prefix(5))
    case .compact:
      return Array(
        candidates
          .sorted { lhs, rhs in
            if lhs.severity.rank != rhs.severity.rank {
              return lhs.severity.rank < rhs.severity.rank
            }
            return categoryRank(lhs.category) < categoryRank(rhs.category)
          }
          .prefix(2)
      )
    }
  }

  // MARK: - Category Builders

  private static func buildCategoryPrompt(
    category: HostOperationalBriefingPromptCategory,
    snapshot: HostDecisionSnapshot,
    mode: HostOperationalBriefingPromptMode
  ) -> HostOperationalBriefingPrompt? {
    switch category {
    case .reservationAttention:
      return buildReservationAttentionPrompt(snapshot: snapshot)
    case .tablePlan:
      return buildTablePlanPrompt(snapshot: snapshot)
    case .guestNotes:
      return buildGuestNotesPrompt(snapshot: snapshot, mode: mode)
    case .timing:
      return buildTimingPrompt(snapshot: snapshot)
    case .booking:
      return buildBookingPrompt(snapshot: snapshot)
    case .general:
      return nil
    }
  }

  private static func buildReservationAttentionPrompt(
    snapshot: HostDecisionSnapshot
  ) -> HostOperationalBriefingPrompt? {
    var lines: [String] = []
    var reservationIDs = Set<Int>()

    let confirmCandidates = snapshot.bookingDecisions.filter { $0.decision == .autoConfirm }
    let manualReviews = snapshot.bookingDecisions.filter { $0.decision == .manualReview }
    confirmCandidates.compactMap(\.reservationID).forEach { reservationIDs.insert($0) }
    manualReviews.compactMap(\.reservationID).forEach { reservationIDs.insert($0) }

    if confirmCandidates.count == 1 {
      lines.append("One reservation may need confirmation review.")
    } else if confirmCandidates.count > 1 {
      lines.append("\(confirmCandidates.count) reservations may need confirmation review.")
    }

    if manualReviews.count == 1 {
      lines.append("One request needs manual review before confirming.")
    } else if manualReviews.count > 1 {
      lines.append("\(manualReviews.count) requests need manual review before confirming.")
    }

    let manualCallIns = snapshot.guestSignals.filter { $0.kind == .manualCallIn }
    if manualCallIns.count == 1 {
      lines.append("One manual call-in should be reviewed before staff acts.")
    } else if manualCallIns.count > 1 {
      lines.append("\(manualCallIns.count) manual call-ins should be reviewed before staff acts.")
    }
    manualCallIns.forEach { reservationIDs.insert($0.reservationID) }

    let duplicates = snapshot.guestSignals.filter { $0.kind == .possibleDuplicate }
    if !duplicates.isEmpty {
      lines.append("A possible correction or duplicate should be reviewed before staff acts.")
      duplicates.forEach { reservationIDs.insert($0.reservationID) }
    }

    let riskSignals = snapshot.guestSignals.filter {
      $0.kind == .cancellationRisk || $0.kind == .noShowRisk
    }
    if riskSignals.count == 1 {
      lines.append("One booking risk signal should be reviewed.")
    } else if riskSignals.count > 1 {
      lines.append("\(riskSignals.count) booking risk signals should be reviewed.")
    }
    riskSignals.forEach { reservationIDs.insert($0.reservationID) }

    appendFactLines(
      category: .reservationAttention,
      facts: snapshot.briefingFacts,
      into: &lines,
      reservationIDs: &reservationIDs,
      maxLines: 1
    )

    return makePrompt(
      category: .reservationAttention,
      lines: lines,
      severity: maxSeverity(
        manualReviews.map { _ in HostSeverity.warning }
          + duplicates.map(\.severity)
          + riskSignals.map(\.severity)
          + confirmCandidates.map { _ in HostSeverity.watch }
      ),
      reservationIDs: Array(reservationIDs)
    )
  }

  private static func buildGuestNotesPrompt(
    snapshot: HostDecisionSnapshot,
    mode: HostOperationalBriefingPromptMode
  ) -> HostOperationalBriefingPrompt? {
    var lines: [String] = []
    var reservationIDs = Set<Int>()

    let returningGuests = snapshot.guestSignals.filter {
      $0.kind == .regularGuest || $0.kind == .importantGuest || $0.kind == .vip
    }
    if mode == .expanded {
      for signal in returningGuests {
        if let line = HostGuestIntelligenceSupport.compactReturningGuestPromptLine(for: signal) {
          lines.append(line)
        }
        reservationIDs.insert(signal.reservationID)
      }
    } else {
      returningGuests.forEach { reservationIDs.insert($0.reservationID) }
    }

    let allergies = snapshot.guestSignals.filter { $0.kind == .allergy }
    if mode == .expanded {
      if allergies.count == 1 {
        lines.append("One allergy note should be reviewed before seating.")
      } else if allergies.count > 1 {
        lines.append("\(allergies.count) allergy notes should be reviewed before seating.")
      }
    } else if !allergies.isEmpty {
      lines.append(
        allergies.count == 1
          ? "One allergy note should be reviewed before seating."
          : "\(allergies.count) allergy notes should be reviewed before seating."
      )
    }
    allergies.forEach { reservationIDs.insert($0.reservationID) }

    let specialOccasions = snapshot.guestSignals.filter { $0.kind == .specialOccasion }
    if mode == .expanded {
      if specialOccasions.count == 1 {
        lines.append("One guest has a special occasion note. Review it before seating.")
      } else if specialOccasions.count > 1 {
        lines.append("\(specialOccasions.count) guests have special occasion notes. Review them before seating.")
      }
    }
    specialOccasions.forEach { reservationIDs.insert($0.reservationID) }

    let preferences = snapshot.guestSignals.filter {
      $0.kind == .seatingPreference || $0.kind == .accessibility
    }
    if mode == .expanded {
      if preferences.count == 1 {
        lines.append("One guest note should be reviewed before seating.")
      } else if preferences.count > 1 {
        lines.append("\(preferences.count) guest notes should be reviewed before seating.")
      }
    }
    preferences.forEach { reservationIDs.insert($0.reservationID) }

    let serviceIssues = snapshot.guestSignals.filter { $0.kind == .previousServiceIssue }
    if !serviceIssues.isEmpty {
      lines.append("A prior service issue should be shared with the server.")
      serviceIssues.forEach { reservationIDs.insert($0.reservationID) }
    }

    if mode == .expanded {
      appendFactLines(
        category: .guestNotes,
        facts: snapshot.briefingFacts,
        into: &lines,
        reservationIDs: &reservationIDs,
        maxLines: 1
      )
    }

    return makePrompt(
      category: .guestNotes,
      lines: lines,
      severity: maxSeverity(
        allergies.map(\.severity)
          + serviceIssues.map(\.severity)
          + specialOccasions.map(\.severity)
          + preferences.map(\.severity)
          + returningGuests.map(\.severity)
      ),
      reservationIDs: Array(reservationIDs)
    )
  }

  private static func buildTablePlanPrompt(
    snapshot: HostDecisionSnapshot
  ) -> HostOperationalBriefingPrompt? {
    var lines: [String] = []
    var reservationIDs = Set<Int>()

    let noTableSignals = snapshot.tableSignals.filter { $0.kind == .noTableAssigned }
    if noTableSignals.count == 1 {
      lines.append(sanitizeLine(noTableSignals[0].detail))
    } else if noTableSignals.count > 1 {
      lines.append("\(noTableSignals.count) reservations have no table assigned.")
    }
    noTableSignals.forEach { reservationIDs.formUnion($0.relatedReservationIDs) }

    let capacityMismatch = snapshot.tableSignals.filter { $0.kind == .tableCapacityMismatch }
    capacityMismatch.prefix(1).forEach { signal in
      lines.append(sanitizeLine(signal.detail))
      reservationIDs.formUnion(signal.relatedReservationIDs)
    }

    let turnRisk = snapshot.tableSignals.filter { $0.kind == .tableTurnRisk }
    if !turnRisk.isEmpty, lines.count < 2 {
      lines.append("Table turn pressure should be reviewed before seating the next party.")
      turnRisk.forEach { reservationIDs.formUnion($0.relatedReservationIDs) }
    }

    let freedTables = snapshot.tableSignals.filter { $0.kind == .cancellationFreedTable }
    freedTables.prefix(1).forEach { signal in
      if lines.count < 2 {
        lines.append(sanitizeLine(signal.detail))
        reservationIDs.formUnion(signal.relatedReservationIDs)
      }
    }

    appendFactLines(
      category: .tablePlan,
      facts: snapshot.briefingFacts,
      into: &lines,
      reservationIDs: &reservationIDs,
      maxLines: 2
    )

    return makePrompt(
      category: .tablePlan,
      lines: lines,
      severity: maxSeverity(
        noTableSignals.map(\.severity)
          + capacityMismatch.map(\.severity)
          + turnRisk.map(\.severity)
      ),
      reservationIDs: Array(reservationIDs)
    )
  }

  private static func buildTimingPrompt(
    snapshot: HostDecisionSnapshot
  ) -> HostOperationalBriefingPrompt? {
    var lines: [String] = []
    var reservationIDs = Set<Int>()

    appendFactLines(
      category: .timing,
      facts: snapshot.briefingFacts,
      into: &lines,
      reservationIDs: &reservationIDs,
      maxLines: 2
    )

    let pressuredSlots = snapshot.slotPressures
      .filter { $0.severity != .calm && $0.reservationCount > 0 }
      .sorted { lhs, rhs in
        if lhs.severity != rhs.severity {
          return slotSeverityRank(lhs.severity) < slotSeverityRank(rhs.severity)
        }
        return lhs.reservationCount > rhs.reservationCount
      }

    if lines.isEmpty, let peak = pressuredSlots.first {
      lines.append("Peak pressure near \(peak.slotTime) should be reviewed.")
    }

    snapshot.seatedTimingSignals
      .filter { ($0.elapsedMinutes ?? 0) >= 60 }
      .prefix(1)
      .forEach { signal in
        if lines.count < 2 {
          lines.append(sanitizeLine(signal.message))
          reservationIDs.insert(signal.reservationID)
        }
      }

    return makePrompt(
      category: .timing,
      lines: lines,
      severity: maxSeverity(snapshot.briefingFacts.filter {
        factCategoriesByGroup[.timing]?.contains($0.category) == true
      }.map(\.severity)),
      reservationIDs: Array(reservationIDs)
    )
  }

  private static func buildBookingPrompt(
    snapshot: HostDecisionSnapshot
  ) -> HostOperationalBriefingPrompt? {
    var lines: [String] = []
    var reservationIDs = Set<Int>()

    let alternates = snapshot.bookingDecisions.filter { $0.decision == .suggestAlternateTime }
    if alternates.count == 1 {
      lines.append("One request may need a safer alternate time.")
    } else if alternates.count > 1 {
      lines.append("\(alternates.count) requests may need safer alternate times.")
    }
    alternates.compactMap(\.reservationID).forEach { reservationIDs.insert($0) }

    let rejects = snapshot.bookingDecisions.filter { $0.decision == .reject }
    if rejects.count == 1 {
      lines.append("One blocked request should be reviewed manually.")
    } else if rejects.count > 1 {
      lines.append("\(rejects.count) blocked requests should be reviewed manually.")
    }
    rejects.compactMap(\.reservationID).forEach { reservationIDs.insert($0) }

    let confirmables = snapshot.bookingDecisions.filter { $0.decision == .autoConfirm }
    if confirmables.count == 1, lines.count < 2 {
      lines.append("One small party looks confirmable, but staff still needs to review.")
      confirmables.compactMap(\.reservationID).forEach { reservationIDs.insert($0) }
    }

    appendFactLines(
      category: .booking,
      facts: snapshot.briefingFacts,
      into: &lines,
      reservationIDs: &reservationIDs,
      maxLines: 1
    )

    let bookingActions = snapshot.suggestedActions.filter {
      $0.kind == .suggestAlternateTime || $0.kind == .confirmReservation
    }
    bookingActions.forEach { reservationIDs.formUnion($0.relatedReservationIDs) }

    return makePrompt(
      category: .booking,
      lines: lines,
      severity: maxSeverity(
        alternates.map { _ in HostSeverity.warning }
          + rejects.map { _ in HostSeverity.critical }
          + confirmables.map { _ in HostSeverity.watch }
      ),
      reservationIDs: Array(reservationIDs)
    )
  }

  // MARK: - Helpers

  private static func appendFactLines(
    category: HostOperationalBriefingPromptCategory,
    facts: [HostBriefingFact],
    into lines: inout [String],
    reservationIDs: inout Set<Int>,
    maxLines: Int
  ) {
    guard let allowed = factCategoriesByGroup[category] else { return }

    for fact in facts where allowed.contains(fact.category) {
      guard lines.count < maxLines else { break }
      if let line = sentence(for: fact), !lines.contains(line) {
        lines.append(line)
        fact.relatedReservationIDs.forEach { reservationIDs.insert($0) }
      }
    }
  }

  private static func makePrompt(
    category: HostOperationalBriefingPromptCategory,
    lines: [String],
    severity: HostSeverity,
    reservationIDs: [Int]
  ) -> HostOperationalBriefingPrompt? {
    let cleaned = lines
      .map(sanitizeLine)
      .filter { !$0.isEmpty }
    guard !cleaned.isEmpty else { return nil }

    return HostOperationalBriefingPrompt(
      id: "operational-\(category.rawValue)",
      title: category.displayTitle,
      body: cleaned.prefix(2).joined(separator: " "),
      category: category,
      severity: severity,
      source: .deterministic,
      relatedReservationIDs: Array(Set(reservationIDs)).sorted()
    )
  }

  private static func sentence(for fact: HostBriefingFact) -> String? {
    let detail = fact.detail.trimmingCharacters(in: .whitespacesAndNewlines)
    if !detail.isEmpty {
      return sanitizeLine(detail)
    }

    let title = fact.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return nil }
    return sanitizeLine(title)
  }

  private static func sanitizeLine(_ text: String) -> String {
    var line = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !line.isEmpty else { return "" }

    let forbidden = [
      "has been assigned", "is assigned", "has been confirmed", "has been reviewed",
      "no changes needed", "all set", "handled", "resolved",
      "mention the occasion at arrival", "mention the occasion",
      "celebrate the occasion", "celebrate with the guest",
      "tell the guest happy", "wish the guest happy", "wish them happy",
      "announce the occasion"
    ]
    let lower = line.lowercased()
    for phrase in forbidden where lower.contains(phrase) {
      return ""
    }

    if !line.hasSuffix(".") {
      line += "."
    }
    return line
  }

  private static func maxSeverity(_ severities: [HostSeverity]) -> HostSeverity {
    severities.min(by: { $0.rank < $1.rank }) ?? .info
  }

  private static func categoryRank(_ category: HostOperationalBriefingPromptCategory) -> Int {
    expandedCategoryOrder.firstIndex(of: category) ?? expandedCategoryOrder.count
  }

  private static func slotSeverityRank(_ severity: HostPressureSeverity) -> Int {
    switch severity {
    case .critical: return 0
    case .busy: return 1
    case .watch: return 2
    case .calm: return 3
    }
  }
}
