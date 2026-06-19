//
//  NewBookingRowInsightBuilder.swift
//  Tryzub Reservations
//
//  Compact per-reservation insight for Bookings → New rows.
//

import Foundation

struct NewBookingRowInsight: Equatable {
  let reservationID: Int
  let guestLine: String?
  let tableLine: String?
  let noteLine: String?
  let isReturningGuest: Bool
  let hasSpecificTableFit: Bool

  var displayLines: [String] {
    var lines: [String] = []
    if let noteLine = noteLine?.nilIfBlank {
      lines.append(noteLine)
    }
    if let tableLine = tableLine?.nilIfBlank {
      lines.append(tableLine)
    } else if let guestLine = guestLine?.nilIfBlank, lines.count < 2 {
      lines.append(guestLine)
    }
    return Array(lines.prefix(2))
  }
}

enum NewBookingRowInsightBuilder {

  static func build(
    reservation: ReservationRecord,
    historyPool: [ReservationRecord],
    tableConfigs: [RestaurantTableConfig],
    largePartyThreshold: Int = HostIntelligenceSettings().largePartyThreshold
  ) -> NewBookingRowInsight? {
    let report = GuestInsightsController().analyze(
      selected: reservation,
      allReservations: historyPool
    )

    let guestLine = guestInsightLine(report: report, reservationID: reservation.remoteID)
    let tableLine = tableInsightLine(
      reservation: reservation,
      tableConfigs: tableConfigs,
      largePartyThreshold: largePartyThreshold
    )
    let noteLine = noteInsightLine(
      for: reservation,
      report: report,
      historyPool: historyPool
    )

    let insight = NewBookingRowInsight(
      reservationID: reservation.remoteID,
      guestLine: guestLine,
      tableLine: tableLine,
      noteLine: noteLine,
      isReturningGuest: report.hasReliableRepeatGuestHistory,
      hasSpecificTableFit: tableLine != nil
    )

    return insight.displayLines.isEmpty ? nil : insight
  }

  static func countSpecificTableFits(
    pending: [ReservationRecord],
    tableConfigs: [RestaurantTableConfig],
    largePartyThreshold: Int = HostIntelligenceSettings().largePartyThreshold
  ) -> Int {
    pending.filter { reservation in
      tableInsightLine(
        reservation: reservation,
        tableConfigs: tableConfigs,
        largePartyThreshold: largePartyThreshold
      ) != nil
    }.count
  }

  static func countAllergyNotes(pending: [ReservationRecord]) -> Int {
    pending.filter { reservation in
      let notes = combinedNotes(for: reservation)
      return HostGuestNoteSnippetExtractor.allergySnippet(from: notes) != nil
    }.count
  }

  static func countPossibleDuplicates(
    pending: [ReservationRecord],
    historyPool: [ReservationRecord]
  ) -> Int {
    let analyzer = GuestInsightsController()
    return pending.filter { reservation in
      let report = analyzer.analyze(selected: reservation, allReservations: historyPool)
      return possibleDuplicateLine(
        report: report,
        reservation: reservation,
        historyPool: historyPool
      ) != nil
    }.count
  }

  static func isLargePartyNeedingTablePlan(
    reservation: ReservationRecord,
    tableConfigs: [RestaurantTableConfig],
    largePartyThreshold: Int = HostIntelligenceSettings().largePartyThreshold
  ) -> Bool {
    tableInsightLine(
      reservation: reservation,
      tableConfigs: tableConfigs,
      largePartyThreshold: largePartyThreshold
    ) == "Large party — check joined tables"
  }

  // MARK: - Guest

  private static func guestInsightLine(
    report: GuestInsightReport,
    reservationID: Int
  ) -> String? {
    _ = reservationID
    guard report.hasReliableRepeatGuestHistory else { return nil }
    return GuestHistorySemantics.seenBeforeRowLine(
      priorReliableVisitCount: report.priorReliableVisitCount,
      lastPriorVisitDisplayDate: report.lastPriorVisitDisplayDate
    )
  }

