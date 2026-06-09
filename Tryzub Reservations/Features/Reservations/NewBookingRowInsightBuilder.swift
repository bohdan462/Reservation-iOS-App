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
      report: report
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
      return possibleDuplicateLine(report: report, reservation: reservation) != nil
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
    report: GuestInsightReport
  ) -> String? {
    if let duplicateLine = possibleDuplicateLine(report: report, reservation: reservation) {
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
    reservation: ReservationRecord
  ) -> String? {
    if report.collapsedDuplicateReservationCount > 0 {
      return "Possible duplicate — compare details"
    }

    let staffNotes = (reservation.staffNotes ?? "").lowercased()
    if staffNotes.contains("possible duplicate") || staffNotes.contains("correction") {
      return "Possible duplicate — compare details"
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
