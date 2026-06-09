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
  let priorityLines: [String]
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
    let allergyCount = NewBookingRowInsightBuilder.countAllergyNotes(pending: pending)
    let duplicateCount = NewBookingRowInsightBuilder.countPossibleDuplicates(
      pending: pending,
      historyPool: historyPool
    )
    let largePartyCount = pending.filter {
      NewBookingRowInsightBuilder.isLargePartyNeedingTablePlan(
        reservation: $0,
        tableConfigs: tableConfigs
      )
    }.count

    guard !pending.isEmpty else {
      return NewBookingsIntelligenceSummary(
        totalPendingCount: 0,
        noTableCount: 0,
        summaryLine: "No new reservations waiting right now.",
        priorityLines: [],
        returningGuestLine: nil,
        tableFitLine: nil
      )
    }

    var summaryParts: [String] = []
    if pending.count == 1 {
      summaryParts.append("1 reservation needs attention")
    } else {
      summaryParts.append("\(pending.count) reservations need attention")
    }
    if noTableCount == 1 {
      summaryParts.append("1 still needs a table")
    } else if noTableCount > 1 {
      summaryParts.append("\(noTableCount) still need tables")
    }
    let summaryLine = summaryParts.joined(separator: " · ")

    var priorityLines: [String] = []
    if allergyCount == 1 {
      priorityLines.append("1 allergy note — tell server first")
    } else if allergyCount > 1 {
      priorityLines.append("\(allergyCount) allergy notes — tell server first")
    }
    if duplicateCount == 1 {
      priorityLines.append("1 possible duplicate — compare details")
    } else if duplicateCount > 1 {
      priorityLines.append("\(duplicateCount) possible duplicates — compare details")
    }
    if largePartyCount == 1 {
      priorityLines.append("1 large party — check joined tables")
    } else if largePartyCount > 1 {
      priorityLines.append("\(largePartyCount) large parties — check joined tables")
    }

    return NewBookingsIntelligenceSummary(
      totalPendingCount: pending.count,
      noTableCount: noTableCount,
      summaryLine: summaryLine,
      priorityLines: Array(priorityLines.prefix(3)),
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
      return "1 party may need a table plan"
    }
    return "\(count) parties may need a table plan"
  }
}

struct NewBookingsIntelligenceCard: View {
  let summary: NewBookingsIntelligenceSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Needs attention")
        .font(.subheadline.weight(.semibold))

      Text(summary.summaryLine)
        .font(.caption)
        .foregroundStyle(.secondary)

      if !summary.priorityLines.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Check first")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

          ForEach(Array(summary.priorityLines.enumerated()), id: \.offset) { _, line in
            HStack(alignment: .top, spacing: 6) {
              Text("•")
                .font(.caption.weight(.bold))
              Text(line)
                .font(.caption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }

      if let returningGuestLine = summary.returningGuestLine {
        Text(returningGuestLine)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let tableFitLine = summary.tableFitLine, summary.priorityLines.isEmpty {
        Text(tableFitLine)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}
