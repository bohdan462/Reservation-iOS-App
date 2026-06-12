//
//  HostOperationalFutureTablePlanningSupport.swift
//
//  Deterministic selected-future-date no-table planning for Host Intelligence.
//  Independent of availability, guest intelligence, and local model output.
//

import Foundation

enum HostOperationalFutureTablePlanningSupport {

  static func planningOutputs(
    reservations: [ReservationRecord],
    selectedDate: Date,
    now: Date
  ) -> (facts: [HostBriefingFact], actions: [HostSuggestedAction]) {
    guard !HostOperationalNoTableSoonSupport.isToday(selectedDate, now: now) else {
      return ([], [])
    }

    let dateKey = selectedDate.reservationDateString()
    let needingTables = reservations.filter { reservation in
      reservation.reservationDate == dateKey
        && HostOperationalNoTableSoonSupport.reservationNeedsTableAttention(reservation)
    }
    guard !needingTables.isEmpty else { return ([], []) }

    let reservationCount = needingTables.count
    let guestCount = needingTables.reduce(0) { $0 + $1.partySize }
    let dateLabel = selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())

    let fact = HostBriefingFact(
      id: "future-no-table-planning-\(dateKey)",
      severity: .warning,
      category: .table,
      title: "\(reservationCount) reservations still need tables.",
      detail: "Assign floor plan tables before service.",
      evidence: [
        "reservationCount=\(reservationCount)",
        "guestCount=\(guestCount)",
        "selectedDate=\(dateKey)"
      ],
      relatedReservationIDs: needingTables.map(\.remoteID),
      suggestedActionTitle: "Assign floor plan tables before service."
    )

    let action = HostSuggestedAction(
      id: "future-table-plan-\(dateKey)",
      severity: .warning,
      kind: .assignTable,
      title: "Review floor plan for \(dateLabel)",
      reason: "\(reservationCount) reservations · \(guestCount) guests without tables",
      relatedReservationIDs: needingTables.map(\.remoteID),
      targetSlotTime: nil,
      targetTableName: nil,
      requiresStaffConfirmation: true
    )

    return ([fact], [action])
  }
}
