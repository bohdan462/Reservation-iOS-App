//
//  HostBookingFactGrouping.swift
//  Tryzub Reservations
//
//  Merges repeated booking-decision facts into one manager-facing alert.
//

import Foundation

enum HostBookingFactGrouping {

  static func groupedFacts(
    from facts: [HostBriefingFact],
    decisions: [HostBookingDecisionResult],
    reservations: [ReservationRecord],
    settings: HostIntelligenceSettings
  ) -> [HostBriefingFact] {
    let decisionByReservationID = Dictionary(
      uniqueKeysWithValues: decisions.compactMap { decision in
        decision.reservationID.map { ($0, decision) }
      }
    )
    let reservationByID = Dictionary(uniqueKeysWithValues: reservations.map { ($0.remoteID, $0) })

    let bookingFacts = facts.filter { $0.category == .bookingDecision || $0.category == .largeParty }
    let otherFacts = facts.filter { !($0.category == .bookingDecision || $0.category == .largeParty) }

    var buckets: [String: [GroupedBookingItem]] = [:]
    var orphans: [HostBriefingFact] = []

    for fact in bookingFacts {
      guard let reservationID = fact.relatedReservationIDs.first,
            let decision = decisionByReservationID[reservationID],
            let reservation = reservationByID[reservationID] else {
        orphans.append(fact)
        continue
      }

      guard let groupKey = groupKey(for: decision, settings: settings) else {
        orphans.append(polishIndividualFact(fact, reservation: reservation, decision: decision))
        continue
      }

      buckets[groupKey, default: []].append(
        GroupedBookingItem(fact: fact, decision: decision, reservation: reservation)
      )
    }

    var mergedFacts: [HostBriefingFact] = []
    for (key, items) in buckets {
      let sortedItems = items.sorted {
        ($0.reservation.serviceDateTime ?? .distantFuture) < ($1.reservation.serviceDateTime ?? .distantFuture)
      }
      if sortedItems.count >= 2,
         let merged = mergedFact(for: key, items: sortedItems, settings: settings) {
        mergedFacts.append(merged)
      } else if let item = sortedItems.first {
        mergedFacts.append(polishIndividualFact(item.fact, reservation: item.reservation, decision: item.decision))
      }
    }

    return otherFacts + mergedFacts + orphans
  }

  // MARK: - Private

  private struct GroupedBookingItem {
    let fact: HostBriefingFact
    let decision: HostBookingDecisionResult
    let reservation: ReservationRecord
  }

  private static func groupKey(
    for decision: HostBookingDecisionResult,
    settings: HostIntelligenceSettings
  ) -> String? {
    switch decision.decision {
    case .autoConfirm:
      guard settings.autoConfirmRecommendationsEnabled else { return nil }
      return "autoConfirm:manageable"
    case .manualReview:
      let reason = decision.reason.lowercased()
      if reason.contains("coming up soon") {
        return "manualReview:dueSoon"
      }
      if reason.contains("large party") {
        return "manualReview:largeParty"
      }
      return nil
    case .suggestAlternateTime:
      return "alternate:\(decision.suggestedTime ?? decision.requestedTime ?? "")"
    case .reject, .noDecision:
      return nil
    }
  }

  private static func mergedFact(
    for key: String,
    items: [GroupedBookingItem],
    settings: HostIntelligenceSettings
  ) -> HostBriefingFact? {
    let reservations = items.map(\.reservation)
    let reservationIDs = reservations.map(\.remoteID)
    let evidence = items.flatMap(\.fact.evidence)
    let severities = items.map(\.fact.severity)
    let severity = severities.min(by: { $0.rank < $1.rank }) ?? .info
    let idSuffix = reservationIDs.sorted().map(String.init).joined(separator: "-")

    switch key {
    case "autoConfirm:manageable":
      return HostBriefingFact(
        id: "booking-fact-group-autoConfirm-\(idSuffix)",
        severity: severity,
        category: .bookingDecision,
        title: "\(namesPhrase(for: reservations)) look safe to confirm.",
        detail: pronounPhrase(for: reservations.count) + " times look manageable, but staff should still check details.",
        evidence: evidence,
        relatedReservationIDs: reservationIDs,
        suggestedActionTitle: "Confirm if details look right."
      )

    case "manualReview:dueSoon":
      return HostBriefingFact(
        id: "booking-fact-group-dueSoon-\(idSuffix)",
        severity: elevatedSeverity(severity, minimum: .watch),
        category: .bookingDecision,
        title: dueSoonTitle(for: reservations),
        detail: "Check details before confirming.",
        evidence: evidence,
        relatedReservationIDs: reservationIDs,
        suggestedActionTitle: "Check before confirming."
      )

    case "manualReview:largeParty":
      return HostBriefingFact(
        id: "booking-fact-group-largeParty-\(idSuffix)",
        severity: elevatedSeverity(severity, minimum: .warning),
        category: .largeParty,
        title: "\(reservations.count) large parties need floor plan review.",
        detail: "Check combined floor plan before confirming.",
        evidence: evidence,
        relatedReservationIDs: reservationIDs,
        suggestedActionTitle: "Check the floor plan."
      )

    default:
      if key.hasPrefix("alternate:"), items.count >= 2 {
        let alternate = items.first?.decision.suggestedTime ?? "another time"
        return HostBriefingFact(
          id: "booking-fact-group-alternate-\(idSuffix)",
          severity: severity,
          category: .bookingDecision,
          title: "\(reservations.count) bookings may fit better at \(alternate).",
          detail: "Check time options with guests before confirming.",
          evidence: evidence,
          relatedReservationIDs: reservationIDs,
          suggestedActionTitle: "Check time options."
        )
      }
      return nil
    }
  }

