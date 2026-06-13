//
//  ArrivalPressureEngine.swift
//  Tryzub Reservations
//
//  Deterministic 15-minute arrival-pressure computation. Shared by the Host
//  summary chart and the manager narrative packet.
//

import Foundation

enum ArrivalPressureEngine {

  private static let bucketMinutes = 15

  // MARK: - Build

  static func build(
    from reservations: [ReservationRecord],
    selectedDate: Date,
    serviceOpen: Date?,
    serviceClose: Date?,
    now: Date = Date(),
    largePartyThreshold: Int = 7,
    returningGuestReservationIDs: Set<Int> = [],
    calendar: Calendar = .current
  ) -> ArrivalPressureSummary {
    let active = reservations.filter { $0.isExpectedGuest && !$0.isHidden }
    let isToday = selectedDate.reservationDateString() == Date.reservationDateString()

    guard let range = resolveBucketRange(
      reservations: active,
      selectedDate: selectedDate,
      serviceOpen: serviceOpen,
      serviceClose: serviceClose,
      calendar: calendar
    ) else {
      return emptySummary(isToday: isToday)
    }

    var bucketStarts: [Date] = []
    var bucketReservations: [Date: [ReservationRecord]] = [:]
    var cursor = range.lowerBound
    while cursor <= range.upperBound {
      bucketStarts.append(cursor)
      bucketReservations[cursor] = []
      guard let next = calendar.date(byAdding: .minute, value: bucketMinutes, to: cursor) else { break }
      cursor = next
    }

    for reservation in active {
      guard let serviceDate = reservation.serviceDateTime else { continue }
      let bucket = floorToBucketStart(serviceDate, calendar: calendar)
      guard bucketReservations[bucket] != nil else { continue }
      bucketReservations[bucket, default: []].append(reservation)
    }

    // Pass 1: raw scores without adjacent weight
    var rawScores: [Double] = []
    rawScores.reserveCapacity(bucketStarts.count)

    for bucketStart in bucketStarts {
      let items = bucketReservations[bucketStart] ?? []
      rawScores.append(rawScore(
        reservationCount: items.count,
        guestCount: items.reduce(0) { $0 + $1.partySize },
        largePartyCount: items.filter { $0.partySize >= largePartyThreshold }.count,
        noTableCount: items.filter { !$0.hasTableAssignment }.count,
        needsReviewCount: items.filter {
          $0.statusValue == .needsReview || $0.statusValue == .new
        }.count
      ))
    }

    // Pass 2: add adjacent stacking
    var finalScores: [Double] = []
    for index in rawScores.indices {
      let prev = index > 0 ? rawScores[index - 1] : 0
      let next = index < rawScores.count - 1 ? rawScores[index + 1] : 0
      finalScores.append(rawScores[index] + prev * 0.35 + next * 0.35)
    }

    let maxScore = max(finalScores.max() ?? 1, 1)
    let peakIndex = finalScores.enumerated().max(by: { $0.element < $1.element })?.offset

    let nextReservation = ReservationRecord.nextExpectedArrivalReservation(
      from: reservations,
      selectedDate: selectedDate,
      now: now
    )
    let nextBucketStart = nextReservation.flatMap {
      ArrivalFlowBucketBuilder.bucketStart(for: $0, calendar: calendar)
    }

    var buckets: [ArrivalPressureBucket] = []
    buckets.reserveCapacity(bucketStarts.count)

    for (index, bucketStart) in bucketStarts.enumerated() {
      let endTime = calendar.date(byAdding: .minute, value: bucketMinutes, to: bucketStart) ?? bucketStart
      let items = bucketReservations[bucketStart] ?? []
      let guestCount = items.reduce(0) { $0 + $1.partySize }
      let reservationItems = items.map {
        ArrivalPressureReservationItem(
          reservation: $0,
          isReturningGuest: returningGuestReservationIDs.contains($0.remoteID)
        )
      }

      buckets.append(ArrivalPressureBucket(
        id: "\(bucketStart.timeIntervalSince1970)",
        startTime: bucketStart,
        endTime: endTime,
        displayTime: displayTime(for: bucketStart, calendar: calendar),
        axisLabel: axisLabel(for: bucketStart, calendar: calendar),
        reservationCount: items.count,
        guestCount: guestCount,
        largePartyCount: items.filter { $0.partySize >= largePartyThreshold }.count,
        noTableCount: items.filter { !$0.hasTableAssignment }.count,
        needsReviewCount: items.filter {
          $0.statusValue == .needsReview || $0.statusValue == .new
        }.count,
        noteSignalCount: items.filter(\.hasGuestNotes).count,
        returningGuestCount: items.filter { returningGuestReservationIDs.contains($0.remoteID) }.count,
        pressureScore: finalScores[index],
        normalizedPressure: finalScores[index] / maxScore,
        items: reservationItems,
        isPeak: index == peakIndex && guestCount > 0,
        isNextArrival: nextBucketStart == bucketStart,
        isPast: isToday && endTime < now
      ))
    }

    let peakBucket = buckets.first(where: { $0.isPeak && $0.hasArrivals })
    let nextBucket = buckets.first(where: { $0.isNextArrival && $0.hasArrivals })
      ?? buckets.first(where: { $0.hasArrivals && (!$0.isPast || !isToday) })

    let nextWaveStart = detectNextWaveStart(buckets: buckets, now: now, isToday: isToday)
    let pressureLevel = classifyPressureLevel(buckets: buckets, peakBucket: peakBucket)
    let timeRelation = currentTimeRelation(
      buckets: buckets,
      peakBucket: peakBucket,
      now: now,
      isToday: isToday
    )

    let managerFacts = buildManagerFacts(
      peakBucket: peakBucket,
      nextWaveStart: nextWaveStart,
      pressureLevel: pressureLevel,
      timeRelation: timeRelation
    )

    let chartCopy = buildChartCopy(
      peakBucket: peakBucket,
      nextBucket: nextBucket,
      nextWaveStart: nextWaveStart,
      pressureLevel: pressureLevel,
      buckets: buckets,
      isToday: isToday,
      now: now
    )

    return ArrivalPressureSummary(
      buckets: buckets,
      peakBucket: peakBucket,
      nextBucket: nextBucket,
      nextWaveStart: nextWaveStart,
      pressureLevel: pressureLevel,
      currentTimeRelation: timeRelation,
      managerFacts: managerFacts,
      chartHeadline: chartCopy.headline,
      chartSubtitle: chartCopy.subtitle,
      peakLegendText: chartCopy.peakLegend,
      nextLegendText: chartCopy.nextLegend
    )
  }

