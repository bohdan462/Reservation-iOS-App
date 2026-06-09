//
//  HostAnalyticsIntelligenceSupport.swift
//  Tryzub Reservations
//
//  Compares live slot pressure with historical reservation analytics patterns.
//  Advisory only — deterministic engine remains authoritative.
//

import Foundation

struct HostAnalyticsMetrics {
  let hasAnalytics: Bool
  let unusuallyBusySlotCount: Int
  let unusuallyLightSlotCount: Int
  let weekdayPressureSignalCount: Int
  let confidence: Double
}

struct HostAnalyticsIntelligenceResult {
  let facts: [HostBriefingFact]
  let actions: [HostSuggestedAction]
  let metrics: HostAnalyticsMetrics
}

enum HostAnalyticsIntelligenceSupport {

  private static let busyRatioWatch = 1.25
  private static let busyRatioWarning = 1.5
  private static let busyRatioCritical = 2.0
  private static let lightRatioThreshold = 0.65
  private static let minLiveGuestsForBusySignal = 8
  private static let maxBusyHourFacts = 3
  private static let maxLightHourFacts = 2

  // MARK: - Public

  static func analyze(
    slotPressures: [HostSlotPressure],
    analyticsSummary: ReservationAnalyticsSummaryDTO?,
    selectedDate: Date,
    now: Date,
    settings: HostIntelligenceSettings
  ) -> HostAnalyticsIntelligenceResult {
    guard settings.includeAnalyticsSignals else {
      return emptyResult
    }

    let confidence = calculateConfidence(analyticsSummary: analyticsSummary)
  let liveHourGuests = calculateLiveHourCounts(from: slotPressures)

    guard let analyticsSummary else {
      return HostAnalyticsIntelligenceResult(
        facts: [],
        actions: [],
        metrics: HostAnalyticsMetrics(
          hasAnalytics: false,
          unusuallyBusySlotCount: 0,
          unusuallyLightSlotCount: 0,
          weekdayPressureSignalCount: 0,
          confidence: confidence
        )
      )
    }

    let historicalHours = normalizeHistoricalHourCounts(from: analyticsSummary)
    let historicalWeekdays = normalizeHistoricalWeekdayCounts(from: analyticsSummary)
    let daysInRange = estimateDaysInRange(analyticsSummary.range) ?? 30

    var facts: [HostBriefingFact] = []

    facts.append(contentsOf: detectUnusuallyBusyHours(
      liveHourGuests: liveHourGuests,
      historicalHourGuests: historicalHours,
      daysInRange: daysInRange,
      slotPressures: slotPressures,
      confidence: confidence
    ))

    facts.append(contentsOf: detectUnusuallyLightHours(
      liveHourGuests: liveHourGuests,
      historicalHourGuests: historicalHours,
      daysInRange: daysInRange,
      selectedDate: selectedDate,
      now: now,
      confidence: confidence
    ))

    if let weekdayFact = detectWeekdayPressure(
      slotPressures: slotPressures,
      historicalWeekdayGuests: historicalWeekdays,
      daysInRange: daysInRange,
      selectedDate: selectedDate,
      confidence: confidence
    ) {
      facts.append(weekdayFact)
    }

    let busyCount = facts.filter { $0.id.hasPrefix("analytics-busy-hour-") }.count
    let lightCount = facts.filter { $0.id.hasPrefix("analytics-light-hour-") }.count
    let weekdayCount = facts.filter { $0.id.hasPrefix("analytics-weekday-") }.count

    return HostAnalyticsIntelligenceResult(
      facts: facts,
      actions: [],
      metrics: HostAnalyticsMetrics(
        hasAnalytics: true,
        unusuallyBusySlotCount: busyCount,
        unusuallyLightSlotCount: lightCount,
        weekdayPressureSignalCount: weekdayCount,
        confidence: confidence
      )
    )
  }

  // MARK: - Normalization

  static func normalizeHistoricalHourCounts(
    from summary: ReservationAnalyticsSummaryDTO
  ) -> [Int: Int] {
    var counts: [Int: Int] = [:]
    for row in summary.byHour {
      guard let hour = parseHourLabel(row.hour) else { continue }
      let value = row.guestsCount > 0 ? row.guestsCount : row.reservationsCount
      guard value > 0 else { continue }
      counts[hour, default: 0] += value
    }
    return counts
  }

  static func normalizeHistoricalWeekdayCounts(
    from summary: ReservationAnalyticsSummaryDTO
  ) -> [Int: Int] {
    var counts: [Int: Int] = [:]
    for row in summary.byWeekday {
      guard let weekday = normalizeWeekday(row.weekday, label: row.label) else { continue }
      let value = row.guestsCount > 0 ? row.guestsCount : row.reservationsCount
      guard value > 0 else { continue }
      counts[weekday, default: 0] += value
    }
    return counts
  }

