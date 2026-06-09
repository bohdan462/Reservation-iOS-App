//
//  HostSuggestedActionRouter.swift
//  Tryzub Reservations
//
//  Maps Host Intelligence suggested actions to safe navigation destinations.
//  Does not perform mutations — staff confirm through existing reservation UI.
//

import Foundation

struct HostSuggestedActionRoute: Equatable {
  enum Destination: Equatable {
    case reservation(remoteID: Int)
    case reservationIntent(remoteID: Int, kind: HostActionKind)
    case slot(slotTime: String)
    case none
  }

  let destination: Destination
  let reason: String
}

enum HostSuggestedActionRouter {

  // MARK: - Routing

  static func route(for action: HostSuggestedAction) -> HostSuggestedActionRoute {
    switch action.kind {
    case .noAction:
      return HostSuggestedActionRoute(
        destination: .none,
        reason: "No route for noAction."
      )

    case .closeSlot:
      if let slotTime = normalizedSlotTime(action.targetSlotTime) {
        return HostSuggestedActionRoute(
          destination: .slot(slotTime: slotTime),
          reason: "Slot review only; blocked-slot management stays in restaurant settings."
        )
      }
      return HostSuggestedActionRoute(
        destination: .none,
        reason: "Close slot suggestion has no target slot."
      )

    case .reviewReservation,
         .assignTable,
         .seatReservation,
         .completeReservation,
         .confirmReservation,
         .markNoShow:
      return reservationRoute(for: action, intentKind: action.kind)

    case .reviewCancellationOpportunity:
      return reservationRoute(for: action, intentKind: .reviewCancellationOpportunity)

    case .alertServer,
         .generateEmailDraft,
         .generateGuestManageLink:
      return reservationRoute(for: action, intentKind: nil)

    case .suggestAlternateTime,
         .holdTable,
         .releaseTable:
      return reservationRoute(for: action, intentKind: nil)
    }
  }

  static func routeDescription(
    for action: HostSuggestedAction,
    dayReservations: [ReservationRecord] = [],
    knownReservations: [ReservationRecord] = []
  ) -> String {
    let route = route(for: action)

    switch route.destination {
    case .none:
      return "Route: none"

    case .slot(let slotTime):
      return "Route: slot \(slotTime)"

    case .reservation(let remoteID):
      let resolved = resolvedRemoteID(
        for: action,
        dayReservations: dayReservations,
        knownReservations: knownReservations
      ) ?? remoteID
      return "Route: reservation \(resolved)"

    case .reservationIntent(let remoteID, let kind):
      let resolved = resolvedRemoteID(
        for: action,
        dayReservations: dayReservations,
        knownReservations: knownReservations
      ) ?? remoteID
      return "Route: reservation \(resolved) (\(kind.rawValue))"
    }
  }

  // MARK: - Resolution

  static func resolvedRemoteID(
    for action: HostSuggestedAction,
    dayReservations: [ReservationRecord],
    knownReservations: [ReservationRecord]
  ) -> Int? {
    let candidates = action.relatedReservationIDs
    guard !candidates.isEmpty else { return nil }

    let lookup = reservationLookup(
      dayReservations: dayReservations,
      knownReservations: knownReservations
    )

    let orderedIDs = preferredReservationIDs(for: action, candidates: candidates, lookup: lookup)

    for remoteID in orderedIDs where lookup[remoteID] != nil {
      return remoteID
    }

    return candidates.first
  }

  static func findReservation(
    remoteID: Int,
    dayReservations: [ReservationRecord],
    knownReservations: [ReservationRecord]
  ) -> ReservationRecord? {
    if let match = dayReservations.first(where: { $0.remoteID == remoteID }) {
      return match
    }
    return knownReservations.first(where: { $0.remoteID == remoteID })
  }

  // MARK: - Private

  private static func reservationRoute(
    for action: HostSuggestedAction,
    intentKind: HostActionKind?
  ) -> HostSuggestedActionRoute {
    guard let remoteID = action.relatedReservationIDs.first else {
      return HostSuggestedActionRoute(
        destination: .none,
        reason: "No related reservation ID."
      )
    }

    let multipleReason = action.relatedReservationIDs.count > 1
      ? "Multiple related reservations; opening the most actionable match."
      : "Opening related reservation."

    if let intentKind {
      return HostSuggestedActionRoute(
        destination: .reservationIntent(remoteID: remoteID, kind: intentKind),
        reason: multipleReason
      )
    }

    return HostSuggestedActionRoute(
      destination: .reservation(remoteID: remoteID),
      reason: multipleReason
    )
  }

  private static func preferredReservationIDs(
    for action: HostSuggestedAction,
    candidates: [Int],
    lookup: [Int: ReservationRecord]
  ) -> [Int] {
    switch action.kind {
    case .reviewCancellationOpportunity:
      let openWork = candidates.filter { lookup[$0]?.isOpenWork == true }
      if !openWork.isEmpty {
        return openWork
      }
      let notCancelled = candidates.filter { lookup[$0]?.statusValue != .cancelled }
      if !notCancelled.isEmpty {
        return notCancelled
      }
      return candidates

    default:
      let openWork = candidates.filter { lookup[$0]?.isOpenWork == true }
      if !openWork.isEmpty {
        return openWork
      }
      return candidates
    }
  }

  private static func reservationLookup(
    dayReservations: [ReservationRecord],
    knownReservations: [ReservationRecord]
  ) -> [Int: ReservationRecord] {
    var lookup: [Int: ReservationRecord] = [:]
    for reservation in knownReservations {
      lookup[reservation.remoteID] = reservation
    }
    for reservation in dayReservations {
      lookup[reservation.remoteID] = reservation
    }
    return lookup
  }

  private static func normalizedSlotTime(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }
}
