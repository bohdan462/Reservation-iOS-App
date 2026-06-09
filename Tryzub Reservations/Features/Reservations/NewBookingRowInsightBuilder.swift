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
    if let guestLine = guestLine?.nilIfBlank {
      lines.append(guestLine)
    }
    if let tableLine = tableLine?.nilIfBlank {
      lines.append(tableLine)
    } else if let noteLine = noteLine?.nilIfBlank {
      lines.append(noteLine)
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
    let noteLine = noteInsightLine(for: reservation)

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

  // MARK: - Guest

  private static func guestInsightLine(
    report: GuestInsightReport,
    reservationID: Int
  ) -> String? {
    guard report.hasReliableRepeatGuestHistory else { return nil }

    var parts = ["Seen before"]

    let visitCount = report.summary.totalMatchedReservations
    if visitCount >= 2, let ordinal = ordinalVisitText(for: visitCount) {
      parts.append(ordinal)
    }

    if let lastVisit = lastPriorCompletedVisitDisplayDate(
      report: report,
      excludingReservationID: reservationID
    ) {
      parts.append("last \(lastVisit)")
    }

    return parts.joined(separator: " · ")
  }

  private static func lastPriorCompletedVisitDisplayDate(
    report: GuestInsightReport,
    excludingReservationID: Int
  ) -> String? {
    priorCompletedOrSeatedReservations(
      report: report,
      excludingReservationID: excludingReservationID
    )
    .sorted { lhs, rhs in
      if lhs.date == rhs.date {
        return lhs.time > rhs.time
      }
      return lhs.date > rhs.date
    }
    .first?
    .displayDate
  }

  private static func priorCompletedOrSeatedReservations(
    report: GuestInsightReport,
    excludingReservationID: Int
  ) -> [GuestMatchedReservation] {
    report.matchedReservations
      .filter { $0.reservationID != excludingReservationID }
      .filter { $0.status == .completed || $0.status == .seated }
  }

  private static func ordinalVisitText(for visitCount: Int) -> String? {
    guard visitCount >= 2 else { return nil }
    switch visitCount {
    case 2: return "2nd visit"
    case 3: return "3rd visit"
    default: return "\(visitCount)th visit"
    }
  }

  // MARK: - Notes

  private static func noteInsightLine(for reservation: ReservationRecord) -> String? {
    let notes = combinedNotes(for: reservation)
    guard !notes.isEmpty else { return nil }

    if let snippet = HostGuestNoteSnippetExtractor.allergySnippet(from: notes) {
      return "Allergy note: \(snippet)"
    }
    if let snippet = HostGuestNoteSnippetExtractor.seatingPreferenceSnippet(from: notes) {
      return "Prefers \(snippet)"
    }
    if HostGuestNoteSnippetExtractor.specialOccasionSnippet(from: notes) != nil {
      return "Occasion note present"
    }
    return nil
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
      return "May need combined table plan"
    }

    return "Needs table planning"
  }
}

private extension String {
  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