  private static func polishIndividualFact(
    _ fact: HostBriefingFact,
    reservation: ReservationRecord,
    decision: HostBookingDecisionResult
  ) -> HostBriefingFact {
    let firstName = staffFirstName(from: reservation.guestName)

    switch decision.decision {
    case .autoConfirm:
      return HostBriefingFact(
        id: fact.id,
        severity: fact.severity,
        category: fact.category,
        title: "\(firstName) looks safe to confirm.",
        detail: "The time looks manageable, but staff should still check details.",
        evidence: fact.evidence,
        relatedReservationIDs: fact.relatedReservationIDs,
        suggestedActionTitle: fact.suggestedActionTitle ?? "Confirm if details look right."
      )
    case .manualReview where decision.reason.lowercased().contains("coming up soon"):
      return HostBriefingFact(
        id: fact.id,
        severity: fact.severity,
        category: fact.category,
        title: "\(firstName)'s booking is coming up soon.",
        detail: "Check details before confirming.",
        evidence: fact.evidence,
        relatedReservationIDs: fact.relatedReservationIDs,
        suggestedActionTitle: fact.suggestedActionTitle ?? "Check before confirming."
      )
    default:
      return fact
    }
  }

  static func staffFirstName(from guestName: String) -> String {
    let trimmed = guestName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "Guest" }
    return trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? trimmed
  }

  private static func dueSoonTitle(for reservations: [ReservationRecord]) -> String {
    let firstNames = reservations.map { staffFirstName(from: $0.guestName) }
    switch reservations.count {
    case 0:
      return "Bookings are coming up soon."
    case 1:
      return "\(firstNames[0])'s booking is coming up soon."
    case 2:
      return "\(namesPhrase(for: reservations))'s bookings are coming up soon."
    case 3:
      return "\(firstNames[0]), \(firstNames[1]), and 1 more booking are coming up soon."
    default:
      return "\(reservations.count) bookings are coming up soon."
    }
  }

  private static func namesPhrase(for reservations: [ReservationRecord]) -> String {
    let firstNames = reservations.map { staffFirstName(from: $0.guestName) }
    switch firstNames.count {
    case 0:
      return "Bookings"
    case 1:
      return firstNames[0]
    case 2:
      return "\(firstNames[0]) and \(firstNames[1])"
    case 3:
      return "\(firstNames[0]), \(firstNames[1]), and 1 more"
    default:
      return "\(firstNames.count) bookings"
    }
  }

  private static func pronounPhrase(for count: Int) -> String {
    count == 1 ? "The" : "Their"
  }

  private static func elevatedSeverity(_ severity: HostSeverity, minimum: HostSeverity) -> HostSeverity {
    severity.rank <= minimum.rank ? severity : minimum
  }
}

#if DEBUG
enum HostBookingFactGroupingSamples {

  static let twoSafeToConfirmTitle = "Nick and Max look safe to confirm."
  static let twoSafeToConfirmDetail =
    "Their times look manageable, but staff should still check details."

  static let threeSafeToConfirmTitle = "Nick, Max, and 1 more look safe to confirm."
  static let twoDueSoonTitle = "Max and Nick's bookings are coming up soon."
  static let singleSafeTitle = "Max looks safe to confirm."
}
#endif
