//
//  AppReservationSession.swift
//  Tryzub Reservations
//
//  Shared reservation controller for intro warmup and the main shell.
//  Also owns the app-wide FreshnessCoordinator so stores and views can ask
//  a single authority whether a scope needs a network fetch.
//

import SwiftData
import SwiftUI

@MainActor
final class AppReservationSession: ObservableObject {
    @Published private(set) var reservationsController: ReservationsController?
    private var environmentKey: String?

    /// Shared freshness coordinator. One per session, recreated on role/credential change.
    /// Inject into FloorPlanStore, GuestIntelligenceStore, and BusinessAnalyticsCoordinator
    /// via environment or initializer — never instantiate a second one inside views.
    let freshness = FreshnessCoordinator()

    func sync(environment: AppEnvironment, context: ModelContext) {
        let key = "\(environment.role.rawValue)-\(environment.username)"
        if environmentKey != key {
            reservationsController?.prepareForLogout()
            environmentKey = key
            reservationsController = ReservationsController(
                environment: environment,
                traceSource: "AppReservationSession"
            )
            reservationsController?.freshnessCoordinator = freshness
        }
        StartupTrace.sessionSync(
            controllerID: reservationsController?.startupTraceControllerID,
            warmup: true
        )
        reservationsController?.beginBackgroundReservationWarmup(context: context)
    }

    func reset() {
        reservationsController?.prepareForLogout()
        reservationsController = nil
        environmentKey = nil
    }
}
