//
//  HostBoardView.swift
//  Tryzub Reservations
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Host Board

struct HostBoardView: View {
    // Cached reservations for the selected service date.
    let reservations: [ReservationRecord]
    var allKnownReservations: [ReservationRecord] = []
    let environment: AppEnvironment
    @Binding var selectedDate: Date
    let failedImportCount: Int
    let isVisible: Bool
    var deferNetworkLoads: Bool = false
    let isAppActive: Bool
    let externalInteractionActive: Bool
    let onAddReservation: () -> Void
    let onManualRefresh: () -> Void
    let onShowFormProblems: () -> Void
    let onOpenReservation: (ReservationRecord) -> Void
    var onOpenFloorSetup: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var hostIntentStore: HostReservationOpenIntentStore
    @EnvironmentObject private var restaurantSettingsStore: RestaurantSettingsStore
    @EnvironmentObject private var guestIntelligenceStore: GuestIntelligenceStore
    @EnvironmentObject private var hostIntelligenceSettingsStore: HostIntelligenceSettingsStore
    @EnvironmentObject private var hostTableConfigStore: HostTableConfigStore
    @EnvironmentObject private var hostIntelligenceController: HostIntelligenceController
    @EnvironmentObject private var hiddenReservations: HiddenReservationsStore
    @EnvironmentObject private var floorPlanStore: FloorPlanStore
    @EnvironmentObject private var activityStore: ReservationActivityStore
    @EnvironmentObject private var emailAutomationSettingsStore: EmailAutomationSettingsStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var pendingAction: ReservationPendingAction?
    @State private var showBackendReminderConfirmation = false
    @State private var clockTick = Date()
    @State private var boardSnapshotsByDateKey: [String: HostBoardSnapshot] = [:]
    /// Last known non-zero reservation count per date key, used to suppress
    /// transient 0-reservation snapshots during tab/visibility transitions.
    @State private var stableCountByDate: [String: Int] = [:]
    @ObservedObject private var onDeviceSupportCoordinator = HostLocalModelAutoPrepareCoordinator.shared
    @State private var isShowingHostIntelligenceReview = false
    @State private var showReminderStats = false
    /// Phase 2: cached deterministic Service Briefing, rebuilt only when inputs change
    /// (selected date, reservations, snapshot, coarse hour bucket) — never from a fetch.
    @State private var serviceBriefingState: HostServiceBriefingViewState?
    /// Tracks the stamp used for the last service briefing build; used to skip no-op rebuilds.
    @State private var lastBuiltServiceBriefingStamp: String = ""
    /// Phase 4: concise booking-load heads-up for the busiest window, shown only during
    /// before/during service. Rebuilt with the briefing (cache-only, no fetch).
    @State private var bookingTopItem: BookingSuggestionViewItem?
    @State private var bookingKnownOnlyNote: String = ""
    @StateObject private var hostBoardViewStateStore = HostBoardViewStateStore()
    /// Single lifecycle coordinator — replaces two independent .task(id:) pipelines
    /// for availability and guest intelligence scheduling.
    @StateObject private var lifecycleCoordinator = HostBoardLifecycleCoordinator()
    @State private var hostBoardHeaderCollapse: CGFloat = 0
    @State private var isPressureExpanded = false
    @State private var hostIntelligenceCardPresentation: HostIntelligenceCardPresentation = .empty
    /// Tracks the presentation key used for the last card build; used to skip no-op card rebuilds.
    @State private var lastBuiltCardInputKey: String = ""
    @AppStorage("host.liveModeEnabled") private var liveHostModeEnabled = false

    private var hasOpenInteraction: Bool {
        externalInteractionActive
            || pendingAction != nil
            || showReminderStats
            || showBackendReminderConfirmation
    }

    /// Narrower gate for Host's own auto-refresh loop.
    /// Detail presentation gates Host UI work (snapshot/evaluate/enrichment/card) via
    /// `externalInteractionActive`, but must not suppress active-window live sync.
    /// Only active edit/create sheets and mutation confirm dialogs block the network call.
    private var hasSyncBlockingInteraction: Bool {
        pendingAction != nil
            || showBackendReminderConfirmation
    }

    private var shouldDeferStartupOptionalLoads: Bool {
        switch controller.startupPresentationState {
        case .checkingCache, .emptyCacheLoadingNetwork:
            return !controller.hasReleasedStartupUI
        case .loadingSavedReservations, .showingCachedDataRefreshing, .ready, .failedNoCache:
            return !controller.canStartNoncriticalStartupLoads
        }
    }

    // Open→close service window for the busy-by-time chart x-axis. Prefers the
    // day availability hours, then public slot bounds; nil falls back to data range.
    private var serviceWindow: ClosedRange<Int>? {
        func hour(_ value: String?) -> Int? {
            guard let value, let h = Int(value.prefix(2)) else { return nil }
            return h
        }

        if let open = hour(todayAvailability?.openTime),
           let close = hour(todayAvailability?.closeTime),
           open <= close {
            return open...close
        }

        let slotHours = (todaySlots?.slots ?? []).compactMap { hour($0.value) }
        if let lo = slotHours.min(), let hi = slotHours.max(), lo <= hi {
            return lo...hi
        }

        return nil
    }

    private var serviceDensityBounds: (open: Date?, close: Date?) {
        let dateKey = selectedDate.reservationDateString()
        func serviceDate(from timeValue: String?) -> Date? {
            guard let timeValue else { return nil }
            let trimmed = timeValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let time = trimmed.count >= 5 ? String(trimmed.prefix(5)) : trimmed
            return ReservationFormatters.serverDateMinute.date(from: "\(dateKey) \(time)")
        }

        if let open = serviceDate(from: todayAvailability?.openTime),
           let close = serviceDate(from: todayAvailability?.closeTime),
           open <= close {
            return (open, close)
        }

        if let window = serviceWindow {
            let open = serviceDate(from: String(format: "%02d:00", window.lowerBound))
            let close = serviceDate(from: String(format: "%02d:00", window.upperBound))
            return (open, close)
        }

        return (nil, nil)
    }

    private var isRunningForPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private var selectedDateKey: String {
        selectedDate.reservationDateString()
    }

    private var currentDateBoardSnapshot: HostBoardSnapshot? {
        guard let snapshot = boardSnapshotsByDateKey[selectedDateKey],
              snapshot.selectedDate.reservationDateString() == selectedDateKey else {
            return nil
        }
        return snapshot
    }

    private var showsReservationLoadingPlaceholder: Bool {
        reservations.isEmpty
            && (stableCountByDate[selectedDateKey] ?? 0) > 0
            && currentDateBoardSnapshot == nil
    }

    private func boardSnapshotRenderContext(
        serviceDensityBounds: (open: Date?, close: Date?)
    ) -> (snapshot: HostBoardSnapshot, source: HostBoardSnapshotRenderSource) {
        if let cached = currentDateBoardSnapshot {
            return (cached, .cached)
        }

        if showsReservationLoadingPlaceholder {
            let loadingSnapshot = HostBoardSnapshot(
                reservations: [],
                selectedDate: selectedDate,
                now: clockTick,
                serviceOpen: serviceDensityBounds.open,
                serviceClose: serviceDensityBounds.close,
                largePartyThreshold: hostIntelligenceSettingsStore.settings.largePartyThreshold
            )
            return (loadingSnapshot, .loading)
        }

        let fallback = HostBoardSnapshot(
            reservations: reservations,
            selectedDate: selectedDate,
            now: clockTick,
            serviceOpen: serviceDensityBounds.open,
            serviceClose: serviceDensityBounds.close,
            largePartyThreshold: hostIntelligenceSettingsStore.settings.largePartyThreshold
        )
        return (fallback, .fallback)
    }

    private var availabilitySummary: ReservationAvailabilitySummary? {
        controller.availabilitySummary(for: selectedDateKey)
    }

    private var todayAvailability: RestaurantDayAvailabilityDTO? {
        availabilitySummary?.availability
    }

    private var todaySlots: ReservationSlotsResponseDTO? {
        availabilitySummary?.slots
    }

    private var todayBlockedSlots: [RestaurantBlockedSlotDTO] {
        availabilitySummary?.blockedSlots ?? []
    }

    private var availabilitySummaryError: String? {
        controller.availabilitySummaryError(for: selectedDateKey)
    }

    private var isLoadingAvailabilitySummary: Bool {
        controller.isAvailabilitySummaryLoading(date: selectedDateKey)
    }

    private var hostIntelligenceReservationStamp: Int {
        var hasher = Hasher()
        for reservation in reservations {
            hasher.combine(reservation.remoteID)
            hasher.combine(reservation.statusValue.rawValue)
            hasher.combine(reservation.tableName ?? "")
            hasher.combine(reservation.displayTime)
            hasher.combine(reservation.partySize)
        }
        return hasher.finalize()
    }

    private var hostIntelligenceSeatedStamp: Int {
        var hasher = Hasher()
        for (id, seatedAt) in controller.localSeatedAtByReservationID.sorted(by: { $0.key < $1.key }) {
            hasher.combine(id)
            hasher.combine(seatedAt.timeIntervalSince1970)
        }
        return hasher.finalize()
    }

    private var hostFloorLegacyOptions: (allowsFallback: Bool, localActiveTableCount: Int) {
        let settings = hostIntelligenceSettingsStore.settings
        return (
            settings.useLegacyAdvisoryTableFallback,
            hostTableConfigStore.activeTables.count
        )
    }

    private var hostFloorTableSource: HostFloorTableSource {
        let options = hostFloorLegacyOptions
        return floorPlanStore.floorSourceStatus(
            for: selectedDateKey,
            allowsLegacyFallback: options.allowsFallback,
            localActiveTableCount: options.localActiveTableCount
        )
    }

    /// Local deterministic Host facts: reservations, date, seated times, settings.
    /// History cache enrichment is intentionally excluded; guest intelligence uses `hostIntelligenceEnrichmentKey`.
    /// Clock minute is intentionally excluded: minute-only ticks must not rerun the full engine.
    /// Time-sensitive row labels are handled by the snapshot via boardSnapshotBuildKey which
    /// includes hostBoardSnapshotTimingRefreshStamp (minute-aware, gated to today + time-sensitive rows).
    private var hostIntelligenceEvaluationKey: String {
        let options = hostFloorLegacyOptions
        return "\(selectedDateKey)-\(hostIntelligenceReservationStamp)-\(hostIntelligenceSeatedStamp)-\(hostIntelligenceSettingsStore.settings.hostDecisionFingerprint)-\(floorPlanStore.layoutFingerprint(for: selectedDateKey, allowsLegacyFallback: options.allowsFallback, localActiveTableCount: options.localActiveTableCount))"
    }

    private var hostIntelligenceEvaluationTaskKey: String {
        guard !liveHostModeEnabled, !externalInteractionActive else {
            return "paused-\(liveHostModeEnabled)-\(externalInteractionActive)"
        }
        return hostIntelligenceEvaluationKey
    }

    private var hostHistoryEnrichmentGenerationKey: String {
        "\(controller.historyCacheEnrichmentGeneration)"
    }

    /// Enrichment-only inputs that may update narrative later without blocking local facts.
    private var hostIntelligenceEnrichmentKey: String {
        let availabilityStamp = availabilitySummary?.loadedAt.timeIntervalSince1970 ?? 0
        let guestIntelStamp = guestIntelligenceStore.cacheStamp(for: selectedDateKey)
        let analyticsStamp = analyticsSummaryIdentity
        let profilePackStamp = guestIntelligenceStore.profilePackCacheStamp(
            for: reservations.map(\.remoteID)
        )
        let options = hostFloorLegacyOptions
        return "\(selectedDateKey)-\(availabilityStamp)-\(guestIntelStamp)-\(analyticsStamp)-\(profilePackStamp)-\(floorPlanStore.layoutFingerprint(for: selectedDateKey, allowsLegacyFallback: options.allowsFallback, localActiveTableCount: options.localActiveTableCount))"
    }

