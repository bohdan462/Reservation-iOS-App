//
//  ReservationsListView.swift
//  Tryzub Reservations
//

import SwiftData
import SwiftUI
import MessageUI
import UIKit

enum StaffInteractionIdleGate {
    static let idleInterval: TimeInterval = 3

    static func ageMs(since lastInteractionAt: Date, now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince(lastInteractionAt) * 1000))
    }

    static func isIdle(since lastInteractionAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastInteractionAt) >= idleInterval
    }

    static func remainingDelay(since lastInteractionAt: Date, now: Date = Date()) -> TimeInterval {
        max(0, idleInterval - now.timeIntervalSince(lastInteractionAt))
    }

    static func trace(
        work: String,
        decision: String,
        reason: String,
        lastInteractionAt: Date,
        delay: TimeInterval? = nil,
        now: Date = Date()
    ) {
        #if DEBUG
        var line = "[INTERACTION_IDLE_TRACE] work=\(work) decision=\(decision) reason=\(reason) ageMs=\(ageMs(since: lastInteractionAt, now: now))"
        if let delay {
            line += " delayMs=\(max(0, Int(delay * 1000)))"
        }
        print(line)
        #endif
    }
}

// MARK: - Root Reservation Shell

struct ReservationsListView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var controller: ReservationsController
    @StateObject private var hiddenReservations = HiddenReservationsStore()
    @StateObject private var privacyCoverSettings = RestaurantPrivacyCoverSettingsStore()
    @StateObject private var hostIntentStore = HostReservationOpenIntentStore()

    let environment: AppEnvironment
    let onLogout: () -> Void

    init(
        environment: AppEnvironment,
        controller: ReservationsController,
        onLogout: @escaping () -> Void = {}
    ) {
        self.environment = environment
        self.onLogout = onLogout
        _controller = ObservedObject(wrappedValue: controller)
        #if DEBUG
        // Production ReservationsListView must be initialized with a session-owned controller.
        assert(
            controller.creationTraceSource != "ReservationsListView_fallback",
            "ReservationsListView must not create or receive a fallback controller"
        )
        StartupTrace.productionShellAttached(controllerID: controller.startupTraceControllerID)
        #endif
    }

    var body: some View {
        StartupRootView(environment: environment, onLogout: onLogout)
            .environmentObject(controller)
            .environmentObject(hiddenReservations)
            .environmentObject(privacyCoverSettings)
            .environmentObject(hostIntentStore)
            .task {
                await controller.beginStartupPresentation(context: modelContext)
            }
    }
}

private struct StartupRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var hiddenReservations: HiddenReservationsStore
    @EnvironmentObject private var privacyCoverSettings: RestaurantPrivacyCoverSettingsStore
    @EnvironmentObject private var hostIntentStore: HostReservationOpenIntentStore
    @Query
    private var startupWindowRows: [ReservationRecord]

    let environment: AppEnvironment
    let onLogout: () -> Void

    init(environment: AppEnvironment, onLogout: @escaping () -> Void) {
        self.environment = environment
        self.onLogout = onLogout
        let bounds = activeReservationWindowQueryBounds()
        let fromDate = bounds.from
        let toDate = bounds.to
        _startupWindowRows = Query(
            filter: #Predicate<ReservationRecord> { reservation in
                !reservation.isHidden
                    && reservation.reservationDate >= fromDate
                    && reservation.reservationDate <= toDate
            }
        )
    }

    var body: some View {
        Group {
            if showsStartupLoading {
                startupLoadingView
            } else {
                ReservationsTabShell(environment: environment, onLogout: onLogout)
            }
        }
        .onAppear {
            #if DEBUG
            let startupDate = Date().reservationDateString()
            DateBoundaryTrace.boundary(
                source: "startup",
                selectedDate: startupDate,
                serviceDate: startupDate,
                afterClose: DateBoundaryTrace.isLikelyAfterClose(selectedDate: Date()),
                autoAdvanced: false,
                decision: "keep_selected_date",
                reason: "startup_uses_calendar_today"
            )
            #endif
            _ = controller.releaseStartupUIFromLocalCacheIfAvailable(context: modelContext)
            controller.noteStartupWindowQueryDelivered(rowCount: startupWindowRows.count)
            if !showsStartupLoading {
                controller.releaseStartupUI()
            }
        }
        .onChange(of: startupWindowRows.count) { _, count in
            controller.noteStartupWindowQueryDelivered(rowCount: count)
        }
        .onChange(of: showsStartupLoading) { _, isLoading in
            if !isLoading {
                controller.releaseStartupUI()
            }
        }
    }

    private var showsStartupLoading: Bool {
        if controller.hasReleasedStartupUI {
            return false
        }

        switch controller.startupPresentationState {
        case .checkingCache, .emptyCacheLoadingNetwork, .failedNoCache:
            return true
        case .loadingSavedReservations, .ready, .showingCachedDataRefreshing:
            return false
        }
    }

    @ViewBuilder
    private var startupLoadingView: some View {
        let presentation = StartupProgressPresenter.fullScreen(
            presentationState: controller.startupPresentationState,
            backgroundWork: controller.startupBackgroundWorkState
        )
        let showsFailure = {
            if case .failedNoCache = controller.startupPresentationState {
                return true
            }
            return false
        }()

        switch controller.startupPresentationState {
        case .checkingCache, .loadingSavedReservations, .emptyCacheLoadingNetwork, .failedNoCache:
            StartupCacheLoadingView(
                presentation: presentation,
                showsFailure: showsFailure,
                onRetry: retryStartup
            )
        case .ready, .showingCachedDataRefreshing:
            EmptyView()
        }
    }

    private func retryStartup() {
        Task {
            await controller.beginStartupPresentation(context: modelContext)
        }
    }
}

private struct ReservationsTabShell: View {
    @EnvironmentObject private var controller: ReservationsController
    @Query
    private var pendingReviewRows: [ReservationRecord]
    @Query
    private var serviceWindowReservations: [ReservationRecord]

    @StateObject private var restaurantSettingsStore: RestaurantSettingsStore
    @StateObject private var hostTableConfigStore: HostTableConfigStore
    @StateObject private var hostIntelligenceSettingsStore: HostIntelligenceSettingsStore
    @StateObject private var hostIntelligenceController: HostIntelligenceController
    @StateObject private var guestIntelligenceStore: GuestIntelligenceStore
    @StateObject private var guestProfileStore: GuestProfileStore
    @StateObject private var businessIntelligenceStore: BusinessIntelligenceStore
    @StateObject private var intelligenceSystemStatusStore: IntelligenceSystemStatusStore
    @StateObject private var floorPlanStore: FloorPlanStore
    @StateObject private var activityStore: ReservationActivityStore
    @StateObject private var emailAutomationSettingsStore: EmailAutomationSettingsStore
    @State private var selectedTab: ReservationsAppTab = .host
    @State private var navigationResetToken = UUID()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    let environment: AppEnvironment
    let onLogout: () -> Void

    init(environment: AppEnvironment, onLogout: @escaping () -> Void = {}) {
        self.environment = environment
        self.onLogout = onLogout
        _restaurantSettingsStore = StateObject(
            wrappedValue: RestaurantSettingsStore(apiClient: environment.apiClient)
        )
        let hostTableConfigStore = HostTableConfigStore()
        let hostIntelligenceSettingsStore = HostIntelligenceSettingsStore()
        _hostTableConfigStore = StateObject(wrappedValue: hostTableConfigStore)
        _hostIntelligenceSettingsStore = StateObject(wrappedValue: hostIntelligenceSettingsStore)
        _hostIntelligenceController = StateObject(
            wrappedValue: HostIntelligenceController(
                settingsStore: hostIntelligenceSettingsStore,
                tableStore: hostTableConfigStore
            )
        )
        _guestIntelligenceStore = StateObject(
            wrappedValue: GuestIntelligenceStore(apiClient: environment.apiClient)
        )
        _guestProfileStore = StateObject(
            wrappedValue: GuestProfileStore(apiClient: environment.apiClient)
        )
        _businessIntelligenceStore = StateObject(
            wrappedValue: BusinessIntelligenceStore(apiClient: environment.apiClient)
        )
        _intelligenceSystemStatusStore = StateObject(
            wrappedValue: IntelligenceSystemStatusStore(apiClient: environment.apiClient)
        )
        _floorPlanStore = StateObject(
            wrappedValue: FloorPlanStore(apiClient: environment.apiClient)
        )
        _activityStore = StateObject(
            wrappedValue: ReservationActivityStore(apiClient: environment.apiClient)
        )
        _emailAutomationSettingsStore = StateObject(
            wrappedValue: EmailAutomationSettingsStore.shared
        )
        let bounds = activeReservationWindowQueryBounds()
        let fromDate = bounds.from
        let toDate = bounds.to
        _pendingReviewRows = Query(
            filter: #Predicate<ReservationRecord> { reservation in
                !reservation.isHidden
                    && reservation.reservationDate >= fromDate
                    && reservation.reservationDate <= toDate
                    && (reservation.status == "new" || reservation.status == "needs_review")
            }
        )
        _serviceWindowReservations = Query(
            filter: #Predicate<ReservationRecord> { reservation in
                !reservation.isHidden
                    && reservation.reservationDate >= fromDate
                    && reservation.reservationDate <= toDate
            },
            sort: [
                SortDescriptor(\ReservationRecord.reservationDate),
                SortDescriptor(\ReservationRecord.reservationTime)
            ]
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeDashboardView(
                environment: environment,
                isActive: selectedTab == .host,
                navigationResetToken: navigationResetToken,
                onStaffInteraction: noteStaffInteraction,
                onOpenFloorSetup: { selectedTab = .floorPlan }
            )
            .tabItem {
                Label(hostTabTitle, systemImage: ReservationsAppTab.host.systemImage)
            }
            .tag(ReservationsAppTab.host)

            FloorPlanView(
                store: floorPlanStore,
                isActive: selectedTab == .floorPlan
            )
            .tabItem {
                Label(ReservationsAppTab.floorPlan.title, systemImage: ReservationsAppTab.floorPlan.systemImage)
            }
            .accessibilityLabel(ReservationsAppTab.floorPlan.accessibilityTitle)
            .tag(ReservationsAppTab.floorPlan)

            ReservationScheduleView(
                environment: environment,
                isActive: selectedTab == .bookings,
                navigationResetToken: navigationResetToken,
                onStaffInteraction: noteStaffInteraction
            )
                .tabItem {
                    Label(ReservationsAppTab.bookings.title, systemImage: ReservationsAppTab.bookings.systemImage)
                }
                .badge(pendingReviewCount)
                .tag(ReservationsAppTab.bookings)

            GuestLookupView(environment: environment, isActive: selectedTab == .guests)
                .tabItem {
                    Label(ReservationsAppTab.guests.title, systemImage: ReservationsAppTab.guests.systemImage)
                }
                .tag(ReservationsAppTab.guests)