  private static func calculateLiveHourCounts(
    from slotPressures: [HostSlotPressure]
  ) -> [Int: LiveHourCounts] {
    var counts: [Int: LiveHourCounts] = [:]
    for pressure in slotPressures where pressure.reservationCount > 0 || pressure.guestCount > 0 {
      guard let hour = parseHourLabel(pressure.slotTime) else { continue }
      var entry = counts[hour] ?? LiveHourCounts(guestCount: 0, reservationCount: 0)
      entry.guestCount += pressure.guestCount
      entry.reservationCount += pressure.reservationCount
      counts[hour] = entry
    }
    return counts
  }

  // MARK: - Analyzers

  private static func detectUnusuallyBusyHours(
    liveHourGuests: [Int: LiveHourCounts],
    historicalHourGuests: [Int: Int],
    daysInRange: Int,
    slotPressures: [HostSlotPressure],
    confidence: Double
  ) -> [HostBriefingFact] {
    guard !historicalHourGuests.isEmpty else { return [] }

    var facts: [HostBriefingFact] = []

    let rankedHours = liveHourGuests.sorted { lhs, rhs in
      lhs.value.guestCount > rhs.value.guestCount
    }

    for (hour, live) in rankedHours {
      guard facts.count < maxBusyHourFacts else { break }
      guard live.guestCount >= minLiveGuestsForBusySignal else { continue }

      guard let historicalTotal = historicalHourGuests[hour], historicalTotal > 0 else { continue }
      let baseline = max(historicalTotal / max(daysInRange, 1), 1)
      let ratio = Double(live.guestCount) / Double(baseline)
      guard ratio >= busyRatioWatch else { continue }

      let hourLabel = displayHour(hour)
      let hasCriticalLiveSlot = slotPressures.contains { pressure in
        guard parseHourLabel(pressure.slotTime) == hour else { return false }
        return pressure.severity == .critical || pressure.severity == .busy
      }

      var severity: HostSeverity = .watch
      if ratio >= busyRatioCritical, hasCriticalLiveSlot, confidence >= 0.5 {
        severity = .critical
      } else if ratio >= busyRatioWarning {
        severity = .warning
      }

      if confidence < 0.5 {
        severity = minSeverity(severity, cap: .watch)
      }

      facts.append(
        HostBriefingFact(
          id: "analytics-busy-hour-\(hour)",
          severity: severity,
          category: .analytics,
          title: "Above usual pressure",
          detail: "\(hourLabel) is above the usual pattern for this service window.",
          evidence: [
            "liveGuests=\(live.guestCount)",
            "historicalBaseline=\(baseline)",
            String(format: "ratio=%.2f", ratio),
            "confidence=\(String(format: "%.2f", confidence))"
          ],
          relatedReservationIDs: [],
          suggestedActionTitle: "Watch arrivals and table turns around \(hourLabel)."
        )
      )
    }

    return facts
  }

  private static func detectUnusuallyLightHours(
    liveHourGuests: [Int: LiveHourCounts],
    historicalHourGuests: [Int: Int],
    daysInRange: Int,
    selectedDate: Date,
    now: Date,
    confidence: Double
  ) -> [HostBriefingFact] {
    guard !historicalHourGuests.isEmpty, confidence >= 0.5 else { return [] }

    var facts: [HostBriefingFact] = []
    let calendar = Calendar.current

    let candidateHours = historicalHourGuests.keys.sorted()
    for hour in candidateHours {
      guard facts.count < maxLightHourFacts else { break }

      let liveGuests = liveHourGuests[hour]?.guestCount ?? 0
      guard liveGuests > 0 else { continue }

      guard let historicalTotal = historicalHourGuests[hour], historicalTotal > 0 else { continue }
      let baseline = max(historicalTotal / max(daysInRange, 1), 1)
      let ratio = Double(liveGuests) / Double(baseline)
      guard ratio <= lightRatioThreshold else { continue }

      guard let slotDate = calendar.date(
        bySettingHour: hour,
        minute: 0,
        second: 0,
        of: selectedDate
      ), slotDate > now else {
        continue
      }

      let hourLabel = displayHour(hour)
      facts.append(
        HostBriefingFact(
          id: "analytics-light-hour-\(hour)",
          severity: .info,
          category: .analytics,
          title: "Lighter than usual window",
          detail: "\(hourLabel) may be a safer alternate window than the usual peak.",
          evidence: [
            "liveGuests=\(liveGuests)",
            "historicalBaseline=\(baseline)",
            String(format: "ratio=%.2f", ratio)
          ],
          relatedReservationIDs: [],
          suggestedActionTitle: nil
        )
      )
    }

    return facts
  }

