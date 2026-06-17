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
    @Published private(set) var aggregateProfile: GuestProfileDTO?

    let analysisCoordinator = GuestInsightsAnalysisCoordinator()

    private var generation = 0
    private var pendingReservationID: Int?
    private var boundStore: GuestIntelligenceStore?
    private var boundGuestProfileStore: GuestProfileStore?
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
        store: GuestIntelligenceStore,
        guestProfileStore: GuestProfileStore
    ) {
        generation += 1
        let currentGeneration = generation
        let reservationID = reservation.remoteID
        let dateKey = reservation.reservationDate

        pendingReservationID = reservationID
        boundStore = store
        boundGuestProfileStore = guestProfileStore
        lastRebuildKey = nil
        aggregateProfile = guestProfileStore.cachedProfile(byReservationID: reservationID)

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
            let aggregate = await guestProfileStore.loadProfile(byReservationID: reservationID)
            guard currentGeneration == generation else { return }
            if let aggregate {
                aggregateProfile = aggregate
                FacadeTrace.event(
                    surface: "guest_profile",
                    name: "aggregate_profile_loaded",
                    extra: "reservation=\(reservationID) generation=\(currentGeneration) stale=\(aggregate.stale == true)"
                )
                requestRebuild(reason: "aggregate_profile_loaded", generation: currentGeneration)
                return
            }

            await store.loadProfile(
                reservationID: reservationID,
                dateKey: dateKey
            )
            guard currentGeneration == generation else { return }
            FacadeTrace.event(
                surface: "guest_profile",
                name: "legacy_profile_loaded",
                extra: "reservation=\(reservationID) generation=\(currentGeneration)"
            )
            requestRebuild(reason: "legacy_profile_loaded", generation: currentGeneration)
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
            aggregateProfile: aggregateProfile,
            localReport: analysisCoordinator.report,
            isAnalyzingLocalCache: analysisCoordinator.isAnalyzingLocalCache
        )
    }

    func reset() {
        generation += 1
        pendingReservationID = nil
        boundStore = nil
        boundGuestProfileStore = nil
        reservationProvider = nil
        lastRebuildKey = nil
        viewState = nil
        localReport = nil
        aggregateProfile = nil
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
            boundGuestProfileStore?.cachedProfile(byReservationID: context.reservation.remoteID)?.id ?? aggregateProfile?.id ?? "no_aggregate",
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