            ReservationMoreView(environment: environment, onLogout: onLogout)
                .tabItem {
                    Label(ReservationsAppTab.more.title, systemImage: ReservationsAppTab.more.systemImage)
                }
                .tag(ReservationsAppTab.more)
        }
        .fontDesign(.rounded)
        .background {
            ReservationsStaffInteractionObserver {
                noteStaffInteraction()
            }
        }
        .background {
            Group {
                if selectedTab == .host {
                    Color(.systemBackground)
                } else {
                    TryzubColors.screenBackground
                }
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .topTrailing) {
            AppNoticeOverlay(
                notices: visibleNotices,
                onDismiss: controller.dismissNotice,
                onClearAll: controller.clearAllNotices
            )
            .padding(.top, noticeTopPadding)
            .padding(.trailing, 14)
        }
        .onAppear {
            controller.setPendingReviewAttentionCount(pendingReviewCount)
        }
        .onChange(of: pendingReviewCount) { _, count in
            controller.setPendingReviewAttentionCount(count)
        }
        .onChange(of: selectedTab) { _, _ in
            noteStaffInteraction()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                evaluateStaleNavigationReset()
                refreshOperationalDataAfterUnlock(reason: "foreground")
            }
        }
        .task {
            await runStaleNavigationResetLoop()
        }
        // Root foreground live-sync loop: fires ~every 60 s while the scene is active,
        // independent of selected tab, Host date, detail navigation, or privacy cover.
        // Backed by controller.performForegroundLiveDeltaIfAllowed which bypasses the
        // 300 s idle freshness TTL when a server cursor already exists.
        .task(id: scenePhase == .active) {
            await runForegroundLiveSyncLoop()
        }
        .restaurantPrivacyCover(
            snapshot: {
                var snap = RestaurantPrivacyCoverDataController.snapshot(from: serviceWindowReservations)
                let briefing = hostIntelligenceController.displayBriefingText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !briefing.isEmpty, briefing != "Nothing needs attention right now." {
                    snap.serviceSummary = RestaurantPrivacyCoverDataController.conciseServiceSummary(from: briefing)
                }
                return snap
            },
            onCoverDismissed: {
                refreshOperationalDataAfterUnlock(reason: "privacy_cover")
            }
        )
        .environmentObject(restaurantSettingsStore)
        .environmentObject(hostTableConfigStore)
        .environmentObject(hostIntelligenceSettingsStore)
        .environmentObject(hostIntelligenceController)
        .environmentObject(guestIntelligenceStore)
        .environmentObject(guestProfileStore)
        .environmentObject(businessIntelligenceStore)
        .environmentObject(intelligenceSystemStatusStore)
        .environmentObject(floorPlanStore)
        .environmentObject(activityStore)
        .environmentObject(emailAutomationSettingsStore)
        .onAppear {
            restaurantSettingsStore.adoptRestaurantSetup(controller.restaurantSetup)
            if floorPlanStore.freshnessCoordinator == nil {
                floorPlanStore.freshnessCoordinator = controller.freshnessCoordinator
            }
            let raw = UserDefaults.standard.string(forKey: HostTableCapacityTextParser.storageKey) ?? ""
            let result = HostTableCapacityTextParser.parse(raw)
            if !result.tables.isEmpty {
                hostTableConfigStore.save(result.tables)
            }
        }
        .onChange(of: controller.restaurantSetup) { _, setup in
            restaurantSettingsStore.adoptRestaurantSetup(setup)
        }
    }

    private var visibleNotices: [AppNotice] {
        controller.notices.filter { notice in
            switch notice.source {
            case .mutation, .email, .credentials:
                return true
            case .startup, .manualToday, .autoToday:
                return selectedTab == .host
            case .schedule:
                return selectedTab == .bookings
            case .review:
                return selectedTab == .bookings
            case .importFailures, .admin:
                return selectedTab == .host || selectedTab == .more
            }
        }
    }

    private var pendingReviewCount: Int {
        pendingReviewRows.count
    }

    private var hostTabTitle: String {
        environment.role == .developer ? "Dev" : ReservationsAppTab.host.title
    }

    private var noticeTopPadding: CGFloat {
        switch selectedTab {
        case .bookings:
            return 112
        case .host, .floorPlan, .guests, .more:
            return 62
        }
    }

    private func noteStaffInteraction() {
        controller.noteStaffInteraction()
    }

    /// Called on foreground return and privacy-cover dismissal.
    /// Uses the cursor-aware live delta path so that reconcile runs even when the
    /// 300 s idle freshness TTL would otherwise block it. Does not idle-gate these
    /// explicit unlock / app-return events; the 55 s interval throttle inside
    /// performForegroundLiveDeltaIfAllowed prevents rapid-fire duplicates.
    @MainActor
    private func refreshOperationalDataAfterUnlock(reason: String) {
        guard controller.hasReleasedStartupUI else { return }
        guard !controller.isStartupNetworkPassInFlight else { return }
        let deltaReason = reason == "privacy_cover" ? "privacy_unlock_reconcile" : "foreground_return"
        #if DEBUG
        print("[LIVE_FOREGROUND_DELTA_TRACE] decision=run reason=\(deltaReason) force=true")
        #endif
        Task { @MainActor in
            await controller.performForegroundLiveDeltaIfAllowed(
                context: modelContext,
                reason: deltaReason
            )
        }
    }

    /// Root foreground live-sync loop. Runs while scenePhase == .active, waits for
    /// startup UI release, then fires a cursor-aware active-window delta every ~60 s.
    /// Continues under privacy cover (cover is UI-only; backend awareness must not stop).
    @MainActor
    private func runForegroundLiveSyncLoop() async {
        guard scenePhase == .active else { return }
        // Spin-wait for startup release; poll every 500 ms so we don't busy-wait.
        while !Task.isCancelled, !controller.hasReleasedStartupUI {
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard !Task.isCancelled else { return }

        while !Task.isCancelled {
            guard scenePhase == .active else { return }
            await controller.performForegroundLiveDeltaIfAllowed(
                context: modelContext,
                reason: "foreground_loop"
            )
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }
        }
    }

    @MainActor
    private func runStaleNavigationResetLoop() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }
            guard scenePhase == .active else { continue }
            evaluateStaleNavigationReset()
        }
    }

    private func evaluateStaleNavigationReset(now: Date = Date()) {
        guard now.timeIntervalSince(controller.lastStaffInteractionAt) >= ReservationsStaleNavigationReset.timeout else { return }
        guard !ReservationsPresentedInteractionProbe.hasPresentedInteraction else { return }

        selectedTab = .host
        navigationResetToken = UUID()
        controller.noteStaffInteraction()
    }
}

private enum ReservationsStaleNavigationReset {
    static let timeout: TimeInterval = 5 * 60
}

private enum ReservationsPresentedInteractionProbe {
    @MainActor
    static var hasPresentedInteraction: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { window in
                containsPresentedController(in: window.rootViewController)
            }
    }

    @MainActor
    private static func containsPresentedController(in viewController: UIViewController?) -> Bool {
        guard let viewController else { return false }
        if viewController.presentedViewController != nil {
            return true
        }
        if let navigationController = viewController as? UINavigationController,
           containsPresentedController(in: navigationController.visibleViewController) {
            return true
        }
        if let tabBarController = viewController as? UITabBarController,
           containsPresentedController(in: tabBarController.selectedViewController) {
            return true
        }
        return viewController.children.contains { child in
            containsPresentedController(in: child)
        }
    }
}

private struct ReservationsStaffInteractionObserver: UIViewRepresentable {
    let onInteraction: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onInteraction: onInteraction)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onInteraction = onInteraction
        DispatchQueue.main.async {
            context.coordinator.attach(to: uiView.window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onInteraction: () -> Void
        private weak var window: UIWindow?
        private let tapGesture = UITapGestureRecognizer()
        private let panGesture = UIPanGestureRecognizer()

        init(onInteraction: @escaping () -> Void) {
            self.onInteraction = onInteraction
            super.init()
            configure(tapGesture)
            configure(panGesture)
        }

        func attach(to newWindow: UIWindow?) {
            guard window !== newWindow else { return }
            detach()
            guard let newWindow else { return }
            window = newWindow
            newWindow.addGestureRecognizer(tapGesture)
            newWindow.addGestureRecognizer(panGesture)
        }

        private func detach() {
            window?.removeGestureRecognizer(tapGesture)
            window?.removeGestureRecognizer(panGesture)
            window = nil
        }

        private func configure(_ gesture: UIGestureRecognizer) {
            gesture.cancelsTouchesInView = false
            gesture.delegate = self
            gesture.addTarget(self, action: #selector(didInteract))
        }

        @objc private func didInteract(_ gesture: UIGestureRecognizer) {
            switch gesture.state {
            case .began, .ended:
                onInteraction()
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

// MARK: - Home Dashboard

private struct HomeDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var hiddenReservations: HiddenReservationsStore
    @Query
    private var reservations: [ReservationRecord]
    @Query
    private var guestInsightHistoryPool: [ReservationRecord]

    // MARK: - Local UI State

    @State private var showManualCreate = false
    @State private var showImportFailures = false
    @State private var selectedDate = Date()
    @State private var navigationPath: [Int] = []
    /// True from the moment a reservation detail is pushed onto the nav stack until
    /// 350 ms after it is dismissed. Used to suppress Host reactive work during the
    /// presentation and pop-back animation so it doesn't compete with navigation.
    @State private var isDetailOrNavigationActive: Bool = false

    let environment: AppEnvironment
    let isActive: Bool
    let navigationResetToken: UUID
    let onStaffInteraction: () -> Void
    var onOpenFloorSetup: (() -> Void)? = nil

    init(
        environment: AppEnvironment,
        isActive: Bool,
        navigationResetToken: UUID,
        onStaffInteraction: @escaping () -> Void,
        onOpenFloorSetup: (() -> Void)? = nil
    ) {
        self.environment = environment
        self.isActive = isActive
        self.navigationResetToken = navigationResetToken
        self.onStaffInteraction = onStaffInteraction
        self.onOpenFloorSetup = onOpenFloorSetup
        let bounds = activeReservationWindowQueryBounds()
        let fromDate = bounds.from
        let toDate = bounds.to
        _reservations = Query(
            filter: #Predicate<ReservationRecord> { reservation in
                !reservation.isHidden
                    && reservation.reservationDate >= fromDate
                    && reservation.reservationDate <= toDate
            },
            sort: [
                SortDescriptor(\ReservationRecord.reservationDate),
                SortDescriptor(\ReservationRecord.reservationTime)
            ]
        )
        _guestInsightHistoryPool = Query(
            filter: #Predicate<ReservationRecord> { reservation in
                !reservation.isHidden
            },
            sort: [
                SortDescriptor(\ReservationRecord.reservationDate),
                SortDescriptor(\ReservationRecord.reservationTime)
            ]
        )
    }

    private var selectedDateReservations: [ReservationRecord] {
        // No isActive guard — the @Query is live regardless of tab visibility.
        // Previously this returned [] when isActive==false, which cascaded through
        // hostIntelligenceReservationStamp → boardSnapshotBuildKey → snapshot task,
        // publishing an empty board on every tab switch and causing the 0→7 flicker.
        // HostBoardView receives isVisible:isActive to gate network and animation behavior.
        let selectedDateKey = selectedDate.reservationDateString()
        let allForDate = reservations.filter { $0.reservationDate == selectedDateKey }
        let filtered = allForDate.filter { record in
            !hiddenReservations.isHidden(record) && record.isHostBoardOperational
        }
        #if DEBUG
        if isActive {
            let afterClose = DateBoundaryTrace.isLikelyAfterClose(selectedDate: selectedDate)
            let tomorrowKey = Calendar.current.date(byAdding: .day, value: 1, to: Date())?.reservationDateString() ?? ""
            let tomorrowRowsFilteredOut = reservations.filter { $0.reservationDate == tomorrowKey && $0.reservationDate != selectedDateKey }.count
            DateBoundaryTrace.boundary(
                source: "host",
                selectedDate: selectedDateKey,
                serviceDate: selectedDateKey,
                afterClose: afterClose,
                autoAdvanced: false,
                decision: "keep_selected_date",
                reason: "host_board_selected_date_binding"
            )
            DateBoundaryTrace.afterClose(
                selectedDate: selectedDateKey,
                afterClose: afterClose,
                todayRows: filtered.count,
                tomorrowRowsFilteredOut: tomorrowRowsFilteredOut
            )
            for record in reservations {
                let isHidden = hiddenReservations.isHidden(record)
                let isOperational = record.isHostBoardOperational
                let dateMatches = record.reservationDate == selectedDateKey
                let included = dateMatches && !isHidden && isOperational
                let reason: String = {
                    if !dateMatches { return "date_mismatch" }
                    if isHidden { return "hidden" }
                    if !isOperational { return "terminal_status" }
                    return "date_match"
                }()
                DateBoundaryTrace.selectedDateFilter(
                    selectedDate: selectedDateKey,
                    recordDate: record.reservationDate,
                    reservationID: record.remoteID,
                    included: included,
                    reason: reason
                )
                MultiDeviceSyncTrace.hostFilterTrace(
                    selectedDate: selectedDateKey,
                    id: record.remoteID,
                    recordDate: record.reservationDate,
                    time: record.reservationTime,
                    status: record.status,
                    hidden: record.isHidden,
                    superseded: record.supersededById != nil,
                    included: included,
                    reason: reason
                )
            }
        }
        #endif
        return ReservationRecord.sortedChronologically(filtered)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            // Child view reads SwiftData cache and sends staff intent back to the controller.
            HostBoardView(
                reservations: selectedDateReservations,
                allKnownReservations: guestInsightHistoryPool,
                environment: environment,
                selectedDate: $selectedDate,
                failedImportCount: controller.importFailureCount,
                isVisible: isActive,
                isAppActive: scenePhase == .active && selectedDate.reservationDateString() == Date.reservationDateString(),
                externalInteractionActive: showManualCreate || showImportFailures || isDetailOrNavigationActive,
                onAddReservation: {
                    onStaffInteraction()
                    showManualCreate = true
                },
                onManualRefresh: {
                    Task {
                        await controller.requestManualTodayRefresh(context: modelContext)
                    }
                },
                onShowFormProblems: {
                    onStaffInteraction()
                    showImportFailures = true
                },
                onOpenReservation: { reservation in
                    onStaffInteraction()
                    navigationPath.append(reservation.remoteID)
                },
                onOpenFloorSetup: onOpenFloorSetup
            )
            .refreshable {
                guard isActive else { return }
                // Staff manual refresh: controller decides whether this becomes a network GET.
                await controller.requestManualTodayRefresh(context: modelContext)
            }
            .navigationDestination(for: Int.self) { remoteID in
                reservationDestination(remoteID: remoteID)
            }
        }
        .fullScreenCover(isPresented: $showManualCreate) {
            ManualReservationFormView(source: "host") { request in
                // Manual call-in create is accepted immediately; no email is sent.
                try await controller.createAcceptedManualReservation(request, context: modelContext)
            }
            .environmentObject(controller)
        }
        .sheet(isPresented: $showImportFailures) {
            ImportFailuresView(
                environment: environment,
                onCreateReservation: { request in
                    // Failed import repair creates a managed reservation through the controller.
                    try await controller.createAcceptedManualReservation(request, context: modelContext)
                },
                onCreated: { _ in }
            )
            .environmentObject(controller)
        }
        .onChange(of: isActive) { wasActive, isNowActive in
            guard !wasActive, isNowActive else { return }
            resetHostToToday(clearNavigation: false)
        }
        .onChange(of: selectedDate) { _, _ in
            onStaffInteraction()
        }
        .onChange(of: navigationPath) { _, newPath in
            onStaffInteraction()
            if !newPath.isEmpty {
                if !isDetailOrNavigationActive {
                    isDetailOrNavigationActive = true
                    #if DEBUG
                    print("[NAV_PRESENTATION_TRACE] detailPresented=true reservationID=\(newPath.last ?? -1) tab=host")
                    #endif
                }
            } else if isDetailOrNavigationActive {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    isDetailOrNavigationActive = false
                    #if DEBUG
                    print("[NAV_PRESENTATION_TRACE] detailPresented=false reason=dismissed tab=host")
                    #endif
                }
            }
        }
        .task(id: navigationResetToken) {
            onStaffInteraction()
            resetHostToToday(clearNavigation: true)
        }
    }

    @ViewBuilder
    private func reservationDestination(remoteID: Int) -> some View {
        ReservationDetailDestinationView(
            remoteID: remoteID,
            environment: environment,
            source: "host_board",
            tab: "host"
        )
    }

    private func resetHostToToday(clearNavigation: Bool) {
        selectedDate = Calendar.current.startOfDay(for: Date())
        if clearNavigation {
            navigationPath.removeAll()
        }
    }

}