    private var hostIntelligenceEnrichmentTaskKey: String {
        guard !liveHostModeEnabled, !externalInteractionActive else {
            return "paused-\(liveHostModeEnabled)-\(externalInteractionActive)"
        }
        return hostIntelligenceEnrichmentKey
    }

    private var hostBoardOperationalLoading: Bool {
        guard selectedDateKey == Date.reservationDateString() else { return false }
        return isLoadingAvailabilitySummary
            || guestIntelligenceStore.isLoading(dateKey: selectedDateKey)
            || hostFloorTableSource == .pendingBackend
    }

    private var hostIntelligenceOperationalMinuteStamp: String {
        guard selectedDateKey == Date.reservationDateString() else {
            return "future-day"
        }
        let components = Calendar.current.dateComponents([.hour, .minute], from: clockTick)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return "op-minute-\(hour * 60 + minute)"
    }

    private var hostBoardSnapshotTimingRefreshStamp: String {
        guard selectedDateKey == Date.reservationDateString() else {
            return "snapshot-time-stable"
        }
        guard hasHostBoardTimeSensitiveRows(now: clockTick) else {
            return "snapshot-time-stable"
        }
        return hostIntelligenceOperationalMinuteStamp
    }

    private func hasHostBoardTimeSensitiveRows(now: Date) -> Bool {
        reservations.contains { reservation in
            switch reservation.statusValue {
            case .seated:
                return true
            case .new, .needsReview, .confirmed:
                guard let reservationAt = hostBoardReservationDateTime(for: reservation) else {
                    return false
                }
                let secondsUntilReservation = reservationAt.timeIntervalSince(now)
                return secondsUntilReservation <= TimeInterval(90 * 60)
            case .completed, .cancelled, .noShow:
                return false
            }
        }
    }

    private func hostBoardReservationDateTime(for reservation: ReservationRecord) -> Date? {
        let rawTime = reservation.reservationTime.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reservation.reservationDate.isEmpty, !rawTime.isEmpty else { return nil }
        if let date = ReservationFormatters.serverDateTime.date(from: "\(reservation.reservationDate) \(rawTime)") {
            return date
        }
        let minuteTime = rawTime.count >= 5 ? String(rawTime.prefix(5)) : rawTime
        return ReservationFormatters.serverDateMinute.date(from: "\(reservation.reservationDate) \(minuteTime)")
    }

    private var hostEvaluationStabilityContext: HostEvaluationStabilityContext {
        let dateNavigationRecent: Bool = {
            guard let navigationAt = controller.hostBoardDateNavigationAt else { return false }
            return clockTick.timeIntervalSince(navigationAt) < HostBriefingHostBoardGate.dateNavigationCooldown
        }()
        return HostEvaluationStabilityContext(
            isReservationRefreshInFlight: controller.isReservationNetworkRefreshInFlight,
            isAvailabilitySummaryLoading: isLoadingAvailabilitySummary,
            isGuestIntelligenceLoading: guestIntelligenceStore.isLoading(dateKey: selectedDateKey),
            selectedDateRecentlyChanged: dateNavigationRecent,
            hostSnapshotIncomplete: shouldDeferStartupOptionalLoads || deferNetworkLoads
        )
    }

    /// How long after a date tap the intelligence/presentation pipeline waits before running.
    /// Sized to absorb rapid tapping across multiple date chips without running evaluate for
    /// every skipped date. Same-day reservation/status changes are not caused by date navigation
    /// so `isHostDateNavigationRecent()` returns false and evaluate remains immediate.
    private static let intelligenceStabilityWindow: TimeInterval = 0.40

    /// Returns true when the staff last tapped a Host date chip within the stability window.
    /// Uses `controller.hostBoardDateNavigationAt` (set by `noteHostBoardSelectedDate`),
    /// which is non-@Published so this call does not create SwiftUI dependency churn.
    private func isHostDateNavigationRecent() -> Bool {
        guard let navigationAt = controller.hostBoardDateNavigationAt else { return false }
        return Date().timeIntervalSince(navigationAt) < HostBoardView.intelligenceStabilityWindow
    }

    /// True when the Host intelligence controller has completed a local evaluate pass for
    /// the current selected date. Gates card rebuild, enrichment, and live card rendering
    /// to prevent old-date facts publishing under a new selected date key.
    private var isHostIntelligenceReadyForSelectedDate: Bool {
        hostIntelligenceController.isEvaluatedForSelectedDate(selectedDateKey)
    }

    private var analyticsSummaryIdentity: String {
        guard hostIntelligenceController.settings.includeAnalyticsSignals,
              let summary = restaurantSettingsStore.analyticsSummary else {
            return "analytics-none"
        }
        let loadedAt = restaurantSettingsStore.analyticsLoadedAt?.timeIntervalSince1970 ?? 0
        return "analytics-\(summary.byHour.count)-\(summary.byWeekday.count)-\(summary.range?.from ?? "")-\(summary.range?.to ?? "")-\(loadedAt)"
    }

    private var cachedAnalyticsSummary: ReservationAnalyticsSummaryDTO? {
        guard hostIntelligenceController.settings.includeAnalyticsSignals else { return nil }
        return restaurantSettingsStore.analyticsSummary
    }

    private var boardSnapshotBuildKey: String {
        // Mirrors the evaluate/enrichment paused-key pattern: while a reservation detail
        // is presented (or settling after pop) the snapshot task becomes stable so the
        // background reactive work stops competing with the navigation animation.
        guard !externalInteractionActive else {
            return "paused-snapshot-\(externalInteractionActive)"
        }
        let options = hostFloorLegacyOptions
        return "\(selectedDateKey)-\(hostIntelligenceReservationStamp)-\(hostBoardSnapshotTimingRefreshStamp)-\(hostTableConfigStore.tableConfigFingerprint)-\(floorPlanStore.layoutFingerprint(for: selectedDateKey, allowsLegacyFallback: options.allowsFallback, localActiveTableCount: options.localActiveTableCount))"
    }

