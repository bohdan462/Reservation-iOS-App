//
//  GuestProfileFacade.swift
//  Tryzub Reservations
//

import Foundation

@MainActor
final class GuestProfileFacade: ObservableObject {
    typealias ReservationProvider = @MainActor () -> (reservation: ReservationRecord, historyPool: [ReservationRecord])?

    @Published private(set) var viewState: GuestProfileViewState?
    @Published private(set) var localReport: GuestInsightReport?

    let analysisCoordinator = GuestInsightsAnalysisCoordinator()

    private var generation = 0
    private var pendingReservationID: Int?
    private var boundStore: GuestIntelligenceStore?
    private var reservationProvider: ReservationProvider?
    private var lastRebuildKey: String?

    init() {
        analysisCoordinator.onAnalysisCompleted = { [weak self] duration, reservationID in
            Task { @MainActor in
                self?.handleLocalAnalysisCompleted(duration: duration, reservationID: reservationID)
            }
        }
    }

    /// Refreshes the provider used after async work so rebuild reads current MainActor reservation/pool.
    func updateReservationProvider(_ provider: @escaping ReservationProvider) {
        reservationProvider = provider
    }

    func loadIfNeeded(
        reservation: ReservationRecord,
        historyPool: [ReservationRecord],
        store: GuestIntelligenceStore
    ) {
        generation += 1
        let currentGeneration = generation
        let reservationID = reservation.remoteID
        let dateKey = reservation.reservationDate

        pendingReservationID = reservationID
        boundStore = store
        lastRebuildKey = nil

        store.ensureSummary(
            reservationID: reservationID,
            dateKey: dateKey
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
                reservationID: reservationID,
                dateKey: dateKey
            )
            guard currentGeneration == generation else { return }
            FacadeTrace.event(
                surface: "guest_profile",
                name: "profile_loaded",
                extra: "reservation=\(reservationID) generation=\(currentGeneration)"
            )
            requestRebuild(reason: "profile_loaded", generation: currentGeneration)
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
        pendingReservationID = nil
        boundStore = nil
        reservationProvider = nil
        lastRebuildKey = nil
        viewState = nil
        localReport = nil
        analysisCoordinator.reset()
    }

    private func handleLocalAnalysisCompleted(duration: TimeInterval, reservationID: Int) {
        guard pendingReservationID == reservationID else { return }
        FacadeTrace.event(
            surface: "guest_profile",
            name: "local_analysis_completed",
            extra: "reservation=\(reservationID) duration=\(Int(duration * 1000))ms"
        )
        requestRebuild(reason: "local_analysis_completed", generation: generation)
    }

    private func requestRebuild(reason: String, generation: Int) {
        guard generation == self.generation else { return }
        guard let store = boundStore,
              let provider = reservationProvider,
              let context = provider() else {
            return
        }

        let rebuildKey = [
            "\(context.reservation.remoteID)",
            store.semanticProfileStamp(
                for: context.reservation.remoteID,
                dateKey: context.reservation.reservationDate
            ),
            "\(analysisCoordinator.isAnalyzingLocalCache)",
            "\(analysisCoordinator.report?.matchedReservations.count ?? 0)"
        ].joined(separator: "|")

        guard lastRebuildKey != rebuildKey else {
            FacadeTrace.event(
                surface: "guest_profile",
                name: "rebuild_skipped",
                extra: "reason=semantic_key_unchanged trigger=\(reason) reservation=\(context.reservation.remoteID)"
            )
            return
        }
        lastRebuildKey = rebuildKey

        FacadeTrace.event(
            surface: "guest_profile",
            name: "rebuild_requested",
            extra: "reason=\(reason) reservation=\(context.reservation.remoteID)"
        )

        rebuildViewState(
            reservation: context.reservation,
            historyPool: context.historyPool,
            store: store
        )
    }
}
