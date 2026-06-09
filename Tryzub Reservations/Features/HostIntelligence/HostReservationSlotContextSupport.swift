//
//  HostReservationSlotContextSupport.swift
//  Tryzub Reservations
//
//  Deterministic arrival-window context for create/edit reservation forms.
//

import Foundation

struct HostReservationSlotContext: Equatable {
  let timeLabel: String
  let headline: String
  let detail: String
  let hints: [String]
  let severity: HostPressureSeverity
  let alternateTimeLabel: String?
}

enum HostReservationSlotContextSupport {

  static func build(
    serviceDate: Date,
    serviceTime: Date,
    partySize: Int,
    excludingReservationID: Int?,
    dayReservations: [ReservationRecord],
    blockedSlotValues: Set<String>,
    isServiceClosed: Bool,
    tableConfigs: [RestaurantTableConfig],
    settings: HostIntelligenceSettings,
    nearbyTimeChoices: [Date] = []
  ) -> HostReservationSlotContext? {
    guard settings.isEnabled else { return nil }
    guard partySize > 0 else { return nil }

    if isServiceClosed {
      return HostReservationSlotContext(
        timeLabel: timeLabel(for: serviceTime),
        headline: "Service closed",
        detail: "This date is not open for reservations.",
        hints: [],
        severity: .critical,
        alternateTimeLabel: nil
      )
    }

    guard let serviceDateTime = combinedServiceDateTime(serviceDate: serviceDate, time: serviceTime) else {
      return nil
    }
    let bucketStart = ReservationDensityCalculator.bucketStart(for: serviceDateTime)

    let slotTimeValue = ReservationFormatters.apiTime.string(from: serviceTime)
    let normalizedSlot = normalizedSlotTime(slotTimeValue)
    let isBlocked = blockedSlotValues.contains(normalizedSlot)

    let peers = matchingReservations(
      in: dayReservations,
      bucketStart: bucketStart,
      excludingReservationID: excludingReservationID
    )

    let guestCount = peers.reduce(0) { $0 + $1.partySize }
    let reservationCount = peers.count
    let largePartyCount = peers.filter { $0.partySize >= settings.largePartyThreshold }.count
    let noTableCount = peers.filter { $0.isOpenWork && !$0.hasTableAssignment }.count
    let projectedGuests = guestCount + partySize

    let severity = classifySeverity(
      isBlocked: isBlocked,
      reservationCount: reservationCount,
      guestCount: guestCount,
      projectedGuests: projectedGuests,
      partySize: partySize,
      largePartyCount: largePartyCount,
      settings: settings
    )

    let headline = headline(
      severity: severity,
      isBlocked: isBlocked,
      reservationCount: reservationCount,
      guestCount: guestCount
    )

    let detail = detailLine(
      reservationCount: reservationCount,
      guestCount: guestCount,
      partySize: partySize,
      projectedGuests: projectedGuests
    )

    var hints: [String] = []
    if isBlocked {
      hints.append("This slot is blocked on the service calendar.")
    }
    if largePartyCount > 0 {
      let label = largePartyCount == 1 ? "Large party" : "\(largePartyCount) large parties"
      hints.append("\(label) already in this window.")
    }
    if noTableCount > 0 {
      let label = noTableCount == 1 ? "1 booking still needs a table" : "\(noTableCount) bookings still need tables"
      hints.append(label)
    }
    if let tableHint = tablePlanningHint(
      partySize: partySize,
      tableConfigs: tableConfigs,
      settings: settings
    ) {
      hints.append(tableHint)
    }

    let alternate = suggestAlternateTime(
      serviceDate: serviceDate,
      serviceTime: serviceTime,
      nearbyTimeChoices: nearbyTimeChoices,
      dayReservations: dayReservations,
      excludingReservationID: excludingReservationID,
      settings: settings
    )
    if let alternate {
      hints.append("Quieter nearby: \(alternate)")
    }

    return HostReservationSlotContext(
      timeLabel: timeLabel(for: serviceTime),
      headline: headline,
      detail: detail,
      hints: Array(hints.prefix(3)),
      severity: severity,
      alternateTimeLabel: alternate
    )
  }

  // MARK: - Matching

  private static func matchingReservations(
    in reservations: [ReservationRecord],
    bucketStart: Date,
    excludingReservationID: Int?
  ) -> [ReservationRecord] {
    reservations.filter { reservation in
      guard reservation.isExpectedGuest else { return false }
      if let excludingReservationID, reservation.remoteID == excludingReservationID {
        return false
      }
      guard let peerBucket = ReservationDensityCalculator.bucketStart(for: reservation) else {
        return false
      }
      return peerBucket == bucketStart
    }
  }

  private static func combinedServiceDateTime(serviceDate: Date, time: Date) -> Date? {
    let dateKey = serviceDate.reservationDateString()
    let timeKey = ReservationFormatters.apiTime.string(from: time)
    if let parsed = ReservationFormatters.serverDateMinute.date(from: "\(dateKey) \(timeKey)") {
      return parsed
    }
    return ReservationFormatters.serverDateTime.date(from: "\(dateKey) \(timeKey)")
  }

