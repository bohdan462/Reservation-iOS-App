//
//  GuestProfileViewState.swift
//  Tryzub Reservations
//

import Foundation

// MARK: - Guest Profile View State

struct GuestProfileHeaderState: Equatable {
    let guestName: String
    let reservationLine: String
    let historyTitle: String
    let historyDetail: String
    let regularityLabel: String?
    let serverLastSeen: String?
}

struct GuestProfileSummaryState: Equatable {
    let summaryText: String?
    let managementNotes: [String]
}

struct ServerGuestVisitState: Equatable, Identifiable {
    let id: Int
    let headline: String
    let detailLine: String
    let guestNoteLine: String?
    let staffNoteLine: String?
}

struct LocalCachedVisitState: Equatable, Identifiable {
    let id: Int
    let displayDate: String
    let displayTime: String
    let partySize: Int
    let statusLabel: String
}

struct GuestProfileNotesState: Equatable {
    let guestNoteCount: Int
    let staffNoteCount: Int
    let showsLocalNotes: Bool
}

enum GuestProfileLoadingState: Equatable {
    case ready
    case loadingServerProfile
    case calculatingLocalCache
    case loadingBoth
}

struct GuestProfileViewState: Equatable {
    let header: GuestProfileHeaderState
    let aggregateProfile: GuestInsightsProfilePresentation.AggregateProfileState?
    let profileSummary: GuestProfileSummaryState?
    let preferenceLines: [String]
    let priorNoteLines: [String]
    let visitAnalyticsLines: [String]
    let serverHistory: [ServerGuestVisitState]
    let localHistory: [LocalCachedVisitState]
    let notes: GuestProfileNotesState?
    let possibleMatchCount: Int
    let warningTitles: [String]
    let loadingState: GuestProfileLoadingState
    let freshness: ScreenFreshnessState
    let showsLocalPreferences: Bool
    let showsLocalBookingHistory: Bool
    let showsSupplementalLocalHistory: Bool
    let localHistorySectionTitle: String?
    let localHistoryScopeNote: String?
    let traceKey: String
}

// MARK: - Builder