  // MARK: - Pressure Formula

  private static func rawScore(
    reservationCount: Int,
    guestCount: Int,
    largePartyCount: Int,
    noTableCount: Int,
    needsReviewCount: Int
  ) -> Double {
    let base = Double(reservationCount)
    let guestWeight = Double(guestCount) / 4.0
    let largePartyWeight = Double(largePartyCount) * 1.25
    let noTableWeight = Double(noTableCount) * 1.5
    let needsReviewWeight = Double(needsReviewCount) * 1.0
    return base + guestWeight + largePartyWeight + noTableWeight + needsReviewWeight
  }

  // MARK: - Wave Detection

  private static func detectNextWaveStart(
    buckets: [ArrivalPressureBucket],
    now: Date,
    isToday: Bool
  ) -> Date? {
    let upcoming = buckets.filter { bucket in
      guard bucket.hasArrivals else { return false }
      if isToday { return bucket.endTime >= now }
      return true
    }
    guard let first = upcoming.first else { return nil }

    // Group adjacent busy buckets (within 30 min) into waves
    var waveStart = first.startTime
    var waveBuckets: [ArrivalPressureBucket] = [first]

    for bucket in upcoming.dropFirst() {
      if let last = waveBuckets.last,
         bucket.startTime.timeIntervalSince(last.endTime) <= 15 * 60 {
        waveBuckets.append(bucket)
      } else {
        break
      }
    }

    if waveBuckets.count >= 2 || (waveBuckets.first?.guestCount ?? 0) >= 4 {
      return waveStart
    }

    // Single busy bucket — still a wave if pressure is meaningful
    if let solo = waveBuckets.first, solo.guestCount >= 3 || solo.reservationCount >= 2 {
      return solo.startTime
    }

    return first.startTime
  }

  private static func classifyPressureLevel(
    buckets: [ArrivalPressureBucket],
    peakBucket: ArrivalPressureBucket?
  ) -> ArrivalPressureLevel {
    guard let peak = peakBucket else { return .calm }
    let peakGuests = peak.guestCount
    let peakReservations = peak.reservationCount

    if peakGuests >= 12 || peakReservations >= 4 || peak.noTableCount >= 3 {
      return .heavy
    }
    if peakGuests >= 8 || peakReservations >= 3 || peak.noTableCount >= 2 {
      return .busy
    }
    if peakGuests >= 4 || peakReservations >= 2 {
      return .building
    }
    return .calm
  }