  // MARK: - Copy

  private static func headline(
    severity: HostPressureSeverity,
    isBlocked: Bool,
    reservationCount: Int,
    guestCount: Int
  ) -> String {
    if isBlocked {
      return "Blocked arrival window"
    }
    switch severity {
    case .critical:
      return "High pressure at this time"
    case .busy:
      return "Busy arrival window"
    case .watch:
      return reservationCount == 0 ? "Some floor activity" : "Building at this time"
    case .calm:
      return guestCount == 0 ? "Clear arrival window" : "Light activity"
    }
  }

  private static func detailLine(
    reservationCount: Int,
    guestCount: Int,
    partySize: Int,
    projectedGuests: Int
  ) -> String {
    if reservationCount == 0 {
      return "No other arrivals in this 15-minute window. Your party of \(partySize) would be first."
    }

    let bookingLabel = reservationCount == 1 ? "1 booking" : "\(reservationCount) bookings"
    let guestLabel = guestCount == 1 ? "1 guest" : "\(guestCount) guests"
    if partySize > 0, projectedGuests > guestCount {
      return "\(bookingLabel) · \(guestLabel) already arriving · with your party, \(projectedGuests) guests"
    }
    return "\(bookingLabel) · \(guestLabel) in this window"
  }

  private static func tablePlanningHint(
    partySize: Int,
    tableConfigs: [RestaurantTableConfig],
    settings: HostIntelligenceSettings
  ) -> String? {
    guard HostTableIntelligenceSupport.shouldSurfaceNoTableFitAdvice(
      partySize: partySize,
      largePartyThreshold: settings.largePartyThreshold
    ) else {
      return nil
    }

    let activeTables = tableConfigs.filter(\.isActive)
    guard !activeTables.isEmpty else { return nil }

    let fitsSingle = activeTables.contains { $0.capacity >= partySize }
    if fitsSingle { return nil }

    let largestSeat = activeTables.map(\.capacity).max() ?? 0
    if partySize > largestSeat {
      return "Your party may need a combined table plan."
    }
    return "Table planning may be needed for this party size."
  }

  private static func suggestAlternateTime(
    serviceDate: Date,
    serviceTime: Date,
    nearbyTimeChoices: [Date],
    dayReservations: [ReservationRecord],
    excludingReservationID: Int?,
    settings: HostIntelligenceSettings
  ) -> String? {
    guard settings.suggestAlternateTimesEnabled else { return nil }
    guard nearbyTimeChoices.count > 1 else { return nil }
    guard let serviceDateTime = combinedServiceDateTime(serviceDate: serviceDate, time: serviceTime) else {
      return nil
    }
    let currentBucket = ReservationDensityCalculator.bucketStart(for: serviceDateTime)

    let currentGuests = matchingReservations(
      in: dayReservations,
      bucketStart: currentBucket,
      excludingReservationID: excludingReservationID
    ).reduce(0) { $0 + $1.partySize }

    let calendar = Calendar.current
    let scored: [(Date, Int)] = nearbyTimeChoices.compactMap { choice in
      guard !calendar.isDate(choice, equalTo: serviceTime, toGranularity: .minute) else { return nil }
      guard let choiceDateTime = combinedServiceDateTime(serviceDate: serviceDate, time: choice) else {
        return nil
      }
      let bucket = ReservationDensityCalculator.bucketStart(for: choiceDateTime)
      let guests = matchingReservations(
        in: dayReservations,
        bucketStart: bucket,
        excludingReservationID: excludingReservationID
      ).reduce(0) { $0 + $1.partySize }
      return (choice, guests)
    }
    .filter { $0.1 < currentGuests }
    .sorted { lhs, rhs in
      if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
      return abs(lhs.0.timeIntervalSince(serviceTime)) < abs(rhs.0.timeIntervalSince(serviceTime))
    }

    guard let best = scored.first else { return nil }
    return timeLabel(for: best.0)
  }

  private static func classifySeverity(
    isBlocked: Bool,
    reservationCount: Int,
    guestCount: Int,
    projectedGuests: Int,
    partySize: Int,
    largePartyCount: Int,
    settings: HostIntelligenceSettings
  ) -> HostPressureSeverity {
    if isBlocked { return .critical }

    if projectedGuests >= Int((Double(settings.restaurantCapacity) * settings.criticalCapacityRatio).rounded()) {
      return .critical
    }

    if reservationCount + 1 > settings.maxReservationsPerSlot {
      return .busy
    }

    if largePartyCount > 0, partySize >= settings.largePartyThreshold {
      return .busy
    }

    if projectedGuests >= Int((Double(settings.restaurantCapacity) * settings.comfortableCapacityRatio).rounded()) {
      return .watch
    }

    if guestCount > 0 || reservationCount > 0 {
      return .watch
    }

    return .calm
  }

  private static func timeLabel(for date: Date) -> String {
    ReservationFormatters.shortTime.string(from: date)
  }

  private static func normalizedSlotTime(_ value: String) -> String {
    value.count >= 5 ? String(value.prefix(5)) : value
  }
}