// MARK: - Schedule View

private enum BookingDateScope: Hashable, Identifiable {
    case today
    case tomorrow
    case yesterday
    case upcoming
    case past
    case last7Days
    case allHistory
    case custom(Date)

    var id: String {
        switch self {
        case .today:
            return "today"
        case .tomorrow:
            return "tomorrow"
        case .yesterday:
            return "yesterday"
        case .upcoming:
            return "upcoming"
        case .past:
            return "past"
        case .last7Days:
            return "last7Days"
        case .allHistory:
            return "allHistory"
        case .custom(let date):
            return "custom-\(date.reservationDateString())"
        }
    }

    var customDate: Date? {
        if case .custom(let date) = self {
            return date
        }
        return nil
    }

    var summaryNoun: String {
        switch self {
        case .past, .allHistory, .last7Days:
            return "records"
        case .today, .tomorrow, .yesterday, .upcoming, .custom:
            return "reservations"
        }
    }

    var isSingleDateScope: Bool {
        switch self {
        case .today, .tomorrow, .yesterday, .custom:
            return true
        case .upcoming, .past, .last7Days, .allHistory:
            return false
        }
    }

    static func defaultScope(for statusScope: ReservationScheduleScope) -> BookingDateScope {
        switch statusScope {
        case .upcoming, .needsReview, .all:
            return .upcoming
        case .noShow, .cancelled:
            return .last7Days
        }
    }

    static func scopes(for statusScope: ReservationScheduleScope) -> [BookingDateScope] {
        switch statusScope {
        case .upcoming, .needsReview:
            return [.today, .tomorrow, .upcoming]
        case .noShow:
            return [.today, .yesterday, .last7Days, .allHistory]
        case .cancelled:
            return [.today, .last7Days, .upcoming, .allHistory]
        case .all:
            return [.today, .upcoming, .past, .allHistory]
        }
    }

    func label(for statusScope: ReservationScheduleScope) -> String {
        switch self {
        case .today:
            return "Today"
        case .tomorrow:
            return "Tomorrow"
        case .yesterday:
            return "Yesterday"
        case .upcoming:
            return statusScope == .all ? "Upcoming" : "Upcoming"
        case .past:
            return "Past"
        case .last7Days:
            return "Last 7 days"
        case .allHistory:
            return "All history"
        case .custom(let date):
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    func contains(reservationDateKey: String, now: Date) -> Bool {
        let calendar = Calendar.current
        let todayKey = now.reservationDateString()

        switch self {
        case .today:
            return reservationDateKey == todayKey
        case .tomorrow:
            let tomorrowKey = calendar.date(byAdding: .day, value: 1, to: now)?.reservationDateString() ?? todayKey
            return reservationDateKey == tomorrowKey
        case .yesterday:
            let yesterdayKey = calendar.date(byAdding: .day, value: -1, to: now)?.reservationDateString() ?? todayKey
            return reservationDateKey == yesterdayKey
        case .upcoming:
            return reservationDateKey >= todayKey
        case .past:
            return reservationDateKey < todayKey
        case .last7Days:
            let startKey = calendar.date(byAdding: .day, value: -6, to: now)?.reservationDateString() ?? todayKey
            return reservationDateKey >= startKey && reservationDateKey <= todayKey
        case .allHistory:
            return true
        case .custom(let date):
            return reservationDateKey == date.reservationDateString()
        }
    }

    func representativeDate(now: Date) -> Date {
        let calendar = Calendar.current
        switch self {
        case .today, .upcoming, .past, .last7Days, .allHistory:
            return now
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: now) ?? now
        case .yesterday:
            return calendar.date(byAdding: .day, value: -1, to: now) ?? now
        case .custom(let date):
            return date
        }
    }

    func prefersNewestFirst(for statusScope: ReservationScheduleScope) -> Bool {
        switch statusScope {
        case .noShow, .cancelled:
            return true
        case .all:
            switch self {
            case .past, .allHistory, .last7Days:
                return true
            case .today, .tomorrow, .yesterday, .upcoming, .custom:
                return false
            }
        case .upcoming, .needsReview:
            return false
        }
    }

    var noShowEmptyTitle: String {
        switch self {
        case .today:
            return "No no-shows today."
        case .yesterday:
            return "No no-shows yesterday."
        case .last7Days:
            return "No no-shows in the last 7 days."
        case .allHistory:
            return "No no-show records found."
        case .custom:
            return "No no-shows on this date."
        case .tomorrow, .upcoming, .past:
            return "No no-show records found."
        }
    }

    var noShowEmptyDescription: String {
        "No guests are marked no-show for this scope."
    }

    var cancelledEmptyTitle: String {
        switch self {
        case .today:
            return "No cancelled reservations today."
        case .last7Days:
            return "No cancellations in the last 7 days."
        case .upcoming:
            return "No upcoming cancellations."
        case .allHistory:
            return "No cancelled reservations found."
        case .custom:
            return "No cancelled reservations on this date."
        case .tomorrow, .yesterday, .past:
            return "No cancelled reservations found."
        }
    }

    var cancelledEmptyDescription: String {
        "Cancelled reservations will appear here when they match this scope."
    }

    var allEmptyTitle: String {
        switch self {
        case .today:
            return "No reservations today."
        case .upcoming:
            return "No upcoming reservations found."
        case .past:
            return "No past reservations found."
        case .allHistory:
            return "No reservation history found."
        case .custom:
            return "No reservations on this date."
        case .tomorrow:
            return "No reservations tomorrow."
        case .yesterday:
            return "No reservations yesterday."
        case .last7Days:
            return "No reservations in the last 7 days."
        }
    }

    var allEmptyDescription: String {
        "Pull to refresh if this device has not loaded recent records yet."
    }
}

private struct BookingGlassSegmentBar<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        let title: String
        let accessibilityLabel: String
        var attentionDotStyle: TryzubStaffStatusDotStyle?