    var body: some View {
        GeometryReader { proxy in
            let safeWidth = proxy.size.width.tryzubFiniteNonNegativeLayoutValue
            let safeHeight = proxy.size.height.tryzubFinitePositiveLayoutValue
            let isTablet = UIDevice.current.userInterfaceIdiom == .pad
            let isWideLayout = isTablet || safeWidth >= 1100
            let densityBounds = serviceDensityBounds
            let renderContext = boardSnapshotRenderContext(serviceDensityBounds: densityBounds)
            let snapshot = renderContext.snapshot
            let showsReservationLoading = renderContext.source == .loading

            let closedPresentation = closedDayPresentation(for: snapshot)

            TryzubHostBoardCanvas {
                Group {
                    if isTablet {
                        hostBoardScrollView(
                            snapshot: snapshot,
                            closedPresentation: closedPresentation,
                            isWideLayout: isWideLayout,
                            safeWidth: safeWidth,
                            includesHeader: false,
                            tracksHeaderCollapse: true,
                            showsReservationLoadingPlaceholder: showsReservationLoading
                        )
                        .safeAreaInset(edge: .top, spacing: 0) {
                            homeServiceHeader(usesInlineDateStrip: true)
                                .padding(.horizontal, 16)
                                .padding(.top, HostBoardHeaderCollapse.lerp(8, 4, hostBoardHeaderCollapse))
                                .padding(.bottom, HostBoardHeaderCollapse.lerp(4, 1, hostBoardHeaderCollapse))
                                .background(Color.clear)
                                .zIndex(10)
                        }
                    } else {
                        hostBoardScrollView(
                            snapshot: snapshot,
                            closedPresentation: closedPresentation,
                            isWideLayout: isWideLayout,
                            safeWidth: safeWidth,
                            includesHeader: true,
                            showsReservationLoadingPlaceholder: showsReservationLoading
                        )
                    }
                }
            }
            .frame(width: safeWidth, height: safeHeight, alignment: .top)
            #if DEBUG
            .onAppear {
                traceHostLayout(width: safeWidth, isWideLayout: isWideLayout)
                traceHostBoardRenderTransition(
                    source: renderContext.source,
                    snapshot: snapshot,
                    reservationsCount: reservations.count
                )
            }
            .onChange(of: hostLayoutTraceID(width: safeWidth, isWideLayout: isWideLayout)) { _, _ in
                traceHostLayout(width: safeWidth, isWideLayout: isWideLayout)
            }
            .onChange(of: "\(selectedDateKey)|\(renderContext.source.rawValue)") { _, _ in
                traceHostBoardRenderTransition(
                    source: renderContext.source,
                    snapshot: snapshot,
                    reservationsCount: reservations.count
                )
            }
            #endif
        }
        .alert(
            pendingActionTitle,
            isPresented: Binding(
                get: { pendingAction != nil && isVisible },
                set: { if !$0 { pendingAction = nil } }
            ),
            actions: {
                if let pendingAction {
                    if pendingAction.action == .confirmOnly {
                        Button(pendingAction.reservation.hasUsableConfirmationEmail ? "Open to confirm" : "Confirm only") {
                            Task {
                                await perform(.confirmOnly, on: pendingAction.reservation)
                            }
                        }

                        ReservationConfirmDialog.backendEmailButton(
                            hasUsableEmail: pendingAction.reservation.hasUsableConfirmationEmail
                        ) {
                            Task {
                                await perform(.confirmAndSendEmail, on: pendingAction.reservation)
                            }
                        }
                    } else {
                        Button(pendingAction.action.fullTitle, role: pendingAction.action.role) {
                            Task {
                                await perform(pendingAction.action, on: pendingAction.reservation)
                            }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingAction = nil
                }
            },
            message: {
                if let pendingAction {
                    Text(pendingAction.action.dialogMessage(for: pendingAction.reservation))
                }
            }
        )
        .confirmationDialog(
            "Send reminders to confirmed guests for today?",
            isPresented: $showBackendReminderConfirmation,
            titleVisibility: .visible
        ) {
            Button("Send Today’s Reminders") {
                Task {
                    await controller.sendDueReminders(for: selectedDateKey, context: modelContext)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This calls the backend reminder batch once. Nothing is sent from iOS directly.")
        }
        .task(id: isVisible && isAppActive) {
            // Starts/stops the auto-refresh loop when Today is visible and app is active.
            guard !isRunningForPreviews else { return }
            await runAutoRefreshLoop()
        }
        .task(id: isVisible) {
            guard !isRunningForPreviews else { return }
            await runClockLoop()
        }
        .task(id: "activity-feed-\(isVisible)-\(deferNetworkLoads)-\(selectedDateKey)-\(hostActivityFeedWarmKey)") {
            await warmVisibleActivityFeedIfNeeded()
        }
        .task(id: boardSnapshotBuildKey) {
            guard !isRunningForPreviews else { return }
            guard !externalInteractionActive else {
                #if DEBUG
                print("[HOST_NAV_GATE_TRACE] work=snapshot decision=skip reason=detail_presented")
                #endif
                traceHostBoardStabilization(event: "snapshot_skipped", detail: "reason=detail_presented")
                return
            }
            traceHostBoardStabilization(event: "snapshot_started", detail: "date=\(selectedDateKey)")
            let started = ContinuousClock.now
            let densityBounds = serviceDensityBounds
            let built = HostBoardSnapshot(
                reservations: reservations,
                selectedDate: selectedDate,
                now: clockTick,
                serviceOpen: densityBounds.open,
                serviceClose: densityBounds.close,
                largePartyThreshold: hostIntelligenceSettingsStore.settings.largePartyThreshold,
                effectiveTableAssignments: floorPlanStore.effectiveTableAssignments(for: selectedDateKey)
            )
            let incomingCount = reservations.count
            let lastStableCount = stableCountByDate[selectedDateKey] ?? 0
            let cachedSnapshot = boardSnapshotsByDateKey[selectedDateKey]
            let cachedMatchesSelectedDate = cachedSnapshot?.selectedDate.reservationDateString() == selectedDateKey

            // Snapshot preservation: if the incoming count is 0 but this date previously
            // had reservations, do not overwrite the stable snapshot. This guards against
            // stale transient-empty snapshots that can slip through if the parent's
            // selectedDateReservations momentarily returns [] (e.g. during view init or
            // edge-case timing before the @Query observer fires on tab return).
            if incomingCount == 0, lastStableCount > 0, cachedMatchesSelectedDate {
                MultiDeviceSyncTrace.hostSnapshotPreserve(
                    date: selectedDateKey,
                    incomingCount: incomingCount,
                    lastStableCount: lastStableCount,
                    preserve: true,
                    reason: "untrusted_empty"
                )
                traceHostBoardSnapshotSkipEmpty(
                    date: selectedDateKey,
                    lastStableCount: lastStableCount
                )
                traceHostBoardStabilization(event: "snapshot_skipped", detail: "reason=untrusted_empty")
                return
            }

            // Commit the snapshot and update stable count.
            if incomingCount > 0 {
                stableCountByDate[selectedDateKey] = incomingCount
            }
            boardSnapshotsByDateKey[selectedDateKey] = built
            traceHostBoardSnapshotPublish(
                date: selectedDateKey,
                count: built.upcoming.count + built.seated.count
            )
            let preserveReason = incomingCount > 0 ? "has_data" : "trusted_empty"
            MultiDeviceSyncTrace.hostSnapshotPreserve(
                date: selectedDateKey,
                incomingCount: incomingCount,
                lastStableCount: lastStableCount,
                preserve: false,
                reason: preserveReason
            )
            UIPressureTrace.phase(
                "host_snapshot_build",
                duration: started.duration(to: .now).pressureTraceTimeInterval,
                extra: "date=\(selectedDateKey) reservations=\(reservations.count)"
            )
            MultiDeviceSyncTrace.hostRender(
                selectedDate: selectedDateKey,
                reservations: reservations.count,
                visibleIDs: reservations.map(\.remoteID)
            )
            traceHostBoardStabilization(event: "snapshot_completed", detail: "date=\(selectedDateKey)")
        }
        .onChange(of: selectedDateKey) { _, dateKey in
            controller.noteHostBoardSelectedDate(dateKey)
            // Synchronously clear controller's old-date intelligence before any task
            // can read displaySnapshot/displayAttentionPresentation/displayBriefingText.
            hostIntelligenceController.beginSelectedDateTransition(to: dateKey)
            // Clear all local date-sensitive presentation state so prior-date card/briefing
            // content cannot render under the new date key.
            hostIntelligenceCardPresentation = .empty
            serviceBriefingState = nil
            bookingTopItem = nil
            bookingKnownOnlyNote = ""
            lastBuiltCardInputKey = ""
            lastBuiltServiceBriefingStamp = ""
        }
        .onAppear {
            hostIntelligenceController.updateDeveloperDiagnosticsAccess(
                controller.capabilities.canViewDeveloperDiagnostics
            )
            controller.noteHostBoardSelectedDate(selectedDateKey)
            controller.refreshHomeServicePresentation(hostOperationalLoading: hostBoardOperationalLoading)
        }
        .onChange(of: controller.capabilities.canViewDeveloperDiagnostics) { _, canView in
            hostIntelligenceController.updateDeveloperDiagnosticsAccess(canView)
        }
        .task(id: "reminder-status-\(isVisible)-\(liveHostModeEnabled)-\(selectedDateKey)-\(emailAutomationSettingsStore.settings.automaticReminderProofEnabled)-\(emailAutomationSettingsStore.settings.manualReminderSendEnabled)-\(controller.restaurantSetup.manualBatchRemindersEnabled)") {
            guard isVisible,
                  !liveHostModeEnabled,
                  selectedDateKey == Date.reservationDateString(),
                  emailAutomationSettingsStore.settings.automaticReminderProofEnabled
                    || emailAutomationSettingsStore.settings.manualReminderSendEnabled
                    || controller.restaurantSetup.manualBatchRemindersEnabled else { return }
            _ = await controller.refreshReminderStatus(for: selectedDateKey)
        }
        .onChange(of: hostBoardViewStateObservationKey, initial: true) { _, _ in
            guard !liveHostModeEnabled, !externalInteractionActive else {
                traceHostBoardStabilization(event: "view_state_skipped", detail: "reason=presentation_hidden")
                return
            }
            guard !isHostDateNavigationRecent() else {
                traceHostBoardStabilization(event: "view_state_skipped", detail: "reason=date_navigation")
                return
            }
            refreshHostBoardViewState(reason: "semantic_key_changed")
        }
        .onChange(of: serviceBriefingObservationKey, initial: true) { _, _ in
            guard !liveHostModeEnabled, !externalInteractionActive else {
                traceHostBoardStabilization(event: "service_briefing_skipped", detail: "reason=presentation_hidden")
                return
            }
            guard !isHostDateNavigationRecent() else {
                traceHostBoardStabilization(event: "service_briefing_skipped", detail: "reason=date_navigation")
                return
            }
            rebuildServiceBriefing()
        }
        .task(id: hostIntelligenceCardTaskKey) {
            guard isHostIntelligenceCardVisible else {
                #if DEBUG
                if externalInteractionActive {
                    print("[HOST_NAV_GATE_TRACE] work=card decision=skip reason=detail_presented")
                }
                #endif
                traceHostBoardStabilization(event: "card_presentation_skipped", detail: "reason=hidden")
                return
            }
            let requestedDateKey = selectedDateKey
            let requestedKey = hostIntelligenceCardPresentationKey
            traceHostBoardStabilization(event: "card_presentation_yielded")
            await Task.yield()
            guard !Task.isCancelled,
                  isHostIntelligenceCardVisible,
                  selectedDateKey == requestedDateKey,
                  requestedKey == hostIntelligenceCardPresentationKey else {
                traceHostBoardStabilization(event: "card_presentation_skipped", detail: "reason=cancelled_or_stale")
                return
            }
            // Require controller to have evaluated for the current date before building the
            // card. Prevents old-date displaySnapshot/displayAttentionPresentation from being
            // published under the new date's presentation key.
            guard isHostIntelligenceReadyForSelectedDate else {
                #if DEBUG
                print("[HOST_NOOP_CPU_GATE_TRACE] work=card decision=skip reason=awaiting_evaluate date=\(selectedDateKey)")
                #endif
                traceHostBoardStabilization(event: "card_presentation_skipped", detail: "reason=awaiting_evaluate")
                return
            }
            traceHostBoardStabilization(event: "card_presentation_started")
            let published = rebuildHostIntelligenceCardPresentation(expectedKey: requestedKey, expectedDateKey: requestedDateKey)
            traceHostBoardStabilization(
                event: published ? "card_presentation_completed" : "card_presentation_skipped",
                detail: published ? "" : "reason=key_changed"
            )
        }
        // Single coordinated task replaces the two independent availability +
        // guest-intelligence tasks. Floor plan fetch is scheduled immediately on Host
        // visibility (never deferred). Availability/guest intel may defer during startup.
        .task(id: "\(isVisible)-\(deferNetworkLoads)-\(controller.canStartNoncriticalStartupLoads)-\(selectedDateKey)") {
            guard !isRunningForPreviews else { return }
            lifecycleCoordinator.handle(
                isVisible: isVisible,
                date: selectedDateKey,
                shouldDefer: deferNetworkLoads || shouldDeferStartupOptionalLoads,
                controller: controller,
                guestIntelligenceStore: guestIntelligenceStore,
                floorPlanStore: floorPlanStore
            )
        }
        .task(id: hostIntelligenceEvaluationTaskKey) {
            guard isVisible else {
                hostIntelligenceController.reset()
                return
            }
            guard !liveHostModeEnabled, !externalInteractionActive else {
                #if DEBUG
                if externalInteractionActive {
                    print("[HOST_NAV_GATE_TRACE] work=evaluate decision=skip reason=detail_presented")
                }
                #endif
                traceHostBoardStabilization(event: "evaluate_skipped", detail: "reason=presentation_hidden")
                return
            }
            // Clock minute is intentionally removed from hostIntelligenceEvaluationKey.
            // If this task fires, something operationally meaningful changed (reservation
            // stamp, seated stamp, settings, or floor layout). Minute-only ticks no longer
            // reach this path.
            #if DEBUG
            print("[HOST_NOOP_CPU_GATE_TRACE] work=evaluate decision=run reason=operational_change reservationStamp=\(hostIntelligenceReservationStamp) date=\(selectedDateKey)")
            #endif
            let requestedDateKey = selectedDateKey
            let requestedEvalKey = hostIntelligenceEvaluationTaskKey
            let wasDebounced = isHostDateNavigationRecent()
            if wasDebounced {
                traceHostBoardStabilization(event: "evaluate_debounced", detail: "duration_ms=\(Int(HostBoardView.intelligenceStabilityWindow * 1000)) date=\(requestedDateKey)")
                do {
                    try await Task.sleep(for: .seconds(HostBoardView.intelligenceStabilityWindow))
                } catch {
                    traceHostBoardStabilization(event: "evaluate_skipped", detail: "reason=cancelled_during_debounce")
                    return
                }
                guard !Task.isCancelled,
                      isVisible,
                      selectedDateKey == requestedDateKey,
                      hostIntelligenceEvaluationTaskKey == requestedEvalKey else {
                    traceHostBoardStabilization(event: "evaluate_skipped", detail: "reason=stale_after_debounce date=\(requestedDateKey)")
                    return
                }
            }
            HostReevalTrace.log(
                trigger: "selected_day_reservation_change",
                immediate: !wasDebounced
            )
            traceHostBoardStabilization(event: "evaluate_started", detail: "date=\(selectedDateKey)")
            let bookingReport = buildBookingLoadReport(bounds: serviceDensityBounds)
            hostIntelligenceController.evaluate(
                input: makeHostEngineInput(now: clockTick),
                stability: hostEvaluationStabilityContext,
                bookingLoadReport: bookingReport
            )
            traceHostBoardStabilization(event: "evaluate_completed", detail: "date=\(selectedDateKey)")
            // Rebuild presentation once after a debounced evaluation settles on the stable
            // date. The onChange handlers are suppressed during navigation, so this is the
            // only path that runs refreshHostBoardViewState / rebuildServiceBriefing for dates
            // where navigation was recent when the task started.
            if wasDebounced, !Task.isCancelled, selectedDateKey == requestedDateKey {
                traceHostBoardStabilization(event: "view_state_rebuild_after_debounce", detail: "date=\(selectedDateKey)")
                refreshHostBoardViewState(reason: "post_evaluate_debounce")
                rebuildServiceBriefing()
            }
        }
        .task(id: hostIntelligenceEnrichmentTaskKey) {
            guard isVisible else {
                traceHostBoardStabilization(event: "enrichment_skipped", detail: "reason=hidden")
                return
            }
            guard !liveHostModeEnabled, !externalInteractionActive else {
                #if DEBUG
                if externalInteractionActive {
                    print("[HOST_NAV_GATE_TRACE] work=enrichment decision=skip reason=detail_presented")
                }
                #endif
                traceHostBoardStabilization(event: "enrichment_skipped", detail: "reason=presentation_hidden")
                return
            }
            let requestedKey = hostIntelligenceEnrichmentKey
            // Capture date at task start for post-sleep stale checks.
            let requestedDateKey = selectedDateKey
            // Sleep longer than intelligenceStabilityWindow (400ms) so evaluate always runs
            // before enrichment can call refreshBriefing. Enrichment at 350ms was racing
            // ahead of evaluate's 400ms debounce, causing HOST_ATTENTION_GROUP_TRACE to log
            // the prior date while view date had already advanced.
            traceHostBoardStabilization(event: "enrichment_debounced", detail: "duration_ms=450")
            do {
                try await Task.sleep(nanoseconds: 450_000_000)
            } catch {
                traceHostBoardStabilization(event: "enrichment_skipped", detail: "reason=cancelled")
                return
            }
            guard !Task.isCancelled, requestedKey == hostIntelligenceEnrichmentKey else {
                traceHostBoardStabilization(event: "enrichment_skipped", detail: "reason=cancelled_or_stale")
                return
            }
            // Require controller to have evaluated for the current date before enriching.
            // Prevents refreshBriefing from operating on prior-date decisionSnapshot/
            // attentionPresentation, which would cause HOST_ATTENTION_GROUP_TRACE to log
            // the old date while enrichment_started logs the new date.
            guard selectedDateKey == requestedDateKey,
                  hostIntelligenceController.isEvaluatedForSelectedDate(requestedDateKey) else {
                #if DEBUG
                print("[HOST_NOOP_CPU_GATE_TRACE] work=enrichment decision=skip reason=awaiting_evaluate date=\(selectedDateKey)")
                #endif
                traceHostBoardStabilization(event: "enrichment_skipped", detail: "reason=awaiting_evaluate")
                return
            }
            traceHostBoardStabilization(event: "enrichment_started", detail: "date=\(selectedDateKey)")
            let options = hostFloorLegacyOptions
            let floorSource = hostFloorTableSource
            let layoutStamp = floorPlanStore.layoutFingerprint(
                for: selectedDateKey,
                allowsLegacyFallback: options.allowsFallback,
                localActiveTableCount: options.localActiveTableCount
            )
            let guestGeneration = [
                guestIntelligenceStore.cacheStamp(for: selectedDateKey),
                guestIntelligenceStore.profilePackCacheStamp(for: reservations.map(\.remoteID))
            ].joined(separator: "|")
            let bookingReport = buildBookingLoadReport(bounds: serviceDensityBounds)
            await hostIntelligenceController.refreshBriefing(
                hostBoardContext: HostBriefingHostBoardContext(
                    selectedDateKey: selectedDateKey,
                    floorSourceLabel: floorSource.traceLabel,
                    layoutFingerprint: layoutStamp,
                    guestIntelligenceGeneration: guestGeneration,
                    isStartupNetworkPassInFlight: controller.isStartupNetworkPassInFlight,
                    isHistoryPrefetching: controller.isHistoryPrefetching,
                    isLocalModelInferenceActive: HostLocalModelInferenceTracker.isActive,
                    isReservationRefreshInFlight: controller.isReservationNetworkRefreshInFlight,
                    isAvailabilitySummaryLoading: controller.isAvailabilitySummaryLoading(date: selectedDateKey),
                    isGuestIntelligenceLoading: guestIntelligenceStore.isLoading(dateKey: selectedDateKey),
                    hostBoardDateNavigationAt: controller.hostBoardDateNavigationAt,
                    startupUIReleasedAt: controller.startupUIReleasedAt,
                    now: clockTick
                ),
                bookingLoadReport: bookingReport
            )
            guard !Task.isCancelled, requestedKey == hostIntelligenceEnrichmentKey else {
                traceHostBoardStabilization(event: "enrichment_skipped", detail: "reason=stale_completion")
                return
            }
            traceHostBoardStabilization(event: "enrichment_completed", detail: "date=\(selectedDateKey)")
        }
        .onChange(of: hostBoardOperationalLoading) { _, isLoading in
            // Coalesce to the next runloop tick. refreshHomeServicePresentation publishes
            // controller state that feeds back into hostBoardOperationalLoading; updating
            // it synchronously inside onChange caused SwiftUI's "tried to update multiple
            // times per frame" churn during startup.
            Task { @MainActor in
                await Task.yield()
                controller.refreshHomeServicePresentation(hostOperationalLoading: isLoading)
            }
        }
        .sheet(isPresented: $showReminderStats) {
            HostReminderStatsSheet(
                context: hostReminderPanelContext,
                onSend: {
                    showReminderStats = false
                    showBackendReminderConfirmation = true
                }
            )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var pendingActionTitle: String {
        guard let pendingAction else {
            return "Update Reservation?"
        }

        return pendingAction.action.dialogTitle(for: pendingAction.reservation)
    }

    private func wideBoard(
        snapshot: HostBoardSnapshot,
        showsReservationLoadingPlaceholder: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            HostBoardColumn(
                title: "Seated",
                subtitle: seatedGuestSubtitle(for: snapshot),
                reservations: snapshot.seated,
                emptyTitle: "No one seated",
                emptySystemImage: "person.2.slash",
                scrollsInternally: false,
                referenceNow: snapshot.now,
                showsServiceGroupHeader: true,
                environment: environment,
                onAction: handleAction,
                onOpenReservation: onOpenReservation
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)

            HomeReservationsPanel(
                snapshot: snapshot,
                referenceNow: snapshot.now,
                scrollsInternally: false,
                showsReservationLoadingPlaceholder: showsReservationLoadingPlaceholder,
                environment: environment,
                onAction: handleAction,
                onOpenReservation: onOpenReservation
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var hostBoardViewStateObservationKey: String {
        guard !liveHostModeEnabled, !externalInteractionActive else {
            return "presentation-hidden-\(liveHostModeEnabled)-\(externalInteractionActive)"
        }
        return hostBoardViewStateBuildKey
    }

    private var hostActivityFeedWarmKey: String {
        reservations
            .map { "\($0.remoteID):\($0.guestName)" }
            .joined(separator: ",")
    }

    private var guestNameByVisibleReservationID: [Int: String] {
        reservations.reduce(into: [Int: String]()) { result, reservation in
            result[reservation.remoteID] = reservation.guestName
        }
    }

    private func warmVisibleActivityFeedIfNeeded() async {
        guard isVisible, !deferNetworkLoads, !isRunningForPreviews else { return }
        let dateKey = selectedDateKey
        let date = selectedDate
        let lastInteractionAt = controller.lastStaffInteractionAt
        let idleDelay = StaffInteractionIdleGate.remainingDelay(since: lastInteractionAt)
        if idleDelay > 0 {
            StaffInteractionIdleGate.trace(
                work: "activity_warm",
                decision: "schedule_after_idle",
                reason: "user_active",
                lastInteractionAt: lastInteractionAt,
                delay: idleDelay
            )
            try? await Task.sleep(for: .seconds(idleDelay))
            guard !Task.isCancelled else { return }
            guard selectedDateKey == dateKey,
                  StaffInteractionIdleGate.isIdle(since: controller.lastStaffInteractionAt) else {
                StaffInteractionIdleGate.trace(
                    work: "activity_warm",
                    decision: "skip",
                    reason: "user_active",
                    lastInteractionAt: controller.lastStaffInteractionAt
                )
                return
            }
        }
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard !Task.isCancelled else { return }
        guard selectedDateKey == dateKey else {
            return
        }
        StaffInteractionIdleGate.trace(
            work: "activity_warm",
            decision: "run",
            reason: "idle",
            lastInteractionAt: controller.lastStaffInteractionAt
        )
        await activityStore.loadActivityFeed(
            date: date,
            perPage: 100,
            isWarmRequest: true,
            guestNameByReservationID: guestNameByVisibleReservationID
        )
    }

    private var hostBoardViewStateBuildKey: String {
        let availabilityStamp = [
            controller.restaurantDayAvailabilityLoadedAt(for: selectedDateKey),
            controller.reservationSlotsLoadedAt(for: selectedDateKey)
        ].compactMap { $0 }.max()?.timeIntervalSince1970 ?? 0
        return [
            selectedDateKey,
            "\(hostIntelligenceReservationStamp)",
            "\(availabilityStamp)",
            hostIntelligenceController.briefingText,
            hostIntelligenceController.decisionSnapshot.templateBriefingText,
            hostIntelligenceController.briefingSource.rawValue,
            "\(hostBoardOperationalLoading)",
            "\(hostIntelligenceController.renderState)",
            "\(hostIntelligenceController.isEnrichmentLoading)",
            "\(failedImportCount)"
        ].joined(separator: "|")
    }

    private var availabilitySummaryLine: String? {
        guard selectedDate.reservationDateString() == Date.reservationDateString() else { return nil }
        return hostBoardViewStateStore.viewState?.availabilityLine
    }

    private func refreshHostBoardViewState(reason: String) {
        hostBoardViewStateStore.rebuildIfNeeded(key: hostBoardViewStateBuildKey, reason: reason) {
            HostBoardViewStateBuilder.build(
                selectedDate: selectedDate,
                reservations: reservations,
                failedImportCount: failedImportCount,
                availabilityState: ReservationAvailabilityFacade.dayState(
                    controller: controller,
                    date: selectedDateKey
                ),
                hostIntelligenceEnabled: hostIntelligenceSettingsStore.settings.isEnabled,
                briefingText: hostIntelligenceController.briefingText,
                templateBriefingText: hostIntelligenceController.decisionSnapshot.templateBriefingText,
                briefingSource: hostIntelligenceController.briefingSource,
                operationalLoading: hostBoardOperationalLoading,
                hostRenderState: hostIntelligenceController.renderState,
                isEnrichmentLoading: hostIntelligenceController.isEnrichmentLoading
            )
        }
    }

    private func shortAvailabilityTime(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return String(value.prefix(5))
    }

    private enum ClosedDayPresentation {
        case open
        case closedEmpty
        case closedWithReservations
    }

    private var hasKnownAvailabilityForSelectedDate: Bool {
        todayAvailability != nil || todaySlots != nil
    }

    private var isSelectedDateClosed: Bool {
        if let availability = todayAvailability, !availability.isOpen {
            return true
        }
        if let slots = todaySlots, !slots.isOpen {
            return true
        }
        return false
    }

    private func closedDayPresentation(for snapshot: HostBoardSnapshot) -> ClosedDayPresentation {
        guard hasKnownAvailabilityForSelectedDate, isSelectedDateClosed else {
            return .open
        }

        let activeReservationCount = snapshot.upcoming.count + snapshot.seated.count
        if activeReservationCount > 0 {
            return .closedWithReservations
        }
        return .closedEmpty
    }

    @ViewBuilder
    private func homeServiceHeader(usesInlineDateStrip: Bool = false) -> some View {
        HomeServiceHeader(
            title: environment.role == .developer ? "Dev" : "Host",
            selectedDate: $selectedDate,
            statusPresentation: controller.homeServiceStatusPresentation,
            canCreateReservation: controller.capabilities.canCreateManualReservations,
            canViewFormProblems: controller.capabilities.canViewFailedImports
                && controller.capabilities.canViewDeveloperDiagnostics,
            failedImportCount: failedImportCount,
            onAddReservation: onAddReservation,
            onManualRefresh: onManualRefresh,
            onShowFormProblems: onShowFormProblems,
            onOpenTimeline: nil,
            onOpenReminderStats: selectedDateKey == Date.reservationDateString()
                ? { showReminderStats = true }
                : nil,
            collapseProgress: hostBoardHeaderCollapse,
            usesInlineDateStrip: usesInlineDateStrip,
            liveHostModeEnabled: $liveHostModeEnabled
        )
    }

    @ViewBuilder
    private func hostBoardScrollView(
        snapshot: HostBoardSnapshot,
        closedPresentation: ClosedDayPresentation,
        isWideLayout: Bool,
        safeWidth: CGFloat,
        includesHeader: Bool,
        tracksHeaderCollapse: Bool = false,
        showsReservationLoadingPlaceholder: Bool = false
    ) -> some View {
        let scrollView = ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if includesHeader {
                    homeServiceHeader()
                }

                if !liveHostModeEnabled {
                    onDeviceSupportStatusBanner
                }

                closedOrOperationalBody(
                    snapshot: snapshot,
                    closedPresentation: closedPresentation,
                    isWideLayout: isWideLayout,
                    availableWidth: safeWidth,
                    showsReservationLoadingPlaceholder: showsReservationLoadingPlaceholder
                )
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, isWideLayout ? 16 : 12)
            .padding(.top, includesHeader ? (isWideLayout ? 8 : 6) : 4)
            .padding(.bottom, ReservationLayout.scrollBottomInset + 12)
        }
        .contentMargins(.bottom, ReservationLayout.topLevelTabScrollBottomInset, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

        if tracksHeaderCollapse {
            scrollView
                .onScrollGeometryChange(for: CGFloat.self, of: { geometry in
                    max(0, geometry.contentOffset.y)
                }) { _, offset in
                    let progress = HostBoardHeaderCollapse.progress(forScrollOffset: offset)
                    let step: CGFloat = 0.05
                    let quantized = min(1, max(0, (progress / step).rounded() * step))
                    guard abs(quantized - hostBoardHeaderCollapse) >= step * 0.9 else { return }
                    hostBoardHeaderCollapse = quantized
                }
        } else {
            scrollView
        }
    }

    @ViewBuilder
    private func closedOrOperationalBody(
        snapshot: HostBoardSnapshot,
        closedPresentation: ClosedDayPresentation,
        isWideLayout: Bool,
        availableWidth: CGFloat,
        showsReservationLoadingPlaceholder: Bool = false
    ) -> some View {
        switch closedPresentation {
        case .closedEmpty:
            ClosedServiceDayView()
                .frame(maxHeight: isWideLayout ? .infinity : nil)

        case .closedWithReservations:
            VStack(alignment: .leading, spacing: 10) {
                ClosedDayReservationsNoticeView(
                    reservationCount: snapshot.upcoming.count + snapshot.seated.count,
                    newCount: snapshot.newReservations.count,
                    reviewCount: snapshot.needsReview.count
                )

                if !liveHostModeEnabled,
                   snapshot.newReservations.count + snapshot.needsReview.count > 0 {
                    closedDayBookingAttentionCard(snapshot: snapshot)
                }

                if isWideLayout {
                    HomeReservationsPanel(
                        snapshot: snapshot,
                        referenceNow: snapshot.now,
                        environment: environment,
                        onAction: handleAction,
                        onOpenReservation: onOpenReservation
                    )
                } else {
                    HomeReservationsPanel(
                        snapshot: snapshot,
                        referenceNow: snapshot.now,
                        scrollsInternally: false,
                        environment: environment,
                        onAction: handleAction,
                        onOpenReservation: onOpenReservation
                    )
                }
            }

        case .open:
            let usesWideStatusPanel = horizontalSizeClass == .regular && availableWidth >= 760

            VStack(alignment: .leading, spacing: 8) {
                if !liveHostModeEnabled {
                    hostOperationalStatusPanel(snapshot: snapshot, isWideLayout: usesWideStatusPanel)
                    HostBoardPressureSection(
                        snapshot: snapshot,
                        reservations: reservations,
                        isExpanded: $isPressureExpanded,
                        onOpenReservation: onOpenReservation
                    )
                }
                if !liveHostModeEnabled {
                    hostIntelligenceSection
                }

                if isWideLayout {
                    wideBoard(
                        snapshot: snapshot,
                        showsReservationLoadingPlaceholder: showsReservationLoadingPlaceholder
                    )
                } else {
                    phoneLists(
                        snapshot: snapshot,
                        showsReservationLoadingPlaceholder: showsReservationLoadingPlaceholder
                    )
                }
            }
            .animation(.snappy(duration: 0.32), value: isPressureExpanded)
        }
    }

    @ViewBuilder
    private func closedDayBookingAttentionCard(snapshot: HostBoardSnapshot) -> some View {
        let intelligenceSnapshot = hostIntelligenceController.decisionSnapshot

        VStack(alignment: .leading, spacing: 8) {
            Text("Booking attention")
                .font(.subheadline.weight(.semibold))

            Text(hostIntelligenceController.briefingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? intelligenceSnapshot.templateBriefingText
                : hostIntelligenceController.briefingText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .hostBoardGlassPanel(cornerRadius: 12)
    }

    @ViewBuilder
    private var onDeviceSupportStatusBanner: some View {
        if onDeviceSupportCoordinator.phase.showsHostTabStatus {
            OnDeviceSupportStatusBanner(
                phase: onDeviceSupportCoordinator.phase,
                style: .compact
            )
        }
    }

    @ViewBuilder
    private func hostOperationalKPIsSection(snapshot: HostBoardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if selectedDateKey == Date.reservationDateString(),
               guestIntelligenceStore.isLoading(dateKey: selectedDateKey),
               guestIntelligenceStore.response(for: selectedDateKey) == nil {
                TryzubSectionLoadingCard(
                    title: "Checking guest context…",
                    systemImage: "person.2"
                )
            }

            HostBoardSummaryCard(
                reservationCount: snapshot.upcoming.count + snapshot.seated.count,
                guestCount: snapshot.expectedGuestCount,
                newCount: snapshot.newReservations.count,
                reviewCount: snapshot.needsReview.count,
                failedImportCount: controller.capabilities.canViewDeveloperDiagnostics ? failedImportCount : 0,
                noTableCount: snapshot.noTableCount,
                arrivalPressure: snapshot.arrivalPressure,
                isSelectedDateToday: snapshot.selectedDate.reservationDateString() == Date.reservationDateString(),
                referenceNow: snapshot.now,
                availabilitySummary: availabilitySummaryLine,
                isAvailabilityLoading: isLoadingAvailabilitySummary,
                onRefreshAvailability: selectedDate.reservationDateString() == Date.reservationDateString()
                    ? { controller.ensureAvailabilitySummary(date: selectedDateKey, force: true) }
                    : nil,
                onOpenReservationByID: { remoteID in
                    if let reservation = reservations.first(where: { $0.remoteID == remoteID }) {
                        onOpenReservation(reservation)
                    }
                }
            )
        }
    }

    @ViewBuilder
    private func hostOperationalStatusPanel(snapshot: HostBoardSnapshot, isWideLayout: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if selectedDateKey == Date.reservationDateString(),
               guestIntelligenceStore.isLoading(dateKey: selectedDateKey),
               guestIntelligenceStore.response(for: selectedDateKey) == nil {
                TryzubSectionLoadingCard(
                    title: "Checking guest context…",
                    systemImage: "person.2"
                )
            }

            HostOperationalStatusPanel(
                reservationCount: snapshot.upcoming.count + snapshot.seated.count,
                guestCount: snapshot.expectedGuestCount,
                newCount: snapshot.newReservations.count,
                reviewCount: snapshot.needsReview.count,
                failedImportCount: controller.capabilities.canViewDeveloperDiagnostics ? failedImportCount : 0,
                noTableCount: snapshot.noTableCount,
                availabilitySummary: availabilitySummaryLine,
                isAvailabilityLoading: isLoadingAvailabilitySummary,
                isWideLayout: isWideLayout,
                onRefreshAvailability: selectedDate.reservationDateString() == Date.reservationDateString()
                    ? { controller.ensureAvailabilitySummary(date: selectedDateKey, force: true) }
                    : nil
            )
        }
    }

    @ViewBuilder
    private func hostRemindersAndIntelligenceSection() -> some View {
        hostIntelligenceSection
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func homeOperationalHeader(snapshot: HostBoardSnapshot, availableWidth: CGFloat) -> some View {
        let isTablet = UIDevice.current.userInterfaceIdiom == .pad
        let horizontalPadding = isTablet ? CGFloat(32) : CGFloat(24)
        let contentWidth = availableWidth - horizontalPadding
        
        // iPad or wide layout (width >= 700): stack reminders and intelligence horizontally
        // iPhone or narrow: keep vertical stacking
        let shouldUseHorizontalLayout = isTablet || contentWidth >= 700
        
        if shouldUseHorizontalLayout {
            // iPad/wide layout: summary full-width, then reminders + intelligence side-by-side
            VStack(alignment: .leading, spacing: 8) {
                if selectedDateKey == Date.reservationDateString(),
                   guestIntelligenceStore.isLoading(dateKey: selectedDateKey),
                   guestIntelligenceStore.response(for: selectedDateKey) == nil {
                    TryzubSectionLoadingCard(
                        title: "Checking guest context…",
                        systemImage: "person.2"
                    )
                }

                HostBoardSummaryCard(
                    reservationCount: snapshot.upcoming.count + snapshot.seated.count,
                    guestCount: snapshot.expectedGuestCount,
                    newCount: snapshot.newReservations.count,
                    reviewCount: snapshot.needsReview.count,
                    failedImportCount: controller.capabilities.canViewDeveloperDiagnostics ? failedImportCount : 0,
                    noTableCount: snapshot.noTableCount,
                    arrivalPressure: snapshot.arrivalPressure,
                    isSelectedDateToday: snapshot.selectedDate.reservationDateString() == Date.reservationDateString(),
                    referenceNow: snapshot.now,
                    availabilitySummary: availabilitySummaryLine,
                    isAvailabilityLoading: isLoadingAvailabilitySummary,
                    onRefreshAvailability: selectedDate.reservationDateString() == Date.reservationDateString()
                        ? { controller.ensureAvailabilitySummary(date: selectedDateKey, force: true) }
                        : nil,
                    onOpenReservationByID: { remoteID in
                        if let reservation = reservations.first(where: { $0.remoteID == remoteID }) {
                            onOpenReservation(reservation)
                        }
                    }
                )
                
                hostIntelligenceSection
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            // iPhone/narrow layout: keep vertical stacking (existing layout)
            VStack(alignment: .leading, spacing: 8) {
                if selectedDateKey == Date.reservationDateString(),
                   guestIntelligenceStore.isLoading(dateKey: selectedDateKey),
                   guestIntelligenceStore.response(for: selectedDateKey) == nil {
                    TryzubSectionLoadingCard(
                        title: "Checking guest context…",
                        systemImage: "person.2"
                    )
                }

                HostBoardSummaryCard(
                    reservationCount: snapshot.upcoming.count + snapshot.seated.count,
                    guestCount: snapshot.expectedGuestCount,
                    newCount: snapshot.newReservations.count,
                    reviewCount: snapshot.needsReview.count,
                    failedImportCount: controller.capabilities.canViewDeveloperDiagnostics ? failedImportCount : 0,
                    noTableCount: snapshot.noTableCount,
                    arrivalPressure: snapshot.arrivalPressure,
                    isSelectedDateToday: snapshot.selectedDate.reservationDateString() == Date.reservationDateString(),
                    referenceNow: snapshot.now,
                    availabilitySummary: availabilitySummaryLine,
                    isAvailabilityLoading: isLoadingAvailabilitySummary,
                    onRefreshAvailability: selectedDate.reservationDateString() == Date.reservationDateString()
                        ? { controller.ensureAvailabilitySummary(date: selectedDateKey, force: true) }
                        : nil,
                    onOpenReservationByID: { remoteID in
                        if let reservation = reservations.first(where: { $0.remoteID == remoteID }) {
                            onOpenReservation(reservation)
                        }
                    }
                )

                hostIntelligenceSection
            }
        }
    }

    private var hostReminderPanelContext: HostReminderPanelContext? {
        let settings = emailAutomationSettingsStore.settings
        let isToday = selectedDateKey == Date.reservationDateString()
        if isToday && (settings.automaticReminderProofEnabled || settings.manualReminderSendEnabled || controller.restaurantSetup.manualBatchRemindersEnabled) {
            let status = controller.lastReminderStatusByDate[selectedDateKey]
            let automation = ResolvedReminderAutomationSettings.resolving(
                setup: controller.restaurantSetup,
                status: status
            )
            let emailUsage = ResolvedEmailUsage.resolving(
                setup: controller.restaurantSetup,
                status: status
            )
            let eligibleCount = status?.summary.eligible ?? 0
            let hasEligibleReminders = eligibleCount > 0
            let dailyEmailLimitReached = emailUsage.hasUsageData && emailUsage.isDailyLimitReached
            let canSendBatchReminders = automation.manualBatchRemindersEnabled
                && hasEligibleReminders
                && !dailyEmailLimitReached

            let summary = HostReminderStaffSummary.build(
                status: status,
                automaticRemindersEnabled: automation.automaticRemindersEnabled,
                manualSendEnabled: settings.manualReminderSendEnabled,
                backendManualBatchEnabled: automation.manualBatchRemindersEnabled,
                reminderLeadHours: automation.reminderLeadHours,
                dailyEmailLimitReached: dailyEmailLimitReached,
                canSendBatchReminders: canSendBatchReminders,
                isLoading: settings.automaticReminderProofEnabled && status == nil
            )

            return HostReminderPanelContext(
                status: status,
                notice: controller.reminderBatchNotice,
                isSending: controller.isSendingReminderBatch,
                showProof: settings.automaticReminderProofEnabled,
                hasEligibleReminders: hasEligibleReminders,
                manualSendEnabled: settings.manualReminderSendEnabled,
                backendManualBatchEnabled: automation.manualBatchRemindersEnabled,
                automaticRemindersEnabled: automation.automaticRemindersEnabled,
                reminderLeadHours: automation.reminderLeadHours,
                emailUsage: emailUsage,
                dailyEmailLimitReached: dailyEmailLimitReached,
                canSendBatchReminders: canSendBatchReminders,
                summary: summary
            )
        }

        return nil
    }

    /// Stamp for the cached Service Briefing rebuild. Includes the clock minute so
    /// mode transitions (e.g. crossing close time) are picked up, plus the snapshot
    /// generation so reservation/status changes refresh it. All inputs are in-memory.
    private var serviceBriefingObservationKey: String {
        guard !liveHostModeEnabled, !externalInteractionActive else {
            return "presentation-hidden-\(liveHostModeEnabled)-\(externalInteractionActive)"
        }
        return serviceBriefingStamp
    }

    private var serviceBriefingStamp: String {
        // Use a coarse hourly bucket so service-mode transitions (before → during → after)
        // are captured without rebuilding the full service briefing every clock minute.
        // Reservation count and snapshot generatedAt ensure reservation/status changes
        // still trigger an immediate rebuild.
        let hourBucket = Int(clockTick.timeIntervalSince1970 / 3600)
        return [
            selectedDateKey,
            String(reservations.count),
            String(Int(hostIntelligenceController.decisionSnapshot.generatedAt.timeIntervalSince1970)),
            "h\(hourBucket)"
        ].joined(separator: "|")
    }

    /// Modes where the deterministic Service Briefing card replaces the live Host
    /// Intelligence card (those are the modes where live "due in X" / "table opened"
    /// facts are useless or wrong). Live service keeps the existing card.
    private func usesServiceBriefingCard(_ mode: ServiceMode) -> Bool {
        switch mode {
        case .afterCloseFinished, .afterCloseNeedsCleanup, .pastRecap, .futurePlanning:
            return true
        case .duringService, .beforeService:
            return false
        }
    }

    /// Rebuilds the Service Briefing from cached data only. No network.
    private func rebuildServiceBriefing() {
        let currentStamp = serviceBriefingStamp
        guard currentStamp != lastBuiltServiceBriefingStamp else {
            #if DEBUG
            print("[HOST_NOOP_CPU_GATE_TRACE] work=service_briefing decision=skip reason=reservation_fingerprint_unchanged date=\(selectedDateKey)")
            #endif
            return
        }
        lastBuiltServiceBriefingStamp = currentStamp
        let bounds = serviceDensityBounds
        var state = HostServiceBriefingViewStateBuilder.build(
            HostServiceBriefingViewStateBuilder.Input(
                now: clockTick,
                selectedDate: selectedDate,
                reservations: reservations,
                snapshot: hostIntelligenceController.decisionSnapshot,
                openTime: bounds.open,
                closeTime: bounds.close,
                selectedDateLabel: selectedDate.formatted(.dateTime.weekday(.wide))
            )
        )
        if usesServiceBriefingCard(state.mode) {
            ServiceIntelligenceTrace.hostCard(display: "service_briefing", mode: state.mode)
        }

        // Phase 4: booking-load heads-up only while there is a service to protect.
        if state.mode == .beforeService || state.mode == .duringService {
            let report = buildBookingLoadReport(bounds: bounds)
            bookingTopItem = BookingLoadActionBuilder.topItem(from: report)
            bookingKnownOnlyNote = report.knownOnlyNote
        } else {
            bookingTopItem = nil
            bookingKnownOnlyNote = ""
        }

        // LOCAL-FIRST-OPS-4A/4B: Build/update unified per-date intelligence snapshot.
        // Runs after state.mode is resolved; skip-gated by fingerprint inside controller.
        // Evaluate-order guard inside updateServiceIntelligenceSnapshot prevents building
        // from an empty HostDecisionSnapshot right after a date switch.
        hostIntelligenceController.updateServiceIntelligenceSnapshot(
            HostServiceIntelligenceSnapshotBuilder.Input(
                now: clockTick,
                selectedDate: selectedDate,
                dateKey: selectedDateKey,
                serviceMode: state.mode,
                dayReservations: reservations,
                snapshot: hostIntelligenceController.decisionSnapshot,
                largePartyThreshold: hostIntelligenceSettingsStore.settings.largePartyThreshold
            )
        )

        // LOCAL-FIRST-OPS-4B-2: substitute snapshot headline/subline for planning/recap
        // modes. Today's HostIntelligenceCard and live-service modes are not touched.
        // Readiness guard prevents stale-date copy (snapshot.dateKey == selectedDateKey
        // is the key invariant; beginSelectedDateTransition resets snapshot to .empty).
        if usesServiceBriefingCard(state.mode) {
            let snap = hostIntelligenceController.serviceIntelligenceSnapshot
            let snapReady = snap.dateKey == selectedDateKey
                && snap.inputFingerprint != "empty"
                && hostIntelligenceController.isEvaluatedForSelectedDate(selectedDateKey)
            if snapReady {
                #if DEBUG
                let truncated = String(snap.headline.prefix(50))
                print("[SERVICE_INTEL_UI_TRACE] surface=host_planning decision=use_snapshot date=\(selectedDateKey) headline=\"\(truncated)\"")
                #endif
                state = state.overridingHeadline(snap.headline, summary: snap.subline ?? "")
            } else {
                #if DEBUG
                print("[SERVICE_INTEL_UI_TRACE] surface=host_planning decision=legacy reason=snapshot_not_ready date=\(selectedDateKey)")
                #endif
            }
        }

        serviceBriefingState = state
    }

    /// Cache-only deterministic booking-load analysis for the selected date.
    private func buildBookingLoadReport(bounds: (open: Date?, close: Date?)) -> BookingLoadReport {
        let capacitySummary = hostFloorCapacitySummary()
        let (seats, isBackendLayout) = BookingLoadSupport.plannedSeats(
            from: capacitySummary,
            localCapacity: hostTableConfigStore.totalActiveCapacity
        )
        let blocked = BookingLoadSupport.blockedMinutes(from: availabilitySummary?.blockedSlots ?? [])
        var thresholds = BookingLoadThresholds.default
        thresholds.largePartyThreshold = hostIntelligenceSettingsStore.settings.largePartyThreshold
        return BookingLoadAnalyzer.analyze(
            BookingLoadAnalyzer.Input(
                date: selectedDateKey,
                reservations: reservations,
                openMinutes: BookingLoadSupport.minutesOfDay(from: bounds.open),
                closeMinutes: BookingLoadSupport.minutesOfDay(from: bounds.close),
                plannedReservableSeats: seats,
                hasBackendLayout: isBackendLayout,
                blockedSlotMinutes: blocked,
                thresholds: thresholds
            )
        )
    }

    @ViewBuilder
    private var hostIntelligenceSection: some View {
        if let serviceBriefingState, usesServiceBriefingCard(serviceBriefingState.mode) {
            HostServiceBriefingCard(state: serviceBriefingState) { intent in
                handleServiceActionIntent(intent)
            }
        } else {
            liveHostIntelligenceSection
            hostFloorSetupPrompt
            if let bookingTopItem {
                HostBookingLoadCompactStrip(item: bookingTopItem, knownOnlyNote: bookingKnownOnlyNote)
            }
        }
    }

    @ViewBuilder
    private var hostFloorSetupPrompt: some View {
        let source = hostFloorTableSource
        let showManagerPrompt = environment.role == .manager || environment.role == .developer
        if showManagerPrompt, source == .notConfigured {
            HostFloorSetupPromptCard(onOpenFloorSetup: onOpenFloorSetup)
        }
    }

    private func hostFloorCapacitySummary() -> TableCapacitySummary {
        let options = hostFloorLegacyOptions
        let source = floorPlanStore.floorSourceStatus(
            for: selectedDateKey,
            allowsLegacyFallback: options.allowsFallback,
            localActiveTableCount: options.localActiveTableCount
        )
        switch source {
        case .backend:
            return floorPlanStore.capacitySummary(
                for: selectedDateKey,
                allowsLegacyFallback: options.allowsFallback,
                localActiveTableCount: options.localActiveTableCount
            )
        case .legacyFallback:
            let summary = TableCapacitySummary.build(
                from: hostTableConfigStore.activeTables,
                source: .legacyFallback
            )
            TableCapacityTrace.summary(summary)
            return summary
        default:
            let summary = TableCapacitySummary.empty(source: source)
            TableCapacityTrace.summary(summary)
            return summary
        }
    }

    private func makeHostEngineInput(now: Date) -> HostEngineInput {
        let options = hostFloorLegacyOptions
        let source = floorPlanStore.floorSourceStatus(
            for: selectedDateKey,
            allowsLegacyFallback: options.allowsFallback,
            localActiveTableCount: options.localActiveTableCount
        )
        let resolved = HostFloorSourceSupport.resolveEngineTables(
            source: source,
            backendTables: floorPlanStore.backendTables(for: selectedDateKey),
            advisoryTables: hostTableConfigStore.tables
        )
        return HostEngineInput(
            now: now,
            selectedDate: selectedDate,
            reservations: reservations,
            availabilitySummary: availabilitySummary,
            analyticsSummary: cachedAnalyticsSummary,
            restaurantSetup: controller.hasLoadedRestaurantSetup ? controller.restaurantSetup : nil,
            localSeatedAtByReservationID: controller.localSeatedAtByReservationID,
            settings: hostIntelligenceSettingsStore.settings,
            tableConfigs: resolved.tableConfigs,
            allKnownReservations: allKnownReservations.isEmpty ? reservations : allKnownReservations,
            backendFloorTables: resolved.backendFloorTables,
            effectiveTableAssignments: floorPlanStore.effectiveTableAssignments(for: selectedDateKey),
            floorTableSource: source,
            guestIntelligenceSummariesByReservationID: guestIntelligenceStore.summariesByReservationID(
                for: selectedDateKey
            ),
            guestProfilePacksByReservationID: guestIntelligenceStore.profilePacks(
                for: reservations.map(\.remoteID)
            )
        )
    }

    @ViewBuilder
    private var liveHostIntelligenceSection: some View {
        // Gate all controller-fed inputs: when the controller has not yet evaluated
        // for the current selected date (e.g. during date navigation debounce), pass
        // empty/nil inputs so no prior-date facts are visible in the card.
        let ready = isHostIntelligenceReadyForSelectedDate
        let snapshot = ready ? hostIntelligenceController.displaySnapshot : .empty
        let useSeparatedPrompts = hostIntelligenceController.settings.useSeparatedBriefingPrompts
        let presentation = ready ? stableHostIntelligenceCardPresentation : .empty
        let cardAttentionPresentation = ready ? hostIntelligenceController.displayAttentionPresentation : .empty
        let cardBriefingText: String? = ready ? hostIntelligenceController.displayBriefingText : nil
        let cardManagerNarrative: ManagerNarrative? = ready ? hostIntelligenceController.displayManagerNarrative : nil
        let cardBriefingSource = ready ? hostIntelligenceController.briefingSource : .template
        let cardRenderState = ready ? hostIntelligenceController.renderState : .evaluating
        let cardIsRefreshing = ready && hostIntelligenceController.isRefreshingAttentionCard

        HostIntelligenceCard(
            snapshot: snapshot,
            presentation: presentation,
            presentationStyle: .compactStrip,
            attentionPresentation: cardAttentionPresentation,
            briefingTextOverride: cardBriefingText,
            managerNarrative: cardManagerNarrative,
            briefingSource: cardBriefingSource,
            showOperationalReview: useSeparatedPrompts,
            staffFacingPresentation: true,
            externalPulseActive: onDeviceSupportCoordinator.phase.pulseIsActive,
            renderState: cardRenderState,
            isRefreshingAttentionCard: cardIsRefreshing,
            onReviewTapped: { isShowingHostIntelligenceReview = true }
        ) { action in
            handleHostIntelligenceAction(action)
        }
        .sheet(isPresented: $isShowingHostIntelligenceReview) {
            NavigationStack {
                HostIntelligenceReviewView(
                    snapshot: snapshot,
                    reservations: reservations,
                    operationalPrompts: presentation.expandedPrompts,
                    briefingText: hostIntelligenceController.displayBriefingText,
                    briefingSource: hostIntelligenceController.briefingSource
                ) { action in
                    handleHostIntelligenceAction(action)
                }
            }
        }

    }

    private var stableHostIntelligenceCardPresentation: HostIntelligenceCardPresentation {
        // Guard against rendering stale card built for a prior selected date.
        // The card key's first pipe-delimited segment is always the date key.
        let cardKey = hostIntelligenceCardPresentation.key
        let cardDateKey = cardKey.components(separatedBy: "|").first ?? ""
        guard cardDateKey == selectedDateKey || cardKey == "empty" else {
            #if DEBUG
            print("[HOST_CARD_STALE_GUARD_TRACE] decision=hide reason=date_mismatch selected=\(selectedDateKey) cardDate=\(cardDateKey)")
            #endif
            return .empty
        }
        return hostIntelligenceCardPresentation
    }

    private var isHostIntelligenceCardVisible: Bool {
        guard isVisible,
              !liveHostModeEnabled,
              !externalInteractionActive,
              !isSelectedDateClosed else { return false }
        guard let serviceBriefingState else { return true }
        return !usesServiceBriefingCard(serviceBriefingState.mode)
    }

    private var hostIntelligenceCardTaskKey: String {
        guard isHostIntelligenceCardVisible else { return "hidden" }
        return "visible|\(hostIntelligenceCardPresentationKey)"
    }

    private var hostIntelligenceCardPresentationKey: String {
        let snapshot = hostIntelligenceController.displaySnapshot
        return [
            selectedDateKey,
            snapshot.llmPacket.briefingFingerprint,
            String(snapshot.generatedAt.timeIntervalSinceReferenceDate),
            String(hostIntelligenceReservationStamp),
            hostHistoryEnrichmentGenerationKey,
            String(allKnownReservations.count),
            hostIntelligenceController.displayAttentionPresentation.presentationFingerprint,
            HostAttentionStableDigest.hexDigest(hostIntelligenceController.displayBriefingText),
            String(hostIntelligenceController.settings.useSeparatedBriefingPrompts)
        ].joined(separator: "|")
    }

    @discardableResult
    private func rebuildHostIntelligenceCardPresentation(
        expectedKey: String? = nil,
        expectedDateKey: String? = nil
    ) -> Bool {
        let dateKey = expectedDateKey ?? selectedDateKey
        let key = expectedKey ?? hostIntelligenceCardPresentationKey
        // Reject if selected date changed since caller captured these keys.
        guard selectedDateKey == dateKey else { return false }
        guard key == hostIntelligenceCardPresentationKey else { return false }

        // Skip rebuild if inputs have not changed since the last build.
        if key == lastBuiltCardInputKey {
            #if DEBUG
            print("[HOST_NOOP_CPU_GATE_TRACE] work=card decision=skip reason=input_key_unchanged date=\(selectedDateKey)")
            #endif
            return true
        }

        // Verify controller has evaluated for the current date before reading its outputs.
        // Prevents old-date displaySnapshot / displayAttentionPresentation from being
        // published under a new-date presentation key.
        guard hostIntelligenceController.isEvaluatedForSelectedDate(dateKey) else {
            #if DEBUG
            print("[HOST_CARD_STALE_GUARD_TRACE] decision=hide reason=controller_date_mismatch selected=\(dateKey) controller=\(hostIntelligenceController.evaluatedSelectedDateKey)")
            #endif
            return false
        }

        let snapshot = hostIntelligenceController.displaySnapshot
        let presentation = HostIntelligenceCardPresentation.build(
            key: key,
            snapshot: snapshot,
            reservations: reservations,
            knownReservations: allKnownReservations,
            reminderContext: nil,
            attentionPresentation: hostIntelligenceController.displayAttentionPresentation,
            briefingText: hostIntelligenceController.displayBriefingText,
            usesSeparatedPrompts: hostIntelligenceController.settings.useSeparatedBriefingPrompts,
            includesReviewItem: true
        )
        // Final publish guard: date and key must still match, and controller still ready.
        guard selectedDateKey == dateKey,
              key == hostIntelligenceCardPresentationKey,
              hostIntelligenceController.isEvaluatedForSelectedDate(dateKey) else { return false }
        lastBuiltCardInputKey = key
        if presentation != hostIntelligenceCardPresentation {
            hostIntelligenceCardPresentation = presentation
        }
        return true
    }

    private func handleHostIntelligenceAction(_ action: HostSuggestedAction) {
        let route = HostSuggestedActionRouter.route(for: action)

        switch route.destination {
        case .reservation(let remoteID), .reservationIntent(let remoteID, _):
            let resolvedRemoteID = HostSuggestedActionRouter.resolvedRemoteID(
                for: action,
                dayReservations: reservations,
                knownReservations: allKnownReservations
            ) ?? remoteID
            guard let reservation = HostSuggestedActionRouter.findReservation(
                remoteID: resolvedRemoteID,
                dayReservations: reservations,
                knownReservations: allKnownReservations
            ) else {
                return
            }
            hostIntentStore.set(
                HostReservationOpenIntent.from(
                    action: action,
                    resolvedRemoteID: resolvedRemoteID
                )
            )
            onOpenReservation(reservation)

        case .slot, .none:
            break
        }
    }

    /// Phase 2: opens the related reservation for a Service Briefing action when it
    /// targets a specific reservation. Aggregate cleanup actions (no reservationID)
    /// are non-tappable no-ops — they are summaries, not single-reservation actions.
    private func handleServiceActionIntent(_ intent: StaffActionIntent) {
        guard let idString = intent.reservationID, let remoteID = Int(idString) else { return }
        guard let reservation = HostSuggestedActionRouter.findReservation(
            remoteID: remoteID,
            dayReservations: reservations,
            knownReservations: allKnownReservations
        ) else { return }
        onOpenReservation(reservation)
    }

    private func phoneLists(
        snapshot: HostBoardSnapshot,
        showsReservationLoadingPlaceholder: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HostBoardColumn(
                title: "Seated",
                subtitle: seatedGuestSubtitle(for: snapshot),
                reservations: snapshot.seated,
                emptyTitle: "No one seated",
                emptySystemImage: "person.2.slash",
                scrollsInternally: false,
                referenceNow: snapshot.now,
                showsServiceGroupHeader: true,
                environment: environment,
                onAction: handleAction,
                onOpenReservation: onOpenReservation
            )

            HomeReservationsPanel(
                snapshot: snapshot,
                referenceNow: snapshot.now,
                scrollsInternally: false,
                showsReservationLoadingPlaceholder: showsReservationLoadingPlaceholder,
                environment: environment,
                onAction: handleAction,
                onOpenReservation: onOpenReservation
            )
        }
    }

    private func seatedGuestSubtitle(for snapshot: HostBoardSnapshot) -> String {
        let guestCount = snapshot.seated.reduce(0) { $0 + $1.partySize }
        return "\(guestCount) \(guestCount == 1 ? "guest" : "guests") dining"
    }

    private func hostLayoutTraceID(width: CGFloat, isWideLayout: Bool) -> String {
        "\(UIDevice.current.userInterfaceIdiom.rawValue)|\(Int(width))|\(horizontalSizeClass.debugDescription)|\(isWideLayout)"
    }

    private func traceHostLayout(width: CGFloat, isWideLayout: Bool) {
        #if DEBUG
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        let reason = UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone"
        let layout = isWideLayout ? "split" : "stacked"
        let contentWidth = min(width, 1100) - (isWideLayout ? 32 : 24)
        let columnWidth = isWideLayout ? max(0, (contentWidth - 16) / 2) : contentWidth
        WorkflowCleanupTrace.log(
            "HOST_LAYOUT_TRACE",
            fields: [
                "device": device,
                "width": "\(Int(width))",
                "horizontalSizeClass": horizontalSizeClass.debugDescription,
                "layout": layout,
                "reason": reason
            ]
        )
        WorkflowCleanupTrace.log(
            "HOST_LAYOUT_TRACE",
            fields: [
                "seatedColumnWidth": "\(Int(columnWidth))",
                "reservationsColumnWidth": "\(Int(columnWidth))"
            ]
        )
        #endif
    }

    // MARK: - Staff Action Routing

    // View sends staff intent only; controller/service decide the network operation.
    private func handleAction(_ action: ReservationHostAction, reservation: ReservationRecord) {
        if action == .confirmOnly || action == .confirmAndSendEmail || action == .cancel || action == .noShow {
            pendingAction = ReservationPendingAction(reservation: reservation, action: action)
        } else if action != .assignTable {
            Task {
                await perform(action, on: reservation)
            }
        }
    }

    // Intent: Converts host-board actions into controller calls.
    // Confirm = PATCH status confirmed; Confirm + Email = POST /confirm.
    private func perform(_ action: ReservationHostAction, on reservation: ReservationRecord) async {
        pendingAction = nil

        switch action {
        case .confirmOnly:
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "start",
                fields: [
                    "source": "host_board",
                    "status": reservation.status,
                    "emailPresent": "\(reservation.hasUsableConfirmationEmail)"
                ]
            )
            if reservation.hasUsableConfirmationEmail {
                onOpenReservation(reservation)
                return
            }
            await controller.updateStatus(reservation: reservation, status: .confirmed, context: modelContext)
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "patch_confirmed",
                fields: ["result": "success"]
            )
            ReservationHaptics.success()
        case .confirmAndSendEmail:
            guard ReservationEmailWorkflow.isBackendConfirmEmailEnabled else { return }
            await controller.confirmReservation(reservation: reservation, context: modelContext)
            ReservationHaptics.success()
        case .seat:
            await controller.updateStatus(reservation: reservation, status: .seated, context: modelContext)
            ReservationHaptics.success()
        case .complete:
            await controller.updateStatus(reservation: reservation, status: .completed, context: modelContext)
            ReservationHaptics.success()
        case .cancel:
            await controller.updateStatus(reservation: reservation, status: .cancelled, context: modelContext)
            ReservationHaptics.warning()
        case .noShow:
            await controller.updateStatus(reservation: reservation, status: .noShow, context: modelContext)
            ReservationHaptics.warning()
        case .assignTable:
            break
        }
    }

    // MARK: - Auto Refresh Loop

    // Intent: Was the Host board's automatic active-window network poll. Demoted in
    // LIVE-SYNC-1B: ReservationsTabShell.runForegroundLiveSyncLoop now owns all
    // automatic active-window reservation network polling. This task remains so the
    // .task(id: isVisible && isAppActive) attachment point is preserved, but it must
    // not issue reservation network calls while the root foreground live loop is active.
    @MainActor
    private func runAutoRefreshLoop() async {
        guard isVisible, isAppActive else { return }
        // Root foreground live-sync loop owns active-window reservation polling once
        // startup UI is released. Host board rebuilds its UI from SwiftData via @Query;
        // it does not need its own network poll to stay current.
        #if DEBUG
        print("[LIVE_SYNC_OWNER_TRACE] owner=host decision=skip reason=root_foreground_owner")
        #endif
        // Task exits; it will be restarted by SwiftUI if isVisible/isAppActive change.
    }

    @MainActor
    private func runClockLoop() async {
        guard isVisible else { return }
        clockTick = Date()

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }

            guard isVisible else { return }
            clockTick = Date()
        }
    }

    private func traceHostBoardRenderTransition(
        source: HostBoardSnapshotRenderSource,
        snapshot: HostBoardSnapshot,
        reservationsCount: Int
    ) {
        #if DEBUG
        let snapshotCount = snapshot.upcoming.count + snapshot.seated.count
        print(
            "[HOST_ROWS_TRACE] event=render_source_changed date=\(selectedDateKey) source=\(source.rawValue) reservations=\(reservationsCount) snapshotCount=\(snapshotCount)"
        )
        #endif
    }

    private func traceHostBoardSnapshotPublish(date: String, count: Int) {
        #if DEBUG
        print("[HOST_ROWS_TRACE] event=snapshot_publish date=\(date) count=\(count)")
        #endif
    }

    private func traceHostBoardSnapshotSkipEmpty(date: String, lastStableCount: Int) {
        #if DEBUG
        print(
            "[HOST_ROWS_TRACE] event=snapshot_skip_empty date=\(date) lastStable=\(lastStableCount)"
        )
        #endif
    }

    private func traceHostBoardStabilization(
        event: String,
        detail: @autoclosure () -> String = ""
    ) {
        #if DEBUG
        let detail = detail()
        let suffix = detail.isEmpty ? "" : " \(detail)"
        print("[HOST_BOARD_STABILIZATION] event=\(event)\(suffix)")
        #endif
    }

}

// MARK: - Host Board Snapshot Render Source

private enum HostBoardSnapshotRenderSource: String {
    case cached
    case fallback
    case loading
}

// MARK: - Pending Host Action

private struct ReservationPendingAction: Identifiable {
    let reservation: ReservationRecord
    let action: ReservationHostAction

    var id: String {
        "\(reservation.remoteID)-\(action.rawValue)"
    }
}

// MARK: - Home Service Header

private enum HostBoardHeaderCollapse {
    /// Full collapse completes quickly once summary content starts sliding under the sticky header.
    static let scrollDistance: CGFloat = 48
    static let minScale: CGFloat = 0.84

    static func lerp(_ expanded: CGFloat, _ collapsed: CGFloat, _ progress: CGFloat) -> CGFloat {
        expanded + (collapsed - expanded) * min(1, max(0, progress))
    }

    static func progress(forScrollOffset offset: CGFloat) -> CGFloat {
        guard offset > 0 else { return 0 }
        let normalized = offset / scrollDistance
        // Ramp up faster at the start so shrink begins as soon as content tucks under the header.
        return min(1, normalized * 1.15)
    }
}

private struct HomeServiceHeader: View {
    let title: String
    @Binding var selectedDate: Date
    let statusPresentation: HomeServiceStatusPresentation
    let canCreateReservation: Bool
    @EnvironmentObject private var controller: ReservationsController
    let canViewFormProblems: Bool
    let failedImportCount: Int
    let onAddReservation: () -> Void
    let onManualRefresh: () -> Void
    let onShowFormProblems: () -> Void
    var onOpenTimeline: (() -> Void)? = nil
    var onOpenReminderStats: (() -> Void)? = nil
    var collapseProgress: CGFloat = 0
    /// iPad Host board: title + sync and date chips share one row when horizontal space allows.
    var usesInlineDateStrip: Bool = false
    @Binding var liveHostModeEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var effectiveCollapse: CGFloat {
        reduceMotion ? 0 : min(1, max(0, collapseProgress))
    }

    private var titleFontSize: CGFloat {
        HostBoardHeaderCollapse.lerp(17, 15, effectiveCollapse)
    }

    private var dateStripHeight: CGFloat {
        HostBoardHeaderCollapse.lerp(46, 36, effectiveCollapse)
    }

    private var headerSpacing: CGFloat {
        HostBoardHeaderCollapse.lerp(8, 2, effectiveCollapse)
    }

    private var horizontalPadding: CGFloat {
        HostBoardHeaderCollapse.lerp(14, 10, effectiveCollapse)
    }

    private var verticalPadding: CGFloat {
        HostBoardHeaderCollapse.lerp(10, 5, effectiveCollapse)
    }

    private var dateStripScale: CGFloat {
        HostBoardHeaderCollapse.lerp(1, 0.9, effectiveCollapse)
    }

    private var showsSecondaryStatus: Bool {
        effectiveCollapse < 0.55
    }

    private var cornerRadius: CGFloat {
        HostBoardHeaderCollapse.lerp(14, 11, effectiveCollapse)
    }

    private var inlineSideRailWidth: CGFloat {
        156
    }

    private var inlineDateStripWidth: CGFloat {
        600
    }

    private var rowSpacing: CGFloat {
        HostBoardHeaderCollapse.lerp(10, 6, effectiveCollapse)
    }

    var body: some View {
        Group {
            if usesInlineDateStrip {
                ViewThatFits(in: .horizontal) {
                    inlineHeaderLayout
                    stackedHeaderLayout
                }
            } else {
                stackedHeaderLayout
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .hostBoardGlassSurface(cornerRadius: cornerRadius)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .zIndex(10)
        .scaleEffect(HostBoardHeaderCollapse.lerp(1, 0.96, effectiveCollapse), anchor: .top)
        .animation(.smooth(duration: 0.32), value: effectiveCollapse)
    }

    private var stackedHeaderLayout: some View {
        VStack(alignment: .leading, spacing: headerSpacing) {
            titleAndActionRow
            serviceDateSelector
        }
    }

    private var inlineHeaderLayout: some View {
        HStack(alignment: .center, spacing: rowSpacing) {
            titleBlock(expandsHorizontally: false, showsInlineSecondaryStatus: false)
                .frame(width: inlineSideRailWidth, alignment: .leading)
                .layoutPriority(2)

            serviceDateSelector
                .frame(width: inlineDateStripWidth)
                .layoutPriority(0)

            actionBar
                .fixedSize()
                .frame(width: inlineSideRailWidth, alignment: .trailing)
                .layoutPriority(3)
                .scaleEffect(HostBoardHeaderCollapse.lerp(1, 0.92, effectiveCollapse))
        }
        .frame(maxWidth: .infinity)
    }

    private var titleAndActionRow: some View {
        HStack(alignment: .center, spacing: rowSpacing) {
            titleBlock(expandsHorizontally: true, showsInlineSecondaryStatus: true)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)
            actionBar
                .fixedSize()
                .layoutPriority(1)
                .scaleEffect(HostBoardHeaderCollapse.lerp(1, 0.92, effectiveCollapse))
        }
    }

    private var serviceDateSelector: some View {
        ReservationServiceDateSelector(
            selectedDate: $selectedDate,
            chipStyle: .hostBoardGlass,
            pinsCalendarToTrailing: true,
            showsCalendarButton: false,
            stripScale: dateStripScale,
            stripScaleAnchor: .center
        )
        .frame(height: dateStripHeight)
    }
    
//OLD VERSION
//    var body: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            ViewThatFits(in: .horizontal) {
//                HStack(alignment: .top, spacing: 14) {
//                    titleBlock
////                        .frame(minWidth: 120)
//                  
//                    dateStrip
//                        .frame(maxWidth: .infinity)
//                        .layoutPriority(0)
//                    openCalendarButton
//                    
//                    
//                    actionBar
//                        .fixedSize()
//                }
//
//                VStack(alignment: .leading, spacing: 12) {
//                    titleBlock
//                    actionBar
//                }
//            }
//
//            ViewThatFits(in: .horizontal) {
////                HStack(alignment: .center, spacing: 12) {
////                    dateStrip
////
////                    Spacer(minLength: 12)
////
////                    openCalendarButton
////                }
//
//                VStack(alignment: .leading, spacing: 10) {
//                    dateStrip
//                    openCalendarButton
//                }
//            }
//        }
//        .padding(.horizontal, 16)
//        .padding(.vertical, 14)
////        .frame(maxWidth: .infinity, alignment: .leading)
//        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
//        .overlay {
//            RoundedRectangle(cornerRadius: 14, style: .continuous)
//                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
//        }
//    }

    private func titleBlock(
        expandsHorizontally: Bool,
        showsInlineSecondaryStatus: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: titleFontSize, weight: .semibold))
                .foregroundStyle(ReservationUIStyle.serviceTitleColor)
                .lineLimit(1)
                .layoutPriority(1)

            HStack(spacing: 6) {
                Text(statusPresentation.primarySyncText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: statusPresentation.primarySyncText)

                TryzubStaffStatusIndicator(
                    style: statusPresentation.dotStyle,
                    showsOfflineIcon: controller.isNetworkDegraded
                )
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .layoutPriority(0)

            if showsInlineSecondaryStatus,
               let secondary = statusPresentation.secondaryProgressText,
               showsSecondaryStatus {
                Text(secondary)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(.tertiary)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: secondary)
            }
        }
        .frame(maxWidth: expandsHorizontally ? .infinity : nil, alignment: .leading)
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            Button {
                ReservationHaptics.selection()
                liveHostModeEnabled.toggle()
            } label: {
                Label("Live", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(liveHostModeEnabled ? Color.white : Color.primary)
                    .frame(width: 58, height: 36)
                    .hostBoardGlassChip(
                        cornerRadius: 18,
                        isSelected: liveHostModeEnabled,
                        strokeOpacity: 0.10
                    )
                    .padding(.horizontal, 3)
                    .padding(.vertical, 4)
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(minWidth: 64, minHeight: 44)
            .contentShape(Rectangle())
            .zIndex(3)
            .accessibilityLabel("Live Host mode")
            .accessibilityValue(liveHostModeEnabled ? "On" : "Off")

            Menu {
                if let onOpenReminderStats {
                    Button {
                        ReservationHaptics.selection()
                        onOpenReminderStats()
                    } label: {
                        Label("Reminder stats", systemImage: "bell.badge")
                    }
                }

                Button {
                    ReservationHaptics.selection()
                    onManualRefresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(controller.isReservationNetworkRefreshInFlight)

                if canViewFormProblems, failedImportCount > 0 {
                    Button {
                        ReservationHaptics.warning()
                        onShowFormProblems()
                    } label: {
                        Label("\(failedImportCount) Form Problems", systemImage: "exclamationmark.triangle")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(ReservationHeaderIconButtonStyle())

            if let onOpenTimeline {
                Button {
                    ReservationHaptics.selection()
                    onOpenTimeline()
                } label: {
                    Image(systemName: "chart.bar.xaxis.ascending")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(ReservationHeaderIconButtonStyle())
                .accessibilityLabel("Service Timeline")
            }

            if canCreateReservation {
                Button {
                    ReservationHaptics.selection()
                    onAddReservation()
                } label: {
                   Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(ReservationHeaderIconButtonStyle())
            }

            
        }
        .zIndex(2)
//        .frame(maxWidth: .infinity, alignment: .trailing)
    }

}
