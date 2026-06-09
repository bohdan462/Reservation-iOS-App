//
//  ArrivalFlowBucket.swift
//  Tryzub Reservations
//
//  15-minute arrival windows for the Home arrival flow chart.
//

import Foundation

struct ArrivalFlowBucket: Identifiable, Equatable {
  let id: String
  let bucketStart: Date
  let displayTime: String
  let axisLabel: String
  let guestCount: Int
  let reservationCount: Int
  let largePartyCount: Int
  let noTableCount: Int
  let needsReviewCount: Int
  let isPeak: Bool
  let isNextArrival: Bool

  var hasArrivals: Bool {
    guestCount > 0
  }
}

enum ArrivalFlowBucketBuilder {

  private static let bucketMinutes = 15

  static func build(
    from reservations: [ReservationRecord],
    selectedDate: Date,
    serviceOpen: Date?,
    serviceClose: Date?,
    nextArrivalBucketStart: Date? = nil,
    largePartyThreshold: Int = 7,
    calendar: Calendar = .current
  ) -> [ArrivalFlowBucket] {
    let active = reservations.filter { $0.isExpectedGuest && !$0.isHidden }
    guard let range = resolveBucketRange(
      reservations: active,
      selectedDate: selectedDate,
      serviceOpen: serviceOpen,
      serviceClose: serviceClose,
      calendar: calendar
    ) else {
      return []
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

    let guestCounts = bucketStarts.map { start in
      (bucketReservations[start] ?? []).reduce(0) { $0 + $1.partySize }
    }
    let peakGuestCount = guestCounts.max() ?? 0

    return bucketStarts.enumerated().map { index, bucketStart in
      let reservationsInBucket = bucketReservations[bucketStart] ?? []
      let guests = guestCounts[index]
      return ArrivalFlowBucket(
        id: "\(bucketStart.timeIntervalSince1970)",
        bucketStart: bucketStart,
        displayTime: displayTime(for: bucketStart, calendar: calendar),
        axisLabel: axisLabel(for: bucketStart, calendar: calendar),
        guestCount: guests,
        reservationCount: reservationsInBucket.count,
        largePartyCount: reservationsInBucket.filter { $0.partySize >= largePartyThreshold }.count,
        noTableCount: reservationsInBucket.filter { !$0.hasTableAssignment }.count,
        needsReviewCount: reservationsInBucket.filter { $0.statusValue == .needsReview || $0.statusValue == .new }.count,
        isPeak: guests > 0 && guests == peakGuestCount,
        isNextArrival: nextArrivalBucketStart == bucketStart
      )
    }
  }

  static func peakBucket(in buckets: [ArrivalFlowBucket]) -> ArrivalFlowBucket? {
    buckets.first(where: { $0.isPeak && $0.hasArrivals })
  }

  static func selectedHeadline(for bucket: ArrivalFlowBucket) -> String {
    let guestLabel = bucket.guestCount == 1 ? "1 guest" : "\(bucket.guestCount) guests"
    return "\(bucket.displayTime) · \(guestLabel)"
  }

  static func selectedSummary(for bucket: ArrivalFlowBucket) -> (headline: String, detail: String?) {
    let headline = selectedHeadline(for: bucket)
    guard bucket.hasArrivals else {
      return (headline, nil)
    }

    if bucket.guestCount <= 2,
       bucket.noTableCount == 0,
       bucket.largePartyCount == 0,
       bucket.needsReviewCount == 0 {
      return (headline, "Light arrival window")
    }

    if bucket.largePartyCount == 1,
       bucket.reservationCount == 1,
       bucket.noTableCount == 0 {
      return (headline, "1 large party · check table plan")
    }

    var detailParts: [String] = []
    let reservationLabel = bucket.reservationCount == 1
      ? "1 reservation"
      : "\(bucket.reservationCount) reservations"
    detailParts.append(reservationLabel)

    if bucket.noTableCount == 1 {
      detailParts.append("1 still needs a table")
    } else if bucket.noTableCount > 1 {
      detailParts.append("\(bucket.noTableCount) still need tables")
    }

    if bucket.largePartyCount == 1 {
      detailParts.append("1 large party · check table plan")
    } else if bucket.largePartyCount > 1 {
      detailParts.append("\(bucket.largePartyCount) large parties · check table plan")
    } else if bucket.needsReviewCount > 0 {
      detailParts.append("needs attention")
    }

    return (headline, detailParts.joined(separator: " · "))
  }

  static func accessibilityLabel(for bucket: ArrivalFlowBucket) -> String {
    var parts = [
      bucket.displayTime,
      bucket.guestCount == 1 ? "1 guest" : "\(bucket.guestCount) guests",
      bucket.reservationCount == 1 ? "1 reservation" : "\(bucket.reservationCount) reservations"
    ]
    if bucket.isPeak {
      parts.insert("Peak arrival time", at: 0)
    }
    if bucket.noTableCount > 0 {
      parts.append(bucket.noTableCount == 1 ? "1 without table" : "\(bucket.noTableCount) without tables")
    }
    if bucket.largePartyCount > 0 {
      parts.append(bucket.largePartyCount == 1 ? "1 large party" : "\(bucket.largePartyCount) large parties")
    }
    return parts.joined(separator: ", ")
  }

  // MARK: - Bucket time helpers (shared with density utilities)

  static func bucketStart(for reservation: ReservationRecord, calendar: Calendar = .current) -> Date? {
    guard let serviceDate = reservation.serviceDateTime else { return nil }
    return floorToBucketStart(serviceDate, calendar: calendar)
  }

  static func bucketStart(for date: Date, calendar: Calendar = .current) -> Date {
    floorToBucketStart(date, calendar: calendar)
  }

  // MARK: - Private

  private static func displayTime(for date: Date, calendar: Calendar) -> String {
    ReservationFormatters.shortTime.string(from: date)
  }

  private static func axisLabel(for date: Date, calendar: Calendar) -> String {
    let hour = calendar.component(.hour, from: date)
    let minute = calendar.component(.minute, from: date)
    if minute == 0 {
      return String(format: "%02d:00", hour)
    }
    return String(format: "%02d:%02d", hour, minute)
  }

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
      return extendRangeIfNeeded(
        lower: lower,
        upper: upper,
        reservations: reservations,
        calendar: calendar
      )
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
      if bucket < rangeLower {
        rangeLower = bucket
      }
      if bucket > rangeUpper {
        rangeUpper = bucket
      }
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
}