  // MARK: - Notes

  private static func noteInsightLine(
    for reservation: ReservationRecord,
    report: GuestInsightReport,
    historyPool: [ReservationRecord]
  ) -> String? {
    if let duplicateLine = possibleDuplicateLine(
      report: report,
      reservation: reservation,
      historyPool: historyPool
    ) {
      return duplicateLine
    }

    let notes = combinedNotes(for: reservation)
    guard !notes.isEmpty else { return nil }

    if HostGuestNoteSnippetExtractor.allergySnippet(from: notes) != nil {
      return "Allergy note — tell server"
    }
    if let snippet = HostGuestNoteSnippetExtractor.seatingPreferenceSnippet(from: notes) {
      return "Accessibility — \(snippet)"
    }
    if GuestHistorySemantics.hasOccasionNoteText(for: reservation) {
      return "Guest note — check before seating"
    }
    return nil
  }

  private static func possibleDuplicateLine(
    report: GuestInsightReport,
    reservation: ReservationRecord,
    historyPool: [ReservationRecord]
  ) -> String? {
    guard isActiveDuplicateCandidate(reservation),
          hasActiveSameDayDuplicatePeer(for: reservation, in: historyPool) else {
      return nil
    }

    return "Possible correction — same phone/email on another active booking today"
  }

  private static func hasActiveSameDayDuplicatePeer(
    for reservation: ReservationRecord,
    in historyPool: [ReservationRecord]
  ) -> Bool {
    let resolver = GuestIdentityResolver()
    let selected = resolver.identity(for: reservation)

    return historyPool.contains { peer in
      guard peer.remoteID != reservation.remoteID,
            peer.reservationDate == reservation.reservationDate,
            isActiveDuplicateCandidate(peer) else {
        return false
      }

      let candidate = resolver.identity(for: peer)
      if let selectedPhone = selected.fullPhoneDigits,
         let candidatePhone = candidate.fullPhoneDigits,
         selectedPhone == candidatePhone {
        return true
      }
      if let selectedEmail = selected.usefulEmail,
         let candidateEmail = candidate.usefulEmail,
         selectedEmail == candidateEmail {
        return true
      }
      guard let match = resolver.match(
        peer,
        against: selected,
        selectedID: reservation.remoteID
      ) else {
        return false
      }
      return match.confidence == .exact || match.confidence == .strong
    }
  }

  private static func isActiveDuplicateCandidate(_ reservation: ReservationRecord) -> Bool {
    let supersededID = reservation.supersededById ?? 0
    return reservation.isExpectedGuest
      && !reservation.isHidden
      && supersededID <= 0
  }

  private static func combinedNotes(for reservation: ReservationRecord) -> String {
    "\(reservation.guestNotes ?? "") \(reservation.staffNotes ?? "")"
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Table

  private static func tableInsightLine(
    reservation: ReservationRecord,
    tableConfigs: [RestaurantTableConfig],
    largePartyThreshold: Int
  ) -> String? {
    if HostTableIntelligenceSupport.assignedTableCapacityMismatch(
      for: reservation,
      tableConfigs: tableConfigs
    ) != nil {
      return "Assigned table may be too small"
    }

    guard !reservation.hasTableAssignment else { return nil }
    guard HostTableIntelligenceSupport.shouldSurfaceNoTableFitAdvice(
      partySize: reservation.partySize,
      largePartyThreshold: largePartyThreshold
    ) else {
      return nil
    }

    let activeTables = tableConfigs.filter(\.isActive)
    guard !activeTables.isEmpty else { return nil }

    let singles = HostTableIntelligenceSupport.findSingleTableFitOptions(
      reservation: reservation,
      tables: activeTables
    )
    let combinations = HostTableIntelligenceSupport.findCombinationTableFitOptions(
      reservation: reservation,
      tables: activeTables
    )

    if singles.isEmpty, !combinations.isEmpty {
      return "Large party — check joined tables"
    }

    return "No table yet — check table fit"
  }
}

private extension String {
  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
