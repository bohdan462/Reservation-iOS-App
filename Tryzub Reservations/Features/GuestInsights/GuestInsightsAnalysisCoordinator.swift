//
//  GuestInsightsAnalysisCoordinator.swift
//  Tryzub Reservations
//

import Foundation

// MARK: - Background Guest Insight Analysis

@MainActor
final class GuestInsightsAnalysisCoordinator: ObservableObject {
    @Published private(set) var report: GuestInsightReport?
    @Published private(set) var isAnalyzingLocalCache = false

    var onAnalysisCompleted: ((_ duration: TimeInterval, _ reservationID: Int) -> Void)?

    private var generation = 0

    func reset() {
        generation += 1
        report = nil
        isAnalyzingLocalCache = false
    }

    func scheduleAnalysis(
        selected: ReservationRecord,
        pool: [ReservationRecord]
    ) {
        generation += 1
        let currentGeneration = generation
        isAnalyzingLocalCache = true
        let started = ContinuousClock.now
        let reservationID = selected.remoteID
        let localTruth = GuestOperationalTruth.localTruthSnapshot(
            selected: selected,
            reservationPool: pool
        )

        let built = UIPressureTrace.measure(
            phase: "guest_insights_snapshot",
            extra: "records=\(pool.count)"
        ) {
            GuestInsightRecordSnapshotBuilder.build(selected: selected, pool: pool)
        }

        let selectedSnapshot = built.selected
        let allSnapshots = built.all

        Task {
            let analyzedReport = await Task.detached(priority: .userInitiated) {
                UIPressureTrace.measure(
                    phase: "guest_insights_analyze_background",
                    extra: "records=\(allSnapshots.count)"
                ) {
                    GuestInsightsController().analyzeSnapshots(
                        selected: selectedSnapshot,
                        all: allSnapshots,
                        localTruth: localTruth
                    )
                }
            }.value

            guard currentGeneration == generation else { return }

            UIPressureTrace.measure(phase: "guest_insights_publish") {
                report = analyzedReport
                isAnalyzingLocalCache = false
            }
            let duration = started.duration(to: .now).pressureTraceTimeInterval
            onAnalysisCompleted?(duration, reservationID)
        }
    }
}
