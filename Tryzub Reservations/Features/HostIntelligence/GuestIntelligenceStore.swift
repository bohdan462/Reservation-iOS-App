//
//  GuestIntelligenceStore.swift
//  Tryzub Reservations
//
//  Shared server-backed guest intelligence cache for Host, Detail, and Guest Insights.
//

import Foundation

enum GuestServerProfileFetchStatus: String, Equatable {
    case loaded
    case failed
    case notFetched

    var displayLabel: String {
        switch self {
        case .loaded: return "loaded"
        case .failed: return "failed"
        case .notFetched: return "not fetched"
        }
    }
}

struct GuestIntelligenceDiagnosticsSnapshot: Equatable {
    var selectedDateKey: String?
    var dateSummaryLoaded: Bool
    var summariesCount: Int
    var profileCacheCount: Int
    var lastMergedSourceByReservationID: [Int: String]
    /// Present when `diagnosticsSnapshot` is called with a reservation ID.
    var serverProfileStatus: String?
}

struct GuestIntelligenceReservationDiagnostics: Equatable {
    var reservationID: Int
    var summaryExists: Bool
    var profileLoaded: Bool
    var dateSummaryLoaded: Bool
    var dateSummarySource: String?
    var profileSource: String?
    var mergedSource: String?
    var backendSeenBefore: Bool
    var backendPriorCount: Int?
    var backendLastSeen: String?
    var localPriorCount: Int
    var metricsSource: String?
    var bookingHistoryScope: String?
    var finalDisplayedHistory: String?
    var semanticTraceKey: String?
    var lastTraceEmittedAt: Date?
    var profileError: String?
    var profilePackVersion: String?
    var profilePackPreviewRows: Int?
    var profilePackHasNotes: Bool?
    var profilePackHasHostPacket: Bool?
    var profilePackSectionPresence: String?
    var serverProfileStatus: String?
}

@MainActor
final class GuestIntelligenceStore: ObservableObject {
    @Published private(set) var responsesByDateKey: [String: GuestIntelligenceDayResponseDTO] = [:]
    @Published private(set) var loadedAtByDateKey: [String: Date] = [:]
    @Published private(set) var errorByDateKey: [String: String] = [:]
    @Published private(set) var profilePackByReservationID: [Int: GuestIntelligenceProfilePackDTO] = [:]
    @Published private(set) var profileByReservationID: [Int: GuestIntelligenceSummaryDTO] = [:]
    @Published private(set) var profileLoadedAtByReservationID: [Int: Date] = [:]
    @Published private(set) var profileErrorByReservationID: [Int: String] = [:]

    private var loadingDateKeys: Set<String> = []
    private var loadingProfileReservationIDs: Set<Int> = []
    private var loadDebounceTask: Task<Void, Never>?
    private var pendingDateKey: String?
    private(set) var selectedDateKey: String?
    private var lastMergedSourceByReservationID: [Int: String] = [:]
    private var profileSourceByReservationID: [Int: String] = [:]
    private var detailOpenedAtByReservationID: [Int: ContinuousClock.Instant] = [:]
    private var lastMergeTraceKeyBySurfaceReservationID: [String: String] = [:]
    private var lastMergeTraceEmittedAtBySurfaceReservationID: [String: Date] = [:]

    private let apiClient: any ReservationsAPIClientProtocol
    private let freshnessInterval: TimeInterval = 180
    private let loadDebounceInterval: TimeInterval = 1.0

    init(apiClient: any ReservationsAPIClientProtocol) {
        self.apiClient = apiClient
    }

    // MARK: - Lookup

    func response(for dateKey: String) -> GuestIntelligenceDayResponseDTO? {
        responsesByDateKey[normalizedDateKey(dateKey)]
    }

