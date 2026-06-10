//
//  HostBoardViewState.swift
//  Tryzub Reservations
//

import Combine
import Foundation

enum HostBoardLoadingState: Equatable {
    case ready
    case loadingOperationalData
    case loadingAvailability
    case evaluatingHostIntelligence
    case enrichingBriefing
}

struct HostBoardMetrics: Equatable {
    let reservationCount: Int
    let seatedCount: Int
    let upcomingCount: Int
    let failedImportCount: Int
}

struct HostAttentionCardState: Equatable {
    let showsIntelligenceCard: Bool
    let briefingText: String
    let templateBriefingText: String
    let briefingSource: HostBriefingWriterSource
    let usesModelBriefing: Bool
}

struct HostBoardViewState: Equatable {
    let selectedDateKey: String
    let metrics: HostBoardMetrics
    let attentionCard: HostAttentionCardState
    let availabilityLine: String?
    let availabilityFreshness: ScreenFreshnessState
    let loadingState: HostBoardLoadingState
    let freshness: ScreenFreshnessState
    let isClosedDay: Bool
}

@MainActor
final class HostBoardViewStateStore: ObservableObject {
    @Published private(set) var viewState: HostBoardViewState?
    private var lastBuildKey: String?

    func rebuildIfNeeded(
        key: String,
        reason: String,
        build: () -> HostBoardViewState
    ) {
        guard lastBuildKey != key else { return }
        lastBuildKey = key
        let started = ContinuousClock.now
        let built = build()
        viewState = built
        FacadeTrace.build(
            surface: "host_board",
            duration: started.duration(to: .now).pressureTraceTimeInterval,
            extra: "reservations=\(built.metrics.reservationCount) reason=\(reason) briefingSource=\(built.attentionCard.briefingSource.rawValue) usesModel=\(built.attentionCard.usesModelBriefing)"
        )
    }

    func reset() {
        lastBuildKey = nil
        viewState = nil
    }
}

enum HostBoardViewStateBuilder {
    @MainActor
    static func build(
        selectedDate: Date,
        reservations: [ReservationRecord],
        failedImportCount: Int,
        availabilityState: AvailabilityDayState,
        hostIntelligenceEnabled: Bool,
        briefingText: String,
        templateBriefingText: String,
        briefingSource: HostBriefingWriterSource,
        operationalLoading: Bool,
        hostRenderState: HostIntelligenceRenderState,
        isEnrichmentLoading: Bool
    ) -> HostBoardViewState {
        let seated = reservations.filter { $0.statusValue == .seated }
        let upcoming = reservations.filter {
            [.new, .needsReview, .confirmed].contains($0.statusValue)
        }

        let loadingState: HostBoardLoadingState = {
            if hostRenderState == .evaluating { return .evaluatingHostIntelligence }
            if isEnrichmentLoading { return .enrichingBriefing }
            if availabilityState.isLoading { return .loadingAvailability }
            if operationalLoading { return .loadingOperationalData }
            return .ready
        }()

        let availabilityLine = HostBoardAvailabilityPresenter.line(
            state: availabilityState
        )

        return HostBoardViewState(
            selectedDateKey: selectedDate.reservationDateString(),
            metrics: HostBoardMetrics(
                reservationCount: reservations.count,
                seatedCount: seated.count,
                upcomingCount: upcoming.count,
                failedImportCount: failedImportCount
            ),
            attentionCard: HostAttentionCardState(
                showsIntelligenceCard: hostIntelligenceEnabled,
                briefingText: briefingText,
                templateBriefingText: templateBriefingText,
                briefingSource: briefingSource,
                usesModelBriefing: briefingSource == .localModel || briefingSource == .repairedLocalModel
            ),
            availabilityLine: availabilityLine,
            availabilityFreshness: availabilityState.slotsFreshness,
            loadingState: loadingState,
            freshness: availabilityState.availabilityFreshness,
            isClosedDay: availabilityState.isClosed
        )
    }
}

enum HostBoardAvailabilityPresenter {
    static func line(state: AvailabilityDayState) -> String? {
        if let error = state.errorMessage {
            return error
        }
        if state.isLoading, !state.hasUsableSlots {
            return "Loading availability…"
        }
        if state.isClosed {
            return "Closed today"
        }

        var parts: [String] = []
        if let availability = state.availability,
           let open = shortTime(availability.openTime),
           let close = shortTime(availability.closeTime) {
            parts.append("\(open)–\(close)")
        }
        if let slots = state.slots {
            parts.append("\(slots.slots.count) open times")
        }
        if !state.blockedSlotValues.isEmpty {
            parts.append("\(state.blockedSlotValues.count) blocked")
        }
        if let statusLine = state.statusLine, parts.isEmpty {
            return statusLine
        }
        return parts.isEmpty ? state.statusLine : parts.joined(separator: " · ")
    }

    private static func shortTime(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5 else { return trimmed }
        return String(trimmed.prefix(5))
    }
}
