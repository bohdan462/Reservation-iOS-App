//
//  HostOperationalNoTableSoonSupport.swift
//  Tryzub Reservations
//
//  Deterministic today-only no-table-soon rules for Host Intelligence.
//  Independent of availability summaries, guest intelligence, and local model output.
//

import Foundation

enum HostOperationalNoTableSoonSupport {

  static let windowMinutes = 45

  static func qualifyingReservations(
    in reservations: [ReservationRecord],
    selectedDate: Date,
    now: Date,
    assignmentsByReservationID: [Int: String] = [:]
  ) -> [ReservationRecord] {
    guard isToday(selectedDate, now: now) else { return [] }

    let selectedDateKey = selectedDate.reservationDateString()
    return reservations.filter { reservation in
      reservation.reservationDate == selectedDateKey
        && qualifies(
          reservation: reservation,
          now: now,
          assignmentsByReservationID: assignmentsByReservationID
        )
    }
  }

  static func firstQualifyingReservation(
    in reservations: [ReservationRecord],
    selectedDate: Date,
    now: Date,
    assignmentsByReservationID: [Int: String] = [:]
  ) -> ReservationRecord? {
    qualifyingReservations(
      in: reservations,
      selectedDate: selectedDate,
      now: now,
      assignmentsByReservationID: assignmentsByReservationID
    ).first
  }

  static func qualifies(
    reservation: ReservationRecord,
    now: Date,
    assignmentsByReservationID: [Int: String] = [:]
  ) -> Bool {
    guard reservationNeedsTableAttention(
      reservation,
      assignmentsByReservationID: assignmentsByReservationID
    ) else { return false }
    guard let serviceDate = reservation.serviceDateTime else { return false }

    let minutesUntil = serviceDate.timeIntervalSince(now) / 60
    if minutesUntil < 0 {
      return true
    }
    return minutesUntil <= Double(windowMinutes)
  }

  static func reservationNeedsTableAttention(
    _ reservation: ReservationRecord,
    assignmentsByReservationID: [Int: String] = [:]
  ) -> Bool {
    guard reservation.isOpenWork,
          !ReservationTableTruth.hasEffectiveTableAssignment(
            for: reservation,
            assignmentsByReservationID: assignmentsByReservationID
          ) else {
      return false
    }
    switch reservation.statusValue {
    case .new, .needsReview, .confirmed:
      return true
    case .seated, .completed, .cancelled, .noShow:
      return false
    }
  }

  static func isToday(_ selectedDate: Date, now: Date) -> Bool {
    selectedDate.reservationDateString() == now.reservationDateString()
  }
}
