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
    private var guestProfileSyncService: GuestProfileSyncService?
    private var guestProfileSyncTask: Task<Void, Never>?

    /// Shared freshness coordinator. One per session, recreated on role/credential change.
    /// Inject into FloorPlanStore, GuestIntelligenceStore, and BusinessAnalyticsCoordinator
    /// via environment or initializer — never instantiate a second one inside views.
    let freshness = FreshnessCoordinator()

    func sync(environment: AppEnvironment, context: ModelContext) {
        let key = "\(environment.role.rawValue)-\(environment.username)"
        if environmentKey != key {
            reservationsController?.prepareForLogout()
            guestProfileSyncTask?.cancel()
            guestProfileSyncTask = nil
            environmentKey = key
            reservationsController = ReservationsController(
                environment: environment,
                traceSource: "AppReservationSession"
            )
            reservationsController?.freshnessCoordinator = freshness
            guestProfileSyncService = GuestProfileSyncService(apiClient: environment.apiClient)
        }
        StartupTrace.sessionSync(
            controllerID: reservationsController?.startupTraceControllerID,
            warmup: true
        )
        reservationsController?.beginBackgroundReservationWarmup(context: context)
        scheduleGuestProfileSyncIfNeeded(context: context)
    }

    func reset() {
        reservationsController?.prepareForLogout()
        guestProfileSyncTask?.cancel()
        guestProfileSyncTask = nil
        guestProfileSyncService = nil
        reservationsController = nil
        environmentKey = nil
    }

    private func scheduleGuestProfileSyncIfNeeded(context: ModelContext) {
        guard guestProfileSyncTask == nil else { return }
        guard let key = environmentKey,
              let controller = reservationsController,
              let syncService = guestProfileSyncService else { return }

        guestProfileSyncTask = Task(priority: .utility) { @MainActor [weak self, weak controller] in
            defer {
                if self?.environmentKey == key {
                    self?.guestProfileSyncTask = nil
                }
            }

            for _ in 0..<180 {
                guard !Task.isCancelled else { return }
                guard self?.environmentKey == key else { return }
                if controller?.canStartNoncriticalStartupLoads == true {
                    break
                }
                try? await Task.sleep(for: .seconds(1))
            }

            guard !Task.isCancelled else { return }
            guard self?.environmentKey == key else { return }
            guard controller?.canStartNoncriticalStartupLoads == true else { return }
            await syncService.syncProfilesIfNeeded(context: context)
        }
    }
}