    func summariesByReservationID(for dateKey: String) -> [Int: GuestIntelligenceSummaryDTO] {
        let key = normalizedDateKey(dateKey)
        guard let items = responsesByDateKey[key]?.items else { return [:] }
        return Dictionary(
            items.map { ($0.reservationId, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    func profilePack(for reservationID: Int) -> GuestIntelligenceProfilePackDTO? {
        profilePackByReservationID[reservationID]
    }

    func matchedVisitPreview(for reservationID: Int) -> [GuestIntelligenceMatchedVisitPreviewDTO] {
        profilePack(for: reservationID)?.matchedVisitPreview ?? []
    }

    func hostProfilePacket(for reservationID: Int) -> GuestIntelligenceHostProfilePacketDTO? {
        profilePack(for: reservationID)?.hostProfilePacket
    }

    func profileDiagnostics(for reservationID: Int) -> GuestIntelligenceProfilePackDiagnostics? {
        guard let pack = profilePack(for: reservationID) else { return nil }
        let preview = pack.matchedVisitPreview
        let hasNotes = preview.contains { $0.hasGuestNotes || $0.hasStaffNotes }
            || pack.noteIntelligence?.latestGuestNotePreview?.isEmpty == false
            || pack.noteIntelligence?.latestStaffNotePreview?.isEmpty == false
        return GuestIntelligenceProfilePackDiagnostics(
            reservationID: reservationID,
            profilePackVersion: pack.profilePackVersion,
            source: profileSourceByReservationID[reservationID],
            hasHistory: pack.history != nil,
            hasProfileSummary: pack.profileSummary != nil,
            hasPreferences: pack.preferences != nil,
            hasNoteIntelligence: pack.noteIntelligence != nil,
            hasVisitAnalytics: pack.visitAnalytics != nil,
            hasHostProfilePacket: pack.hostProfilePacket != nil,
            previewRowCount: preview.count,
            hasNotes: hasNotes
        )
    }

    /// Unified lookup: full profile pack summary first, then date-level summary.
    func summary(for reservationID: Int, dateKey: String) -> GuestIntelligenceSummaryDTO? {
        if let packSummary = profilePack(for: reservationID)?.resolvedSummary {
            return packSummary
        }
        if let profile = profileByReservationID[reservationID] {
            return profile
        }
        return summariesByReservationID(for: dateKey)[reservationID]
    }

    func hasDateSummaryLoaded(dateKey: String) -> Bool {
        responsesByDateKey[normalizedDateKey(dateKey)] != nil
    }

    func hasProfileLoaded(reservationID: Int) -> Bool {
        profilePackByReservationID[reservationID] != nil || profileByReservationID[reservationID] != nil
    }

    func hasFullProfilePack(reservationID: Int) -> Bool {
        profilePackByReservationID[reservationID] != nil
            && profileSourceByReservationID[reservationID] == "reservation_endpoint"
    }

    func hasServerAnswer(for reservationID: Int, dateKey: String) -> Bool {
        if profileLoadedAtByReservationID[reservationID] != nil {
            return true
        }
        return hasDateSummaryLoaded(dateKey: dateKey)
    }

    func isLoading(dateKey: String) -> Bool {
        loadingDateKeys.contains(normalizedDateKey(dateKey))
    }

    func isLoadingProfile(reservationID: Int) -> Bool {
        loadingProfileReservationIDs.contains(reservationID)
    }

    func error(for dateKey: String) -> String? {
        errorByDateKey[normalizedDateKey(dateKey)]
    }

    func profileError(for reservationID: Int) -> String? {
        profileErrorByReservationID[reservationID]
    }

    func loadedAt(for dateKey: String) -> Date? {
        loadedAtByDateKey[normalizedDateKey(dateKey)]
    }

    func profileLoadedAt(for reservationID: Int) -> Date? {
        profileLoadedAtByReservationID[reservationID]
    }

    func cacheStamp(for dateKey: String) -> String {
        let key = normalizedDateKey(dateKey)
        let loadedStamp = loadedAtByDateKey[key]?.timeIntervalSince1970 ?? 0
        let response = responsesByDateKey[key]
        let generatedAt = response?.generatedAt ?? ""
        let itemCount = response?.items.count ?? 0
        return "\(key)-\(loadedStamp)-\(generatedAt)-\(itemCount)"
    }

    func profileCacheStamp(for reservationID: Int) -> String {
        let loadedStamp = profileLoadedAtByReservationID[reservationID]?.timeIntervalSince1970 ?? 0
        let classification = profileByReservationID[reservationID]?.classification
        return "\(reservationID)-\(loadedStamp)-\(classification.map { String(describing: $0) } ?? "none")"
    }

    func profilePacks(for reservationIDs: [Int]) -> [Int: GuestIntelligenceProfilePackDTO] {
        var result: [Int: GuestIntelligenceProfilePackDTO] = [:]
        for reservationID in reservationIDs {
            if let pack = profilePack(for: reservationID) {
                result[reservationID] = pack
            }
        }
        return result
    }

    func profilePackCacheStamp(for reservationIDs: [Int]) -> String {
        reservationIDs
            .map { semanticProfileStamp(for: $0, dateKey: selectedDateKey ?? "") }
            .joined(separator: "|")
    }

    /// Stable stamp for merge/trace dedupe — excludes volatile load timestamps.
    func semanticProfileStamp(for reservationID: Int, dateKey: String) -> String {
        let summary = summary(for: reservationID, dateKey: dateKey)
        let profilePack = profilePack(for: reservationID)
        let serverAnswered = hasServerAnswer(for: reservationID, dateKey: dateKey)
        let backendSeenBefore = GuestHistorySemantics.isBackendSeenBefore(
            serverSummary: summary,
            profilePack: profilePack
        )
        let mergedSource = GuestHistorySemantics.serverBackedMergeSource(
            serverSummary: summary,
            serverAnswered: serverAnswered,
            profilePack: profilePack
        )
        return GuestHistorySemantics.semanticMergeDedupeKey(
            surface: "profile",
            reservationID: reservationID,
            mergedSource: mergedSource,
            backendSeenBefore: backendSeenBefore,
            localPriorCount: -1,
            profilePack: profilePack
        )
    }

    func serverProfileFetchStatus(for reservationID: Int) -> GuestServerProfileFetchStatus {
        if let error = profileError(for: reservationID)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty {
            return .failed
        }
        if hasFullProfilePack(reservationID: reservationID) {
            return .loaded
        }
        if profileSourceByReservationID[reservationID] == "reservation_endpoint",
           profilePack(for: reservationID) != nil {
            return .loaded
        }
        return .notFetched
    }

    func diagnosticsSnapshot(
        dateKey: String,
        reservationID: Int? = nil
    ) -> GuestIntelligenceDiagnosticsSnapshot {
        let key = normalizedDateKey(dateKey)
        let serverProfileStatus = reservationID.map {
            serverProfileFetchStatus(for: $0).displayLabel
        }
        return GuestIntelligenceDiagnosticsSnapshot(
            selectedDateKey: selectedDateKey,
            dateSummaryLoaded: responsesByDateKey[key] != nil,
            summariesCount: responsesByDateKey[key]?.items.count ?? 0,
            profileCacheCount: profileByReservationID.count,
            lastMergedSourceByReservationID: lastMergedSourceByReservationID,
            serverProfileStatus: serverProfileStatus
        )
    }

    func markDetailOpened(reservationID: Int) {
        detailOpenedAtByReservationID[reservationID] = .now
    }

    func sinceOpenMs(reservationID: Int) -> Int? {
        guard let openedAt = detailOpenedAtByReservationID[reservationID] else { return nil }
        return Int(openedAt.duration(to: .now).pressureTraceTimeInterval * 1000)
    }

    func recordMergePresentation(
        surface: String,
        reservationID: Int,
        guestName: String,
        localReport: GuestInsightReport,
        selectedReservation: ReservationRecord,
        reservationPool: [ReservationRecord],
        dateKey: String,
        semanticStamp: String
    ) {
        let serverSummary = summary(for: reservationID, dateKey: dateKey)
        let serverAnswered = hasServerAnswer(for: reservationID, dateKey: dateKey)
        let profilePack = profilePack(for: reservationID)
        let mergeStarted = ContinuousClock.now
        let merged = GuestHistorySemantics.mergedHistoryLine(
            guestName: guestName,
            localReport: localReport,
            serverSummary: serverSummary,
            serverAnswered: serverAnswered,
            profilePack: profilePack,
            selectedReservation: selectedReservation,
            reservationPool: reservationPool,
            truthSurface: surface
        )
        let mergeDurationMs = Int(mergeStarted.duration(to: .now).pressureTraceTimeInterval * 1000)
        let backendSeenBefore = GuestHistorySemantics.isBackendSeenBefore(
            serverSummary: serverSummary,
            profilePack: profilePack
        )
        let dedupeKey = GuestHistorySemantics.semanticMergeDedupeKey(
            surface: surface,
            reservationID: reservationID,
            mergedSource: merged.source,
            backendSeenBefore: backendSeenBefore,
            localPriorCount: localReport.priorReliableVisitCount,
            profilePack: profilePack
        )
        _ = semanticStamp

        let changed = GuestIntelTrace.mergedIfChanged(
            surface: surface,
            reservationID: reservationID,
            dedupeKey: dedupeKey,
            source: merged.source.rawValue,
            localPrior: localReport.priorReliableVisitCount,
            backendSeenBefore: backendSeenBefore,
            durationMs: mergeDurationMs
        )
        guard changed else { return }

        lastMergedSourceByReservationID[reservationID] = merged.source.rawValue
        lastMergeTraceKeyBySurfaceReservationID["\(surface)-\(reservationID)"] = dedupeKey
        lastMergeTraceEmittedAtBySurfaceReservationID["\(surface)-\(reservationID)"] = Date()

        if merged.source == .backendSeenBefore || merged.source == .localReliablePriorVisits {
            GuestIntelTrace.detailIfChanged(
                surface: surface,
                reservationID: reservationID,
                dedupeKey: dedupeKey,
                shown: true,
                source: GuestHistorySemantics.detailTraceSource(for: merged.source),
                sinceOpenMs: sinceOpenMs(reservationID: reservationID)
            )
        }
    }

    func reservationDiagnostics(
        reservationID: Int,
        dateKey: String,
        localReport: GuestInsightReport,
        guestName: String,
        surface: String = "diagnostics"
    ) -> GuestIntelligenceReservationDiagnostics {
        let key = normalizedDateKey(dateKey)
        let summary = summary(for: reservationID, dateKey: key)
        let serverAnswered = hasServerAnswer(for: reservationID, dateKey: key)
        let semanticStamp = semanticProfileStamp(for: reservationID, dateKey: key)
        let profilePack = profilePack(for: reservationID)
        let packDiagnostics = profileDiagnostics(for: reservationID)
        let mergedContext = GuestHistorySemantics.insightsMergedContext(
            guestName: guestName,
            localReport: localReport,
            serverSummary: summary,
            serverAnswered: serverAnswered,
            profileStamp: semanticStamp,
            profilePack: profilePack
        )
        let surfaceKey = "\(surface)-\(reservationID)"
        return GuestIntelligenceReservationDiagnostics(
            reservationID: reservationID,
            summaryExists: summary != nil,
            profileLoaded: hasProfileLoaded(reservationID: reservationID),
            dateSummaryLoaded: hasDateSummaryLoaded(dateKey: key),
            dateSummarySource: hasDateSummaryLoaded(dateKey: key) ? "date_endpoint" : nil,
            profileSource: profileSourceByReservationID[reservationID],
            mergedSource: lastMergedSourceByReservationID[reservationID] ?? mergedContext.mergedSource.rawValue,
            backendSeenBefore: summary.map { GuestHistorySemantics.isServerReturning($0) } ?? false,
            backendPriorCount: GuestHistorySemantics.reliableBackendPriorCount(summary),
            backendLastSeen: GuestHistorySemantics.serverLastSeenDisplay(
                summary,
                mergedSource: mergedContext.mergedSource
            ),
            localPriorCount: localReport.priorReliableVisitCount,
            metricsSource: mergedContext.metrics.source.rawValue,
            bookingHistoryScope: mergedContext.bookingHistory.scope.rawValue,
            finalDisplayedHistory: mergedContext.historyTitle,
            semanticTraceKey: mergedContext.traceKey,
            lastTraceEmittedAt: lastMergeTraceEmittedAtBySurfaceReservationID[surfaceKey],
            profileError: profileError(for: reservationID),
            profilePackVersion: packDiagnostics?.profilePackVersion,
            profilePackPreviewRows: packDiagnostics?.previewRowCount,
            profilePackHasNotes: packDiagnostics?.hasNotes,
            profilePackHasHostPacket: packDiagnostics?.hasHostProfilePacket,
            profilePackSectionPresence: packDiagnostics.map(profileSectionPresenceLabel),
            serverProfileStatus: serverProfileFetchStatus(for: reservationID).displayLabel
        )
    }

    private func profileSectionPresenceLabel(_ diagnostics: GuestIntelligenceProfilePackDiagnostics) -> String {
        var sections: [String] = []
        if diagnostics.hasHistory { sections.append("history") }
        if diagnostics.hasProfileSummary { sections.append("profile_summary") }
        if diagnostics.hasPreferences { sections.append("preferences") }
        if diagnostics.hasNoteIntelligence { sections.append("note_intelligence") }
        if diagnostics.hasVisitAnalytics { sections.append("visit_analytics") }
        if diagnostics.hasHostProfilePacket { sections.append("host_profile_packet") }
        return sections.isEmpty ? "none" : sections.joined(separator: ",")
    }

    // MARK: - Fetch Scheduling

    func scheduleLoad(dateKey: String, force: Bool = false, isSelectedDate: Bool = true) {
        let key = normalizedDateKey(dateKey)
        guard !key.isEmpty else { return }

        if !force, isFresh(key), responsesByDateKey[key] != nil {
            return
        }

        if let previous = pendingDateKey, previous != key {
            DateLoadTrace.cancelled(date: previous, reason: "date_changed")
            StartupPolicyTrace.guestIntelligenceCancelled(date: previous, reason: "date_changed")
        }

        let delayMs = Int(ceil(loadDebounceInterval * 1000))
        DateLoadTrace.scheduled(date: key, type: "guest_intelligence", delayMs: delayMs)
        StartupPolicyTrace.guestIntelligenceScheduled(
            date: key,
            selected: isSelectedDate,
            delaySeconds: Int(ceil(loadDebounceInterval))
        )

        if isSelectedDate {
            selectedDateKey = key
        }
        pendingDateKey = key
        loadDebounceTask?.cancel()
        loadDebounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.loadDebounceInterval))
            guard !Task.isCancelled else { return }
            guard self.pendingDateKey == key else { return }
            await self.load(dateKey: key, force: force)
            self.loadDebounceTask = nil
        }
    }

    /// Ensures server-backed summary is available without blocking the caller.
    func ensureSummary(reservationID: Int, dateKey: String, force: Bool = false) {
        let key = normalizedDateKey(dateKey)
        guard reservationID > 0, !key.isEmpty else { return }

        if !hasDateSummaryLoaded(dateKey: key) || force {
            scheduleLoad(dateKey: key, force: force, isSelectedDate: false)
        }

        if !force,
           hasFullProfilePack(reservationID: reservationID),
           isProfileFresh(reservationID: reservationID) {
            return
        }

        if !force,
           summary(for: reservationID, dateKey: key) != nil,
           hasFullProfilePack(reservationID: reservationID) {
            return
        }

        guard needsReservationProfileEndpoint(reservationID: reservationID, force: force) else {
            return
        }

        Task { [weak self] in
            await self?.loadProfile(reservationID: reservationID, dateKey: key, force: force)
        }
    }

    func needsReservationProfileEndpoint(reservationID: Int, force: Bool = false) -> Bool {
        if force { return true }
        if hasFullProfilePack(reservationID: reservationID) {
            return !isProfileFresh(reservationID: reservationID)
        }
        if let pack = profilePack(for: reservationID),
           profileSourceByReservationID[reservationID] == "reservation_endpoint",
           !pack.matchedVisitPreview.isEmpty,
           isProfileFresh(reservationID: reservationID) {
            return false
        }
        return true
    }

    func cancelScheduledLoad(reason: String = "visibility") {
        if let previous = pendingDateKey {
            DateLoadTrace.cancelled(date: previous, reason: reason)
            StartupPolicyTrace.guestIntelligenceCancelled(date: previous, reason: reason)
        }
        pendingDateKey = nil
        loadDebounceTask?.cancel()
        loadDebounceTask = nil
    }

    func load(dateKey: String, force: Bool = false) async {
        let key = normalizedDateKey(dateKey)
        guard !key.isEmpty else { return }
        guard !loadingDateKeys.contains(key) else { return }

        if !force, isFresh(key), let cached = responsesByDateKey[key] {
            GuestIntelTrace.dateSummaryCompleted(
                date: key,
                count: cached.items.count,
                durationMs: 0,
                cacheHit: true
            )
            return
        }

        loadingDateKeys.insert(key)
        defer { loadingDateKeys.remove(key) }

        let started = ContinuousClock.now
        GuestIntelTrace.dateSummaryStart(date: key)

        do {
            let response = try await apiClient.fetchGuestIntelligence(
                date: key,
                reason: .guestIntelligence
            )
            let selectedMismatch = selectedDateKey != key
            adoptDateResponse(response, dateKey: key)
            let durationMs = Int(started.duration(to: .now).pressureTraceTimeInterval * 1000)
            DateLoadTrace.completed(date: key, type: "guest_intelligence", durationMs: durationMs)
            GuestIntelTrace.dateSummaryCompleted(
                date: key,
                count: response.items.count,
                durationMs: durationMs,
                cacheHit: false
            )
            GuestIntelTrace.dateSummaryCached(date: key, selectedMismatch: selectedMismatch)

            if selectedMismatch {
                DateLoadTrace.ignoredResponse(date: key, reason: "not_selected")
            }
            errorByDateKey.removeValue(forKey: key)
        } catch {
            guard !error.isCancellationLike else {
                DateLoadTrace.cancelled(date: key, reason: "cancelled")
                return
            }
            guard selectedDateKey == key else {
                DateLoadTrace.ignoredResponse(date: key, reason: "not_selected")
                return
            }
            errorByDateKey[key] = IntelligenceStoreMessaging.displayMessage(for: error)
        }
    }

    func loadProfile(
        reservationID: Int,
        dateKey: String,
        force: Bool = false
    ) async {
        guard reservationID > 0 else { return }

        if !force,
           isProfileFresh(reservationID: reservationID),
           hasFullProfilePack(reservationID: reservationID) {
            let pack = profilePack(for: reservationID)
            GuestIntelTrace.profileStart(reservationID: reservationID, cacheHit: true)
            GuestIntelTrace.profileCompleted(reservationID: reservationID, durationMs: 0, cacheHit: true)
            GuestProfileTrace.profilePackDecoded(
                reservationID: reservationID,
                previewRows: pack?.matchedVisitPreview.count ?? 0,
                managementNotes: pack?.profileSummary?.managementNotes.count ?? 0,
                noteSignalBuckets: pack?.noteIntelligence?.allNoteSignals.count ?? 0,
                hasHostPacket: pack?.hostProfilePacket != nil,
                durationMs: 0,
                cacheHit: true
            )
            return
        }

        guard !loadingProfileReservationIDs.contains(reservationID) else { return }
        loadingProfileReservationIDs.insert(reservationID)
        defer { loadingProfileReservationIDs.remove(reservationID) }

        let started = ContinuousClock.now
        GuestIntelTrace.profileStart(reservationID: reservationID, cacheHit: false)

        do {
            let pack = try await apiClient.fetchGuestIntelligenceProfile(
                reservationID: reservationID,
                reason: .guestIntelligence
            )
            adoptProfilePack(pack, reservationID: reservationID, source: "reservation_endpoint")
            profileErrorByReservationID.removeValue(forKey: reservationID)
            let durationMs = Int(started.duration(to: .now).pressureTraceTimeInterval * 1000)
            GuestIntelTrace.profileCompleted(
                reservationID: reservationID,
                durationMs: durationMs,
                cacheHit: false
            )
            let previewRows = pack.matchedVisitPreview.count
            GuestProfileTrace.profilePackDecoded(
                reservationID: reservationID,
                previewRows: previewRows,
                managementNotes: pack.profileSummary?.managementNotes.count ?? 0,
                noteSignalBuckets: pack.noteIntelligence?.allNoteSignals.count ?? 0,
                hasHostPacket: pack.hostProfilePacket != nil,
                durationMs: durationMs,
                cacheHit: false
            )
            if previewRows > 0 {
                GuestProfileTrace.profileSection(
                    reservationID: reservationID,
                    source: "profile_endpoint",
                    section: "matched_visit_preview",
                    rows: previewRows
                )
            }
        } catch {
            guard !error.isCancellationLike else { return }
            if case ReservationAPIError.serverError(let code, _) = error, code == 404 {
                profileLoadedAtByReservationID[reservationID] = Date()
                profileErrorByReservationID.removeValue(forKey: reservationID)
                return
            }
            profileErrorByReservationID[reservationID] = IntelligenceStoreMessaging.displayMessage(for: error)
        }
    }

    func reset() {
        cancelScheduledLoad()
        responsesByDateKey = [:]
        loadedAtByDateKey = [:]
        errorByDateKey = [:]
        profilePackByReservationID = [:]
        profileByReservationID = [:]
        profileLoadedAtByReservationID = [:]
        profileErrorByReservationID = [:]
        loadingProfileReservationIDs = []
        lastMergedSourceByReservationID = [:]
        profileSourceByReservationID = [:]
        detailOpenedAtByReservationID = [:]
        lastMergeTraceKeyBySurfaceReservationID = [:]
        lastMergeTraceEmittedAtBySurfaceReservationID = [:]
    }

    // MARK: - Private

    private func adoptDateResponse(
        _ response: GuestIntelligenceDayResponseDTO,
        dateKey: String
    ) {
        let key = normalizedDateKey(dateKey)
        responsesByDateKey[key] = response
        loadedAtByDateKey[key] = Date()
        for item in response.items where item.reservationId > 0 {
            let reservationID = item.reservationId
            if profileSourceByReservationID[reservationID] == "reservation_endpoint",
               profilePackByReservationID[reservationID] != nil {
                if profileByReservationID[reservationID] == nil {
                    profileByReservationID[reservationID] = item
                }
                continue
            }

            let pack = GuestIntelligenceProfilePackDTO.fromLegacySummary(item)
            adoptProfilePack(pack, reservationID: reservationID, source: "date_endpoint")
        }
    }

    private func adoptProfilePack(
        _ pack: GuestIntelligenceProfilePackDTO,
        reservationID: Int,
        source: String
    ) {
        let resolvedID = pack.reservationId > 0 ? pack.reservationId : reservationID
        let storedPack: GuestIntelligenceProfilePackDTO
        if pack.reservationId == 0, reservationID > 0 {
            storedPack = pack.replacingReservationID(reservationID)
        } else {
            storedPack = pack
        }

        if source == "reservation_endpoint"
            || profilePackByReservationID[resolvedID] == nil
            || profileSourceByReservationID[resolvedID] != "reservation_endpoint" {
            profilePackByReservationID[resolvedID] = storedPack
        }

        if let summary = storedPack.resolvedSummary {
            profileByReservationID[resolvedID] = summary
        }

        profileLoadedAtByReservationID[resolvedID] = Date()
        if source == "reservation_endpoint"
            || profileSourceByReservationID[resolvedID] != "reservation_endpoint" {
            profileSourceByReservationID[resolvedID] = source
        }
    }

    private func isProfileFresh(reservationID: Int) -> Bool {
        guard let loadedAt = profileLoadedAtByReservationID[reservationID] else { return false }
        return Date().timeIntervalSince(loadedAt) < freshnessInterval
    }

    private func normalizedDateKey(_ dateKey: String) -> String {
        dateKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isFresh(_ key: String) -> Bool {
        guard let loadedAt = loadedAtByDateKey[key] else { return false }
        return Date().timeIntervalSince(loadedAt) < freshnessInterval
    }
}