  private static func currentTimeRelation(
    buckets: [ArrivalPressureBucket],
    peakBucket: ArrivalPressureBucket?,
    now: Date,
    isToday: Bool
  ) -> ArrivalCurrentTimeRelation {
    guard isToday else { return .beforeService }
    guard let peak = peakBucket else { return .beforeService }

    if now < peak.startTime {
      let hasUpcoming = buckets.contains { $0.hasArrivals && $0.startTime > now && $0.startTime < peak.startTime }
      return hasUpcoming ? .beforeWave : .beforeService
    }
    if now >= peak.startTime && now <= peak.endTime.addingTimeInterval(30 * 60) {
      return .duringWave
    }
    return .afterPeak
  }

  // MARK: - Manager Facts

  private static func buildManagerFacts(
    peakBucket: ArrivalPressureBucket?,
    nextWaveStart: Date?,
    pressureLevel: ArrivalPressureLevel,
    timeRelation: ArrivalCurrentTimeRelation
  ) -> ArrivalPressureManagerFacts {
    let peakWindow = peakBucket?.windowLabel
    let nextWave = nextWaveStart.map { ReservationFormatters.shortTime.string(from: $0) }

    let summaryLine: String = {
      guard let peak = peakBucket else {
        return "Service pressure is calm with no meaningful arrival wave."
      }
      var parts: [String] = []
      let resLabel = peak.reservationCount == 1 ? "1 reservation" : "\(peak.reservationCount) reservations"
      let guestLabel = peak.guestCount == 1 ? "1 guest" : "\(peak.guestCount) guests"
      parts.append("Peak around \(peak.displayTime) with \(resLabel) / \(guestLabel)")
      if peak.noTableCount > 0 {
        parts.append("\(peak.noTableCount) still need tables in the peak window")
      }
      if let next = nextWave, next != peak.displayTime {
        parts.append("next wave starts \(next)")
      }
      return parts.joined(separator: "; ")
    }()

    return ArrivalPressureManagerFacts(
      peakWindow: peakWindow,
      peakReservationCount: peakBucket?.reservationCount ?? 0,
      peakGuestCount: peakBucket?.guestCount ?? 0,
      nextWaveStart: nextWave,
      pressureLevel: pressureLevel.displayName,
      noTableInPeakCount: peakBucket?.noTableCount ?? 0,
      largePartyInPeakCount: peakBucket?.largePartyCount ?? 0,
      noteSignalsInPeak: peakBucket?.noteSignalCount ?? 0,
      returningGuestSignalsInPeak: peakBucket?.returningGuestCount ?? 0,
      currentTimeRelation: timeRelation.rawValue,
      pressureSummaryLine: summaryLine
    )
  }

  // MARK: - Chart Copy

  private static func buildChartCopy(
    peakBucket: ArrivalPressureBucket?,
    nextBucket: ArrivalPressureBucket?,
    nextWaveStart: Date?,
    pressureLevel: ArrivalPressureLevel,
    buckets: [ArrivalPressureBucket],
    isToday: Bool,
    now: Date
  ) -> (headline: String, subtitle: String, peakLegend: String, nextLegend: String?) {
    guard let peak = peakBucket else {
      return (
        "No arrival pressure on this day",
        "Tap a wave to see who is coming.",
        "—",
        nil
      )
    }

    let resLabel = peak.reservationCount == 1 ? "1 reservation" : "\(peak.reservationCount) reservations"
    let guestLabel = peak.guestCount == 1 ? "1 guest" : "\(peak.guestCount) guests"
    let headline = "Peak around \(peak.displayTime) · \(resLabel) / \(guestLabel)"

    var subtitleParts: [String] = []
    if let waveStart = nextWaveStart {
      let waveTime = ReservationFormatters.shortTime.string(from: waveStart)
      if waveTime != peak.displayTime {
        subtitleParts.append("Next wave starts \(waveTime)")
      }
    }

    if peak.noTableCount > 0 {
      subtitleParts.append("No-table pressure inside the \(peak.displayTime) wave")
    } else if pressureLevel == .calm {
      let upcoming = buckets.filter { $0.hasArrivals && (!$0.isPast || !isToday) }
      if let first = upcoming.first, isToday, first.startTime > now {
        let quietUntil = ReservationFormatters.shortTime.string(from: first.startTime)
        subtitleParts.insert("Quiet until \(quietUntil), then pressure builds", at: 0)
      }
    }

    if subtitleParts.isEmpty {
      subtitleParts.append("Tap a wave to see who is coming.")
    }

    let peakLegend = "\(peak.displayTime) · \(guestLabel)"
    let nextLegend: String? = {
      guard let next = nextBucket, next.hasArrivals else { return nil }
      let label = next.guestCount == 1 ? "1 guest" : "\(next.guestCount) guests"
      if isToday, next.startTime >= now {
        let minutes = Int(ceil(next.startTime.timeIntervalSince(now) / 60))
        if minutes <= 5 { return "\(next.displayTime) · soon" }
        if minutes < 60 { return "\(next.displayTime) · in \(minutes)m" }
        let hours = minutes / 60
        let rem = minutes % 60
        return "\(next.displayTime) · in \(hours)h \(rem)m"
      }
      return "\(next.displayTime) · \(label)"
    }()

    return (headline, subtitleParts.joined(separator: " · "), peakLegend, nextLegend)
  }