        var id: Value { value }
    }

    let segments: [Segment]
    @Binding var selection: Value

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(segments) { segment in
                    button(for: segment, isSelected: selection == segment.value)
                }
            }
            .padding(4)
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .scrollClipDisabled()
    }

    private func button(for segment: Segment, isSelected: Bool) -> some View {
        Button {
            guard selection != segment.value else { return }
            ReservationHaptics.selection()
            selection = segment.value
        } label: {
            HStack(spacing: 5) {
                Text(segment.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                if let attentionDotStyle = segment.attentionDotStyle {
                    TryzubStaffStatusDot(style: attentionDotStyle, diameter: 5)
                }
            }
            .font(.subheadline.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color(.systemBackground).opacity(0.88))
                        .shadow(color: Color.black.opacity(0.08), radius: 5, y: 2)
                }
            }
            .overlay {
                if isSelected {
                    Capsule()
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(segment.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct BookingDateScopeBar: View {
    let scopes: [BookingDateScope]
    @Binding var selection: BookingDateScope
    let onCalendarTap: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleScopes) { scope in
                    scopeButton(scope)
                }

                Button {
                    ReservationHaptics.selection()
                    onCalendarTap()
                } label: {
                    Image(systemName: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 42, height: 40)
                        .background(.thinMaterial, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary.opacity(0.78))
                .accessibilityLabel("Choose reservation date")
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }

    private var visibleScopes: [BookingDateScope] {
        guard case .custom = selection else { return scopes }
        return scopes + [selection]
    }

    private func scopeButton(_ scope: BookingDateScope) -> some View {
        let isSelected = selection == scope
        return Button {
            guard selection != scope else { return }
            ReservationHaptics.selection()
            selection = scope
        } label: {
            Text(scope.label(for: .all))
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, 13)
                .frame(minHeight: 40)
                .background {
                    Capsule()
                        .fill(isSelected ? Color(.systemBackground).opacity(0.9) : Color.clear)
                }
                .overlay {
                    Capsule()
                        .stroke(Color.primary.opacity(isSelected ? 0.12 : 0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .background(.thinMaterial, in: Capsule())
        .accessibilityLabel(scope.label(for: .all))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct BookingDatePickerSheet: View {
    @Binding var draftDate: Date
    let title: String
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Reservation date",
                    selection: $draftDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .padding()

                Spacer(minLength: 0)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onApply)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ReservationScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var hiddenReservations: HiddenReservationsStore
    @EnvironmentObject private var hostTableConfigStore: HostTableConfigStore
    @EnvironmentObject private var activityStore: ReservationActivityStore
    @Query
    private var reservations: [ReservationRecord]
    @Query
    private var allCachedReservations: [ReservationRecord]

    // MARK: - Local UI State

    @State private var scope: ReservationScheduleScope = .upcoming
    @State private var dateScope: BookingDateScope = .upcoming
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var calendarDraftDate = Date()
    @State private var isCalendarPresented = false
    @State private var isLoadingAllPage = false
    @State private var allModeRecords: [ReservationRecord] = []
    @State private var allModeRemoteIDs: [Int] = []
    @State private var allModeLoadGeneration = 0
    @State private var allModeLoadedPage = 0
    @State private var allModeTotal: Int?
    @State private var allModeTotalPages = 0
    @State private var allModeErrorMessage: String?
    @State private var navigationPath: [Int] = []
    /// True from the moment a reservation detail is pushed until 350 ms after it is
    /// dismissed. Pauses filter/insight/activation work so Bookings does not compete
    /// with the navigation animation.
    @State private var isDetailOrNavigationActive: Bool = false

    let environment: AppEnvironment
    let isActive: Bool
    let navigationResetToken: UUID
    let onStaffInteraction: () -> Void

    init(
        environment: AppEnvironment,
        isActive: Bool,
        navigationResetToken: UUID,
        onStaffInteraction: @escaping () -> Void
    ) {
        self.environment = environment
        self.isActive = isActive
        self.navigationResetToken = navigationResetToken
        self.onStaffInteraction = onStaffInteraction
        let bounds = activeReservationWindowQueryBounds()
        let fromDate = bounds.from
        let toDate = bounds.to
        _reservations = Query(
            filter: #Predicate<ReservationRecord> { reservation in
                !reservation.isHidden
                    && reservation.reservationDate >= fromDate
                    && reservation.reservationDate <= toDate
            },
            sort: [
                SortDescriptor(\ReservationRecord.reservationDate),
                SortDescriptor(\ReservationRecord.reservationTime)
            ]
        )
        _allCachedReservations = Query(
            filter: #Predicate<ReservationRecord> { reservation in
                !reservation.isHidden
            },
            sort: [
                SortDescriptor(\ReservationRecord.reservationDate, order: .reverse),
                SortDescriptor(\ReservationRecord.reservationTime, order: .reverse)
            ]
        )
    }

    private var usesAllModeCache: Bool {
        scope == .all
    }

    // Schedule reads cached rows; sync freshness is handled by ReservationsController.
    private var displayedReservations: [ReservationRecord] {
        scheduleRows(applyingSearch: true, tracingDateBoundary: true)
    }

    private func scheduleRows(
        applyingSearch: Bool,
        tracingDateBoundary: Bool
    ) -> [ReservationRecord] {
        guard isActive else { return [] }
        let now = Date()
        let trimmedSearchText = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)

        var rows: [ReservationRecord] = {
            switch scope {
            case .all:
                // Use the bounded active-window @Query for date scopes that don't need
                // historical records. This prevents iterating the full 4000+ SwiftData
                // pool when staff is viewing today/upcoming reservations on the All tab.
                // activeReservationWindowQueryBounds covers yesterday through +120 days,
                // which is sufficient for .today, .upcoming, .tomorrow, and .custom dates
                // within that range.
                switch dateScope {
                case .past, .allHistory:
                    // Historical views need the full pool — user explicitly asked for past records.
                    return allCachedReservations
                default:
                    // Active/future scopes: use the bounded query.
                    return reservations
                }
            case .cancelled, .noShow:
                // These tabs default to last7Days and can show allHistory; keep full pool
                // because their records may predate the active-window query start.
                return allCachedReservations
            case .upcoming, .needsReview:
                return reservations
            }
        }()

        if scope == .all, !allModeRecords.isEmpty {
            let existingIDs = Set(rows.map(\.remoteID))
            rows.append(contentsOf: allModeRecords.filter { !existingIDs.contains($0.remoteID) })
        }

        rows = rows.filter { !hiddenReservations.isHidden($0) }
        let candidateRows = rows

        switch scope {
        case .upcoming:
            rows = rows.filter {
                $0.statusValue == .new
            }
        case .needsReview:
            rows = rows.filter {
                $0.statusValue == .needsReview
            }
        case .noShow:
            rows = rows.filter {
                $0.statusValue == .noShow
            }
        case .cancelled:
            rows = rows.filter {
                $0.statusValue == .cancelled
            }
        case .all:
            break
        }

        rows = rows.filter { dateScope.contains(reservationDateKey: $0.reservationDate, now: now) }

        if tracingDateBoundary {
            traceBookingsDateBoundary(candidateRows: candidateRows, includedRows: rows)
        }

        if applyingSearch, !trimmedSearchText.isEmpty {
            rows = rows.filter { $0.matchesSearch(trimmedSearchText) }
        }

        return dateScope.prefersNewestFirst(for: scope)
            ? ReservationRecord.sortedNewestFirst(rows)
            : ReservationRecord.sortedChronologically(rows)
    }

    private var sections: [ReservationDateSection] {
        ReservationRecord.dateSections(
            from: displayedReservations,
            newestFirst: dateScope.prefersNewestFirst(for: scope)
        )
    }

    private var filterTraceKey: String {
        guard !isDetailOrNavigationActive else {
            return "paused-filter|\(isDetailOrNavigationActive)"
        }
        // Use tracingDateBoundary: false here — boundary trace is heavy for large lists
        // and should only run inside the task body, not in the SwiftUI key computation path.
        // Cap IDs to count + first 10 to avoid O(n) string construction for large lists
        // (e.g. All+allHistory = 4162 records). The count + prefix is a sufficient
        // discriminator for task scheduling; exact full-ID equality is not required.
        let rows = scheduleRows(applyingSearch: true, tracingDateBoundary: false)
        let prefix = rows.prefix(10).map { String($0.remoteID) }.joined(separator: ",")
        return "\(reminderDateKey)|\(scope.rawValue)|\(dateScope.id)|\(debouncedSearchText)|\(rows.count)|\(prefix)"
    }

    private var reminderDateKey: String {
        bookingsSelectedDateKey
    }

    private var bookingsSelectedDateKey: String {
        dateScope.representativeDate(now: Date()).reservationDateString()
    }

    private func traceBookingsDateBoundary(
        candidateRows: [ReservationRecord],
        includedRows: [ReservationRecord]
    ) {
        #if DEBUG
        guard isActive else { return }
        guard dateScope.isSingleDateScope else { return }

        let selectedKey = bookingsSelectedDateKey
        let includedIDs = Set(includedRows.map(\.remoteID))
        let selectedDate = dateScope.representativeDate(now: Date())
        let afterClose = DateBoundaryTrace.isLikelyAfterClose(selectedDate: selectedDate)
        let tomorrowKey = Calendar.current.date(byAdding: .day, value: 1, to: Date())?.reservationDateString() ?? ""
        let tomorrowRowsFilteredOut = candidateRows.filter {
            $0.reservationDate == tomorrowKey
                && $0.reservationDate != selectedKey
                && !includedIDs.contains($0.remoteID)
        }.count

        DateBoundaryTrace.boundary(
            source: "bookings",
            selectedDate: selectedKey,
            serviceDate: selectedKey,
            afterClose: afterClose,
            autoAdvanced: false,
            decision: "keep_selected_date",
            reason: "bookings_tab_selected_date_filter"
        )
        DateBoundaryTrace.afterClose(
            selectedDate: selectedKey,
            afterClose: afterClose,
            todayRows: includedRows.count,
            tomorrowRowsFilteredOut: tomorrowRowsFilteredOut
        )

        // Cap per-record trace to avoid O(n) debug output when candidateRows is large
        // (e.g. All+Today with allCachedReservations as base before the scope fix).
        // 50 rows is sufficient to diagnose date-boundary filtering issues.
        let maxPerRecordTrace = 50
        for (index, record) in candidateRows.enumerated() {
            guard index < maxPerRecordTrace else {
                #if DEBUG
                print("[BOOKINGS_ROW_TRUTH_TRACE] decision=skip reason=trace_cap_reached candidateCount=\(candidateRows.count) cap=\(maxPerRecordTrace)")
                #endif
                break
            }
            let included = includedIDs.contains(record.remoteID)
            let reason: String = {
                if record.reservationDate != selectedKey { return "date_mismatch" }
                if record.statusValue == .completed || record.statusValue == .cancelled || record.statusValue == .noShow {
                    return scope == .all ? "date_match" : "terminal_status"
                }
                return "date_match"
            }()
            DateBoundaryTrace.selectedDateFilter(
                selectedDate: selectedKey,
                recordDate: record.reservationDate,
                reservationID: record.remoteID,
                included: included,
                reason: reason
            )
        }
        #endif
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                Section {
                    scheduleControls
                }

                if let allModeErrorMessage {
                    Section {
                        Label(allModeErrorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                if controller.isSyncing
                    && !controller.hasReleasedStartupUI
                    && reservations.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Loading bookings...")
                            Spacer()
                        }
                        .padding(.vertical, 24)
                    }
                } else if sections.isEmpty {
                    Section {
                        ContentUnavailableView(
                            emptyStateTitle,
                            systemImage: "calendar",
                            description: Text(emptyStateDescription)
                        )
                    }
                } else {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.reservations) { reservation in
                                ReservationNavigationRow(
                                    reservation: reservation,
                                    environment: environment,
                                    context: .schedule,
                                    showsSubmittedTime: scope == .upcoming || scope == .needsReview,
                                    showsRowActions: showsRowActions(for: reservation),
                                    onOpenDetails: {
                                        onStaffInteraction()
                                        navigationPath.append($0.remoteID)
                                    }
                                )
                            }
                        } header: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title)
                                Text(section.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if scope == .all {
                    Section {
                        HStack(spacing: 12) {
                            Text(allModeSummaryText)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 8)

                            if allModeHasMore, dateScope == .allHistory {
                                Button {
                                    Task {
                                        await loadAllPage(reset: false, caller: "load_more_button")
                                    }
                                } label: {
                                    if isLoadingAllPage {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Text("Load More")
                                            .font(.caption.weight(.semibold))
                                    }
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.primary.opacity(0.82))
                                .padding(.horizontal, 10)
                                .frame(minHeight: 30)
                                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                                }
                                .disabled(isLoadingAllPage)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bookings")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search name, phone, email, table")
            .listStyle(.plain)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .contentMargins(.bottom, ReservationLayout.topLevelTabScrollBottomInset, for: .scrollContent)
            .refreshable {
                await refreshBookingsSelection(caller: "refreshable")
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await refreshBookingsSelection(caller: "toolbar")
                        }
                    } label: {
                        if controller.isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(controller.isSyncing)
                    .accessibilityLabel("Refresh")
                }
            }
            .onAppear {
                // Every time Bookings activates: staff-review rows open Review.
                // Normal fresh submissions stay under New.
                if reviewAttentionCount > 0 {
                    scope = .needsReview
                }
            }
            .task(id: isActive) {
                guard isActive else { return }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                guard !isDetailOrNavigationActive else {
                    #if DEBUG
                    print("[BOOKINGS_NAV_GATE_TRACE] work=activation_refresh decision=skip reason=detail_presented")
                    #endif
                    return
                }
                let lastInteractionAt = controller.lastStaffInteractionAt
                let idleDelay = StaffInteractionIdleGate.remainingDelay(since: lastInteractionAt)
                if idleDelay > 0 {
                    StaffInteractionIdleGate.trace(
                        work: "bookings_activation_refresh",
                        decision: "schedule_after_idle",
                        reason: "user_active",
                        lastInteractionAt: lastInteractionAt,
                        delay: idleDelay
                    )
                    try? await Task.sleep(for: .seconds(idleDelay))
                    guard !Task.isCancelled,
                          isActive,
                          StaffInteractionIdleGate.isIdle(since: controller.lastStaffInteractionAt) else {
                        StaffInteractionIdleGate.trace(
                            work: "bookings_activation_refresh",
                            decision: "skip",
                            reason: "user_active",
                            lastInteractionAt: controller.lastStaffInteractionAt
                        )
                        return
                    }
                }
                StaffInteractionIdleGate.trace(
                    work: "bookings_activation_refresh",
                    decision: "run",
                    reason: "idle",
                    lastInteractionAt: controller.lastStaffInteractionAt
                )
                // Bookings tab activation: controller fetches only when cached active window is stale.
                await controller.scheduleBecameActive(context: modelContext)
            }
            .task(id: isActive) {
                guard isActive else { return }
                await runBookingsAutoRefreshLoop()
            }
            .task(id: searchText) {
                guard isActive else { return }
                let value = searchText
                try? await Task.sleep(for: .milliseconds(250))
                if !Task.isCancelled {
                    debouncedSearchText = value
                }
            }
            .onChange(of: searchText) { _, _ in
                onStaffInteraction()
            }
            .task(id: filterTraceKey) {
                guard isActive else { return }
                guard !isDetailOrNavigationActive else {
                    #if DEBUG
                    print("[BOOKINGS_NAV_GATE_TRACE] work=filter_trace decision=skip reason=detail_presented")
                    #endif
                    return
                }
                // Run scheduleRows with tracingDateBoundary: true here (inside the task,
                // not in the key computation path) so the boundary trace fires once per
                // real filter change rather than on every SwiftUI render cycle.
                let rows = scheduleRows(applyingSearch: true, tracingDateBoundary: true)
                // Cap IDs to prevent logging thousands of reservation IDs in a single trace.
                // Full ID printing causes log spam and contributes to allocation pressure.
                let maxTracedIDs = 10
                let firstIDs = rows.prefix(maxTracedIDs).map { String($0.remoteID) }.joined(separator: ",")
                let omitted = max(0, rows.count - maxTracedIDs)
                #if DEBUG
                // Emit scope source decision for the All tab so smoke logs show the pool used.
                if scope == .all {
                    switch dateScope {
                    case .past, .allHistory:
                        print("[BOOKINGS_SCOPE_TRACE] tab=All source=full_history count=\(rows.count)")
                        if rows.count > 200 {
                            print("[BOOKINGS_SCOPE_TRACE] tab=All decision=large_result source=full_history count=\(rows.count)")
                        }
                    default:
                        print("[BOOKINGS_SCOPE_TRACE] tab=All source=active_window count=\(rows.count)")
                    }
                }
                #endif
                WorkflowCleanupTrace.log(
                    "BOOKINGS_TAB_TRACE",
                    fields: [
                        "date": reminderDateKey,
                        "tab": scope.rawValue,
                        "count": "\(rows.count)"
                    ]
                )
                WorkflowCleanupTrace.log(
                    "BOOKINGS_FILTER_TRACE",
                    fields: [
                        "date": reminderDateKey,
                        "tab": scope.rawValue,
                        "count": "\(rows.count)",
                        "firstIDs": firstIDs,
                        "omitted": "\(omitted)"
                    ]
                )
                if !debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    WorkflowCleanupTrace.log(
                        "SEARCH_RESULT_TRACE",
                        fields: [
                            "query": "redacted",
                            "results": "\(rows.count)",
                            "firstIDs": firstIDs,
                            "omitted": "\(omitted)"
                        ]
                    )
                }
            }
            .task(id: activityFeedWarmTaskKey) {
                await warmVisibleBookingsActivityFeeds()
            }
            .onChange(of: scope) { _, newScope in
                onStaffInteraction()
                allModeLoadGeneration += 1
                dateScope = BookingDateScope.defaultScope(for: newScope)
                if newScope != .all {
                    isLoadingAllPage = false
                }
            }
            .onChange(of: dateScope.id) { _, _ in
                onStaffInteraction()
            }
            .onChange(of: navigationPath) { _, newPath in
                onStaffInteraction()
                if !newPath.isEmpty {
                    if !isDetailOrNavigationActive {
                        isDetailOrNavigationActive = true
                        #if DEBUG
                        print("[NAV_PRESENTATION_TRACE] detailPresented=true reservationID=\(newPath.last ?? -1) tab=bookings")
                        #endif
                    }
                } else if isDetailOrNavigationActive {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled else { return }
                        isDetailOrNavigationActive = false
                        #if DEBUG
                        print("[NAV_PRESENTATION_TRACE] detailPresented=false reason=dismissed tab=bookings")
                        #endif
                    }
                }
            }
            .navigationDestination(for: Int.self) { remoteID in
                reservationDestination(remoteID: remoteID)
            }
            .sheet(isPresented: $isCalendarPresented) {
                BookingDatePickerSheet(
                    draftDate: $calendarDraftDate,
                    title: "Choose date",
                    onCancel: {
                        isCalendarPresented = false
                    },
                    onApply: {
                        let selectedDate = calendarDraftDate
                        dateScope = .custom(selectedDate)
                        isCalendarPresented = false
                        Task {
                            await refreshBookingsDate(
                                selectedDate.reservationDateString(),
                                trigger: .calendarSelection,
                                force: false
                            )
                        }
                    }
                )
            }
            .task(id: navigationResetToken) {
                onStaffInteraction()
                navigationPath.removeAll()
            }
        }
    }

    // Intent: Was the Bookings tab's automatic active-window network poll. Demoted in
    // LIVE-SYNC-1B: ReservationsTabShell.runForegroundLiveSyncLoop now owns all
    // automatic active-window reservation network polling. The Bookings list rebuilds
    // from SwiftData via @Query and does not need its own periodic network poll.
    @MainActor
    private func runBookingsAutoRefreshLoop() async {
        guard isActive else { return }
        // Root foreground live-sync loop owns active-window reservation polling once
        // startup UI is released. Do not issue a duplicate reservation network call here.
        #if DEBUG
        print("[LIVE_SYNC_OWNER_TRACE] owner=bookings decision=skip reason=root_foreground_owner")
        #endif
        // Task exits; restarted by SwiftUI if isActive changes.
    }

    private func refreshBookingsSelection(caller: String) async {
        guard isActive else { return }

        if dateScope.customDate != nil {
            await refreshBookingsDate(
                bookingsSelectedDateKey,
                trigger: .manualRefresh,
                force: true
            )
            return
        }

        if scope == .all {
            if usesAllModeCache {
                controller.scheduleHistoryPrefetchWhenReady(context: modelContext, force: true)
                await controller.requestScheduleRefresh(context: modelContext)
            } else {
                await loadAllPage(reset: true, caller: "\(caller)_all")
            }
        } else {
            // Bookings manual refresh stays on the shared active-window path for range scopes.
            await controller.requestScheduleRefresh(context: modelContext)
        }
    }

    private func refreshBookingsDate(
        _ date: String,
        trigger: ReservationsController.ScheduleDateRefreshTrigger,
        force: Bool
    ) async {
        do {
            try await controller.refreshScheduleDate(
                context: modelContext,
                date: date,
                trigger: trigger,
                force: force
            )
        } catch {
            #if DEBUG
            print("[FUTURE_DATE_FETCH_TRACE] date=\(date) decision=skip reason=failed trigger=\(trigger.rawValue) error=\(error.localizedDescription)")
            #endif
        }
    }

    private var newAttentionCount: Int {
        reservations.filter { reservation in
            !hiddenReservations.isHidden(reservation)
                && reservation.statusValue == .new
        }.count
    }

    private var reviewAttentionCount: Int {
        reservations.filter { reservation in
            !hiddenReservations.isHidden(reservation)
                && reservation.statusValue == .needsReview
        }.count
    }

    private var scheduleControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            BookingGlassSegmentBar(
                segments: ReservationScheduleScope.allCases.map { statusScope in
                    BookingGlassSegmentBar<ReservationScheduleScope>.Segment(
                        value: statusScope,
                        title: scheduleSegmentTitle(for: statusScope),
                        accessibilityLabel: "\(scheduleSegmentTitle(for: statusScope)) reservations",
                        attentionDotStyle: attentionDotStyle(for: statusScope)
                    )
                },
                selection: $scope
            )

            BookingDateScopeBar(
                scopes: BookingDateScope.scopes(for: scope),
                selection: $dateScope,
                onCalendarTap: openCalendarPicker
            )
        }
    }

    private func attentionDotStyle(for statusScope: ReservationScheduleScope) -> TryzubStaffStatusDotStyle? {
        switch statusScope {
        case .upcoming:
            return newAttentionCount > 0 ? .greenFlashing : nil
        case .needsReview:
            return reviewAttentionCount > 0 ? .redFlashing : nil
        case .noShow, .all, .cancelled:
            return nil
        }
    }

    private func openCalendarPicker() {
        calendarDraftDate = dateScope.customDate ?? dateScope.representativeDate(now: Date())
        isCalendarPresented = true
    }

    private func showsRowActions(for reservation: ReservationRecord) -> Bool {
        switch scope {
        case .cancelled, .noShow:
            return false
        case .all:
            return reservation.statusValue != .cancelled
                && reservation.statusValue != .noShow
                && reservation.statusValue != .completed
        case .upcoming, .needsReview:
            return true
        }
    }

    private var emptyStateTitle: String {
        if !debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No reservations match this search."
        }

        switch scope {
        case .upcoming:
            return "No new reservations."
        case .needsReview:
            return "No reservations need review."
        case .noShow:
            return dateScope.noShowEmptyTitle
        case .cancelled:
            return dateScope.cancelledEmptyTitle
        case .all:
            return dateScope.allEmptyTitle
        }
    }

    private var emptyStateDescription: String {
        if !debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Search checks guest name, phone, email, and table."
        }

        switch scope {
        case .upcoming:
            return "New online submissions will appear here."
        case .needsReview:
            return "Compare details before confirming."
        case .noShow:
            return dateScope.noShowEmptyDescription
        case .cancelled:
            return dateScope.cancelledEmptyDescription
        case .all:
            return dateScope.allEmptyDescription
        }
    }

    private func scheduleSegmentTitle(for scope: ReservationScheduleScope) -> String {
        scope.title
    }

    private var allModeSummaryText: String {
        if let customDate = dateScope.customDate {
            let dateLabel = customDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            return "Showing \(displayedReservations.count) on \(dateLabel)"
        }

        if usesAllModeCache {
            if controller.isHistoryPrefetching {
                return "\(displayedReservations.count) \(dateScope.summaryNoun) · loading older history…"
            }
            return "\(displayedReservations.count) \(dateScope.summaryNoun) · \(dateScope.label(for: scope))"
        }

        guard let allModeTotal else {
            return isLoadingAllPage ? "Loading history..." : "History not loaded"
        }

        return "Showing \(min(displayedReservations.count, allModeTotal)) of \(allModeTotal)"
    }

    private var allModeHasMore: Bool {
        !usesAllModeCache
            && scope == .all
            && dateScope == .allHistory
            && allModeLoadedPage > 0
            && allModeLoadedPage < allModeTotalPages
    }

    private func loadAllPage(reset: Bool, caller: String) async {
        guard isActive, scope == .all else {
            ReservationAPILogger.skip(
                reason: .scheduleAllBlocked,
                message: "schedule_all_page blocked caller=\(caller) scope=\(scope.rawValue) isActive=\(isActive)"
            )
            return
        }

        guard !isLoadingAllPage else { return }
        isLoadingAllPage = true
        allModeErrorMessage = nil
        let generation = allModeLoadGeneration
        defer { isLoadingAllPage = false }

        let page = reset ? 1 : allModeLoadedPage + 1
        let search = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank

        do {
            let response = try await controller.loadScheduleAllPage(
                context: modelContext,
                page: page,
                search: search,
                isAllScope: scope == .all,
                isScheduleTabActive: isActive,
                callerContext: "\(caller) tab=Schedule scope=\(scope.rawValue) generation=\(generation)",
                isStillAllowed: {
                    isActive && scope == .all && generation == allModeLoadGeneration
                }
            )
            guard generation == allModeLoadGeneration, isActive, scope == .all else {
                ReservationAPILogger.skip(
                    reason: .scheduleAllBlocked,
                    message: "schedule_all_page result ignored caller=\(caller) generation=\(generation) currentGeneration=\(allModeLoadGeneration) scope=\(scope.rawValue) isActive=\(isActive)"
                )
                return
            }
            if reset {
                allModeRemoteIDs = []
                allModeRecords = []
            }
            let existingIDs = Set(allModeRemoteIDs)
            allModeRemoteIDs.append(contentsOf: response.data.map(\.id).filter { !existingIDs.contains($0) })
            refreshAllModeRecords()
            allModeLoadedPage = page
            allModeTotal = response.total
            allModeTotalPages = response.totalPages
        } catch {
            allModeErrorMessage = error.localizedDescription
        }
    }

    private func refreshAllModeRecords() {
        guard !allModeRemoteIDs.isEmpty else {
            allModeRecords = []
            return
        }

        do {
            let repository = ReservationRepository(context: modelContext)
            allModeRecords = ReservationRecord.sortedNewestFirst(
                try repository.records(remoteIDs: allModeRemoteIDs)
            )
        } catch {
            allModeErrorMessage = error.localizedDescription
        }
    }

    private var reservationLookupRows: [ReservationRecord] {
        if usesAllModeCache { return allCachedReservations }
        if scope == .all { return allModeRecords }
        return reservations
    }

    private var activityFeedWarmDateKeys: [String] {
        // List-level activity evidence is optional and can churn network/state during
        // tab changes and search. Detail/activity screens still load activity on demand.
        []
    }

    private var activityFeedWarmTaskKey: String {
        "activity-feed-disabled-\(isActive)"
    }

    private func warmVisibleBookingsActivityFeeds() async {
        guard isActive else { return }

        for dateKey in activityFeedWarmDateKeys {
            guard !Task.isCancelled,
                  let date = ReservationFormatters.reservationDateKey.date(from: dateKey) else {
                continue
            }

            await activityStore.loadActivityFeed(
                date: date,
                perPage: 100,
                guestNameByReservationID: guestNameByReservationID(forActivityDate: dateKey)
            )
        }
    }

    private func guestNameByReservationID(forActivityDate dateKey: String) -> [Int: String] {
        displayedReservations
            .filter { $0.reservationDate == dateKey }
            .reduce(into: [Int: String]()) { result, reservation in
                result[reservation.remoteID] = reservation.guestName
            }
    }

    @ViewBuilder
    private func reservationDestination(remoteID: Int) -> some View {
        ReservationDetailDestinationView(
            remoteID: remoteID,
            environment: environment,
            source: debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "schedule" : "search",
            tab: scope.rawValue
        )
    }
}

