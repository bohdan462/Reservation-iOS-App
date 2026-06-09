//
//  AppReservationSession.swift
//  Tryzub Reservations
//
//  Shared reservation controller for intro warmup and the main shell.
//

import SwiftData
import SwiftUI

@MainActor
final class AppReservationSession: ObservableObject {
    private(set) var reservationsController: ReservationsController?
    private var environmentKey: String?

    func sync(environment: AppEnvironment, context: ModelContext) {
        let key = "\(environment.role.rawValue)-\(environment.username)"
        if environmentKey != key {
            reservationsController?.prepareForLogout()
            environmentKey = key
            reservationsController = ReservationsController(environment: environment)
        }
        reservationsController?.beginBackgroundReservationWarmup(context: context)
    }

    func reset() {
        reservationsController?.prepareForLogout()
        reservationsController = nil
        environmentKey = nil
    }
}
