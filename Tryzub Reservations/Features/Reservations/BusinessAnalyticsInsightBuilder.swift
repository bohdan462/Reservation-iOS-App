//
//  BusinessAnalyticsInsightBuilder.swift
//  Tryzub Reservations
//
//  Deterministic interpretation lines for backend aggregate analytics.
//

import Foundation

enum BusinessAnalyticsInsightBuilder {

  static func build(from summary: ReservationAnalyticsSummaryDTO) -> [String] {
    var lines: [String] = []

    if let metrics = summary.summary, metrics.reservationsCount > 0 {
      lines.append(
        "\(metrics.reservationsCount) direct reservations brought \(metrics.guestsCount) guests."
      )

      if let avgPartySize = metrics.avgPartySize, avgPartySize > 0 {
        lines.append(
          "Average party size is \(formattedAverage(avgPartySize)) guests."
        )
      }
    }

    if let peakHour = summary.byHour.max(by: { lhs, rhs in
      if lhs.reservationsCount == rhs.reservationsCount {
        return lhs.guestsCount < rhs.guestsCount
      }
      return lhs.reservationsCount < rhs.reservationsCount
    }), peakHour.reservationsCount > 0 {
      lines.append(
        "\(displayHour(peakHour.hour)) is the strongest booking hour with \(peakHour.reservationsCount) reservations and \(peakHour.guestsCount) guests."
      )

      if let pressureWindow = peakPressureWindow(from: summary.byHour) {
        lines.append(pressureWindow)
      }
    }

    let waitingCount = statusCount(in: summary.byStatus, statuses: ["new", "needs_review"])
    if waitingCount > 0 {
      let label = waitingCount == 1 ? "reservation is" : "reservations are"
      lines.append("\(waitingCount) new \(label) waiting for staff review.")
    }

    if let pipeline = summary.pipelineHealth,
       pipeline.flamingoInboundTotal > 0 {
      lines.append(
        "Pipeline captured \(pipeline.managedRowsWithSourceSubmissionId) of \(pipeline.flamingoInboundTotal) submissions."
      )
    }

    return Array(lines.prefix(6))
  }

  // MARK: - Private

  private static func statusCount(
    in rows: [ReservationAnalyticsStatusRowDTO],
    statuses: Set<String>
  ) -> Int {
    rows.filter { statuses.contains($0.status.lowercased()) }
      .reduce(0) { $0 + $1.reservationsCount }
  }

  private static func peakPressureWindow(from rows: [ReservationAnalyticsHourRowDTO]) -> String? {
    guard let peak = rows.max(by: { $0.reservationsCount < $1.reservationsCount }),
          peak.reservationsCount > 0,
          let peakHour = hourValue(from: peak.hour) else {
      return nil
    }

    let neighborHours = rows.compactMap { row -> (Int, ReservationAnalyticsHourRowDTO)? in
      guard let hour = hourValue(from: row.hour) else { return nil }
      return (hour, row)
    }
    .filter { abs($0.0 - peakHour) <= 1 }
    .map(\.1)

    guard neighborHours.count >= 2 else { return nil }

    let hours = neighborHours.compactMap { hourValue(from: $0.hour) }.sorted()
    guard let start = hours.first, let end = hours.last, end > start else { return nil }

    return "\(displayHourValue(start))–\(displayHourValue(end)) is the main pressure window."
  }

  private static func formattedAverage(_ value: Double) -> String {
    String(format: "%.2f", value)
  }

  private static func displayHour(_ value: String) -> String {
    hourValue(from: value).map(displayHourValue) ?? value
  }

  private static func hourValue(from value: String) -> Int? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if let hour = Int(trimmed.prefix(2)) {
      return hour
    }
    return nil
  }

  private static func displayHourValue(_ hour: Int) -> String {
    let normalized = (hour % 24 + 24) % 24
    let adjusted = normalized % 12 == 0 ? 12 : normalized % 12
    let suffix = normalized < 12 ? "AM" : "PM"
    return "\(adjusted) \(suffix)"
  }
}