// MARK: - Pending Review View

private struct ReservationReviewQueueView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var hiddenReservations: HiddenReservationsStore

    // MARK: - Local UI State

    @State private var scope: ReservationQueueScope = .pending
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var navigationPath: [Int] = []

    let reservations: [ReservationRecord]
    let environment: AppEnvironment
    let isActive: Bool

    private var visibleReservations: [ReservationRecord] {
        reservations.filter { !hiddenReservations.isHidden($0) }
    }

    private var pendingAttentionCount: Int {
        visibleReservations.filter {
            $0.statusValue == .new || $0.statusValue == .needsReview
        }.count
    }

    private var needsReviewCount: Int {
        visibleReservations.filter { $0.statusValue == .needsReview }.count
    }

    // Pending is the staff default: new and needs_review, oldest submitted first.
    private var queueReservations: [ReservationRecord] {
        guard isActive else { return [] }
        let trimmedSearchText = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = reservations.filter { reservation in
            guard !hiddenReservations.isHidden(reservation) else { return false }
            switch scope {
            case .pending:
                return reservation.statusValue == .new || reservation.statusValue == .needsReview
            case .needsReview:
                return reservation.statusValue == .needsReview
            }
        }

        let searchedRows = trimmedSearchText.isEmpty
            ? rows
            : rows.filter { $0.matchesSearch(trimmedSearchText) }

        return ReservationRecord.sortedByCreatedAtAscending(searchedRows)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                Section {
                    Picker("Queue", selection: $scope) {
                        Text(queuePickerLabel(for: .pending)).tag(ReservationQueueScope.pending)
                        Text(queuePickerLabel(for: .needsReview)).tag(ReservationQueueScope.needsReview)
                    }
                    .pickerStyle(.segmented)
                }

                if queueReservations.isEmpty {
                    Section {
                        ContentUnavailableView(
                            scope == .needsReview ? "Nothing Needs Review" : "No Pending Reservations",
                            systemImage: scope == .needsReview ? "checkmark.seal" : "tray",
                            description: Text("Pull to refresh or adjust search.")
                        )
                    }
                } else {
                    Section {
                        ForEach(queueReservations) { reservation in
                            ReservationNavigationRow(
                                reservation: reservation,
                                environment: environment,
                                context: .review,
                                contextNote: reviewContext(for: reservation),
                                onOpenDetails: { navigationPath.append($0.remoteID) }
                            )
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scope == .pending ? "Pending reservations" : "Needs review")
                            Text("Oldest submitted first")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Name, phone, email")
            .listStyle(.plain)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .contentMargins(.bottom, ReservationLayout.topLevelTabScrollBottomInset, for: .scrollContent)
            .refreshable {
                guard isActive else { return }
                // Staff manual queue refresh: controller fetches new + needs_review.
                await controller.requestReviewRefresh(context: modelContext)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            guard isActive else { return }
                            // Same pending queue refresh path as pull-to-refresh.
                            await controller.requestReviewRefresh(context: modelContext)
                        }
                    } label: {
                        if controller.isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(controller.isSyncing)
                    .accessibilityLabel("Refresh")
                }
            }
            .task(id: isActive) {
                guard isActive else { return }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                // Legacy Review screen activation; visible Needs Review now lives in Bookings.
                await controller.reviewBecameActive(context: modelContext)
            }
            .task(id: searchText) {
                guard isActive else { return }
                let value = searchText
                try? await Task.sleep(for: .milliseconds(250))
                if !Task.isCancelled {
                    debouncedSearchText = value
                }
            }
            .navigationDestination(for: Int.self) { remoteID in
                reservationDestination(remoteID: remoteID)
            }
        }
    }

    @ViewBuilder
    private func reservationDestination(remoteID: Int) -> some View {
        ReservationDetailDestinationView(
            remoteID: remoteID,
            environment: environment,
            source: debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "review" : "search",
            tab: scope.rawValue
        )
    }

    private func queuePickerLabel(for scope: ReservationQueueScope) -> String {
        switch scope {
        case .pending:
            let count = pendingAttentionCount
            return count > 0 ? "Pending (\(count))" : "Pending"
        case .needsReview:
            let count = needsReviewCount
            return count > 0 ? "Needs Review (\(count))" : "Needs Review"
        }
    }

    // Intent: Small operational context for pending queue triage.
    private func reviewContext(for reservation: ReservationRecord) -> String? {
        if reservation.statusValue == .needsReview {
            return "Needs review"
        }

        if reservation.partySize >= 7 {
            return "Large party"
        }

        let activeSameDay = reservations.filter {
            $0.reservationDate == reservation.reservationDate
                && !hiddenReservations.isHidden($0)
                && $0.statusValue != .cancelled
                && $0.statusValue != .noShow
        }
        let dayGuests = activeSameDay.reduce(0) { $0 + $1.partySize }
        let sameTime = activeSameDay.filter {
            String($0.reservationTime.prefix(5)) == String(reservation.reservationTime.prefix(5))
        }

        if sameTime.count > 1 {
            return "Same time conflict"
        }

        if dayGuests >= 20 {
            return "Busy service day"
        }

        return nil
    }
}

