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
    @EnvironmentObject private var emailAutomationSettingsStore: EmailAutomationSettingsStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var pendingAction: ReservationPendingAction?
    @State private var showBackendReminderConfirmation = false
    @State private var clockTick = Date()
    @State private var boardSnapshot: HostBoardSnapshot?
    /// Last known non-zero reservation count per date key, used to suppress
    /// transient 0-reservation snapshots during tab/visibility transitions.
    @State private var stableCountByDate: [String: Int] = [:]
    @ObservedObject private var onDeviceSupportCoordinator = HostLocalModelAutoPrepareCoordinator.shared
    @State private var isShowingHostIntelligenceReview = false
    @State private var showShiftReminders = false
    /// Phase 2: cached deterministic Service Briefing, rebuilt only when inputs change
    /// (selected date, reservations, snapshot, clock minute) — never from a fetch.
    @State private var serviceBriefingState: HostServiceBriefingViewState?
    /// Phase 4: concise booking-load heads-up for the busiest window, shown only during
    /// before/during service. Rebuilt with the briefing (cache-only, no fetch).
    @State private var bookingTopItem: BookingSuggestionViewItem?
    @State private var bookingKnownOnlyNote: String = ""
    @StateObject private var hostBoardViewStateStore = HostBoardViewStateStore()
    /// Single lifecycle coordinator — replaces two independent .task(id:) pipelines
    /// for availability and guest intelligence scheduling.
    @StateObject private var lifecycleCoordinator = HostBoardLifecycleCoordinator()

    private var hasOpenInteraction: Bool {
        externalInteractionActive
            || pendingAction != nil
            || showShiftReminders
            || showBackendReminderConfirmation
    }

    private var shiftReminderEligibleReservations: [ReservationRecord] {
        ShiftReminderEligibility.eligibleReservations(
            from: allKnownReservations,
            dateKey: selectedDateKey,
            isHidden: { hiddenReservations.isHidden($0) }
        )
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
    private var hostIntelligenceEvaluationKey: String {
        let options = hostFloorLegacyOptions
        return "\(selectedDateKey)-\(hostIntelligenceReservationStamp)-\(hostIntelligenceSeatedStamp)-\(hostIntelligenceOperationalMinuteStamp)-\(hostIntelligenceSettingsStore.settings.hostDecisionFingerprint)-\(floorPlanStore.layoutFingerprint(for: selectedDateKey, allowsLegacyFallback: options.allowsFallback, localActiveTableCount: options.localActiveTableCount))"
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
        "\(selectedDateKey)-\(hostIntelligenceReservationStamp)-\(hostIntelligenceOperationalMinuteStamp)-\(hostTableConfigStore.tableConfigFingerprint)"
    }

    var body: some View {
        GeometryReader { proxy in
            let safeWidth = proxy.size.width.tryzubFiniteNonNegativeLayoutValue
            let safeHeight = proxy.size.height.tryzubFinitePositiveLayoutValue
            let isTablet = UIDevice.current.userInterfaceIdiom == .pad
            let isWideLayout = isTablet || safeWidth >= 1100
            let snapshot = boardSnapshot ?? HostBoardSnapshot(
                reservations: reservations,
                selectedDate: selectedDate,
                now: clockTick,
                serviceOpen: serviceDensityBounds.open,
                serviceClose: serviceDensityBounds.close,
                largePartyThreshold: hostIntelligenceSettingsStore.settings.largePartyThreshold
            )

            let closedPresentation = closedDayPresentation(for: snapshot)

            TryzubHostBoardCanvas {
                Group {
                    if isTablet {
                        hostBoardScrollView(
                            snapshot: snapshot,
                            closedPresentation: closedPresentation,
                            isWideLayout: isWideLayout,
                            safeWidth: safeWidth,
                            includesHeader: false
                        )
                        .safeAreaInset(edge: .top, spacing: 0) {
                            homeServiceHeader
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                                .background(Color.clear)
                        }
                    } else {
                        hostBoardScrollView(
                            snapshot: snapshot,
                            closedPresentation: closedPresentation,
                            isWideLayout: isWideLayout,
                            safeWidth: safeWidth,
                            includesHeader: true
                        )
                    }
                }
            }
            .frame(width: safeWidth, height: safeHeight, alignment: .top)
            .task(id: hostLayoutTraceID(width: safeWidth, isWideLayout: isWideLayout)) {
                traceHostLayout(width: safeWidth, isWideLayout: isWideLayout)
            }
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
                        Button("Confirm only") {
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
        .task(id: boardSnapshotBuildKey) {
            guard !isRunningForPreviews else { return }
            let started = ContinuousClock.now
            let densityBounds = serviceDensityBounds
            let built = HostBoardSnapshot(
                reservations: reservations,
                selectedDate: selectedDate,
                now: clockTick,
                serviceOpen: densityBounds.open,
                serviceClose: densityBounds.close,
                largePartyThreshold: hostIntelligenceSettingsStore.settings.largePartyThreshold
            )
            let incomingCount = reservations.count
            let lastStableCount = stableCountByDate[selectedDateKey] ?? 0

            // Snapshot preservation: if the incoming count is 0 but this date previously
            // had reservations, do not overwrite the stable snapshot. This guards against
            // stale transient-empty snapshots that can slip through if the parent's
            // selectedDateReservations momentarily returns [] (e.g. during view init or
            // edge-case timing before the @Query observer fires on tab return).
            if incomingCount == 0, lastStableCount > 0 {
                MultiDeviceSyncTrace.hostSnapshotPreserve(
                    date: selectedDateKey,
                    incomingCount: incomingCount,
                    lastStableCount: lastStableCount,
                    preserve: true,
                    reason: "untrusted_empty"
                )
                // Preserve: keep the existing snapshot, do not publish empty.
                return
            }

            // Commit the snapshot and update stable count.
            if incomingCount > 0 {
                stableCountByDate[selectedDateKey] = incomingCount
            }
            boardSnapshot = built
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
        }
        .onChange(of: selectedDateKey) { _, dateKey in
            controller.noteHostBoardSelectedDate(dateKey)
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
        .task(id: "reminder-status-\(isVisible)-\(selectedDateKey)-\(emailAutomationSettingsStore.settings.automaticReminderProofEnabled)-\(emailAutomationSettingsStore.settings.manualReminderSendEnabled)") {
            guard isVisible,
                  selectedDateKey == Date.reservationDateString(),
                  emailAutomationSettingsStore.settings.automaticReminderProofEnabled
                    || emailAutomationSettingsStore.settings.manualReminderSendEnabled else { return }
            _ = await controller.refreshReminderStatus(for: selectedDateKey)
        }
        .onChange(of: hostBoardViewStateBuildKey, initial: true) { _, _ in
            refreshHostBoardViewState(reason: "semantic_key_changed")
        }
        .onChange(of: serviceBriefingStamp, initial: true) { _, _ in
            rebuildServiceBriefing()
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
        .task(id: hostIntelligenceEvaluationKey) {
            guard isVisible else {
                hostIntelligenceController.reset()
                return
            }
            HostReevalTrace.log(
                trigger: "selected_day_reservation_change",
                immediate: true
            )
            let bookingReport = buildBookingLoadReport(bounds: serviceDensityBounds)
            hostIntelligenceController.evaluate(
                input: makeHostEngineInput(now: clockTick),
                stability: hostEvaluationStabilityContext,
                bookingLoadReport: bookingReport
            )
        }
        .task(id: hostHistoryEnrichmentGenerationKey) {
            guard isVisible else { return }
            HostReevalTrace.log(
                trigger: "history_generation",
                debounced: true
            )
        }
        .onChange(of: hostIntelligenceEnrichmentKey) { _, _ in
            HostReevalTrace.log(
                trigger: "guest_intelligence_summary",
                immediate: true
            )
        }
        .task(id: hostIntelligenceEnrichmentKey) {
            guard isVisible else { return }
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
        .sheet(isPresented: $showShiftReminders) {
            ShiftReminderReviewSheet(
                dateKey: selectedDateKey,
                reservations: shiftReminderEligibleReservations
            )
            .environmentObject(controller)
        }
    }

    private var pendingActionTitle: String {
        guard let pendingAction else {
            return "Update Reservation?"
        }

        return pendingAction.action.dialogTitle(for: pendingAction.reservation)
    }

    private func wideBoard(snapshot: HostBoardSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            HostBoardColumn(
                title: "Seated",
                subtitle: "\(snapshot.seated.count) seated",
                reservations: snapshot.seated,
                emptyTitle: "No one seated",
                emptySystemImage: "person.2.slash",
                scrollsInternally: false,
                referenceNow: snapshot.now,
                environment: environment,
                onAction: handleAction,
                onOpenReservation: onOpenReservation
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)

            HomeReservationsPanel(
                snapshot: snapshot,
                referenceNow: snapshot.now,
                scrollsInternally: false,
                environment: environment,
                onAction: handleAction,
                onOpenReservation: onOpenReservation
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
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

    private var homeServiceHeader: some View {
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
            onOpenShiftReminders: { showShiftReminders = true }
        )
    }

    @ViewBuilder
    private func hostBoardScrollView(
        snapshot: HostBoardSnapshot,
        closedPresentation: ClosedDayPresentation,
        isWideLayout: Bool,
        safeWidth: CGFloat,
        includesHeader: Bool
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if includesHeader {
                    homeServiceHeader
                }

                onDeviceSupportStatusBanner

                closedOrOperationalBody(
                    snapshot: snapshot,
                    closedPresentation: closedPresentation,
                    isWideLayout: isWideLayout,
                    availableWidth: safeWidth
                )
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, isWideLayout ? 16 : 12)
            .padding(.top, includesHeader ? (isWideLayout ? 8 : 6) : 4)
            .padding(.bottom, ReservationLayout.scrollBottomInset + 12)
        }
        .contentMargins(.bottom, ReservationLayout.scrollBottomInset, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func closedOrOperationalBody(
        snapshot: HostBoardSnapshot,
        closedPresentation: ClosedDayPresentation,
        isWideLayout: Bool,
        availableWidth: CGFloat
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

                if snapshot.newReservations.count + snapshot.needsReview.count > 0 {
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
            let isWideIPad = horizontalSizeClass == .regular && availableWidth >= 900
            
            if isWideIPad {
                // iPad wide layout: KPIs → Lists → Service Pressure → Reminders + Intelligence
                hostOperationalKPIsSection(snapshot: snapshot)
                wideBoard(snapshot: snapshot)
                hostOperationalServicePressureSection(snapshot: snapshot)
                hostRemindersAndIntelligenceSection()
            } else {
                // iPhone/narrow layout: original order (KPIs → Service Pressure → Reminders → Intelligence → Lists)
                homeOperationalHeader(snapshot: snapshot, availableWidth: availableWidth)
                
                if isWideLayout {
                    wideBoard(snapshot: snapshot)
                } else {
                    phoneLists(snapshot: snapshot)
                }
            }
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
    private func hostOperationalServicePressureSection(snapshot: HostBoardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Service pressure")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TryzubColors.primaryText)
                    Text(snapshot.arrivalPressure.chartSubtitle)
                        .font(.caption2)
                        .foregroundStyle(TryzubColors.mutedText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Peak")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(TryzubColors.mutedText)
                        Text(snapshot.arrivalPressure.peakLegendText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(TryzubColors.primaryText)
                            .lineLimit(1)
                    }
                    if let next = snapshot.arrivalPressure.nextLegendText {
                        HStack(spacing: 4) {
                            Text("Next")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(TryzubColors.mutedText)
                            Text(next)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(TryzubColors.primaryText)
                                .lineLimit(1)
                        }
                    }
                }
            }

            ArrivalPressureWaveChart(
                summary: snapshot.arrivalPressure,
                height: 112,
                isToday: snapshot.selectedDate.reservationDateString() == Date.reservationDateString(),
                now: snapshot.now,
                onOpenReservation: { remoteID in
                    if let reservation = reservations.first(where: { $0.remoteID == remoteID }) {
                        onOpenReservation(reservation)
                    }
                }
            )
        }
        .padding(12)
        .hostBoardGlassPanel(cornerRadius: ReservationUIStyle.cardCorner, strokeOpacity: 0.12)
    }

    @ViewBuilder
    private func hostRemindersAndIntelligenceSection() -> some View {
        HStack(alignment: .top, spacing: 16) {
            hostReminderBatchCard
                .frame(width: 360, alignment: .topLeading)
            
            hostIntelligenceSection
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
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
                
                // Reminders + Intelligence in HStack for wide layout
                HStack(alignment: .top, spacing: 16) {
                    // Today's Reminders: fixed width around 360
                    hostReminderBatchCard
                        .frame(width: 360, alignment: .topLeading)
                    
                    // Host Intelligence: flexible width
                    hostIntelligenceSection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
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

                hostReminderBatchCard

                hostIntelligenceSection
            }
        }
    }

    @ViewBuilder
    private var hostReminderBatchCard: some View {
        let settings = emailAutomationSettingsStore.settings
        let isToday = selectedDateKey == Date.reservationDateString()
        if isToday && (settings.automaticReminderProofEnabled || settings.manualReminderSendEnabled) {
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
            let canSendBatchReminders = settings.manualReminderSendEnabled
                && automation.manualBatchRemindersEnabled
                && hasEligibleReminders
                && !dailyEmailLimitReached

            HostReminderBatchCard(
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
                onSend: { showBackendReminderConfirmation = true }
            )
        }
    }

    /// Stamp for the cached Service Briefing rebuild. Includes the clock minute so
    /// mode transitions (e.g. crossing close time) are picked up, plus the snapshot
    /// generation so reservation/status changes refresh it. All inputs are in-memory.
    private var serviceBriefingStamp: String {
        let minute = Int(clockTick.timeIntervalSince1970 / 60)
        return [
            selectedDateKey,
            String(reservations.count),
            String(Int(hostIntelligenceController.decisionSnapshot.generatedAt.timeIntervalSince1970)),
            String(minute)
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
        let bounds = serviceDensityBounds
        let state = HostServiceBriefingViewStateBuilder.build(
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
        serviceBriefingState = state
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
                BookingLoadHostCard(item: bookingTopItem, knownOnlyNote: bookingKnownOnlyNote)
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
        let snapshot = hostIntelligenceController.displaySnapshot
        let useSeparatedPrompts = hostIntelligenceController.settings.useSeparatedBriefingPrompts
        let compactPrompts = useSeparatedPrompts
            ? HostOperationalBriefingPromptBuilder.buildCompactPrompts(from: snapshot)
            : []
        let expandedPrompts = useSeparatedPrompts
            ? HostOperationalBriefingPromptBuilder.buildExpandedPrompts(from: snapshot)
            : []

        HostIntelligenceCard(
            snapshot: snapshot,
            attentionPresentation: hostIntelligenceController.displayAttentionPresentation,
            briefingTextOverride: hostIntelligenceController.displayBriefingText,
            managerNarrative: hostIntelligenceController.displayManagerNarrative,
            briefingSource: hostIntelligenceController.briefingSource,
            compactOperationalPrompts: compactPrompts,
            showOperationalReview: useSeparatedPrompts,
            staffFacingPresentation: true,
            externalPulseActive: onDeviceSupportCoordinator.phase.pulseIsActive,
            renderState: hostIntelligenceController.renderState,
            isRefreshingAttentionCard: hostIntelligenceController.isRefreshingAttentionCard,
            onReviewTapped: useSeparatedPrompts ? { isShowingHostIntelligenceReview = true } : nil
        ) { action in
            handleHostIntelligenceAction(action)
        }
        .sheet(isPresented: $isShowingHostIntelligenceReview) {
            NavigationStack {
                HostIntelligenceReviewView(
                    snapshot: snapshot,
                    operationalPrompts: expandedPrompts,
                    briefingText: hostIntelligenceController.displayBriefingText,
                    briefingSource: hostIntelligenceController.briefingSource
                ) { action in
                    handleHostIntelligenceAction(action)
                }
            }
        }

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

    private func phoneLists(snapshot: HostBoardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HostBoardColumn(
                title: "Seated",
                subtitle: "\(snapshot.seated.count) seated",
                reservations: snapshot.seated,
                emptyTitle: "No one seated",
                emptySystemImage: "person.2.slash",
                scrollsInternally: false,
                referenceNow: snapshot.now,
                environment: environment,
                onAction: handleAction,
                onOpenReservation: onOpenReservation
            )

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

    // Intent: Keeps Today fresh without interrupting staff while sheets/dialogs are open.
    // Network: Controller may call GET /managed-reservations?date=today.
    @MainActor
    private func runAutoRefreshLoop() async {
        guard isVisible, isAppActive else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }

            guard isVisible, isAppActive else { return }

            #if DEBUG
            let selectedKey = selectedDate.reservationDateString()
            DateBoundaryTrace.boundary(
                source: "autoRefresh",
                selectedDate: selectedKey,
                serviceDate: selectedKey,
                afterClose: DateBoundaryTrace.isLikelyAfterClose(selectedDate: selectedDate),
                autoAdvanced: false,
                decision: "keep_selected_date",
                reason: "host_auto_refresh_never_advances_date"
            )
            #endif
            await controller.autoRefreshDashboardIfAllowed(
                context: modelContext,
                isInteractionActive: hasOpenInteraction,
                isAppActive: isAppActive,
                source: .host
            )
        }
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

}

// MARK: - Host Snapshot

private struct HostBoardSnapshot {
    let selectedDate: Date
    let now: Date
    let upcoming: [ReservationRecord]
    let seated: [ReservationRecord]
    let needsReview: [ReservationRecord]
    let newReservations: [ReservationRecord]
    let noTableCount: Int
    let expectedGuestCount: Int
    let peakTimeText: String
    let nextReservationText: String?
    let arrivalPressure: ArrivalPressureSummary

    // Active same-day reservations remain visible until staff changes status.
    // Time only chooses the "next" highlight; it does not auto-complete or hide rows.
    init(
        reservations: [ReservationRecord],
        selectedDate: Date,
        now: Date,
        serviceOpen: Date? = nil,
        serviceClose: Date? = nil,
        largePartyThreshold: Int = 7
    ) {
        self.selectedDate = selectedDate
        self.now = now
        upcoming = ReservationRecord.sortedForHostBoard(
            reservations.filter {
                $0.statusValue == .new || $0.statusValue == .needsReview || $0.statusValue == .confirmed
            },
            now: now
        )
        seated = ReservationRecord.sortedChronologically(
            reservations.filter { $0.statusValue == .seated }
        )
        needsReview = upcoming.filter { $0.statusValue == .needsReview }
        newReservations = upcoming.filter { $0.statusValue == .new }
        noTableCount = upcoming.filter { !$0.hasTableAssignment }.count
        expectedGuestCount = upcoming.reduce(0) { $0 + $1.partySize } + seated.reduce(0) { $0 + $1.partySize }

        let isToday = selectedDate.reservationDateString() == Date.reservationDateString()
        let nextReservation = ReservationRecord.nextExpectedArrivalReservation(
            from: reservations,
            selectedDate: selectedDate,
            now: now
        )
        let pressureReservations = upcoming + seated
        arrivalPressure = ArrivalPressureEngine.build(
            from: pressureReservations,
            selectedDate: selectedDate,
            serviceOpen: serviceOpen,
            serviceClose: serviceClose,
            now: now,
            largePartyThreshold: largePartyThreshold
        )
        peakTimeText = arrivalPressure.peakLegendText
        nextReservationText = arrivalPressure.nextLegendText
            ?? Self.nextReservationText(
                for: nextReservation,
                isToday: isToday,
                now: now
            )
    }

    private static func nextReservationText(
        for reservation: ReservationRecord?,
        isToday: Bool,
        now: Date
    ) -> String? {
        guard isToday, let reservation, let serviceDate = reservation.serviceDateTime else {
            return nil
        }

        let time = ReservationFormatters.shortTime.string(from: serviceDate)
        let minutes = Int(ceil(abs(serviceDate.timeIntervalSince(now)) / 60))

        if serviceDate < now {
            if minutes <= 10 {
                return "\(time) · now"
            }
            return "\(time) · \(durationText(minutes: minutes)) late"
        }
        if minutes <= 5 {
            return "\(time) · soon"
        }
        return "\(time) · in \(durationText(minutes: minutes))"
    }

    private static func durationText(minutes: Int) -> String {
        let minutes = max(minutes, 1)
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
    }
}

// MARK: - Pending Host Action

private struct ReservationPendingAction: Identifiable {
    let reservation: ReservationRecord
    let action: ReservationHostAction

    var id: String {
        "\(reservation.remoteID)-\(action.rawValue)"
    }
}

// MARK: - Summary Card

private struct HostBoardSummaryCard: View {
    let reservationCount: Int
    let guestCount: Int
    let newCount: Int
    let reviewCount: Int
    let failedImportCount: Int
    let noTableCount: Int
    let arrivalPressure: ArrivalPressureSummary
    var isSelectedDateToday = true
    var referenceNow: Date = Date()
    var availabilitySummary: String?
    var isAvailabilityLoading = false
    var onRefreshAvailability: (() -> Void)?
    var onOpenReservationByID: ((Int) -> Void)?

    private var stats: [HostBoardStat] {
        var items = [
            HostBoardStat(value: reservationCount, label: "Booked"),
            HostBoardStat(value: guestCount, label: "Guests"),
            HostBoardStat(value: newCount, label: "New"),
            HostBoardStat(value: reviewCount, label: "Review"),
            HostBoardStat(value: noTableCount, label: "No table")
        ]
        if failedImportCount > 0 {
            items.append(HostBoardStat(value: failedImportCount, label: "Forms"))
        }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    ForEach(stats) { stat in
                        statItem(stat)
                    }
                    Spacer(minLength: 0)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(stats) { statItem($0) }
                }
            }

            if let availabilitySummary {
                HStack(spacing: 8) {
                    Text(availabilitySummary)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(TryzubColors.mutedText)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let onRefreshAvailability {
                        Button(action: onRefreshAvailability) {
                            if isAvailabilityLoading {
                                TryzubSubtleLoadingDot(diameter: 6)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(TryzubColors.mutedText)
                        .disabled(isAvailabilityLoading)
                    }
                }
            } else if isAvailabilityLoading {
                HStack(spacing: 8) {
                    Text("Checking available times…")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(TryzubColors.mutedText)
                    Spacer(minLength: 0)
                    TryzubSubtleLoadingDot(diameter: 6)
                }
            }
        }
        .padding(10)
        .hostBoardGlassPanel(cornerRadius: ReservationUIStyle.cardCorner)
    }

    private func statItem(_ stat: HostBoardStat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(stat.value)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(stat.value == 0 ? TryzubColors.mutedText : TryzubColors.primaryText)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.35), value: stat.value)
                .lineLimit(1)
            Text(stat.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(TryzubColors.mutedText)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .hostBoardGlassCapsule()
        .fixedSize(horizontal: true, vertical: false)
    }

    private func timelineLegend(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(TryzubColors.mutedText)
            Text(value)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TryzubColors.primaryText)
                .lineLimit(1)
        }
    }
}

private struct HostReminderBatchCard: View {
    let status: ReservationReminderStatusResponse?
    let notice: String?
    let isSending: Bool
    let showProof: Bool
    let hasEligibleReminders: Bool
    let manualSendEnabled: Bool
    let backendManualBatchEnabled: Bool
    let automaticRemindersEnabled: Bool
    let reminderLeadHours: Int
    let emailUsage: ResolvedEmailUsage
    let dailyEmailLimitReached: Bool
    let canSendBatchReminders: Bool
    let onSend: () -> Void

    private var summary: HostReminderStaffSummary {
        HostReminderStaffSummary.build(
            status: status,
            automaticRemindersEnabled: automaticRemindersEnabled,
            manualSendEnabled: manualSendEnabled,
            backendManualBatchEnabled: backendManualBatchEnabled,
            reminderLeadHours: reminderLeadHours,
            dailyEmailLimitReached: dailyEmailLimitReached,
            canSendBatchReminders: canSendBatchReminders,
            isLoading: showProof && status == nil
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(summary.title, systemImage: "bell.badge")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(summary.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let secondary = summary.secondary {
                Text(secondary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TryzubColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if canSendBatchReminders {
                Button {
                    onSend()
                } label: {
                    Label(summary.actionLabel ?? "Send reminders", systemImage: "paperplane")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isSending)
            } else if let actionLabel = summary.actionLabel {
                Text(actionLabel)
                    .frame(maxWidth: .infinity)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(TryzubColors.mutedText)
                    .padding(.vertical, 10)
            }

            if let notice, !notice.isEmpty {
                Text(notice)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TryzubColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .hostBoardGlassPanel(cornerRadius: 12)
    }
}

private struct HostReminderStaffSummary {
    enum Severity {
        case ok
        case attention
        case blocked
        case info
    }

    let title: String
    let message: String
    let secondary: String?
    let actionLabel: String?
    let severity: Severity

    static func build(
        status: ReservationReminderStatusResponse?,
        automaticRemindersEnabled: Bool,
        manualSendEnabled: Bool,
        backendManualBatchEnabled: Bool,
        reminderLeadHours: Int,
        dailyEmailLimitReached: Bool,
        canSendBatchReminders: Bool,
        isLoading: Bool
    ) -> HostReminderStaffSummary {
        let title = "Guest reminders"

        if isLoading {
            return HostReminderStaffSummary(
                title: title,
                message: "Checking whether guests still need reminders.",
                secondary: nil,
                actionLabel: nil,
                severity: .info
            )
        }

        if !automaticRemindersEnabled {
            return HostReminderStaffSummary(
                title: title,
                message: "Automatic reminders are off.",
                secondary: cutoffLine(skipped: status?.summary.skipped ?? 0, leadHours: reminderLeadHours),
                actionLabel: canSendBatchReminders ? "Send reminders" : nil,
                severity: canSendBatchReminders ? .attention : .info
            )
        }

        if dailyEmailLimitReached {
            return HostReminderStaffSummary(
                title: title,
                message: "Reminder sending is paused for today.",
                secondary: "The daily email limit has been reached.",
                actionLabel: nil,
                severity: .blocked
            )
        }

        if manualSendEnabled && !backendManualBatchEnabled {
            return HostReminderStaffSummary(
                title: title,
                message: "Guest reminders are controlled from Restaurant Settings.",
                secondary: "Manual batch sending is off for this restaurant.",
                actionLabel: nil,
                severity: .info
            )
        }

        let eligible = status?.summary.eligible ?? 0
        if canSendBatchReminders, eligible > 0 {
            return HostReminderStaffSummary(
                title: title,
                message: "\(eligible) \(eligible == 1 ? "reminder can" : "reminders can") be sent now.",
                secondary: "Send reminders before the dinner rush.",
                actionLabel: "Send reminders",
                severity: .attention
            )
        }

        if let status {
            let skipped = status.summary.skipped
            let failed = status.summary.failed
            if failed > 0 {
                return HostReminderStaffSummary(
                    title: title,
                    message: "\(failed) \(failed == 1 ? "reminder needs" : "reminders need") a staff check.",
                    secondary: skipped > 0 ? cutoffLine(skipped: skipped, leadHours: reminderLeadHours) : nil,
                    actionLabel: nil,
                    severity: .attention
                )
            }
            if skipped > 0 {
                return HostReminderStaffSummary(
                    title: title,
                    message: "No reminders can be sent right now.",
                    secondary: cutoffLine(skipped: skipped, leadHours: reminderLeadHours),
                    actionLabel: nil,
                    severity: .info
                )
            }
            return HostReminderStaffSummary(
                title: title,
                message: "Guest reminders are handled for today.",
                secondary: "No one needs a reminder right now.",
                actionLabel: nil,
                severity: .ok
            )
        }

        return HostReminderStaffSummary(
            title: title,
            message: "Guest reminders are handled for today.",
            secondary: "No one needs a reminder right now.",
            actionLabel: nil,
            severity: .ok
        )
    }

    private static func cutoffLine(skipped: Int, leadHours: Int) -> String? {
        guard skipped > 0 else { return nil }
        let cutoff: String
        if leadHours > 0 {
            cutoff = " because \(skipped == 1 ? "they are" : "they are") inside the \(leadHours)-hour cutoff"
        } else {
            cutoff = ""
        }
        return "\(skipped) \(skipped == 1 ? "guest was" : "guests were") skipped\(cutoff)."
    }
}

private struct HostBoardStat: Identifiable {
    let value: Int
    let label: String
    var id: String { label }
}

// MARK: - Availability Indicator

private struct HomeAvailabilityIndicator: View {
    let availability: RestaurantDayAvailabilityDTO?
    let slots: ReservationSlotsResponseDTO?
    let blockedCount: Int
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isClosed ? "calendar.badge.exclamationmark" : "calendar.badge.clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isClosed ? .red : .secondary)
                .frame(width: 28, height: 28)
                .hostBoardGlassSurface(cornerRadius: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(isClosed ? "Reservations closed today" : "Today availability")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isClosed ? .red : .primary)

                Text(summaryText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: onRefresh) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isLoading)
        }
        .padding(10)
        .hostBoardGlassSurface(cornerRadius: 10)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isClosed ? Color.red.opacity(0.07) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isClosed ? Color.red.opacity(0.18) : Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var isClosed: Bool {
        if let availability {
            return !availability.isOpen
        }
        if let slots {
            return !slots.isOpen
        }
        return false
    }

    private var summaryText: String {
        if let errorMessage {
            return errorMessage
        }

        if isLoading && availability == nil && slots == nil {
            return "Checking available times…"
        }

        if isClosed {
            return sourceText
        }

        var parts: [String] = []
        if let availability,
           let openTime = shortTime(availability.openTime),
           let closeTime = shortTime(availability.closeTime) {
            parts.append("\(openTime)-\(closeTime)")
        }
        parts.append("\(slots?.slots.count ?? 0) public slots")
        if sourceText == "Special override" {
            parts.append(sourceText)
        }
        if blockedCount > 0 {
            parts.append("Blocked slots: \(blockedCount)")
        }
        return parts.joined(separator: " | ")
    }

    private var sourceText: String {
        switch availability?.source.lowercased() ?? slots?.source?.lowercased() {
        case "special":
            return "Special override"
        case "weekly":
            return "Weekly"
        case .some(let source):
            return source.capitalized
        case nil:
            return "Server availability"
        }
    }

    private func shortTime(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return String(value.prefix(5))
    }
}

// MARK: - Home Service Header

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
    var onOpenShiftReminders: (() -> Void)? = nil

    private var compactServiceDateText: String {
        if Calendar.current.isDateInToday(selectedDate) {
            return selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                titleBlock
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(0)
                actionBar
                    .fixedSize()
                    .layoutPriority(1)
            }

            ReservationServiceDateSelector(selectedDate: $selectedDate, chipStyle: .hostBoardGlass)
                .padding(7)
                .hostBoardGlassSurface(cornerRadius: 13)
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .hostBoardGlassSurface(cornerRadius: 14)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
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

    private var titleBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(ReservationUIStyle.serviceTitleColor)
                .lineLimit(1)

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

            if let secondary = statusPresentation.secondaryProgressText {
                Text(secondary)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(.tertiary)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            Menu {
                if let onOpenShiftReminders {
                    Button {
                        ReservationHaptics.selection()
                        onOpenShiftReminders()
                    } label: {
                        Label("Shift reminders", systemImage: "bell.badge")
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
//        .frame(maxWidth: .infinity, alignment: .trailing)
    }

}

// MARK: - Host Columns / Rows

private struct HostBoardColumn: View {
    let title: String
    let subtitle: String
    let reservations: [ReservationRecord]
    let emptyTitle: String
    let emptySystemImage: String
    var scrollsInternally = true
    var referenceNow = Date()
    let environment: AppEnvironment
    let onAction: (ReservationHostAction, ReservationRecord) -> Void
    let onOpenReservation: (ReservationRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if scrollsInternally {
                ScrollView {
                    columnContent
                        .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                columnContent
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: scrollsInternally ? CGFloat.infinity : nil,
            alignment: .topLeading
        )
    }

    @ViewBuilder
    private var columnContent: some View {
        if reservations.isEmpty {
            CompactEmptyHostState(title: emptyTitle, systemImage: emptySystemImage)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(reservations) { reservation in
                    HostBoardReservationRow(
                        reservation: reservation,
                        referenceNow: referenceNow,
                        environment: environment,
                        onAction: onAction,
                        onOpenReservation: onOpenReservation
                    )
                }
            }
        }
    }
}

private struct HomeReservationsPanel: View {
    let snapshot: HostBoardSnapshot
    var referenceNow = Date()
    var scrollsInternally = true
    let environment: AppEnvironment
    let onAction: (ReservationHostAction, ReservationRecord) -> Void
    let onOpenReservation: (ReservationRecord) -> Void

    private var hourSections: [ReservationHourSection] {
        ReservationRecord.hourSections(from: snapshot.upcoming)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reservations")
                        .font(.headline.weight(.medium))
                }

                Spacer()
            }

            if scrollsInternally {
                ScrollView {
                    reservationsContent
                        .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                reservationsContent
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: scrollsInternally ? CGFloat.infinity : nil,
            alignment: .topLeading
        )
    }

    @ViewBuilder
    private var reservationsContent: some View {
        if hourSections.isEmpty {
            CompactEmptyHostState(
                title: "No active reservations",
                systemImage: "calendar.badge.checkmark"
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(hourSections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary.opacity(0.82))
                            Text(section.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        LazyVStack(spacing: 8) {
                            ForEach(section.reservations) { reservation in
                                HostBoardReservationRow(
                                    reservation: reservation,
                                    referenceNow: referenceNow,
                                    environment: environment,
                                    onAction: onAction,
                                    onOpenReservation: onOpenReservation
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct HostBoardReservationRow: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var floorPlanStore: FloorPlanStore

    let reservation: ReservationRecord
    var referenceNow = Date()
    let environment: AppEnvironment
    let onAction: (ReservationHostAction, ReservationRecord) -> Void
    let onOpenReservation: (ReservationRecord) -> Void

    @State private var tableAssignmentReservation: ReservationRecord?
    @State private var seatPromptReservation: ReservationRecord?
    @State private var seatAfterTableAssignment = false

    var body: some View {
        // Reuses the same compact reservation cell used by Schedule and Review.
        ReservationRowView(
            reservation: reservation,
            showsDate: false,
            context: rowContext,
            contextNote: seatedDurationText,
            seatedDurationDotStyle: seatedDurationDotStyle,
            capabilities: controller.capabilities,
            onTableTap: controller.capabilities.canEditReservationDetails && !controller.isNetworkDegraded
                ? { tableAssignmentReservation = reservation }
                : nil,
            displayStyle: .hostBoard
        ) {
            ReservationActionButtons(
                reservation: reservation,
                capabilities: controller.capabilities,
                compact: true,
                includeSecondary: false,
                compactMinHeight: 40,
                isBusy: controller.isActionInProgress(for: reservation) || controller.isNetworkDegraded,
                onAction: { action in
                    handle(action)
                },
                onSeatRequiresTableChoice: {
                    seatPromptReservation = reservation
                }
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            ReservationHaptics.selection()
            onOpenReservation(reservation)
        }
        .onLongPressGesture {
            ReservationHaptics.lightImpact()
        }
        .contextMenu {
            Button {
                onOpenReservation(reservation)
            } label: {
                Label("Details", systemImage: "info.circle")
            }

            ForEach(actionPolicy.contextMenuActions) { action in
                Button(role: action.role) {
                    handle(action)
                } label: {
                    Label(action.fullTitle, systemImage: action.systemImage)
                }
            }
        }
        .reservationSeatTableChoice(
            seatPromptReservation: $seatPromptReservation,
            onAssignTable: { reservation in
                seatAfterTableAssignment = true
                tableAssignmentReservation = reservation
            },
            onSeatWithoutTable: { reservation in
                onAction(.seat, reservation)
            }
        )
        .sheet(item: $tableAssignmentReservation) { reservation in
            TableAssignmentSheet(reservation: reservation) { tableName in
                await TableAssignmentCoordinator.assign(
                    reservationID: reservation.remoteID,
                    tableName: tableName,
                    floorPlanStore: floorPlanStore,
                    controller: controller,
                    context: modelContext
                )
                if seatAfterTableAssignment {
                    seatAfterTableAssignment = false
                    await controller.updateStatus(
                        reservation: reservation,
                        status: .seated,
                        context: modelContext
                    )
                    ReservationHaptics.success()
                }
            }
        }
    }

    private var actionPolicy: ReservationHostActionPolicy {
        ReservationHostActionPolicy(reservation: reservation, capabilities: controller.capabilities)
    }

    private var rowContext: ReservationRowContext {
        if reservation.statusValue == .seated {
            return .todaySeated
        }
        return .todayUpcoming
    }

    private var seatedDurationText: String? {
        controller.seatedDurationText(for: reservation, now: referenceNow)
    }

    private var seatedDurationDotStyle: TryzubStaffStatusDotStyle? {
        guard rowContext == .todaySeated else { return nil }
        return controller.seatedDurationDotStyle(for: reservation, now: referenceNow)
    }

    private func handle(_ action: ReservationHostAction) {
        if action == .assignTable {
            tableAssignmentReservation = reservation
        } else {
            onAction(action, reservation)
        }
    }
}

private struct CompactEmptyHostState: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .hostBoardGlassCapsule()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ReservationPresentationTime {
    static func hourLabel(from hourString: String) -> String {
        guard let hour = Int(hourString) else { return hourString }
        let adjustedHour = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return "\(adjustedHour) \(suffix)"
    }
}

// MARK: - Floor Setup Prompt

private struct HostFloorSetupPromptCard: View {
    var onOpenFloorSetup: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Floor plan not set up yet", systemImage: "square.grid.3x3.topleft.filled")
                .font(.subheadline.weight(.semibold))
            Text("Set up tables in the Floor tab.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let onOpenFloorSetup {
                Button("Open Floor Setup", action: onOpenFloorSetup)
                    .font(.footnote.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .hostBoardGlassPanel(cornerRadius: 12)
    }
}