  private static func detectWeekdayPressure(
    slotPressures: [HostSlotPressure],
    historicalWeekdayGuests: [Int: Int],
    daysInRange: Int,
    selectedDate: Date,
    confidence: Double
  ) -> HostBriefingFact? {
    guard confidence >= 0.5 else { return nil }

    let weekday = Calendar.current.component(.weekday, from: selectedDate)
    guard let historicalTotal = historicalWeekdayGuests[weekday], historicalTotal > 0 else {
      return nil
    }

    let weekdayOccurrences = max(estimateWeekdayOccurrences(in: daysInRange), 1)
    let baseline = max(historicalTotal / weekdayOccurrences, 1)
    let liveGuests = slotPressures.reduce(0) { $0 + $1.guestCount }
    guard liveGuests >= minLiveGuestsForBusySignal else { return nil }

    let ratio = Double(liveGuests) / Double(baseline)
    guard ratio >= busyRatioWatch else { return nil }

    let weekdayName = Calendar.current.weekdaySymbols[weekday - 1]
    var severity: HostSeverity = ratio >= busyRatioWarning ? .warning : .watch
    if confidence < 0.5 {
      severity = .info
    }

    return HostBriefingFact(
      id: "analytics-weekday-\(weekday)",
      severity: severity,
      category: .analytics,
      title: "Above usual weekday pattern",
      detail: "Tonight looks heavier than the usual \(weekdayName) pattern based on loaded historical data.",
      evidence: [
        "liveGuestsToday=\(liveGuests)",
        "weekdayBaseline=\(baseline)",
        String(format: "ratio=%.2f", ratio),
        "basedOnLoadedCache=true"
      ],
      relatedReservationIDs: [],
      suggestedActionTitle: "Plan staffing and turns with the heavier weekday trend in mind."
    )
  }

  // MARK: - Confidence

  private static func calculateConfidence(
    analyticsSummary: ReservationAnalyticsSummaryDTO?
  ) -> Double {
    guard let analyticsSummary else { return 0 }

    var confidence = 0.65
    let hourCounts = normalizeHistoricalHourCounts(from: analyticsSummary)
    let weekdayCounts = normalizeHistoricalWeekdayCounts(from: analyticsSummary)

    if !hourCounts.isEmpty {
      confidence += 0.2
    }
    if !weekdayCounts.isEmpty {
      confidence += 0.1
    }

    if let health = analyticsSummary.pipelineHealth,
       health.flamingoInboundTotal > 0 {
      let completeness = Double(health.managedRowsWithSourceSubmissionId)
        / Double(max(health.flamingoInboundTotal, 1))
      if completeness >= 0.8 {
        confidence += 0.05
      }
    }

    return min(max(confidence, 0), 0.95)
  }

  // MARK: - Helpers

  private struct LiveHourCounts {
    var guestCount: Int
    var reservationCount: Int
  }

  private static var emptyResult: HostAnalyticsIntelligenceResult {
    HostAnalyticsIntelligenceResult(
      facts: [],
      actions: [],
      metrics: HostAnalyticsMetrics(
        hasAnalytics: false,
        unusuallyBusySlotCount: 0,
        unusuallyLightSlotCount: 0,
        weekdayPressureSignalCount: 0,
        confidence: 0
      )
    )
  }

  private static func parseHourLabel(_ value: String) -> Int? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let intValue = Int(trimmed), (0...23).contains(intValue) {
      return intValue
    }

    let normalized = trimmed.count >= 5 ? String(trimmed.prefix(5)) : trimmed
    let parts = normalized.split(separator: ":")
    if let hourPart = parts.first, let hour = Int(hourPart), (0...23).contains(hour) {
      return hour
    }

    let lower = trimmed.lowercased()
    if lower.contains("pm") || lower.contains("am") {
      let digits = lower.filter(\.isNumber)
      if let hour = Int(digits), (1...12).contains(hour) {
        if lower.contains("pm"), hour < 12 { return hour + 12 }
        if lower.contains("am"), hour == 12 { return 0 }
        return hour
      }
    }

    return nil
  }

  private static func normalizeWeekday(_ weekday: Int?, label: String?) -> Int? {
    if let weekday, (1...7).contains(weekday) {
      return weekday
    }

    guard let label else { return nil }
    let lower = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let names = Calendar.current.weekdaySymbols.enumerated()
    for (index, name) in names {
      if lower.hasPrefix(name.lowercased()) {
        return index + 1
      }
    }

    let shortNames = Calendar.current.shortWeekdaySymbols.enumerated()
    for (index, name) in shortNames {
      if lower.hasPrefix(name.lowercased()) {
        return index + 1
      }
    }

    return nil
  }

  private static func estimateDaysInRange(_ range: ReservationAnalyticsRangeDTO?) -> Int? {
    guard let from = range?.from,
          let to = range?.to,
          let start = ReservationFormatters.reservationDateKey.date(from: from),
          let end = ReservationFormatters.reservationDateKey.date(from: to) else {
      return nil
    }

    let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
    return max(days + 1, 1)
  }

  private static func estimateWeekdayOccurrences(in daysInRange: Int) -> Int {
    max(daysInRange / 7, 1)
  }

  private static func displayHour(_ hour: Int) -> String {
    var components = DateComponents()
    components.hour = hour
    components.minute = 0
    let date = Calendar.current.date(from: components) ?? Date()
    return ReservationFormatters.shortTime.string(from: date)
  }

  private static func minSeverity(_ severity: HostSeverity, cap: HostSeverity) -> HostSeverity {
    severity.rank <= cap.rank ? severity : cap
  }
}