// MARK: - More View

private struct ReservationMoreView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var privacyCoverSettings: RestaurantPrivacyCoverSettingsStore
    @EnvironmentObject private var settingsStore: RestaurantSettingsStore

    @EnvironmentObject private var hostTableConfigStore: HostTableConfigStore
    @EnvironmentObject private var hostIntelligenceSettingsStore: HostIntelligenceSettingsStore
    @EnvironmentObject private var floorPlanStore: FloorPlanStore
    @ObservedObject private var onDeviceSupportCoordinator = HostLocalModelAutoPrepareCoordinator.shared
    @State private var showManualCreate = false
    @State private var showFailedImports = false
    @State private var showLogoutConfirmation = false
    @State private var path: [ReservationMoreDestination] = []

    let environment: AppEnvironment
    let onLogout: () -> Void

    init(environment: AppEnvironment, onLogout: @escaping () -> Void = {}) {
        self.environment = environment
        self.onLogout = onLogout
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: ReservationMoreDestination.notices) {
                        HStack {
                            Label("Notices", systemImage: "bell")
                            Spacer()
                            if !controller.notices.isEmpty {
                                Text("\(controller.notices.count)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    NavigationLink(value: ReservationMoreDestination.serviceBoardGuide) {
                        Label("Service Board Guide", systemImage: "questionmark.circle")
                    }
                }

                RestaurantPrivacyCoverSettingsSection(settings: privacyCoverSettings)

                if controller.capabilities.canViewDeveloperDiagnostics {
                    OnDeviceSupportMoreSection(coordinator: onDeviceSupportCoordinator)
                }

                Section("Restaurant Operations") {
                    NavigationLink(value: ReservationMoreDestination.cancelled) {
                        Label("Cancelled Reservations", systemImage: "xmark.circle")
                    }

                    if controller.capabilities.canViewHiddenReservations {
                        NavigationLink(value: ReservationMoreDestination.hidden) {
                            Label("Hidden Reservations", systemImage: "archivebox")
                        }
                    }

                    if controller.capabilities.canManageRestaurantSettings {
                        NavigationLink(value: ReservationMoreDestination.restaurantSettings) {
                            Label("Restaurant Settings", systemImage: "gearshape")
                        }

                        NavigationLink(value: ReservationMoreDestination.todayAvailability) {
                            Label("Today Availability", systemImage: "calendar.badge.clock")
                        }

                        NavigationLink(value: ReservationMoreDestination.weeklyHours) {
                            Label("Weekly Hours", systemImage: "clock")
                        }

                        NavigationLink(value: ReservationMoreDestination.blockedTimeSlots) {
                            Label("Blocked Time Slots", systemImage: "nosign")
                        }

                        NavigationLink(value: ReservationMoreDestination.hostIntelligenceSettings) {
                            Label("Host Intelligence Settings", systemImage: "brain.head.profile")
                        }
                    }

                    if controller.capabilities.canCreateManualReservations {
                        Button {
                            showManualCreate = true
                        } label: {
                            Label("Create Manual Reservation", systemImage: "plus.circle")
                        }
                    }
                }

                Section("Business") {
                    NavigationLink(value: ReservationMoreDestination.activityHistory) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Activity History")
                                Text("Changes, cancellations, and table updates")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                    }

                    NavigationLink(value: ReservationMoreDestination.serviceIntelligence) {
                        Label("Service Intelligence", systemImage: "sparkles")
                    }

                    if controller.capabilities.canViewAnalytics {
                        NavigationLink(value: ReservationMoreDestination.businessAnalytics) {
                            Label("Business Analytics", systemImage: "chart.bar")
                        }
                    }

                    NavigationLink(value: ReservationMoreDestination.regularGuests) {
                        Label("Regulars / Guest Memory", systemImage: "person.2.crop.square.stack")
                    }
                }

                if controller.capabilities.canViewFailedImports
                    || controller.capabilities.canViewDeveloperDiagnostics {
                    Section("Developer / Support") {
                        if controller.capabilities.canViewFailedImports {
                            Button {
                                showFailedImports = true
                            } label: {
                                Label("Failed Imports", systemImage: "exclamationmark.triangle")
                            }
                        }

                        if controller.capabilities.canViewDeveloperDiagnostics {
                            NavigationLink(value: ReservationMoreDestination.diagnostics) {
                                Label("API & App Diagnostics", systemImage: "stethoscope")
                            }
                        }
                    }
                }


                Section("Account") {
                    LabeledContent("Role", value: environment.role.displayName)
                    LabeledContent("User", value: environment.username)

                    Button(role: .destructive) {
                        showLogoutConfirmation = true
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("More")
            .contentMargins(.bottom, ReservationLayout.topLevelTabScrollBottomInset, for: .scrollContent)
            .navigationDestination(for: ReservationMoreDestination.self) { destination in
                moreDestination(destination)
            }
            .alert("Log out?", isPresented: $showLogoutConfirmation) {
                Button("Log Out", role: .destructive) {
                    logout()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You’ll need your WordPress app password to sign in again.")
            }
            .fullScreenCover(isPresented: $showManualCreate) {
                ManualReservationFormView(source: "more") { request in
                    // Manual call-in create is accepted immediately; no email is sent.
                    try await controller.createAcceptedManualReservation(request, context: modelContext)
                }
            }
            .sheet(isPresented: $showFailedImports) {
                ImportFailuresView(
                    environment: environment,
                    onCreateReservation: { request in
                        try await controller.createAcceptedManualReservation(request, context: modelContext)
                    },
                    onCreated: { _ in }
                )
                .environmentObject(controller)
            }
        }
    }

    private func logout() {
        showManualCreate = false
        showFailedImports = false
        path.removeAll()
        controller.prepareForLogout()
        onLogout()
    }

    @ViewBuilder
    private func moreDestination(_ destination: ReservationMoreDestination) -> some View {
        switch destination {
        case .cancelled:
            CancelledReservationsView(
                environment: environment,
                onOpenDetails: { reservation in
                    path.append(.cancelledDetail(remoteID: reservation.remoteID))
                }
            )
        case .cancelledDetail(let remoteID):
            ReservationDetailDestinationView(
                remoteID: remoteID,
                environment: environment,
                source: "cancelled",
                tab: "Cancelled"
            )
        case .hidden:
            HiddenReservationsView(environment: environment)
        case .restaurantSettings:
            RestaurantSettingsView(settingsStore: settingsStore)
        case .todayAvailability:
            TodayAvailabilityView(settingsStore: settingsStore)
        case .weeklyHours:
            WeeklyHoursView(settingsStore: settingsStore)
        case .blockedTimeSlots:
            BlockedTimeSlotsView(settingsStore: settingsStore)
        case .serviceIntelligence:
            GlobalServiceIntelligenceView(environment: environment)
        case .activityHistory:
            ActivityHistoryView()
        case .businessAnalytics:
            BusinessAnalyticsView(settingsStore: settingsStore)
        case .serviceBoardGuide:
            ServiceBoardGuideView()
        case .regularGuests:
            RegularGuestsView(environment: environment)
        case .hostIntelligenceSettings:
            HostIntelligenceSettingsView(
                settingsStore: hostIntelligenceSettingsStore,
                tableStore: hostTableConfigStore,
                floorPlanStore: floorPlanStore,
                capabilities: controller.capabilities,
                restaurantSetup: controller.hasLoadedRestaurantSetup ? controller.restaurantSetup : nil
            )
        case .diagnostics:
            DeveloperDiagnosticsView(environment: environment)
                .environmentObject(controller)
        case .notices:
            AppNoticesScreen(
                notices: controller.notices,
                onDismiss: controller.dismissNotice,
                onClearAll: controller.clearAllNotices
            )
        }
    }

}

private enum ReservationMoreDestination: Hashable {
    case notices
    case cancelled
    case cancelledDetail(remoteID: Int)
    case hidden
    case restaurantSettings
    case todayAvailability
    case weeklyHours
    case blockedTimeSlots
    case serviceIntelligence
    case activityHistory
    case businessAnalytics
    case serviceBoardGuide
    case regularGuests
    case hostIntelligenceSettings
    case diagnostics
}

private struct ReservationDetailDestinationView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var hiddenReservations: HiddenReservationsStore
    @Query private var reservations: [ReservationRecord]
    @State private var isFetching = false
    @State private var fetchAttempted = false
    @State private var fetchResult: String?

    let remoteID: Int
    let environment: AppEnvironment
    let source: String
    let tab: String

    init(remoteID: Int, environment: AppEnvironment, source: String = "route", tab: String = "unknown") {
        self.remoteID = remoteID
        self.environment = environment
        self.source = source
        self.tab = tab
        _reservations = Query(
            filter: #Predicate<ReservationRecord> { $0.remoteID == remoteID },
            sort: [
                SortDescriptor(\ReservationRecord.reservationDate, order: .reverse),
                SortDescriptor(\ReservationRecord.reservationTime, order: .reverse)
            ]
        )
    }

    var body: some View {
        if let reservation = reservations.first {
            if hiddenReservations.isHidden(reservation) {
                ContentUnavailableView(
                    "Reservation no longer exists or was hidden.",
                    systemImage: "eye.slash",
                    description: Text("This reservation is hidden from normal staff lists.")
                )
                .task {
                    logRoute(localFound: true)
                    logFetch(result: "hidden")
                }
            } else {
                ReservationDetailView(reservation: reservation, environment: environment)
                    .task {
                        logRoute(localFound: true)
                        logFetch(result: "local")
                    }
            }
        } else if isFetching {
            ProgressView("Loading reservation...")
        } else {
            ContentUnavailableView(
                "Reservation no longer exists or was hidden.",
                systemImage: "calendar.badge.exclamationmark",
                description: Text(fetchResult == "error" ? "Could not load this reservation. Check the connection and try again." : "It may have been removed from the server or hidden.")
            )
            .task {
                await fetchMissingReservationIfNeeded()
            }
        }
    }

    @MainActor
    private func fetchMissingReservationIfNeeded() async {
        guard !fetchAttempted else { return }
        fetchAttempted = true
        logRoute(localFound: false)
        isFetching = true
        let dto = await controller.reconcileReservation(id: remoteID, context: modelContext)
        isFetching = false
        if dto == nil {
            fetchResult = "not_found"
            logFetch(result: "not_found")
        } else {
            fetchResult = "server"
            logFetch(result: "server")
        }
    }

    private func logRoute(localFound: Bool) {
        WorkflowCleanupTrace.log(
            "DETAIL_ROUTE_TRACE",
            fields: [
                "source": source,
                "tab": tab,
                "reservationID": "\(remoteID)",
                "localFound": "\(localFound)"
            ]
        )
    }

    private func logFetch(result: String) {
        WorkflowCleanupTrace.log(
            "DETAIL_FETCH_TRACE",
            fields: [
                "reservationID": "\(remoteID)",
                "result": result
            ]
        )
    }
}

