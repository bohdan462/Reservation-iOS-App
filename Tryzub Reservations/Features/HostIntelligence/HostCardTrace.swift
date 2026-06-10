//
//  HostCardTrace.swift
//  Tryzub Reservations
//
//  DEBUG-only tracing for Host card evaluation and empty-state policy.
//

import Foundation

struct HostCardTraceNoTableCandidate: Equatable {
  let id: Int
  let name: String
  let time: String
  let status: String
  let table: String
}

enum HostCardTrace {

  static func noTableSoonCandidate(
    in reservations: [ReservationRecord],
    selectedDate: Date,
    now: Date
  ) -> HostCardTraceNoTableCandidate? {
    guard let reservation = HostOperationalNoTableSoonSupport.firstQualifyingReservation(
      in: reservations,
      selectedDate: selectedDate,
      now: now
    ) else {
      return nil
    }

    return HostCardTraceNoTableCandidate(
      id: reservation.remoteID,
      name: reservation.guestName,
      time: reservation.displayTime,
      status: reservation.statusValue.rawValue,
      table: reservation.hasTableAssignment ? (reservation.tableName ?? "assigned") : "none"
    )
  }

  static func log(
    selectedDate: String,
    lastAttentionSelectedDate: String?,
    preserveAllowed: Bool,
    dateChanged: Bool,
    localEvaluationComplete: Bool,
    enrichmentLoading: Bool,
    display: String,
    factCount: Int,
    actionCount: Int,
    renderState: HostIntelligenceRenderState,
    emptyAllowed: Bool,
    preservedPrevious: Bool,
    noTableSoonCandidate: HostCardTraceNoTableCandidate?
  ) {
    #if DEBUG
    let lastAttention = lastAttentionSelectedDate ?? "none"
    print(
      """
      [HOST_CARD_TRACE] selected=\(selectedDate) lastAttentionSelected=\(lastAttention) preserveAllowed=\(preserveAllowed) dateChanged=\(dateChanged) localEvaluationComplete=\(localEvaluationComplete) enrichmentLoading=\(enrichmentLoading) display=\(display) facts=\(factCount) actions=\(actionCount) render=\(renderState.rawValue) emptyAllowed=\(emptyAllowed) preserved=\(preservedPrevious)
      """
    )
    if let noTableSoonCandidate {
      print(
        """
        [HOST_CARD_TRACE] noTableSoonCandidate=true id=\(noTableSoonCandidate.id) name=\(noTableSoonCandidate.name) time=\(noTableSoonCandidate.time) status=\(noTableSoonCandidate.status) table=\(noTableSoonCandidate.table)
        """
      )
    } else {
      print("[HOST_CARD_TRACE] noTableSoonCandidate=false")
    }
    #endif
  }
}
