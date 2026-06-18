//
//  FloorPlanReservationFitSupport.swift
//  Tryzub Reservations
//
//  Rank unassigned reservations by party-size fit for a selected floor table.
//

import Foundation

enum FloorPlanReservationFitSupport {

  static func proposals(
    for table: RestaurantTableDTO,
    reservations: [ManagedReservationDTO]
  ) -> [HostTableAssignmentProposal] {
    reservations
      .map { reservation in
        buildProposal(for: reservation, table: table)
      }
      .sorted { lhs, rhs in
        if lhs.isAvailable != rhs.isAvailable { return lhs.isAvailable }
        if lhs.isRecommended != rhs.isRecommended { return lhs.isRecommended }
        let leftRank = fitRank(for: lhs)
        let rightRank = fitRank(for: rhs)
        if leftRank != rightRank { return leftRank < rightRank }
        let leftTime = reservations.first(where: { "\($0.id)" == lhs.id })?.reservationTime ?? ""
        let rightTime = reservations.first(where: { "\($0.id)" == rhs.id })?.reservationTime ?? ""
        if leftTime != rightTime { return leftTime < rightTime }
        return lhs.tableLabel.localizedCaseInsensitiveCompare(rhs.tableLabel) == .orderedAscending
      }
  }

  // MARK: - Private

  private static func buildProposal(
    for reservation: ManagedReservationDTO,
    table: RestaurantTableDTO
  ) -> HostTableAssignmentProposal {
    let partySize = reservation.partySize
    let minCapacity = table.minCapacity
    let maxCapacity = max(table.minCapacity, table.maxCapacity)
    let fitQuality = HostTableIntelligenceSupport.fitQuality(
      partySize: partySize,
      capacity: maxCapacity
    )

    let detail: String?
    if partySize > maxCapacity {
      detail = "Party of \(partySize) exceeds seats \(FloorPlanPresentation.capacityRange(min: minCapacity, max: maxCapacity))"
    } else {
      detail = nil
    }

    let isAvailable = partySize <= maxCapacity
    let isRecommended = isAvailable && fitQuality != .unavailable

    return HostTableAssignmentProposal(
      id: "\(reservation.id)",
      tableLabel: reservation.guestName,
      summary: proposalSummary(
        reservation: reservation,
        partySize: partySize,
        fitQuality: fitQuality
      ),
      detail: detail,
      isRecommended: isRecommended,
      isAvailable: isAvailable,
      seatCount: maxCapacity,
      fitDescription: fitLabel(for: fitQuality).lowercased()
    )
  }

  private static func proposalSummary(
    reservation: ManagedReservationDTO,
    partySize: Int,
    fitQuality: HostTableFitQuality
  ) -> String {
    let time = FloorPlanPresentation.displayTime(reservation.reservationTime)
    let fitLabel: String
    switch fitQuality {
    case .exact: fitLabel = "Exact fit"
    case .tight: fitLabel = "Tight fit"
    case .comfortable: fitLabel = "Comfortable fit"
    case .oversized: fitLabel = "Roomy fit"
    case .unavailable: fitLabel = "Check capacity"
    }
    return "\(time) · \(partySize) · \(fitLabel.lowercased())"
  }

  private static func fitLabel(for quality: HostTableFitQuality) -> String {
    switch quality {
    case .exact: return "Matches party"
    case .tight: return "Tight"
    case .comfortable: return "Comfortable"
    case .oversized: return "Roomy"
    case .unavailable: return "May be tight"
    }
  }

  private static func fitRank(for proposal: HostTableAssignmentProposal) -> Int {
    guard proposal.isAvailable else { return 4 }
    if proposal.detail != nil { return 3 }
    if proposal.isRecommended { return 0 }
    return 2
  }
}