// MARK: - Cancelled Reservations View

private struct CancelledReservationsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var hiddenReservations: HiddenReservationsStore
    @Query
    private var reservations: [ReservationRecord]

    let environment: AppEnvironment
    let onOpenDetails: (ReservationRecord) -> Void

    @State private var isLoading = false
    @State private var errorMessage: String?

    private let window: (from: String, to: String)

    init(
        environment: AppEnvironment,
        onOpenDetails: @escaping (ReservationRecord) -> Void
    ) {
        self.environment = environment
        self.onOpenDetails = onOpenDetails
        let window = CancelledReservationsPresenter.defaultWindow()
        self.window = window
        let statusCancelled = ReservationStatus.cancelled.rawValue
        let from = window.from
        let to = window.to
        _reservations = Query(
            filter: #Predicate<ReservationRecord> { record in
                record.status == statusCancelled
                    && record.reservationDate >= from
                    && record.reservationDate <= to
            },
            sort: [
                SortDescriptor(\ReservationRecord.reservationDate, order: .reverse),
                SortDescriptor(\ReservationRecord.reservationTime, order: .reverse)
            ]
        )
    }

    private var cancelledRows: [ReservationRecord] {
        ReservationRecord.sortedNewestFirst(
            reservations.filter {
                $0.statusValue == .cancelled
                    && !hiddenReservations.isHidden($0)
                    && $0.reservationDate >= window.from
                    && $0.reservationDate <= window.to
            }
        )
    }

    var body: some View {
        List {
            Section {
                Text("Real cancelled reservations from \(window.from) through \(window.to). Hidden/test rows live in admin cleanup instead.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            if isLoading && cancelledRows.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading cancelled reservations...")
                        Spacer()
                    }
                    .padding(.vertical, 24)
                }
            } else if cancelledRows.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Cancelled Reservations",
                        systemImage: "xmark.circle",
                        description: Text("Cancelled guest self-service and staff cancellations will appear here.")
                    )
                }
            } else {
                Section("Cancelled reservations") {
                    ForEach(cancelledRows) { reservation in
                        ReservationNavigationRow(
                            reservation: reservation,
                            environment: environment,
                            context: .schedule,
                            contextNote: "Cancelled",
                            onOpenDetails: onOpenDetails
                        )
                    }
                }
            }
        }
        .navigationTitle("Cancelled Reservations")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.plain)
        .contentMargins(.bottom, ReservationLayout.topLevelTabScrollBottomInset, for: .scrollContent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load(force: true) }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoading)
            }
        }
        .task {
            // Lazy screen load: status=cancelled window fetch, upsert-only.
            await load(force: false)
        }
        .refreshable {
            // Staff manual refresh: forces the cancelled status window fetch.
            await load(force: true)
        }
    }

    private func load(force: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            _ = try await controller.loadCancelledReservations(context: modelContext, force: force)
        } catch {
            if !error.isCancellationLike {
                errorMessage = error.isOfflineLike
                    ? "You're offline. Showing saved data."
                    : error.localizedDescription
            }
        }
    }
}

private enum CancelledReservationsPresenter {
    static func defaultWindow() -> (from: String, to: String) {
        let now = Date()
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let to = calendar.date(byAdding: .day, value: 60, to: now) ?? now
        return (from.reservationDateString(), to.reservationDateString())
    }
}

// MARK: - Hidden Reservations View

private struct HiddenReservationsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @Query
    private var reservations: [ReservationRecord]

    let environment: AppEnvironment

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hardDeleteCandidate: ReservationRecord?
    @State private var hardDeletingIDs: Set<Int> = []
    @State private var loadedPage = 0
    @State private var totalPages = 1

    private var hiddenRows: [ReservationRecord] {
        ReservationRecord.sortedNewestFirst(
            reservations.filter(\.isHidden)
        )
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        _reservations = Query(
            filter: #Predicate<ReservationRecord> { record in
                record.isHidden
            },
            sort: [
                SortDescriptor(\ReservationRecord.reservationDate, order: .reverse),
                SortDescriptor(\ReservationRecord.reservationTime, order: .reverse)
            ]
        )
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            if isLoading && hiddenRows.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading hidden reservations...")
                        Spacer()
                    }
                    .padding(.vertical, 24)
                }
            } else if hiddenRows.isEmpty {
                ContentUnavailableView(
                    "No Hidden Reservations",
                    systemImage: "archivebox",
                    description: Text("Wrong manual entries hidden from service lists will appear here.")
                )
            } else {
                Section("Hidden from service lists") {
                    ForEach(hiddenRows) { reservation in
                        VStack(alignment: .leading, spacing: 10) {
                            NavigationLink {
                                ReservationDetailView(reservation: reservation, environment: environment)
                            } label: {
                                HiddenReservationRow(reservation: reservation)
                            }
                            .buttonStyle(.plain)

                            Button {
                                Task {
                                    await restore(reservation)
                                }
                            } label: {
                                Label("Restore to lists", systemImage: "arrow.uturn.backward")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 38)
                            }
                            .buttonStyle(.plain)
                            .disabled(controller.isNetworkDegraded)
                            .foregroundStyle(.primary.opacity(0.82))
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                            }

                            if controller.capabilities.canHardDeleteReservations {
                                Button(role: .destructive) {
                                    hardDeleteCandidate = reservation
                                } label: {
                                    if hardDeletingIDs.contains(reservation.remoteID) {
                                        ProgressView()
                                            .frame(maxWidth: .infinity, minHeight: 38)
                                    } else {
                                        Label("Permanently delete test reservation", systemImage: "trash")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity, minHeight: 38)
                                    }
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                                        .stroke(Color.red.opacity(0.28), lineWidth: 1)
                                }
                                .disabled(hardDeletingIDs.contains(reservation.remoteID) || controller.isNetworkDegraded)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    if loadedPage > 0 && loadedPage < totalPages {
                        Button {
                            Task {
                                await loadHiddenReservations(force: false, page: loadedPage + 1)
                            }
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            } else {
                                Text("Load More")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                        }
                        .disabled(isLoading)
                    }
                }
            }
        }
        .listStyle(.plain)
        .contentMargins(.bottom, ReservationLayout.topLevelTabScrollBottomInset, for: .scrollContent)
        .navigationTitle("Hidden Reservations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await loadHiddenReservations(force: true, page: 1)
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoading)
            }
        }
        .confirmationDialog(
            "Permanently delete this test reservation?",
            isPresented: Binding(
                get: { hardDeleteCandidate != nil },
                set: { if !$0 { hardDeleteCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Permanently delete test reservation", role: .destructive) {
                if let candidate = hardDeleteCandidate {
                    Task {
                        await hardDelete(candidate)
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                hardDeleteCandidate = nil
            }
        } message: {
            Text("Use permanent delete only for admin/developer cleanup of test or noise reservations. Staff should normally hide wrong entries.")
        }
        .task {
            // Lazy admin/dev load: hidden rows are fetched only when this screen opens.
            await loadHiddenReservations(force: hiddenRows.isEmpty, page: 1)
        }
        .refreshable {
            await loadHiddenReservations(force: true, page: 1)
        }
    }

    private func loadHiddenReservations(force: Bool, page: Int) async {
        guard !isLoading else { return }
        guard controller.capabilities.canViewHiddenReservations else {
            errorMessage = "This account cannot view hidden reservations."
            return
        }
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let response = try await controller.loadHiddenReservationsPage(
                context: modelContext,
                page: page,
                force: force
            )
            loadedPage = page == 1 ? response.page : max(loadedPage, response.page)
            totalPages = max(response.totalPages, 1)
        } catch {
            errorMessage = error.isOfflineLike
                ? "No internet connection. Showing saved reservations."
                : "Could not load hidden reservations. Please try again."
        }
    }

    private func restore(_ reservation: ReservationRecord) async {
        errorMessage = nil
        do {
            _ = try await controller.restoreHiddenReservation(
                reservation: reservation,
                context: modelContext
            )
            ReservationHaptics.success()
        } catch {
            errorMessage = "Could not restore this reservation. Please try again."
            ReservationHaptics.warning()
        }
    }

    private func hardDelete(_ reservation: ReservationRecord) async {
        let remoteID = reservation.remoteID
        guard !hardDeletingIDs.contains(remoteID) else { return }

        hardDeleteCandidate = nil
        hardDeletingIDs.insert(remoteID)
        errorMessage = nil

        defer {
            hardDeletingIDs.remove(remoteID)
        }

        do {
            try await controller.hardDeleteReservation(
                reservation: reservation,
                context: modelContext,
                cleanupReason: "iOS admin test cleanup"
            )
            ReservationHaptics.warning()
        } catch {
            errorMessage = "Could not permanently delete this test reservation. Please try again."
            ReservationHaptics.warning()
        }
    }
}

private struct HiddenReservationRow: View {
    let reservation: ReservationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(reservation.guestName)
                    .font(.headline.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(reservation.sourceDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 12) {
                Label(reservation.displayDate, systemImage: "calendar")
                Label(reservation.displayTime, systemImage: "clock")
                if !reservation.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(reservation.formattedPhone, systemImage: "phone")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            HiddenReservationInfoLine(title: "Reason", value: reservation.hiddenReason?.nilIfBlank ?? "Hidden wrong entry")
            HiddenReservationInfoLine(title: "Hidden", value: HiddenReservationDateFormatting.server(reservation.hiddenAt))
        }
        .padding(.vertical, 4)
    }
}

private struct HiddenReservationInfoLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}

