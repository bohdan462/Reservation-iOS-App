//
//  HostReservationOpenIntentStore.swift
//  Tryzub Reservations
//
//  In-memory store for Host Intelligence reservation open context.
//

import Foundation

@MainActor
final class HostReservationOpenIntentStore: ObservableObject {
  @Published private(set) var currentIntent: HostReservationOpenIntent?

  func set(_ intent: HostReservationOpenIntent) {
    currentIntent = intent
  }

  func consume(for reservationRemoteID: Int) -> HostReservationOpenIntent? {
    guard let intent = currentIntent,
          intent.reservationRemoteID == reservationRemoteID else {
      return nil
    }
    return intent
  }

  func clear() {
    currentIntent = nil
  }

  func clearIfMatches(_ intentID: String) {
    if currentIntent?.id == intentID {
      currentIntent = nil
    }
  }
}
