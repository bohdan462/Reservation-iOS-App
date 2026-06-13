//
//  HostBoardView.swift
//  Tryzub Reservations
//

import SwiftUI
import SwiftData

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

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var hostIntentStore: HostReservationOpenIntentStore
    @EnvironmentObject private var restaurantSettingsStore: RestaurantSettingsStore
    @EnvironmentObject private var guestIntelligenceStore: GuestIntelligenceStore
    @EnvironmentObject private var hostIntelligenceSettingsStore: HostIntelligenceSettingsStore
    @EnvironmentObject private var hostTableConfigStore: HostTableConfigStore
    @EnvironmentObject private var hostIntelligenceController: HostIntelligenceController
    @EnvironmentObject private var floorPlanStore: FloorPlanStore

    @State private var pendingAction: ReservationPendingAction?
    @State private var clockTick = Date()
    @State private var boardSnapshot: HostBoardSnapshot?
    @ObservedObject private var onDeviceSupportCoordinator = HostLocalModelAutoPrepareCoordinator.shared
    @State private var isShowingHostIntelligenceReview = false
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

    /// Local deterministic Host facts: reservations, date, seated times, settings.
    /// History cache enrichment is intentionally excluded; guest intelligence uses `hostIntelligenceEnrichmentKey`.
    private var hostIntelligenceEvaluationKey: String {
        "\(selectedDateKey)-\(hostIntelligenceReservationStamp)-\(hostIntelligenceSeatedStamp)-\(hostIntelligenceOperationalMinuteStamp)-\(hostIntelligenceSettingsStore.settings.hostDecisionFingerprint)-\(hostTableConfigStore.tableConfigFingerprint)"
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
        return "\(selectedDateKey)-\(availabilityStamp)-\(guestIntelStamp)-\(analyticsStamp)-\(profilePackStamp)"
    }

    private var hostBoardOperationalLoading: Bool {
        guard selectedDateKey == Date.reservationDateString() else { return false }
        return isLoadingAvailabilitySummary
            || guestIntelligenceStore.isLoading(dateKey: selectedDateKey)
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
            let safeHeight = proxy.size.height.tryzubFiniteNonNegativeLayoutValue
            let snapshot = boardSnapshot ?? HostBoardSnapshot(
                reservations: reservations,
                selectedDate: selectedDate,
                now: clockTick,
                serviceOpen: serviceDensityBounds.open,
                serviceClose: serviceDensityBounds.close,
                largePartyThreshold: hostIntelligenceSettingsStore.settings.largePartyThreshold
            )

            let closedPresentation = closedDayPresentation(for: snapshot)

            Group {
                // Both wide and narrow use a single outer ScrollView so the entire Host board
                // (header + intelligence + lists) scrolls as one unified page.
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        homeServiceHeader
                        onDeviceSupportStatusBanner

                        closedOrOperationalBody(
                            snapshot: snapshot,
                            closedPresentation: closedPresentation,
                            isWideLayout: safeWidth >= 1100
                        )
                    }
                    .padding(.bottom, 12)
                }
            }
            .padding(.horizontal, safeWidth >= 1100 ? 16 : 12)
            .padding(.top, safeWidth >= 1100 ? 8 : 6)
            .padding(.bottom, ReservationLayout.scrollBottomInset)
            .frame(maxWidth: 1100)
            .frame(width: safeWidth, height: safeHeight, alignment: .top)
            .background(TryzubColors.screenBackground)
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
            boardSnapshot = built
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
            controller.noteHostBoardSelectedDate(selectedDateKey)
            controller.refreshHomeServicePresentation(hostOperationalLoading: hostBoardOperationalLoading)
        }
        .onChange(of: hostBoardViewStateBuildKey, initial: true) { _, _ in
            refreshHostBoardViewState(reason: "semantic_key_changed")
        }
        .onChange(of: serviceBriefingStamp, initial: true) { _, _ in
            rebuildServiceBriefing()
        }
        // Single coordinated task replaces the two independent availability +
        // guest-intelligence tasks. HostBoardLifecycleCoordinator emits [HOST_LIFECYCLE]
        // traces, skips work when data is already fresh/in-flight, and provides one
        // visible lifecycle path: visible → date_changed → hidden.
        .task(id: "\(isVisible)-\(deferNetworkLoads)-\(controller.canStartNoncriticalStartupLoads)-\(selectedDateKey)") {
            guard !isRunningForPreviews else { return }
            lifecycleCoordinator.handle(
                isVisible: isVisible,
                date: selectedDateKey,
                shouldDefer: deferNetworkLoads || shouldDeferStartupOptionalLoads,
                controller: controller,
                guestIntelligenceStore: guestIntelligenceStore
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
            hostIntelligenceController.evaluate(
                input: makeHostEngineInput(now: clockTick),
                stability: hostEvaluationStabilityContext
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
            await hostIntelligenceController.refreshBriefing(
                hostBoardContext: HostBriefingHostBoardContext(
                    isStartupNetworkPassInFlight: controller.isStartupNetworkPassInFlight,
                    isHistoryPrefetching: controller.isHistoryPrefetching,
                    isLocalModelInferenceActive: HostLocalModelInferenceTracker.isActive,
                    isReservationRefreshInFlight: controller.isReservationNetworkRefreshInFlight,
                    isAvailabilitySummaryLoading: controller.isAvailabilitySummaryLoading(date: selectedDateKey),
                    isGuestIntelligenceLoading: guestIntelligenceStore.isLoading(dateKey: selectedDateKey),
                    hostBoardDateNavigationAt: controller.hostBoardDateNavigationAt,
                    startupUIReleasedAt: controller.startupUIReleasedAt,
                    now: clockTick
                )
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
            onShowFormProblems: onShowFormProblems
        )
    }

    @ViewBuilder
    private func closedOrOperationalBody(
        snapshot: HostBoardSnapshot,
        closedPresentation: ClosedDayPresentation,
        isWideLayout: Bool
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
            homeOperationalHeader(snapshot: snapshot)

            if isWideLayout {
                wideBoard(snapshot: snapshot)
            } else {
                phoneLists(snapshot: snapshot)
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
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    private func homeOperationalHeader(snapshot: HostBoardSnapshot) -> some View {
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
                peakTimeText: snapshot.peakTimeText,
                nextReservationText: snapshot.nextReservationText,
                arrivalBuckets: snapshot.arrivalBuckets,
                isSelectedDateToday: snapshot.selectedDate.reservationDateString() == Date.reservationDateString(),
                availabilitySummary: availabilitySummaryLine,
                isAvailabilityLoading: isLoadingAvailabilitySummary,
                onRefreshAvailability: selectedDate.reservationDateString() == Date.reservationDateString()
                    ? { controller.ensureAvailabilitySummary(date: selectedDateKey, force: true) }
                    : nil
            )

            hostIntelligenceSection
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
        let capacitySummary = floorPlanStore.capacitySummary
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
            if let bookingTopItem {
                BookingLoadHostCard(item: bookingTopItem, knownOnlyNote: bookingKnownOnlyNote)
            }
        }
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

    private func makeHostEngineInput(now: Date) -> HostEngineInput {
        // Use the broader history pool (all known reservations from the shell) so
        // guest-memory signals draw on history beyond the selected day.
        // backendFloorTables feeds the engine canonical table layout when available,
        // so table suggestions reflect actual backend table inventory rather than
        // the local UserDefaults HostTableConfigStore.
        HostEngineInput(
            now: now,
            selectedDate: selectedDate,
            reservations: reservations,
            availabilitySummary: availabilitySummary,
            analyticsSummary: cachedAnalyticsSummary,
            restaurantSetup: controller.hasLoadedRestaurantSetup ? controller.restaurantSetup : nil,
            localSeatedAtByReservationID: controller.localSeatedAtByReservationID,
            settings: hostIntelligenceSettingsStore.settings,
            tableConfigs: hostTableConfigStore.tables,
            allKnownReservations: allKnownReservations.isEmpty ? reservations : allKnownReservations,
            backendFloorTables: floorPlanStore.viewState.tables,
            guestIntelligenceSummariesByReservationID: guestIntelligenceStore.summariesByReservationID(
                for: selectedDateKey
            ),
            guestProfilePacksByReservationID: guestIntelligenceStore.profilePacks(
                for: reservations.map(\.remoteID)
            )
        )
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
            await controller.updateStatus(reservation: reservation, status: .confirmed, context: modelContext)
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
    let arrivalBuckets: [ArrivalFlowBucket]

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
        nextReservationText = Self.nextReservationText(
            for: nextReservation,
            isToday: isToday,
            now: now
        )
        let pressureReservations = upcoming + seated
        let nextArrivalBucketStart = nextReservation.flatMap {
            ArrivalFlowBucketBuilder.bucketStart(for: $0)
        }
        arrivalBuckets = ArrivalFlowBucketBuilder.build(
            from: pressureReservations,
            selectedDate: selectedDate,
            serviceOpen: serviceOpen,
            serviceClose: serviceClose,
            nextArrivalBucketStart: nextArrivalBucketStart,
            largePartyThreshold: largePartyThreshold
        )
        peakTimeText = Self.peakTimeText(from: arrivalBuckets)
    }

    private static func peakTimeText(from buckets: [ArrivalFlowBucket]) -> String {
        guard let peak = ArrivalFlowBucketBuilder.peakBucket(in: buckets) else {
            return "—"
        }
        let guestLabel = peak.guestCount == 1 ? "1 guest" : "\(peak.guestCount) guests"
        return "\(peak.displayTime) · \(guestLabel)"
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
    let peakTimeText: String
    let nextReservationText: String?
    let arrivalBuckets: [ArrivalFlowBucket]
    var isSelectedDateToday = true
    var availabilitySummary: String?
    var isAvailabilityLoading = false
    var onRefreshAvailability: (() -> Void)?

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
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 0) {
                    ForEach(Array(stats.enumerated()), id: \.element.label) { index, stat in
                        if index > 0 {
                            Divider().frame(height: 26).opacity(0.4)
                                .padding(.horizontal, 10)
                        }
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

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Arrival flow")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TryzubColors.primaryText)
                        Text(isSelectedDateToday
                            ? "Today's arrivals by 15-minute window"
                            : "Arrivals by 15-minute window")
                            .font(.caption2)
                            .foregroundStyle(TryzubColors.mutedText)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 4) {
                        timelineLegend(label: "Peak", value: peakTimeText)
                        if let nextReservationText {
                            timelineLegend(label: "Next", value: nextReservationText)
                        }
                    }
                }

                ReservationDensityWaveChart(
                    buckets: arrivalBuckets,
                    height: 96
                )
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(TryzubColors.border, lineWidth: 1)
        }
    }

    private func statItem(_ stat: HostBoardStat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(stat.value)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
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
        .fixedSize()
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
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

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
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    private var backgroundColor: Color {
        isClosed ? Color(.systemRed).opacity(0.08) : Color(.secondarySystemGroupedBackground)
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

    private var serviceDateText: String {
        selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // Wide (iPad): everything on one row
            HStack(alignment: .top, spacing: 10) {
                titleBlock
                ReservationServiceDateSelector(selectedDate: $selectedDate)
                    .frame(maxWidth: .infinity)
                actionBar
                    .fixedSize()
            }

            // Narrow (iPhone): title + actions, then dates below
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    titleBlock
                    Spacer(minLength: 8)
                    actionBar
                        .fixedSize()
                }

                ReservationServiceDateSelector(selectedDate: $selectedDate)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(ReservationUIStyle.serviceTitleColor)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(serviceDateText)
                        .lineLimit(1)
                        .contentTransition(.interpolate)
                        .animation(.snappy(duration: 0.35), value: selectedDate.reservationDateString())

                    Text("·")
                        .foregroundStyle(.quaternary)

                    Text(statusPresentation.primarySyncText)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: statusPresentation.primarySyncText)

                    TryzubStaffStatusIndicator(
                        style: statusPresentation.dotStyle,
                        showsOfflineIcon: controller.isNetworkDegraded
                    )
                }

                if let secondary = statusPresentation.secondaryProgressText {
                    Text(secondary)
                        .lineLimit(1)
                        .foregroundStyle(.tertiary)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: secondary)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .frame(minWidth: 168, alignment: .leading)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Menu {
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
                    .frame(width: 42, height: 40)
            }
            .buttonStyle(ReservationHeaderIconButtonStyle())
            
            if canCreateReservation {
                Button {
                    ReservationHaptics.selection()
                    onAddReservation()
                } label: {
                   Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 42, height: 40)
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
                    Text("\(snapshot.upcoming.count) active for selected date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if scrollsInternally {
                ScrollView {
                    reservationsContent
                        .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
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
                : nil
        ) {
            ReservationActionButtons(
                reservation: reservation,
                capabilities: controller.capabilities,
                compact: true,
                includeSecondary: false,
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
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
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