private enum HiddenReservationDateFormatting {
    private static let parser: DateFormatter = {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return parser
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func server(_ dateString: String?) -> String {
        guard let dateString = dateString?.nilIfBlank else {
            return "-"
        }

        guard let date = parser.date(from: dateString) else {
            return dateString
        }

        return displayFormatter.string(from: date)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Reservation Navigation Row

private struct ReservationNavigationRow: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var floorPlanStore: FloorPlanStore

    let reservation: ReservationRecord
    let environment: AppEnvironment
    var context: ReservationRowContext = .schedule
    var contextNote: String?
    var showsSubmittedTime = false
    var newBookingInsight: NewBookingRowInsight?
    var showsRowActions = true
    let onOpenDetails: (ReservationRecord) -> Void

    @State private var pendingAction: ReservationHostAction?
    @State private var tableAssignmentReservation: ReservationRecord?
    @State private var seatPromptReservation: ReservationRecord?
    @State private var seatAfterTableAssignment = false
    @State private var hideCandidate: ReservationRecord?
    @State private var hardDeleteCandidate: ReservationRecord?

    var body: some View {
        ReservationRowView(
            reservation: reservation,
            context: context,
            contextNote: contextNote ?? seatedDurationText,
            showsSubmittedTime: showsSubmittedTime,
            newBookingInsight: newBookingInsight,
            seatedDurationDotStyle: seatedDurationDotStyle,
            capabilities: controller.capabilities,
            onTableTap: controller.capabilities.canEditReservationDetails && !controller.isNetworkDegraded
                ? { tableAssignmentReservation = reservation }
                : nil,
            showsAutoConfirmedAdornment: showsAutoConfirmedAdornment
        ) {
            if showsRowActions {
                ReservationActionButtons(
                    reservation: reservation,
                    capabilities: controller.capabilities,
                    compact: true,
                    includeSecondary: false,
                    isBusy: controller.isActionInProgress(for: reservation) || controller.isNetworkDegraded,
                    onAction: { action in
                        handleAction(action)
                    },
                    onSeatRequiresTableChoice: {
                        seatPromptReservation = reservation
                    }
                )
            } else {
                ReservationStatusBadge(status: reservation.statusValue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            ReservationHaptics.selection()
            onOpenDetails(reservation)
        }
        .onLongPressGesture {
            ReservationHaptics.lightImpact()
        }
        .contextMenu {
            Button {
                onOpenDetails(reservation)
            } label: {
                Label("Details", systemImage: "info.circle")
            }

            ForEach(contextMenuActions) { action in
                Button(role: action.role) {
                    handleAction(action)
                } label: {
                    Label(action.fullTitle, systemImage: action.systemImage)
                }
            }

            if showsReservationCleanupActions {
                Divider()

                if canHideFromLongPress {
                    Button(role: .destructive) {
                        hideCandidate = reservation
                    } label: {
                        Label("Hide from normal lists", systemImage: "eye.slash")
                    }
                    .disabled(controller.isNetworkDegraded || controller.isActionInProgress(for: reservation))
                }

                if controller.capabilities.canHardDeleteReservations {
                    Button(role: .destructive) {
                        hardDeleteCandidate = reservation
                    } label: {
                        Label("Permanently delete", systemImage: "trash")
                    }
                    .disabled(controller.isNetworkDegraded || controller.isActionInProgress(for: reservation))
                }
            }
        }
        .reservationSeatTableChoice(
            seatPromptReservation: $seatPromptReservation,
            onAssignTable: { reservation in
                seatAfterTableAssignment = true
                tableAssignmentReservation = reservation
            },
            onSeatWithoutTable: { _ in
                Task { await perform(.seat) }
            }
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .confirmationDialog(
            pendingAction?.dialogTitle(for: reservation) ?? "Update Reservation?",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingAction {
                if pendingAction == .confirmOnly {
                    Button("Confirm only") {
                        Task {
                            await perform(.confirmOnly)
                        }
                    }

                    ReservationConfirmDialog.backendEmailButton(
                        hasUsableEmail: reservation.hasUsableConfirmationEmail
                    ) {
                        Task {
                            await perform(.confirmAndSendEmail)
                        }
                    }
                } else {
                    Button(pendingAction.fullTitle, role: pendingAction.role) {
                        Task {
                            await perform(pendingAction)
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            if let pendingAction {
                Text(pendingAction.dialogMessage(for: reservation))
            }
        }
        .confirmationDialog(
            "Hide this reservation?",
            isPresented: Binding(
                get: { hideCandidate != nil },
                set: { if !$0 { hideCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Hide from normal lists", role: .destructive) {
                if let candidate = hideCandidate {
                    Task {
                        await hideReservation(candidate)
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                hideCandidate = nil
            }
        } message: {
            Text(hideConfirmationMessage)
        }
        .confirmationDialog(
            "Permanently delete this reservation?",
            isPresented: Binding(
                get: { hardDeleteCandidate != nil },
                set: { if !$0 { hardDeleteCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Permanently delete reservation", role: .destructive) {
                if let candidate = hardDeleteCandidate {
                    Task {
                        await hardDeleteReservation(candidate)
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                hardDeleteCandidate = nil
            }
        } message: {
            Text("Developer mode only. This permanently removes the server reservation and deletes the local cache row after the server confirms.")
        }
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

    private var seatedDurationText: String? {
        controller.seatedDurationText(for: reservation)
    }

    private var seatedDurationDotStyle: TryzubStaffStatusDotStyle? {
        controller.seatedDurationDotStyle(for: reservation)
    }

    private var showsAutoConfirmedAdornment: Bool {
        reservation.isAutoConfirmedByBackend
    }

    // MARK: - Available Staff Actions

    // Intent: Rows expose compact staff actions; no API clients/services are created here.
    private var contextMenuActions: [ReservationHostAction] {
        ReservationHostActionPolicy(
            reservation: reservation,
            capabilities: controller.capabilities
        )
        .contextMenuActions
    }

    private var canHideFromLongPress: Bool {
        guard !reservation.isHidden else { return false }

        if controller.capabilities.canHardDeleteReservations {
            return true
        }

        return reservation.canSoftHideAsWrongEntry
    }

    private var showsReservationCleanupActions: Bool {
        canHideFromLongPress || controller.capabilities.canHardDeleteReservations
    }

    private var hideConfirmationMessage: String {
        if controller.capabilities.canHardDeleteReservations {
            return "Developer mode can hide any reservation from normal staff lists without deleting backend history."
        }

        return "Staff and manager modes can only hide manual reservations. The reservation remains in backend history."
    }

    // MARK: - Staff Action Routing

    private func handleAction(_ action: ReservationHostAction) {
        switch action {
        case .assignTable:
            tableAssignmentReservation = reservation
        case .confirmOnly, .confirmAndSendEmail, .cancel, .noShow:
            pendingAction = action
        case .seat, .complete:
            Task {
                await perform(action)
            }
        }
    }

    // Intent: Converts row actions into controller calls.
    // Confirm = PATCH status confirmed; Confirm + Email = POST /confirm.
    private func perform(_ action: ReservationHostAction) async {
        pendingAction = nil

        switch action {
        case .confirmOnly:
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "start",
                fields: [
                    "source": "bookings_row",
                    "status": reservation.status,
                    "emailPresent": "\(reservation.hasUsableConfirmationEmail)"
                ]
            )
            if reservation.hasUsableConfirmationEmail {
                onOpenDetails(reservation)
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
            if reservation.statusValue == .noShow {
                WorkflowCleanupTrace.log(
                    "NO_SHOW_FLOW_TRACE",
                    fields: [
                        "reservation": "\(reservation.remoteID)",
                        "action": "seat_after_no_show",
                        "result": "success"
                    ]
                )
            }
            ReservationHaptics.success()
        case .cancel:
            await controller.updateStatus(reservation: reservation, status: .cancelled, context: modelContext)
            ReservationHaptics.warning()
        case .assignTable:
            tableAssignmentReservation = reservation
        case .complete:
            await controller.updateStatus(reservation: reservation, status: .completed, context: modelContext)
            ReservationHaptics.success()
        case .noShow:
            await controller.updateStatus(reservation: reservation, status: .noShow, context: modelContext)
            WorkflowCleanupTrace.log(
                "NO_SHOW_FLOW_TRACE",
                fields: [
                    "reservation": "\(reservation.remoteID)",
                    "action": "mark_no_show",
                    "result": "success"
                ]
            )
            ReservationHaptics.warning()
        }
    }

    // Intent: Long-press cleanup action. Non-developer modes only reach this for manual rows.
    // Network: PATCH /managed-reservations/{id} with is_hidden=true.
    private func hideReservation(_ reservation: ReservationRecord) async {
        hideCandidate = nil

        do {
            let reason = controller.capabilities.canHardDeleteReservations
                ? "iOS developer cleanup"
                : "Wrong manual entry"
            _ = try await controller.hideWrongEntry(
                reservation: reservation,
                reason: reason,
                context: modelContext
            )
            ReservationHaptics.warning()
        } catch {
            ReservationHaptics.warning()
        }
    }

    // Intent: Developer-only cleanup of test/noise reservations.
    // Network: DELETE /managed-reservations/{id}?force=1.
    private func hardDeleteReservation(_ reservation: ReservationRecord) async {
        hardDeleteCandidate = nil

        do {
            try await controller.hardDeleteReservation(
                reservation: reservation,
                context: modelContext,
                cleanupReason: "iOS developer long-press cleanup"
            )
            ReservationHaptics.warning()
        } catch {
            ReservationHaptics.warning()
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Reservations") {
    let roleStore = AppRoleStore()
    roleStore.select(.developer)

    let environment = AppEnvironment(apiClient: ReservationsAPIClient.preview, role: .developer)
    return ReservationsListView(
        environment: environment,
        controller: .preview(environment: environment)
    )
        .environmentObject(roleStore)
        .modelContainer(ReservationPreviewData.previewContainer)
}
#endif
