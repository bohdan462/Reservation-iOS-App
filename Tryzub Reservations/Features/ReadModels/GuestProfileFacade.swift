//
//  GuestProfileFacade.swift
//  Tryzub Reservations
//

import Foundation

@MainActor
final class GuestProfileFacade: ObservableObject {
    @Published private(set) var viewState: GuestProfileViewState?
    @Published private(set) var localReport: GuestInsightReport?

    let analysisCoordinator = GuestInsightsAnalysisCoordinator()

    private var generation = 0
    private var pendingLoad: (
        reservation: ReservationRecord,
        historyPool: [ReservationRecord],
        store: GuestIntelligenceStore
    )?

    init() {
        analysisCoordinator.onAnalysisCompleted = { [weak self] duration, reservationID in
            Task { @MainActor in
                self?.handleLocalAnalysisCompleted(duration: duration, reservationID: reservationID)
            }
        }
    }

    func loadIfNeeded(
        reservation: ReservationRecord,
        historyPool: [ReservationRecord],
        store: GuestIntelligenceStore
    ) {
        generation += 1
        let currentGeneration = generation
        pendingLoad = (reservation, historyPool, store)

        store.ensureSummary(
            reservationID: reservation.remoteID,
            dateKey: reservation.reservationDate
        )

        analysisCoordinator.scheduleAnalysis(
            selected: reservation,
            pool: historyPool
        )

        rebuildViewState(
            reservation: reservation,
            historyPool: historyPool,
            store: store
        )

        Task {
            await store.loadProfile(
                reservationID: reservation.remoteID,
                dateKey: reservation.reservationDate
            )
            guard currentGeneration == generation else { return }
            rebuildViewState(
                reservation: reservation,
                historyPool: historyPool,
                store: store
            )
        }
    }

    func rebuildViewState(
        reservation: ReservationRecord,
        historyPool: [ReservationRecord],
        store: GuestIntelligenceStore
    ) {
        localReport = analysisCoordinator.report
        viewState = GuestProfileViewStateBuilder.build(
            reservation: reservation,
            historyPool: historyPool,
            store: store,
            localReport: analysisCoordinator.report,
            isAnalyzingLocalCache: analysisCoordinator.isAnalyzingLocalCache
        )
    }

    func reset() {
        generation += 1
        pendingLoad = nil
        viewState = nil
        localReport = nil
        analysisCoordinator.reset()
    }

    private func handleLocalAnalysisCompleted(duration: TimeInterval, reservationID: Int) {
        guard let pending = pendingLoad, pending.reservation.remoteID == reservationID else { return }
        FacadeTrace.event(
            surface: "guest_profile",
            name: "local_analysis_completed",
            extra: "reservation=\(reservationID) duration=\(Int(duration * 1000))ms"
        )
        rebuildViewState(
            reservation: pending.reservation,
            historyPool: pending.historyPool,
            store: pending.store
        )
    }
}