  // MARK: - Empty

  private static func emptySummary(isToday: Bool) -> ArrivalPressureSummary {
    let facts = ArrivalPressureManagerFacts(
      peakWindow: nil,
      peakReservationCount: 0,
      peakGuestCount: 0,
      nextWaveStart: nil,
      pressureLevel: ArrivalPressureLevel.calm.displayName,
      noTableInPeakCount: 0,
      largePartyInPeakCount: 0,
      noteSignalsInPeak: 0,
      returningGuestSignalsInPeak: 0,
      currentTimeRelation: isToday ? ArrivalCurrentTimeRelation.beforeService.rawValue : ArrivalCurrentTimeRelation.beforeService.rawValue,
      pressureSummaryLine: "No arrival pressure on this day."
    )
    return ArrivalPressureSummary(
      buckets: [],
      peakBucket: nil,
      nextBucket: nil,
      nextWaveStart: nil,
      pressureLevel: .calm,
      currentTimeRelation: .beforeService,
      managerFacts: facts,
      chartHeadline: "No arrival pressure on this day",
      chartSubtitle: "Tap a wave to see who is coming.",
      peakLegendText: "—",
      nextLegendText: nil
    )
  }

  // MARK: - Range Helpers (shared with ArrivalFlowBucketBuilder)

  private static func resolveBucketRange(
    reservations: [ReservationRecord],
    selectedDate: Date,
    serviceOpen: Date?,
    serviceClose: Date?,
    calendar: Calendar
  ) -> ClosedRange<Date>? {
    if let serviceOpen, let serviceClose, serviceOpen <= serviceClose {
      let lower = floorToBucketStart(serviceOpen, calendar: calendar)
      let upper = floorToBucketStart(serviceClose, calendar: calendar)
      return extendRangeIfNeeded(lower: lower, upper: upper, reservations: reservations, calendar: calendar)
    }

    let serviceDates = reservations.compactMap(\.serviceDateTime)
    guard let earliest = serviceDates.min(), let latest = serviceDates.max() else {
      return nil
    }

    let paddedLower = calendar.date(byAdding: .hour, value: -1, to: earliest) ?? earliest
    let paddedUpper = calendar.date(byAdding: .hour, value: 1, to: latest) ?? latest
    let lower = floorToBucketStart(paddedLower, calendar: calendar)
    let upper = floorToBucketStart(paddedUpper, calendar: calendar)
    return lower...max(lower, upper)
  }

  private static func extendRangeIfNeeded(
    lower: Date,
    upper: Date,
    reservations: [ReservationRecord],
    calendar: Calendar
  ) -> ClosedRange<Date> {
    var rangeLower = lower
    var rangeUpper = upper
    for reservation in reservations {
      guard let serviceDate = reservation.serviceDateTime else { continue }
      let bucket = floorToBucketStart(serviceDate, calendar: calendar)
      if bucket < rangeLower { rangeLower = bucket }
      if bucket > rangeUpper { rangeUpper = bucket }
    }
    return rangeLower...rangeUpper
  }

  private static func floorToBucketStart(_ date: Date, calendar: Calendar) -> Date {
    var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    let minute = components.minute ?? 0
    components.minute = (minute / bucketMinutes) * bucketMinutes
    components.second = 0
    components.nanosecond = 0
    return calendar.date(from: components) ?? date
  }

  private static func displayTime(for date: Date, calendar: Calendar) -> String {
    ReservationFormatters.shortTime.string(from: date)
  }

  private static func axisLabel(for date: Date, calendar: Calendar) -> String {
    let hour = calendar.component(.hour, from: date)
    let minute = calendar.component(.minute, from: date)
    guard minute == 0 else { return "" }
    return String(format: "%02d:00", hour)
  }
}
