//
//  NewBookingsIntelligenceCard.swift
//  Tryzub Reservations
//
//  Compact deterministic booking safety summary for the Bookings → New tab.
//

import SwiftUI

struct NewBookingsIntelligenceSummary: Equatable {
  let totalPendingCount: Int
  let noTableCount: Int
  let summaryLine: String
  let returningGuestLine: String?
  let tableFitLine: String?

  static func build(
    from reservations: [ReservationRecord],
    historyPool: [ReservationRecord],
    tableConfigs: [RestaurantTableConfig] = []
  ) -> NewBookingsIntelligenceSummary {
    let pending = reservations.filter {
      $0.statusValue == .new || $0.statusValue == .needsReview
    }
    let noTableCount = pending.filter { !$0.hasTableAssignment }.count
    let returningCount = returningGuestCount(pending: pending, historyPool: historyPool)
    let tableFitCount = NewBookingRowInsightBuilder.countSpecificTableFits(
      pending: pending,
      tableConfigs: tableConfigs
    )

    guard !pending.isEmpty else {
      return NewBookingsIntelligenceSummary(
        totalPendingCount: 0,
        noTableCount: 0,
        summaryLine: "No new reservations waiting right now.",
        returningGuestLine: nil,
        tableFitLine: nil
      )
    }

    var summaryParts = ["\(pending.count) waiting"]
    if noTableCount > 0 {
      summaryParts.append("\(noTableCount) need tables")
    }
    let summaryLine = summaryParts.joined(separator: " · ")

    return NewBookingsIntelligenceSummary(
      totalPendingCount: pending.count,
      noTableCount: noTableCount,
      summaryLine: summaryLine,
      returningGuestLine: returningGuestLine(count: returningCount),
      tableFitLine: tableFitLine(count: tableFitCount)
    )
  }

  private static func returningGuestCount(
    pending: [ReservationRecord],
    historyPool: [ReservationRecord]
  ) -> Int {
    let analyzer = GuestInsightsController()
    return pending.filter { reservation in
      let report = analyzer.analyze(selected: reservation, allReservations: historyPool)
      return report.hasReliableRepeatGuestHistory
    }.count
  }

  private static func returningGuestLine(count: Int) -> String? {
    guard count > 0 else { return nil }
    if count == 1 {
      return "1 returning guest in this queue"
    }
    return "\(count) returning guests in this queue"
  }

  private static func tableFitLine(count: Int) -> String? {
    guard count > 0 else { return nil }
    if count == 1 {
      return "1 party needs table planning"
    }
    return "\(count) parties need table planning"
  }
}

struct NewBookingsIntelligenceCard: View {
  let summary: NewBookingsIntelligenceSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("New booking review")
        .font(.subheadline.weight(.semibold))

      Text(summary.summaryLine)
        .font(.caption)
        .foregroundStyle(.secondary)

      if let returningGuestLine = summary.returningGuestLine {
        Text(returningGuestLine)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let tableFitLine = summary.tableFitLine {
        Text(tableFitLine)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}
