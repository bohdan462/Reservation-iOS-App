//
//  ArrivalPressureModels.swift
//  Tryzub Reservations
//
//  Deterministic arrival-pressure shapes for the service wave chart and
//  manager narrative facts. No LLM, no network.
//

import Foundation

// MARK: - Pressure Level

enum ArrivalPressureLevel: String, Codable, Equatable, CaseIterable {
  case calm
  case building
  case busy
  case heavy

  var displayName: String {
    switch self {
    case .calm: return "calm"
    case .building: return "building"
    case .busy: return "busy"
    case .heavy: return "heavy"
    }
  }
}

enum ArrivalCurrentTimeRelation: String, Codable, Equatable {
  case beforeService
  case beforeWave
  case duringWave
  case afterPeak
}

// MARK: - Reservation Item (lightweight, safe for sheets)

struct ArrivalPressureReservationItem: Identifiable, Equatable {
  let remoteID: Int
  let guestName: String
  let displayTime: String
  let partySize: Int
  let status: ReservationStatus
  let tableName: String?
  let hasGuestNotes: Bool
  let needsReview: Bool
  let hasNoTable: Bool
  let isSeated: Bool
  let isReturningGuest: Bool

  var id: Int { remoteID }

  init(
    reservation: ReservationRecord,
    effectiveTableLabel: String? = nil,
    isReturningGuest: Bool = false
  ) {
    remoteID = reservation.remoteID
    guestName = reservation.guestName
    displayTime = reservation.displayTime
    partySize = reservation.partySize
    status = reservation.statusValue
    tableName = effectiveTableLabel ?? reservation.assignedTableName
    hasGuestNotes = reservation.hasGuestNotes
    needsReview = reservation.statusValue == .needsReview || reservation.statusValue == .new
    hasNoTable = tableName == nil
    isSeated = reservation.statusValue == .seated
    self.isReturningGuest = isReturningGuest
  }
}

// MARK: - Bucket

struct ArrivalPressureBucket: Identifiable, Equatable {
  let id: String
  let startTime: Date
  let endTime: Date
  let displayTime: String
  let axisLabel: String
  let reservationCount: Int
  let guestCount: Int
  let largePartyCount: Int
  let noTableCount: Int
  let needsReviewCount: Int
  let noteSignalCount: Int
  let returningGuestCount: Int
  /// Raw deterministic pressure score (pre-normalization).
  let pressureScore: Double
  /// 0…1 for chart height.
  let normalizedPressure: Double
  let items: [ArrivalPressureReservationItem]
  var isPeak: Bool
  var isNextArrival: Bool
  var isPast: Bool

  var hasArrivals: Bool { reservationCount > 0 }

  var windowLabel: String {
    let end = ReservationFormatters.shortTime.string(from: endTime)
    return "\(displayTime)–\(end)"
  }
}

// MARK: - Manager Facts (fed to narrative packet)

struct ArrivalPressureManagerFacts: Equatable, Codable {
  let peakWindow: String?
  let peakReservationCount: Int
  let peakGuestCount: Int
  let nextWaveStart: String?
  let pressureLevel: String
  let noTableInPeakCount: Int
  let largePartyInPeakCount: Int
  let noteSignalsInPeak: Int
  let returningGuestSignalsInPeak: Int
  let currentTimeRelation: String
  /// One-line operational summary for the model.
  let pressureSummaryLine: String
}

// MARK: - Summary

struct ArrivalPressureSummary: Equatable {
  let buckets: [ArrivalPressureBucket]
  let peakBucket: ArrivalPressureBucket?
  let nextBucket: ArrivalPressureBucket?
  let nextWaveStart: Date?
  let pressureLevel: ArrivalPressureLevel
  let currentTimeRelation: ArrivalCurrentTimeRelation
  let managerFacts: ArrivalPressureManagerFacts
  /// Top operational line shown above the chart.
  let chartHeadline: String
  /// Secondary line under the headline.
  let chartSubtitle: String
  /// Peak legend text for the summary card.
  let peakLegendText: String
  /// Next legend text for the summary card.
  let nextLegendText: String?

  var hasArrivals: Bool {
    buckets.contains(where: \.hasArrivals)
  }
}