enum GuestProfileViewStateBuilder {
    @MainActor
    static func build(
        reservation: ReservationRecord,
        historyPool: [ReservationRecord],
        store: GuestIntelligenceStore,
        aggregateProfile: GuestProfileDTO? = nil,
        localReport: GuestInsightReport?,
        isAnalyzingLocalCache: Bool,
        now: Date = Date()
    ) -> GuestProfileViewState {
        let started = ContinuousClock.now

        let reservationID = reservation.remoteID
        let dateKey = reservation.reservationDate
        let profilePack = store.profilePack(for: reservationID)
        let aggregateState = GuestInsightsProfilePresentation.aggregateState(from: aggregateProfile)
        let serverSummary = store.summary(for: reservationID, dateKey: dateKey)
        let serverAnswered = store.hasServerAnswer(for: reservationID, dateKey: dateKey)
        let isLoadingProfile = store.isLoadingProfile(reservationID: reservationID)

        let mergedContext: GuestHistorySemantics.GuestInsightsMergedContext? = {
            guard let localReport else { return nil }
            return GuestHistorySemantics.insightsMergedContext(
                guestName: reservation.guestName,
                localReport: localReport,
                serverSummary: serverSummary,
                serverAnswered: serverAnswered,
                profileStamp: store.semanticProfileStamp(for: reservationID, dateKey: dateKey),
                profilePack: profilePack
            )
        }()

        let localCachedHistory: GuestHistorySemantics.GuestInsightsBookingHistoryPresentation? = {
            guard let localReport else { return nil }
            return GuestHistorySemantics.localCachedHistoryPresentation(
                localReport: localReport,
                profilePack: profilePack
            )
        }()

        let header = GuestProfileHeaderState(
            guestName: cleaned(aggregateProfile?.primaryName) ?? reservation.guestName,
            reservationLine: "\(reservation.displayDate) at \(reservation.displayTime) · party of \(reservation.partySize)",
            historyTitle: aggregateState != nil ? "Backend guest profile" : (mergedContext?.historyTitle ?? (profilePack != nil ? "Seen before" : "Guest history")),
            historyDetail: aggregateState?.sourceLine ?? mergedContext?.historyDetail ?? fallbackHistoryDetail(
                profilePack: profilePack,
                isLoadingProfile: isLoadingProfile
            ),
            regularityLabel: mergedContext?.mergedRegularity?.displayName,
            serverLastSeen: mergedContext?.serverLastSeenDisplay
        )

        let profileSummary = profilePack.map {
            GuestProfileSummaryState(
                summaryText: $0.profileSummary?.summaryText,
                managementNotes: $0.profileSummary?.managementNotes ?? []
            )
        }

        let serverHistory = GuestInsightsProfilePresentation.serverVisitRows(from: profilePack).map {
            ServerGuestVisitState(
                id: $0.id,
                headline: $0.headline,
                detailLine: $0.detailLine,
                guestNoteLine: $0.guestNoteLine,
                staffNoteLine: $0.staffNoteLine
            )
        }

        let localHistory = (localReport?.bookingHistory ?? []).map {
            LocalCachedVisitState(
                id: $0.reservationID,
                displayDate: $0.displayDate,
                displayTime: $0.displayTime,
                partySize: $0.partySize,
                statusLabel: $0.status.rawValue.replacingOccurrences(of: "_", with: " ")
            )
        }

        let notes = localReport.map {
            GuestProfileNotesState(
                guestNoteCount: $0.noteHistory.filter { $0.noteType == .guest }.count,
                staffNoteCount: $0.noteHistory.filter { $0.noteType == .staff }.count,
                showsLocalNotes: !$0.noteHistory.isEmpty
            )
        }

        let loadingState: GuestProfileLoadingState = {
            if isAnalyzingLocalCache && isLoadingProfile { return .loadingBoth }
            if isAnalyzingLocalCache { return .calculatingLocalCache }
            if isLoadingProfile && profilePack == nil { return .loadingServerProfile }
            return .ready
        }()

        let freshness = ScreenFreshnessState.from(
            loadedAt: profilePack != nil ? now : nil,
            ttl: DataFreshnessPolicy.standard.guestIntelligenceTTL,
            now: now,
            isLoading: isLoadingProfile && profilePack == nil
        )

        let built = GuestProfileViewState(
            header: header,
            aggregateProfile: aggregateState,
            profileSummary: hasProfileSummaryContent(profileSummary) ? profileSummary : nil,
            preferenceLines: aggregateState?.preferenceLines ?? GuestInsightsProfilePresentation.preferenceLines(from: profilePack),
            priorNoteLines: aggregateState?.noteLines ?? GuestInsightsProfilePresentation.priorNoteLines(from: profilePack),
            visitAnalyticsLines: aggregateState == nil ? GuestInsightsProfilePresentation.visitAnalyticsLines(from: profilePack) : [],
            serverHistory: aggregateState == nil ? serverHistory : [],
            localHistory: localHistory,
            notes: notes,
            possibleMatchCount: localReport?.possibleMatches.count ?? 0,
            warningTitles: localReport?.warnings.map(\.title) ?? [],
            loadingState: loadingState,
            freshness: freshness,
            showsLocalPreferences: aggregateState == nil && profilePack == nil && localReport != nil,
            showsLocalBookingHistory: aggregateState == nil && serverHistory.isEmpty && localReport != nil,
            showsSupplementalLocalHistory: aggregateState != nil ? localReport != nil : localCachedHistory != nil,
            localHistorySectionTitle: localCachedHistory?.sectionTitle,
            localHistoryScopeNote: aggregateState != nil ? "Offline supplement based on reservations saved on this device." : localCachedHistory?.scopeNote,
            traceKey: mergedContext?.traceKey
                ?? store.semanticProfileStamp(for: reservationID, dateKey: dateKey)
        )

        let source: String
        if aggregateState != nil {
            source = localReport != nil ? "aggregate_profile+local_supplement" : "aggregate_profile"
        } else if profilePack != nil, localReport != nil, !isAnalyzingLocalCache {
            source = "profile_pack+local_report"
        } else if localReport != nil {
            source = "merged"
        } else {
            source = "profile_pack"
        }
        FacadeTrace.build(
            surface: "guest_profile",
            duration: started.duration(to: .now).pressureTraceTimeInterval,
            extra: "source=\(source) reservation=\(reservation.remoteID)"
        )

        return built
    }

    private static func hasProfileSummaryContent(_ summary: GuestProfileSummaryState?) -> Bool {
        guard let summary else { return false }
        let text = summary.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !text.isEmpty || !summary.managementNotes.isEmpty
    }

    private static func fallbackHistoryDetail(
        profilePack: GuestIntelligenceProfilePackDTO?,
        isLoadingProfile: Bool
    ) -> String {
        if profilePack != nil {
            return "Server guest profile loaded."
        }
        if isLoadingProfile {
            return "Guest history loading…"
        }
        return "Found in local cache when server profile is not ready."
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
