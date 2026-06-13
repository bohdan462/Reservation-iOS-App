//
//  ReservationsController.swift
//  Tryzub Reservations
//

import Foundation
import SwiftData

@MainActor
final class ReservationsController: ObservableObject {
    // MARK: - Published UI State

    // Tracks staff-visible refreshes that update the SwiftData reservation cache.
    @Published private(set) var isSyncing = false {
        didSet { publishOperationState() }
    }

    // True while the one-time cold-start reservation + setup sync is still running.
    @Published private(set) var isStartupNetworkPassInFlight = false {
        didSet { refreshStaffStatusDotStyle() }
    }

    // Presentation-only entrance state for cache-first launch.
    @Published private(set) var startupPresentationState: StartupPresentationState = .checkingCache
    @Published private(set) var startupNetworkPassError: String?
    @Published private(set) var localCacheStoreHasReservations = false
    @Published private(set) var hasReleasedStartupUI = false
    @Published private(set) var startupUIReleasedAt: Date?

    /// Bumped once after background history prefetch writes new rows into SwiftData.
    @Published private(set) var historyCacheEnrichmentGeneration = 0

    /// True while background history prefetch is actively upserting cache rows.
    @Published private(set) var isHistoryPrefetching = false

    /// Selected service date on the Host board; used to defer history prefetch during date setup.
    @Published private(set) var hostBoardSelectedDateKey: String?
    private(set) var hostBoardDateNavigationAt: Date?

    // Tracks the quiet host-board loop that keeps today's cache warm.
    @Published private(set) var isAutoRefreshing = false {
        didSet { publishOperationState() }
    }

    // Remote reservation IDs currently being patched or confirmed.
    @Published private(set) var actionInProgressIDs: Set<Int> = [] {
        didSet { publishOperationState() }
    }

    // True while a call-in/manual reservation is being created on the server.
    @Published private(set) var isCreatingReservation = false {
        didSet { publishOperationState() }
    }
    @Published private(set) var isCheckingImportFailureCount = false {
        didSet { publishOperationState() }
    }

    // Last successful server-to-cache reservation sync.
    @Published private(set) var lastSyncedAt: Date? {
        didSet { refreshHomeServicePresentation() }
    }

    /// Last time the app confirmed visible reservation cache is acceptable to show.
    @Published private(set) var lastFreshnessCheckedAt: Date? {
        didSet { refreshHomeServicePresentation() }
    }

    @Published private(set) var cacheTrustSource: ReservationCacheTrustSource = .unknown {
        didSet { refreshHomeServicePresentation() }
    }

    /// Shared app-wide freshness authority (owned by AppReservationSession). The
    /// controller keeps its proven scope-state machine as the executor and mirrors its
    /// active-window decisions here so all surfaces read one [FRESHNESS_COORDINATOR] log
    /// and Phase 6 surfaces can consult a single source of truth.
    var freshnessCoordinator: FreshnessCoordinator?

    @Published private(set) var startupBackgroundWorkState: StartupBackgroundWorkState = .idle {
        didSet {
            #if DEBUG
            if oldValue != startupBackgroundWorkState {
                StartupPolicyTrace.startupBackgroundWork(startupBackgroundWorkState)
            }
            #endif
        }
    }

    @Published private(set) var homeServiceStatusPresentation = HomeServiceStatusPresentation(
        primarySyncText: "Saved data",
        secondaryProgressText: nil,
        dotStyle: .yellowStatic
    )

    // Staff-facing live/sync indicator for Home and Bookings headers.
    @Published private(set) var staffStatusDotStyle: TryzubStaffStatusDotStyle = .yellowStatic

    // Short staff-facing notices for refreshes, mutations, and diagnostics.
    @Published private(set) var notices: [AppNotice] = []
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published var importFailureCount: Int = 0
    @Published var importFailureCountError: String?
    @Published private(set) var restaurantSetup: RestaurantSetup = .default
    @Published private(set) var isLoadingRestaurantSetup = false {
        didSet { refreshHomeServicePresentation() }
    }
    @Published private(set) var isSavingRestaurantSetup = false
    @Published private(set) var isLoadingRestaurantHours = false
    @Published private(set) var isSavingRestaurantHours = false
    @Published private(set) var isLoadingRestaurantDayAvailability = false
    @Published private(set) var isSavingRestaurantDayAvailability = false
    @Published private(set) var isLoadingReservationAnalytics = false
    @Published private(set) var latestEmailStatusByReservationID: [Int: ReservationEmailStatus] = [:]

    // Developer diagnostics show which sync scopes are fresh, busy, or cooling down.
    @Published private(set) var syncScopeSnapshots: [SyncScopeSnapshot] = []

    // Single snapshot of global, per-screen, and per-row work for future UI bindings.
    @Published private(set) var operationState = ReservationOperationState()
    @Published private(set) var latestRefreshDecision: ReservationRefreshDecision?
    @Published private(set) var availabilitySummaryByDate: [String: ReservationAvailabilitySummary] = [:]
    @Published private(set) var availabilitySummaryLoadingDates: Set<String> = [] {
        didSet { refreshHomeServicePresentation() }
    }
    @Published private(set) var availabilitySummaryErrorsByDate: [String: String] = [:]
    @Published private(set) var localSeatedAtByReservationID: [Int: Date] = [:]

    // MARK: - Sync State

    private var restaurantSetupLoadedAt: Date?
    private var dayAvailabilityCacheByDate: [String: (value: RestaurantDayAvailabilityDTO, loadedAt: Date)] = [:]
    private var dayAvailabilityTasksByDate: [String: Task<RestaurantDayAvailabilityDTO, Error>] = [:]
    private var reservationSlotsCacheByDate: [String: (value: ReservationSlotsResponseDTO, loadedAt: Date)] = [:]
    private var reservationSlotsTasksByDate: [String: Task<ReservationSlotsResponseDTO, Error>] = [:]
    private var blockedSlotsCacheByDate: [String: (value: RestaurantBlockedSlotsResponseDTO, loadedAt: Date)] = [:]
    private var blockedSlotsTasksByDate: [String: Task<RestaurantBlockedSlotsResponseDTO, Error>] = [:]
    private var lastAutoRefreshAttemptAt: Date?
    private var lastAutoRefreshFailureAt: Date?
    private var manualAttemptByScope: [ReservationSyncScope: Date] = [:]
    private var syncStateByScope: [ReservationSyncScope: SyncScopeState] = [:]
    private var serverCursorByScope: [ReservationSyncScope: String] = [:]
    private var activeSyncIntentByScope: [ReservationSyncScope: ReservationSyncIntent] = [:] {
        didSet { publishOperationState() }
    }
    private var reconcilingReservationIDs: Set<Int> = [] {
        didSet { publishOperationState() }
    }
    private var availabilitySummaryTasksByDate: [String: Task<Void, Never>] = [:]
    private var availabilitySummaryDebounceTask: Task<Void, Never>?
    private var availabilitySummaryPendingDate: String?
    private let availabilitySummaryDebounceInterval: TimeInterval = 0.4
    private var activeWindowRefreshTask: Task<Bool, Never>?
    private var activeWindowRefreshScope: ReservationSyncScope?
    private var currentStartupPassID: String?
    private var currentActiveWindowRefreshID: String?
    private let controllerInstanceID = StartupTrace.makeInstanceID()
    #if DEBUG
    private(set) var creationTraceSource: String
    #endif
    private var lastOfflineNoticeAt: Date?
    private var pendingReviewAttentionCount = 0
    private var staffStatusBoundaryTask: Task<Void, Never>?
    private let networkPathMonitor = NetworkPathMonitor()
    @Published private(set) var isNetworkPathSatisfied = true

    // MARK: - Refresh Timing

    private let autoRefreshInterval: TimeInterval = 60
    /// TTL for IDLE automatic active-window refresh. The 60s `autoRefreshInterval` only
    /// throttles how often we *evaluate*; freshness must be judged against a much longer
    /// window so a successful startup delta is not re-fetched ~60s later while idle.
    /// Manual refresh, mutation reconcile, and window/date change bypass this.
    private let activeWindowAutoRefreshTTL: TimeInterval = 300
    private let autoRefreshFailureCooldown: TimeInterval = 180
    private let historyPrefetchStabilizationDelay: TimeInterval = 25
    private let historyPrefetchDateNavigationCooldown: TimeInterval = 5
    private let historyPrefetchGuardPollInterval: TimeInterval = 5
    private let historyPrefetchMaxGuardPollAttempts = 72
    private let manualRefreshCooldown: TimeInterval = 8
    private let scheduleFreshnessInterval: TimeInterval = 300
    private let reviewFreshnessInterval: TimeInterval = 120
    private let importFailureCountFreshnessInterval: TimeInterval = 300
    private let offlineNoticeCooldown: TimeInterval = 60
    private let availabilitySummaryFreshnessInterval: TimeInterval = 300
    private let restaurantSetupFreshnessInterval: TimeInterval = 300
    private let dateOperationsFreshnessInterval: TimeInterval = 180
    private let noncriticalStartupDeferralInterval: TimeInterval = 8
    private let syncCursorDefaultsKey = "tryzub.sync.serverCursors.v1"
    private let syncScopeSuccessDefaultsKey = "tryzub.sync.scopeLastSuccessAt.v1"
    private let syncActiveWindowBoundsKey = "tryzub.sync.activeWindowBounds.v1"
    private var persistedActiveWindowBounds: PersistedActiveWindowBounds?

    // MARK: - Dependencies

    let environment: AppEnvironment

    var capabilities: AppCapabilities {
        environment.capabilities
    }

    var hasActiveMutation: Bool {
        !actionInProgressIDs.isEmpty || isCreatingReservation
    }

    private var hasActiveReservationRefresh: Bool {
        isSyncing || isAutoRefreshing || activeWindowRefreshTask != nil
    }

    /// User-visible reservation refresh only. Background startup delta and automatic
    /// active-window sync must not block Home interactions.
    var isReservationNetworkRefreshInFlight: Bool {
        isSyncing
    }

    private var isBackgroundReservationFreshnessCheckInFlight: Bool {
        hasReleasedStartupUI && activeWindowRefreshTask != nil
    }

    var isNetworkDegraded: Bool {
        if !isNetworkPathSatisfied {
            return true
        }
        guard let lastOfflineNoticeAt else { return false }
        return Date().timeIntervalSince(lastOfflineNoticeAt) < offlineNoticeCooldown
    }

    /// Updates attention-driven green flash when new / needs-review rows change in SwiftData.
    func setPendingReviewAttentionCount(_ count: Int) {
        guard pendingReviewAttentionCount != count else { return }
        pendingReviewAttentionCount = count
        refreshStaffStatusDotStyle()
    }

    var hasLoadedRestaurantSetup: Bool {
        restaurantSetupLoadedAt != nil
    }

    /// True after cache-first UI release and the noncritical startup deferral window has elapsed.
    var canStartNoncriticalStartupLoads: Bool {
        guard hasReleasedStartupUI else { return false }
        guard !isStartupNetworkPassInFlight else { return false }
        guard let releasedAt = startupUIReleasedAt else { return false }
        return Date().timeIntervalSince(releasedAt) >= noncriticalStartupDeferralInterval
    }

    private var hasAttemptedInitialLoad = false
    private var hasStartedStartupPresentation = false
    private var startupNetworkPassTask: Task<Void, Never>?
    private var historyPrefetchTask: Task<Void, Never>?
    private var deferredRestaurantSetupTask: Task<Void, Never>?
    private let localSeatedTimestampsKey = "tryzub.localSeatedTimestamps"

    // MARK: - Initialization

    init(environment: AppEnvironment, traceSource: String = "init") {
        self.environment = environment
        self.localSeatedAtByReservationID = Self.loadLocalSeatedTimestamps()
        #if DEBUG
        self.creationTraceSource = traceSource
        #endif
        loadPersistedSyncMetadata()
        refreshHomeServicePresentation()
        StartupTrace.controllerCreated(id: controllerInstanceID, source: traceSource)
        networkPathMonitor.start { [weak self] isSatisfied in
            self?.applyNetworkPathStatus(isSatisfied)
        }
    }

    var startupTraceControllerID: String {
        controllerInstanceID
    }

    deinit {
        networkPathMonitor.stop()
    }

    func prepareForLogout() {
        HostLocalModelWarmthTracker.reset()
        cancelOwnedTasksForSessionEnd()
        notices.removeAll()
        errorMessage = nil
        noticeMessage = nil
        hasAttemptedInitialLoad = false
        hasStartedStartupPresentation = false
        startupNetworkPassTask?.cancel()
        startupNetworkPassTask = nil
        historyPrefetchTask?.cancel()
        historyPrefetchTask = nil
        deferredRestaurantSetupTask?.cancel()
        deferredRestaurantSetupTask = nil
        startupPresentationState = .checkingCache
        startupNetworkPassError = nil
        localCacheStoreHasReservations = false
        hasReleasedStartupUI = false
        startupUIReleasedAt = nil
        isHistoryPrefetching = false
        serverCursorByScope = [:]
        syncStateByScope = [:]
        UserDefaults.standard.removeObject(forKey: syncCursorDefaultsKey)
        UserDefaults.standard.removeObject(forKey: syncScopeSuccessDefaultsKey)
        UserDefaults.standard.removeObject(forKey: syncActiveWindowBoundsKey)
        persistedActiveWindowBounds = nil
        lastFreshnessCheckedAt = nil
        cacheTrustSource = .unknown
        startupBackgroundWorkState = .idle
    }

    /// Synchronous local-only gate. Safe to call from view `onAppear` before async startup work.
    @discardableResult
    func releaseStartupUIFromLocalCacheIfAvailable(context: ModelContext) -> Bool {
        guard !hasReleasedStartupUI else { return true }
        guard Self.hasUsableCachedReservations(in: context) else { return false }

        localCacheStoreHasReservations = true
        markStartupUIReleased()
        switch startupPresentationState {
        case .checkingCache, .loadingSavedReservations:
            startupPresentationState = .showingCachedDataRefreshing
        case .emptyCacheLoadingNetwork, .failedNoCache, .showingCachedDataRefreshing, .ready:
            break
        }
        hydrateCacheMetadataSync(context: context)
        ReservationSyncDiagnostics.startupUIReleased(hasCache: true)
        return true
    }

    func releaseStartupUI() {
        markStartupUIReleased()
        guard startupPresentationState == .loadingSavedReservations else { return }
        startupPresentationState = isStartupNetworkPassInFlight
            ? .showingCachedDataRefreshing
            : .ready
    }

    private func cancelOwnedTasksForSessionEnd() {
        dayAvailabilityTasksByDate.values.forEach { $0.cancel() }
        dayAvailabilityTasksByDate.removeAll()
        reservationSlotsTasksByDate.values.forEach { $0.cancel() }
        reservationSlotsTasksByDate.removeAll()
        blockedSlotsTasksByDate.values.forEach { $0.cancel() }
        blockedSlotsTasksByDate.removeAll()
        availabilitySummaryTasksByDate.values.forEach { $0.cancel() }
        availabilitySummaryTasksByDate.removeAll()
        availabilitySummaryDebounceTask?.cancel()
        availabilitySummaryDebounceTask = nil
        availabilitySummaryPendingDate = nil
        staffStatusBoundaryTask?.cancel()
        staffStatusBoundaryTask = nil
        startupNetworkPassTask?.cancel()
        startupNetworkPassTask = nil
        historyPrefetchTask?.cancel()
        historyPrefetchTask = nil
        deferredRestaurantSetupTask?.cancel()
        deferredRestaurantSetupTask = nil
        activeWindowRefreshTask?.cancel()
        activeWindowRefreshTask = nil
        activeWindowRefreshScope = nil
    }

    private func applyNetworkPathStatus(_ isSatisfied: Bool) {
        guard isNetworkPathSatisfied != isSatisfied else { return }
        isNetworkPathSatisfied = isSatisfied

        if isSatisfied {
            lastOfflineNoticeAt = nil
        } else if let lastOffline = lastOfflineNoticeAt {
            if Date().timeIntervalSince(lastOffline) >= offlineNoticeCooldown {
                lastOfflineNoticeAt = Date()
            }
        } else {
            lastOfflineNoticeAt = Date()
        }

        publishOperationState()
    }

    // MARK: - App / Screen Lifecycle

    // Intent: App starts with cached reservations visible, then refreshes the shared active window.
    // Called by: ReservationsListView root task.
    // Network: GET /managed-reservations?from=...&to=... when refresh proceeds.
    @discardableResult
    func loadIfNeeded(context: ModelContext) async -> Bool {
        guard !hasAttemptedInitialLoad else {
            StartupTrace.lifecycle(
                controllerID: controllerInstanceID,
                event: "loadIfNeeded_skipped",
                uiReleased: hasReleasedStartupUI,
                startupPassActive: isStartupNetworkPassInFlight
            )
            return true
        }
        hasAttemptedInitialLoad = true
        StartupTrace.lifecycle(
            controllerID: controllerInstanceID,
            event: "loadIfNeeded",
            cacheHit: Self.hasUsableCachedReservations(in: context),
            uiReleased: hasReleasedStartupUI,
            startupPassActive: isStartupNetworkPassInFlight
        )

        do {
            // Created per operation so the repository uses the current ModelContext.
            let repository = ReservationRepository(context: context)
            if let latestLocalSyncDate = try repository.latestLocalSyncDate() {
                lastSyncedAt = latestLocalSyncDate
            }
        } catch {
            postNotice(
                severity: .warning,
                source: .startup,
                title: "Saved data check failed",
                message: "The app could not inspect the local cache."
            )
        }

        return await performStartupActiveWindowRefresh(context: context)
    }

    @discardableResult
    private func performStartupActiveWindowRefresh(context: ModelContext) async -> Bool {
        let cacheHit = Self.hasUsableCachedReservations(in: context)
        let scope = activeWindowScope()
        let activeWindowFresh = isScopeFresh(scope, freshnessInterval: scheduleFreshnessInterval)
        let hasCursor = serverCursor(for: scope) != nil

        let policy: StartupRefreshPolicy
        let reason: String
        if !cacheHit {
            policy = .coldFull
            reason = "no_cache"
        } else if activeWindowFresh {
            policy = .skip
            reason = "fresh_cache"
        } else if hasCursor {
            policy = .delta
            reason = "stale_cache_with_cursor"
        } else {
            policy = .full
            reason = "missing_cursor"
        }

        StartupPolicyTrace.policy(
            cacheHit: cacheHit,
            activeWindowFresh: activeWindowFresh,
            hasServerCursor: hasCursor,
            policy: policy,
            reason: reason,
            setupLoadedFromCache: hasLoadedRestaurantSetup,
            remoteSetupStarted: false
        )

        switch policy {
        case .skip:
            noteFreshnessChecked(reason: "fresh_cache")
            // Anchor the active-window freshness clock to this startup confirmation
            // (session-only; not persisted). Without this, the TTL keeps counting from
            // the stale persisted lastSuccessAt, so a Bookings/schedule activation a few
            // minutes after launch full-fetched even though startup just confirmed fresh.
            markScopeRecentlyTouched(scope)
            recordActiveWindowFreshness(.useCache(reason: "startup_cache_fresh"))
            freshnessCoordinator?.markCacheHit(freshnessActiveWindowScope())
            recordRefreshDecision(scope: scope, mode: .startup, outcome: "skipped_fresh")
            StartupTrace.activeWindow(
                controllerID: controllerInstanceID,
                trigger: "startupPolicy",
                scope: scope.description,
                action: "skipped_fresh",
                startupPassID: currentStartupPassID,
                uiReleased: hasReleasedStartupUI,
                startupPassActive: isStartupNetworkPassInFlight,
                force: false,
                mode: "startup"
            )
            ReservationAPILogger.skip(
                reason: .scopeSkipFresh,
                message: "\(scope.description) startup skipped because cache is fresh"
            )
            return true
        case .coldFull, .full:
            return await performActiveWindowRefresh(
                context: context,
                mode: .startup,
                force: false,
                allowStartupDelta: false
            )
        case .delta:
            if hasReleasedStartupUI {
                startBackgroundStartupDelta(context: context)
                return true
            }
            return await performActiveWindowRefresh(
                context: context,
                mode: .startup,
                force: false,
                allowStartupDelta: true
            )
        }
    }

    private func startBackgroundStartupDelta(context: ModelContext) {
        recordRefreshDecision(scope: activeWindowScope(), mode: .startup, outcome: "delta_background")
        StartupTrace.activeWindow(
            controllerID: controllerInstanceID,
            trigger: "startupPolicy",
            scope: activeWindowScope().description,
            action: "network_delta_background",
            startupPassID: currentStartupPassID,
            uiReleased: hasReleasedStartupUI,
            startupPassActive: isStartupNetworkPassInFlight,
            force: false,
            mode: "startup"
        )
        Task(priority: .utility) { @MainActor in
            _ = await self.performActiveWindowRefresh(
                context: context,
                mode: .startup,
                force: false,
                allowStartupDelta: true
            )
            self.noteFreshnessChecked(reason: "startup_delta_background")
            self.refreshHomeServicePresentation()
        }
    }

    private func scheduleDeferredNoncriticalStartupWork(context: ModelContext) {
        Task(priority: .utility) { @MainActor in
            let delay = await self.noncriticalStartupDeferralRemaining()
            if delay > 0 {
                StartupPolicyTrace.noncriticalDeferred(
                    work: "startup_pass_followups",
                    delaySeconds: Int(ceil(delay))
                )
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            self.startDeferredRestaurantSetupIfNeeded()
            self.scheduleHistoryPrefetchWhenReady(context: context)
        }
    }

    private func noncriticalStartupDeferralRemaining() async -> TimeInterval {
        guard let releasedAt = startupUIReleasedAt else {
            return noncriticalStartupDeferralInterval
        }
        return max(0, noncriticalStartupDeferralInterval - Date().timeIntervalSince(releasedAt))
    }

    // Intent: Non-blocking reservation sync for intro/login chrome.
    // Never gates UI on network; hands off to ReservationsListView when it appears.
    func beginBackgroundReservationWarmup(context: ModelContext) {
        StartupTrace.lifecycle(
            controllerID: controllerInstanceID,
            event: "beginBackgroundReservationWarmup",
            cacheHit: Self.hasUsableCachedReservations(in: context),
            uiReleased: hasReleasedStartupUI,
            startupPassActive: isStartupNetworkPassInFlight,
            presentationState: String(describing: startupPresentationState)
        )
        guard !hasStartedStartupPresentation else {
            startStartupNetworkPassInBackgroundIfNeeded(context: context, trigger: "backgroundWarmup_reentry")
            return
        }
        hasStartedStartupPresentation = true
        startupNetworkPassError = nil

        if Self.hasUsableCachedReservations(in: context) {
            _ = releaseStartupUIFromLocalCacheIfAvailable(context: context)
        } else {
            localCacheStoreHasReservations = false
            hydrateCacheMetadataSync(context: context)
            startupPresentationState = .showingCachedDataRefreshing
            markStartupUIReleased()
        }

        startStartupNetworkPassInBackgroundIfNeeded(context: context, trigger: "backgroundWarmup")
    }

    // Intent: Cache-first entrance. Shows tabs immediately when SwiftData has reservations.
    func beginStartupPresentation(context: ModelContext) async {
        StartupTrace.lifecycle(
            controllerID: controllerInstanceID,
            event: "beginStartupPresentation",
            cacheHit: Self.hasUsableCachedReservations(in: context),
            uiReleased: hasReleasedStartupUI,
            startupPassActive: isStartupNetworkPassInFlight,
            presentationState: String(describing: startupPresentationState)
        )
        if case .failedNoCache = startupPresentationState {
            hasAttemptedInitialLoad = false
            hasStartedStartupPresentation = false
            startupNetworkPassTask?.cancel()
            startupNetworkPassTask = nil
        }

        guard !hasStartedStartupPresentation else {
            if hasReleasedStartupUI {
                startStartupNetworkPassInBackgroundIfNeeded(context: context, trigger: "beginStartupPresentation_reentry")
            }
            return
        }
        hasStartedStartupPresentation = true
        startupNetworkPassError = nil

        if Self.hasUsableCachedReservations(in: context) {
            _ = releaseStartupUIFromLocalCacheIfAvailable(context: context)
            startStartupNetworkPassInBackgroundIfNeeded(context: context, trigger: "beginStartupPresentation_cacheHit")
            return
        }

        localCacheStoreHasReservations = false
        hasReleasedStartupUI = false
        startupUIReleasedAt = nil
        startupPresentationState = .emptyCacheLoadingNetwork
        hydrateCacheMetadataSync(context: context)

        let refreshSucceeded = await performStartupNetworkPass(context: context)
        if Self.hasUsableCachedReservations(in: context) {
            markStartupUIReleased()
            startupPresentationState = .ready
            scheduleDeferredNoncriticalStartupWork(context: context)
            return
        }

        if refreshSucceeded {
            markStartupUIReleased()
            startupPresentationState = .ready
            scheduleDeferredNoncriticalStartupWork(context: context)
            return
        }

        hasReleasedStartupUI = false
        startupUIReleasedAt = nil
        startupPresentationState = .failedNoCache(
            StartupProgressPresenter.staffNoCacheFailureMessage
        )
    }

    func startStartupNetworkPassInBackgroundIfNeeded(
        context: ModelContext,
        trigger: String = "unspecified"
    ) {
        guard startupNetworkPassTask == nil else {
            StartupTrace.lifecycle(
                controllerID: controllerInstanceID,
                event: "startup_pass_skipped",
                uiReleased: hasReleasedStartupUI,
                startupPassActive: isStartupNetworkPassInFlight,
                presentationState: "task_exists trigger=\(trigger)"
            )
            return
        }
        guard !isStartupNetworkPassInFlight else {
            StartupTrace.lifecycle(
                controllerID: controllerInstanceID,
                event: "startup_pass_skipped",
                uiReleased: hasReleasedStartupUI,
                startupPassActive: true,
                presentationState: "in_flight trigger=\(trigger)"
            )
            return
        }

        let passID = StartupTrace.makePassID()
        currentStartupPassID = passID
        StartupTrace.startupPass(
            controllerID: controllerInstanceID,
            passID: passID,
            phase: "background_start trigger=\(trigger)",
            uiReleased: hasReleasedStartupUI
        )

        startupNetworkPassTask = Task(priority: .utility) { @MainActor in
            _ = await self.performStartupNetworkPass(context: context, passID: passID)
            self.scheduleDeferredNoncriticalStartupWork(context: context)
            self.startupNetworkPassTask = nil
        }
    }

    func noteHostBoardSelectedDate(_ dateKey: String) {
        if hostBoardSelectedDateKey != dateKey {
            DateSwitchTrace.begin(from: hostBoardSelectedDateKey, to: dateKey)
            hostBoardDateNavigationAt = Date()
        }
        hostBoardSelectedDateKey = dateKey
    }

    func isHostBoardDateNetworkBusy(_ dateKey: String) -> Bool {
        isAvailabilitySummaryLoading(date: dateKey)
            || reservationSlotsTasksByDate[dateKey] != nil
            || blockedSlotsTasksByDate[dateKey] != nil
    }

    func canStartHistoryPrefetchNow(force: Bool = false) -> Bool {
        guard hasReleasedStartupUI else { return false }
        guard !isStartupNetworkPassInFlight else { return false }
        guard !isHistoryPrefetching else { return false }
        guard !HostLocalModelInferenceTracker.isActive else { return false }

        if let releasedAt = startupUIReleasedAt {
            guard Date().timeIntervalSince(releasedAt) >= historyPrefetchStabilizationDelay else {
                return false
            }
        } else {
            return false
        }

        if let dateKey = hostBoardSelectedDateKey,
           isHostBoardDateNetworkBusy(dateKey) {
            return false
        }

        if let navigationAt = hostBoardDateNavigationAt,
           Date().timeIntervalSince(navigationAt) < historyPrefetchDateNavigationCooldown {
            return false
        }

        return true
    }

    func scheduleHistoryPrefetchWhenReady(context: ModelContext, force: Bool = false) {
        guard hasReleasedStartupUI else { return }
        guard historyPrefetchTask == nil else { return }
        if !force, !ReservationHistoryPrefetcher.shouldRun(force: false) {
            ReservationSyncDiagnostics.historyPrefetchSkipped(reason: "fresh")
            return
        }

        historyPrefetchTask = Task(priority: .utility) { @MainActor in
            defer { self.historyPrefetchTask = nil }

            while !self.canStartNoncriticalStartupLoads {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }

            if let releasedAt = self.startupUIReleasedAt {
                let remaining = self.historyPrefetchStabilizationDelay - Date().timeIntervalSince(releasedAt)
                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                }
            } else {
                try? await Task.sleep(for: .seconds(self.historyPrefetchStabilizationDelay))
            }
            guard !Task.isCancelled else { return }

            for _ in 0..<self.historyPrefetchMaxGuardPollAttempts {
                guard !Task.isCancelled else { return }
                if self.canStartHistoryPrefetchNow(force: force) {
                    break
                }
                try? await Task.sleep(for: .seconds(self.historyPrefetchGuardPollInterval))
            }

            guard self.canStartHistoryPrefetchNow(force: force) else {
                ReservationSyncDiagnostics.historyPrefetchSkipped(reason: "guards_blocked")
                return
            }

            self.isHistoryPrefetching = true
            defer { self.isHistoryPrefetching = false }

            let rowsWritten = await ReservationHistoryPrefetcher.prefetchIfNeeded(
                apiClient: self.environment.apiClient,
                context: context,
                force: force
            )
            if let rowsWritten, rowsWritten > 0 {
                self.historyCacheEnrichmentGeneration += 1
            }
        }
    }

    func startHistoryPrefetchInBackgroundIfNeeded(context: ModelContext, force: Bool = false) {
        scheduleHistoryPrefetchWhenReady(context: context, force: force)
    }

    private func markStartupUIReleased() {
        guard !hasReleasedStartupUI else { return }
        hasReleasedStartupUI = true
        startupUIReleasedAt = Date()
        refreshHomeServicePresentation()
        HostLocalModelAutoPrepareCoordinator.shared.scheduleWhenReady(controller: self)
    }

    private func startDeferredRestaurantSetupIfNeeded() {
        guard deferredRestaurantSetupTask == nil else { return }
        guard !hasLoadedRestaurantSetup else { return }
        guard !isLoadingRestaurantSetup else { return }
        StartupPolicyTrace.remoteSetupStarted(fromCache: hasLoadedRestaurantSetup)
        deferredRestaurantSetupTask = Task(priority: .utility) { @MainActor in
            let previousBookingWindowDays = self.restaurantSetup.bookingWindowDays
            let previousScope = self.activeWindowScope()
            _ = try? await self.loadRestaurantSetup()
            if self.restaurantSetup.bookingWindowDays != previousBookingWindowDays {
                self.markScopeStale(previousScope)
                StartupPolicyTrace.policy(
                    cacheHit: self.localCacheStoreHasReservations,
                    activeWindowFresh: false,
                    hasServerCursor: self.serverCursor(for: previousScope) != nil,
                    policy: .full,
                    reason: "setup_booking_window_changed",
                    setupLoadedFromCache: false,
                    remoteSetupStarted: true
                )
            }
            self.deferredRestaurantSetupTask = nil
        }
    }

    // Intent: Runs the cold-start active_window refresh without blocking cache-first UI.
    // On cache-hit launch this is background-only; `isSyncing` stays false after UI release.
    // Network: GET active window (may take 15s+); restaurant setup is deferred separately.
    @discardableResult
    func performStartupNetworkPass(
        context: ModelContext,
        passID: String? = nil
    ) async -> Bool {
        let resolvedPassID = passID ?? currentStartupPassID ?? StartupTrace.makePassID()
        currentStartupPassID = resolvedPassID
        guard !isStartupNetworkPassInFlight else {
            StartupTrace.startupPass(
                controllerID: controllerInstanceID,
                passID: resolvedPassID,
                phase: "skipped_already_in_flight",
                uiReleased: hasReleasedStartupUI
            )
            return false
        }
        isStartupNetworkPassInFlight = true
        StartupTrace.startupPass(
            controllerID: controllerInstanceID,
            passID: resolvedPassID,
            phase: "in_flight",
            uiReleased: hasReleasedStartupUI
        )
        defer {
            isStartupNetworkPassInFlight = false
            if currentStartupPassID == resolvedPassID {
                currentStartupPassID = nil
            }
            StartupTrace.startupPass(
                controllerID: controllerInstanceID,
                passID: resolvedPassID,
                phase: "finished",
                uiReleased: hasReleasedStartupUI
            )
            if startupPresentationState == .showingCachedDataRefreshing {
                startupPresentationState = .ready
            }
        }

        startupNetworkPassError = nil
        let refreshSucceeded = await loadIfNeeded(context: context)
        if !refreshSucceeded {
            startupNetworkPassError = notices.last(where: { $0.source == .startup })?.message
                ?? "Could not refresh reservations."
        }

        return refreshSucceeded
    }

    static func hasUsableCachedReservations(in context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<ReservationRecord>(
            predicate: #Predicate<ReservationRecord> { reservation in
                !reservation.isHidden
            }
        )
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor))?.isEmpty == false)
    }

    private func shouldShowGlobalRefreshProgress(
        mode: ReservationRefreshMode,
        force: Bool
    ) -> Bool {
        switch mode {
        case .manual:
            return true
        case .startup:
            return !hasReleasedStartupUI
        case .automatic:
            return false
        case .schedule, .review:
            return force
        }
    }

    func noteStartupWindowQueryDelivered(rowCount: Int) {
        guard startupPresentationState == .loadingSavedReservations else { return }
        releaseStartupUI()
    }

    private func hydrateCacheMetadataSync(context: ModelContext) {
        do {
            let repository = ReservationRepository(context: context)
            if let latestLocalSyncDate = try repository.latestLocalSyncDate() {
                lastSyncedAt = latestLocalSyncDate
                adoptLocalSyncSuccess(for: activeWindowScope(), at: latestLocalSyncDate)
            }
        } catch {
            // Cache metadata is optional for presentation; startup refresh may still proceed.
        }
        adoptPersistedFreshnessTrustIfAvailable()
    }

    private func loadPersistedSyncMetadata() {
        if let rawCursors = UserDefaults.standard.dictionary(forKey: syncCursorDefaultsKey) as? [String: String] {
            for (key, cursor) in rawCursors {
                guard let scope = ReservationSyncScope(persistenceKey: key) else { continue }
                serverCursorByScope[scope] = cursor
            }
        }

        if let rawSuccess = UserDefaults.standard.dictionary(forKey: syncScopeSuccessDefaultsKey) as? [String: TimeInterval] {
            for (key, timestamp) in rawSuccess {
                guard let scope = ReservationSyncScope(persistenceKey: key) else { continue }
                var state = syncStateByScope[scope] ?? SyncScopeState()
                state.lastSuccessAt = Date(timeIntervalSince1970: timestamp)
                syncStateByScope[scope] = state
            }
        }

        if let data = UserDefaults.standard.data(forKey: syncActiveWindowBoundsKey),
           let bounds = try? JSONDecoder().decode(PersistedActiveWindowBounds.self, from: data) {
            persistedActiveWindowBounds = bounds
        }

        reconcileActiveWindowSyncMetadata()
        adoptPersistedFreshnessTrustIfAvailable()
        publishSyncScopeSnapshots()
    }

    private func adoptPersistedFreshnessTrustIfAvailable() {
        let scope = activeWindowScope()
        let persistedFresh = isScopeFresh(scope, freshnessInterval: scheduleFreshnessInterval)
        guard persistedFresh,
              let checkedAt = syncStateByScope[scope]?.lastSuccessAt else {
            #if DEBUG
            StartupPolicyTrace.headerInitialTrust(checked: false, persistedFresh: persistedFresh)
            #endif
            return
        }
        lastFreshnessCheckedAt = checkedAt
        if cacheTrustSource == .unknown {
            cacheTrustSource = .freshnessCheck
        }
        #if DEBUG
        StartupPolicyTrace.headerInitialTrust(checked: true, persistedFresh: true)
        #endif
    }

    private func noteFreshnessChecked(reason: String) {
        let now = Date()
        lastFreshnessCheckedAt = now
        cacheTrustSource = .freshnessCheck
        StartupPolicyTrace.freshnessChecked(at: now, reason: reason)
        refreshHomeServicePresentation()
    }

    private func noteReservationServerSyncCompleted() {
        let now = Date()
        lastSyncedAt = now
        lastFreshnessCheckedAt = now
        cacheTrustSource = .serverSync
        refreshHomeServicePresentation()
    }

    private func persistSyncMetadata() {
        let cursors = Dictionary(
            uniqueKeysWithValues: serverCursorByScope.map { ($0.key.persistenceKey, $0.value) }
        )
        UserDefaults.standard.set(cursors, forKey: syncCursorDefaultsKey)

        let successes = Dictionary(
            uniqueKeysWithValues: syncStateByScope.compactMap { scope, state -> (String, TimeInterval)? in
                guard let lastSuccessAt = state.lastSuccessAt else { return nil }
                return (scope.persistenceKey, lastSuccessAt.timeIntervalSince1970)
            }
        )
        UserDefaults.standard.set(successes, forKey: syncScopeSuccessDefaultsKey)
    }

    private func adoptLocalSyncSuccess(for scope: ReservationSyncScope, at date: Date) {
        var state = syncStateByScope[scope] ?? SyncScopeState()
        if state.lastSuccessAt == nil {
            state.lastSuccessAt = date
            syncStateByScope[scope] = state
            persistSyncMetadata()
            publishSyncScopeSnapshots()
        }
    }

    private func persistActiveWindowBoundsIfNeeded(
        scope: ReservationSyncScope,
        window: (from: String, to: String)
    ) {
        guard case .activeWindow = scope else { return }
        let bounds = PersistedActiveWindowBounds(
            from: window.from,
            to: window.to,
            bookingWindowDays: activeWindowBookingWindowDays()
        )
        persistedActiveWindowBounds = bounds
        if let data = try? JSONEncoder().encode(bounds) {
            UserDefaults.standard.set(data, forKey: syncActiveWindowBoundsKey)
        }
    }

    private func reconcileActiveWindowSyncMetadata() {
        let currentScope = activeWindowScope()
        let hasCursor = serverCursor(for: currentScope) != nil
        let hasFreshness = syncStateByScope[currentScope]?.lastSuccessAt != nil
        if hasCursor && hasFreshness {
            return
        }

        if let bounds = persistedActiveWindowBounds {
            let persistedScope = ReservationSyncScope.activeWindow(from: bounds.from, to: bounds.to)
            if persistedScope.persistenceKey != currentScope.persistenceKey {
                migrateActiveWindowSyncMetadata(from: persistedScope, to: currentScope)
            }
            if serverCursor(for: currentScope) != nil,
               syncStateByScope[currentScope]?.lastSuccessAt != nil {
                return
            }
        }

        adoptNearestActiveWindowSyncMetadata(for: currentScope)
    }

    private func migrateActiveWindowSyncMetadata(
        from sourceScope: ReservationSyncScope,
        to targetScope: ReservationSyncScope
    ) {
        guard sourceScope.persistenceKey != targetScope.persistenceKey else { return }

        if serverCursor(for: targetScope) == nil,
           let cursor = serverCursor(for: sourceScope) {
            serverCursorByScope[targetScope] = cursor
        }

        if syncStateByScope[targetScope]?.lastSuccessAt == nil,
           let sourceState = syncStateByScope[sourceScope] {
            syncStateByScope[targetScope] = sourceState
        }

        if serverCursor(for: targetScope) != nil || syncStateByScope[targetScope]?.lastSuccessAt != nil {
            persistSyncMetadata()
        }
    }

    private func adoptNearestActiveWindowSyncMetadata(for targetScope: ReservationSyncScope) {
        guard case .activeWindow(let targetFrom, let targetTo) = targetScope else { return }

        let candidates = serverCursorByScope.keys.compactMap { scope -> (ReservationSyncScope, Int)? in
            guard case .activeWindow(let from, let to) = scope else { return nil }
            guard to == targetTo else { return nil }
            guard let distance = Self.reservationDateDayDistance(from: from, to: targetFrom) else { return nil }
            guard distance <= 1 else { return nil }
            return (scope, distance)
        }
        .sorted { $0.1 < $1.1 }

        guard let nearest = candidates.first?.0 else { return }
        migrateActiveWindowSyncMetadata(from: nearest, to: targetScope)
    }

    private static func reservationDateDayDistance(from: String, to: String) -> Int? {
        guard let fromDate = ReservationFormatters.reservationDateKey.date(from: from),
              let toDate = ReservationFormatters.reservationDateKey.date(from: to) else {
            return nil
        }
        let days = Calendar.current.dateComponents([.day], from: fromDate, to: toDate).day ?? 0
        return abs(days)
    }

    // MARK: - Legacy Refresh Entry Points

    // Intent: Refreshes the schedule window cache, not every historical reservation.
    // Rename note: A later cleanup should call this refreshScheduleWindowCache.
    func refreshScheduleWindowCache(context: ModelContext) async {
        await requestScheduleRefresh(context: context, source: .manual)
    }

    // MARK: - Active Window Sync

    // Intent: Legacy wrapper for Home refresh; current implementation refreshes the shared active window.
    // Called by: Home pull-to-refresh and toolbar refresh.
    // Network: GET /managed-reservations?from=...&to=....
    @discardableResult
    func refreshDashboard(context: ModelContext) async -> Bool {
        await requestManualTodayRefresh(context: context, source: .manual)
    }

    // Intent: Runs staff-requested Home refresh with busy/cooldown guards.
    // Current normal flow is shared active-window full refresh, not a today-only endpoint.
    // Writes: SwiftData through ReservationSyncService.
    // Network: GET /managed-reservations?from=...&to=....
    @discardableResult
    func requestManualTodayRefresh(
        context: ModelContext,
        source: ReservationSyncIntent = .manual
    ) async -> Bool {
        let scope = activeWindowScope()

        guard !hasActiveMutation else {
            ReservationAPILogger.skip(reason: .manualSkipBusy, message: "\(scope.description) skipped because a mutation is active")
            return false
        }

        guard !hasActiveReservationRefresh else {
            ReservationAPILogger.skip(reason: .manualSkipBusy, message: "\(scope.description) skipped because a refresh is already active")
            return false
        }

        guard allowManualAttempt(for: scope) else {
            ReservationAPILogger.skip(reason: .manualSkipCooldown, message: "\(scope.description) manual refresh cooldown active")
            return false
        }

        return await performActiveWindowRefresh(
            context: context,
            mode: source == .startup ? .startup : .manual,
            force: true
        )
    }

    // MARK: - Schedule Sync

    // Intent: Schedule tab became visible; refresh only if the schedule cache is stale.
    // Network: GET /managed-reservations?from=...&to=... when stale.
    func scheduleBecameActive(context: ModelContext) async {
        let scope = activeWindowScope()
        if isScopeInFailureCooldown(scope) {
            recordRefreshDecision(scope: scope, mode: .schedule, outcome: "skipped_cooldown")
            ReservationAPILogger.skip(reason: .autoSkipCooldown, message: "\(scope.description) schedule activation skipped because failure cooldown is active")
            return
        }
        guard !isScopeFresh(scope, freshnessInterval: scheduleFreshnessInterval) else {
            recordActiveWindowFreshness(.useCache(reason: "fresh_schedule_activation"))
            recordRefreshDecision(scope: scope, mode: .schedule, outcome: "skipped_fresh")
            ReservationAPILogger.skip(reason: .scopeSkipFresh, message: "\(scope.description) schedule activation skipped because cache is fresh")
            return
        }
        await performActiveWindowRefresh(context: context, mode: .schedule, force: false)
    }

    // Intent: Staff manually refreshes the schedule window.
    // Network: GET /managed-reservations?from=...&to=...
    @discardableResult
    func requestScheduleRefresh(
        context: ModelContext,
        source: ReservationSyncIntent = .manual
    ) async -> Bool {
        await performActiveWindowRefresh(context: context, mode: .schedule, force: source == .manual)
    }

    // Intent: Schedule All mode pages historical rows on demand without replacing local cache.
    // Network: GET /managed-reservations?page=...&per_page=100.
    func loadScheduleAllPage(
        context: ModelContext,
        page: Int,
        search: String?,
        isAllScope: Bool,
        isScheduleTabActive: Bool,
        callerContext: String,
        isStillAllowed: @escaping () -> Bool = { true }
    ) async throws -> ReservationsResponse {
        guard isScheduleTabActive, isAllScope else {
            ReservationAPILogger.skip(
                reason: .scheduleAllBlocked,
                message: "schedule_all_page blocked caller=\(callerContext) isScheduleTabActive=\(isScheduleTabActive) isAllScope=\(isAllScope)"
            )
            throw ReservationControllerError.actionAlreadyInProgress
        }

        let response = try await environment.apiClient.fetchReservations(
            page: page,
            perPage: 100,
            date: nil,
            from: nil,
            to: nil,
            status: nil,
            search: search,
            includeHidden: false,
            reason: .scheduleAllPage
        )

        guard isStillAllowed() else {
            ReservationAPILogger.skip(
                reason: .scheduleAllBlocked,
                message: "schedule_all_page cache write blocked caller=\(callerContext) page=\(page)"
            )
            return response
        }

        let repository = ReservationRepository(context: context)
        try repository.upsert(response.data)
        noteReservationServerSyncCompleted()
        return response
    }

    // Intent: Schedule All mode refreshes one service date from the server.
    // Network: GET /managed-reservations?date=YYYY-MM-DD.
    func refreshScheduleDate(
        context: ModelContext,
        date: String,
        search: String? = nil
    ) async throws {
        let response = try await environment.apiClient.fetchReservations(
            page: 1,
            perPage: 100,
            date: date,
            from: nil,
            to: nil,
            status: nil,
            search: search,
            includeHidden: false,
            reason: .scheduleDate
        )

        let repository = ReservationRepository(context: context)
        try repository.upsert(response.data)
        noteReservationServerSyncCompleted()
    }

    // MARK: - Pending Review Sync

    // Intent: Pending/Review screen became visible; refresh only when cached queue is stale.
    // Network: GET /managed-reservations?status=new and status=needs_review.
    func reviewBecameActive(context: ModelContext) async {
        let scope = activeWindowScope()
        if isScopeInFailureCooldown(scope) {
            recordRefreshDecision(scope: scope, mode: .review, outcome: "skipped_cooldown")
            ReservationAPILogger.skip(reason: .autoSkipCooldown, message: "\(scope.description) review activation skipped because failure cooldown is active")
            return
        }
        guard !isScopeFresh(scope, freshnessInterval: reviewFreshnessInterval) else {
            recordRefreshDecision(scope: scope, mode: .review, outcome: "skipped_fresh")
            ReservationAPILogger.skip(reason: .scopeSkipFresh, message: "\(scope.description) review activation skipped because cache is fresh")
            return
        }
        await performActiveWindowRefresh(context: context, mode: .review, force: false)
    }

    // Intent: Staff manually refreshes the pending review queue.
    // Network: GET /managed-reservations?status=new and status=needs_review.
    @discardableResult
    func requestReviewRefresh(
        context: ModelContext,
        source: ReservationSyncIntent = .manual
    ) async -> Bool {
        await performActiveWindowRefresh(context: context, mode: .review, force: source == .manual)
    }

    // MARK: - Cancelled Reservations

    // Intent: Staff opens cancelled operational history; this is not hidden/test cleanup.
    // Network: GET /managed-reservations?status=cancelled&from=...&to=...
    // SwiftData: Upserts returned rows only; this status-scoped response is not broad delete truth.
    @discardableResult
    func loadCancelledReservations(context: ModelContext, force: Bool = false) async throws -> [ReservationDTO] {
        let response = try await loadCancelledReservationsPage(context: context, page: 1, force: force)
        return response.data
    }

    @discardableResult
    func loadCancelledReservationsPage(
        context: ModelContext,
        page: Int,
        force: Bool = false
    ) async throws -> ReservationsResponse {
        let window = cancelledReservationsWindow()
        let scope = ReservationSyncScope.cancelledWindow(from: window.from, to: window.to)

        if page == 1, !force, isScopeFresh(scope, freshnessInterval: scheduleFreshnessInterval) {
            return ReservationsResponse(
                success: true,
                serverTime: nil,
                page: 1,
                perPage: 100,
                total: 0,
                totalPages: 1,
                data: []
            )
        }

        guard beginScope(scope, intent: force ? .manual : .screenActive) else {
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "\(scope.description) skipped because this scope is already in flight")
            return ReservationsResponse(
                success: true,
                serverTime: nil,
                page: page,
                perPage: 100,
                total: 0,
                totalPages: 1,
                data: []
            )
        }

        do {
            let response = try await environment.apiClient.fetchReservations(
                page: page,
                perPage: 100,
                date: nil,
                from: window.from,
                to: window.to,
                status: .cancelled,
                search: nil,
                includeHidden: false,
                reason: .cancelledReservationsPage
            )
            let repository = ReservationRepository(context: context)
            if !response.data.isEmpty {
                try repository.upsert(response.data)
            }
            markScopeSuccess(scope)
            return response
        } catch {
            if error.isCancellationLike {
                markScopeCancelled(scope)
            } else {
                markScopeFailure(scope)
                if error.isOfflineLike {
                    postOfflineNotice(source: .schedule, requestReason: .cancelledReservations, error: error)
                }
            }
            throw error
        }
    }

    // MARK: - Today Auto Refresh

    // Intent: Quietly keeps the host board current while staff are not mid-action.
    // Called by: HostBoardView auto-refresh loop.
    // Network: GET /managed-reservations?date=today when allowed.
    func autoRefreshDashboardIfAllowed(
        context: ModelContext,
        isInteractionActive: Bool,
        isAppActive: Bool,
        source: VisibleLiveRefreshSource = .host
    ) async {
        guard isAppActive else {
            MultiDeviceSyncTrace.visibleLiveRefresh(source: source, decision: "skip", reason: "app_inactive")
            ReservationAPILogger.skip(reason: .autoSkipInactive, message: "app is not active")
            return
        }

        guard !isInteractionActive else {
            MultiDeviceSyncTrace.visibleLiveRefresh(source: source, decision: "skip", reason: "interaction_active")
            ReservationAPILogger.skip(reason: .autoSkipBusy, message: "host interaction is active")
            return
        }

        guard !hasActiveReservationRefresh,
              !hasActiveMutation,
              !isCheckingImportFailureCount else {
            MultiDeviceSyncTrace.visibleLiveRefresh(source: source, decision: "skip", reason: "controller_busy")
            ReservationAPILogger.skip(reason: .autoSkipBusy, message: "controller is busy")
            return
        }

        let scope = activeWindowScope()
        let now = Date()

        if let lastAttempt = lastAutoRefreshAttemptAt,
           now.timeIntervalSince(lastAttempt) < autoRefreshInterval {
            MultiDeviceSyncTrace.visibleLiveRefresh(source: source, decision: "skip", reason: "interval_throttle")
            ReservationAPILogger.skip(reason: .autoSkipBusy, message: "auto-refresh interval has not passed")
            return
        }

        if let lastFailure = lastAutoRefreshFailureAt,
           now.timeIntervalSince(lastFailure) < autoRefreshFailureCooldown {
            MultiDeviceSyncTrace.visibleLiveRefresh(source: source, decision: "skip", reason: "failure_cooldown")
            ReservationAPILogger.skip(reason: .autoSkipCooldown, message: "auto-refresh failure cooldown active")
            return
        }

        let elapsedSinceSuccess = syncStateByScope[scope]?.lastSuccessAt
            .map { now.timeIntervalSince($0) }
        let hasCursor = serverCursor(for: scope) != nil

        // Visible live refresh policy:
        //   • When a server cursor exists we ALWAYS run a lightweight active-window delta
        //     GET — cache freshness (the 300s idle TTL) must NOT suppress this. This is
        //     what lets a manual reservation created on another device appear here within
        //     one 60s auto-refresh interval.
        //   • When no cursor exists yet, only a full sync can advance us. Cache freshness
        //     MAY skip that full sync to avoid hammering full GETs while idle.
        if hasCursor {
            MultiDeviceSyncTrace.visibleLiveRefresh(source: source, decision: "delta", reason: "cursor_exists")
            ActiveWindowFreshnessTrace.autoCheck(
                source: "autoRefreshDashboard",
                decision: "fetch",
                reason: "visible_live_delta",
                elapsed: elapsedSinceSuccess,
                ttl: activeWindowAutoRefreshTTL
            )
        } else if isScopeFresh(scope, freshnessInterval: activeWindowAutoRefreshTTL) {
            MultiDeviceSyncTrace.visibleLiveRefresh(source: source, decision: "skip", reason: "full_fresh_no_cursor")
            recordActiveWindowFreshness(.useCache(reason: "fresh_automatic"))
            recordRefreshDecision(scope: scope, mode: .automatic, outcome: "skipped_fresh")
            ActiveWindowFreshnessTrace.autoCheck(
                source: "autoRefreshDashboard",
                decision: "skip",
                reason: "recent_success_no_cursor",
                elapsed: elapsedSinceSuccess,
                ttl: activeWindowAutoRefreshTTL
            )
            ReservationAPILogger.skip(
                reason: .scopeSkipFresh,
                message: "\(scope.description) auto refresh skipped: full sync fresh and no delta cursor"
            )
            return
        } else {
            MultiDeviceSyncTrace.visibleLiveRefresh(source: source, decision: "full", reason: "no_cursor_stale")
            ActiveWindowFreshnessTrace.autoCheck(
                source: "autoRefreshDashboard",
                decision: "fetch",
                reason: "visible_live_full",
                elapsed: elapsedSinceSuccess,
                ttl: activeWindowAutoRefreshTTL
            )
        }

        lastAutoRefreshAttemptAt = now

        let didRefresh = await performActiveWindowRefresh(context: context, mode: .automatic, force: false)
        if !didRefresh {
            lastAutoRefreshFailureAt = Date()
            markScopeFailure(scope, cooldown: autoRefreshFailureCooldown)
        }
    }

    @discardableResult
    private func performActiveWindowRefresh(
        context: ModelContext,
        mode: ReservationRefreshMode,
        force: Bool,
        allowStartupDelta: Bool = false
    ) async -> Bool {
        let window = activeWindow()
        let scope = ReservationSyncScope.activeWindow(from: window.from, to: window.to)

        let trigger = activeWindowTriggerName(for: mode)

        if let existing = activeWindowRefreshTask {
            if activeWindowRefreshScope == scope {
                recordRefreshDecision(scope: scope, mode: mode, outcome: "coalesced_in_flight")
                StartupTrace.activeWindow(
                    controllerID: controllerInstanceID,
                    trigger: trigger,
                    scope: scope.description,
                    action: "coalesced_same_scope",
                    refreshID: currentActiveWindowRefreshID,
                    startupPassID: currentStartupPassID,
                    uiReleased: hasReleasedStartupUI,
                    startupPassActive: isStartupNetworkPassInFlight,
                    force: force,
                    mode: String(describing: mode)
                )
                ReservationAPILogger.skip(
                    reason: .scopeSkipInFlight,
                    message: "\(scope.description) same active-window scope coalesced with in-flight refresh"
                )
                return await existing.value
            }

            recordRefreshDecision(scope: scope, mode: mode, outcome: "scope_changed_not_coalesced")
            StartupTrace.activeWindow(
                controllerID: controllerInstanceID,
                trigger: trigger,
                scope: scope.description,
                action: "scope_changed_not_coalesced",
                refreshID: currentActiveWindowRefreshID,
                startupPassID: currentStartupPassID,
                uiReleased: hasReleasedStartupUI,
                startupPassActive: isStartupNetworkPassInFlight,
                force: force,
                mode: String(describing: mode)
            )
            ReservationAPILogger.skip(
                reason: .scopeSkipInFlight,
                message: "\(scope.description) different active-window scope not coalesced (in-flight: \(activeWindowRefreshScope?.description ?? "unknown"))"
            )
        }

        let refreshID = StartupTrace.makePassID()
        currentActiveWindowRefreshID = refreshID
        let capturedScope = scope
        StartupTrace.activeWindow(
            controllerID: controllerInstanceID,
            trigger: trigger,
            scope: scope.description,
            action: "start",
            refreshID: refreshID,
            startupPassID: currentStartupPassID,
            uiReleased: hasReleasedStartupUI,
            startupPassActive: isStartupNetworkPassInFlight,
            force: force,
            mode: String(describing: mode)
        )
        let task = Task { @MainActor in
            await self.performActiveWindowRefreshBody(
                context: context,
                mode: mode,
                force: force,
                allowStartupDelta: allowStartupDelta,
                window: window,
                scope: capturedScope,
                refreshID: refreshID,
                trigger: trigger
            )
        }
        activeWindowRefreshTask = task
        activeWindowRefreshScope = capturedScope
        let result = await task.value
        if activeWindowRefreshScope == capturedScope {
            activeWindowRefreshTask = nil
            activeWindowRefreshScope = nil
            if currentActiveWindowRefreshID == refreshID {
                currentActiveWindowRefreshID = nil
            }
        }
        return result
    }

    private func activeWindowTriggerName(for mode: ReservationRefreshMode) -> String {
        switch mode {
        case .startup: return "loadIfNeeded"
        case .manual: return "manualRefresh"
        case .schedule: return "scheduleBecameActive"
        case .review: return "reviewBecameActive"
        case .automatic: return "autoRefreshDashboard"
        }
    }

    @discardableResult
    private func performActiveWindowRefreshBody(
        context: ModelContext,
        mode: ReservationRefreshMode,
        force: Bool,
        allowStartupDelta: Bool,
        window: (from: String, to: String),
        scope: ReservationSyncScope,
        refreshID: String,
        trigger: String
    ) async -> Bool {
        if !force,
           mode != .automatic,
           isScopeFresh(scope, freshnessInterval: mode == .review ? reviewFreshnessInterval : scheduleFreshnessInterval) {
            recordActiveWindowFreshness(.useCache(reason: "scope_fresh_\(mode)"))
            recordRefreshDecision(scope: scope, mode: mode, outcome: "skipped_fresh")
            StartupTrace.activeWindow(
                controllerID: controllerInstanceID,
                trigger: trigger,
                scope: scope.description,
                action: "skipped_fresh",
                refreshID: refreshID,
                startupPassID: currentStartupPassID,
                uiReleased: hasReleasedStartupUI,
                startupPassActive: isStartupNetworkPassInFlight,
                force: force,
                mode: String(describing: mode)
            )
            ReservationAPILogger.skip(reason: .scopeSkipFresh, message: "\(scope.description) skipped because cache is fresh")
            return true
        }

        guard beginScope(scope, intent: mode.syncIntent) else {
            recordActiveWindowFreshness(.joinInFlight(reason: "scope_in_flight"))
            recordRefreshDecision(scope: scope, mode: mode, outcome: "skipped_in_flight")
            StartupTrace.activeWindow(
                controllerID: controllerInstanceID,
                trigger: trigger,
                scope: scope.description,
                action: "skipped_scope_in_flight",
                refreshID: refreshID,
                startupPassID: currentStartupPassID,
                uiReleased: hasReleasedStartupUI,
                startupPassActive: isStartupNetworkPassInFlight,
                force: force,
                mode: String(describing: mode)
            )
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "\(scope.description) skipped because this scope is already in flight")
            return mode == .automatic
        }

        let showsGlobalProgress = shouldShowGlobalRefreshProgress(mode: mode, force: force)
        if mode == .automatic {
            isAutoRefreshing = true
        } else if showsGlobalProgress {
            isSyncing = true
        }
        clearScopedMessages(for: mode.noticeSource)

        recordActiveWindowFreshness(.fetch(reason: force ? "forced_\(mode)" : "stale_\(mode)"))
        let freshnessScope = freshnessActiveWindowScope()
        freshnessCoordinator?.markInFlight(freshnessScope)

        do {
            let repository = ReservationRepository(context: context)
            let service = ReservationSyncService(
                client: environment.apiClient,
                repository: repository,
                controllerTraceID: controllerInstanceID
            )
            let result: ReservationSyncResult
            let deltaCursor: String?
            let shouldAttemptDelta: Bool
            var resolvedSyncMode = "full"
            var resolvedCursorUsed: String?
            if mode == .automatic || (mode == .startup && allowStartupDelta) {
                deltaCursor = serverCursor(for: scope)
                shouldAttemptDelta = deltaCursor != nil
            } else {
                deltaCursor = nil
                shouldAttemptDelta = false
            }
            if shouldAttemptDelta, let cursor = deltaCursor {
                resolvedSyncMode = "delta"
                resolvedCursorUsed = cursor
                recordRefreshDecision(scope: scope, mode: mode, outcome: "delta")
                StartupTrace.activeWindow(
                    controllerID: controllerInstanceID,
                    trigger: trigger,
                    scope: scope.description,
                    action: "network_delta",
                    refreshID: refreshID,
                    startupPassID: currentStartupPassID,
                    uiReleased: hasReleasedStartupUI,
                    startupPassActive: isStartupNetworkPassInFlight,
                    force: force,
                    mode: String(describing: mode)
                )
                do {
                    result = try await service.syncActiveWindowChanges(
                        from: window.from,
                        to: window.to,
                        since: cursor,
                        reason: .activeWindowDelta
                    )
                } catch {
                    if error.isCancellationLike { throw error }
                    resolvedSyncMode = "delta_fallback_full"
                    recordRefreshDecision(scope: scope, mode: mode, outcome: "delta_failed_full_recovery")
                    StartupTrace.activeWindow(
                        controllerID: controllerInstanceID,
                        trigger: trigger,
                        scope: scope.description,
                        action: "delta_failed_fallback_full",
                        refreshID: refreshID,
                        startupPassID: currentStartupPassID,
                        uiReleased: hasReleasedStartupUI,
                        startupPassActive: isStartupNetworkPassInFlight,
                        force: force,
                        mode: String(describing: mode)
                    )
                    result = try await service.syncActiveWindowFull(
                        from: window.from,
                        to: window.to,
                        reason: mode.activeWindowRequestReason
                    )
                }
            } else {
                recordRefreshDecision(scope: scope, mode: mode, outcome: "full")
                StartupTrace.activeWindow(
                    controllerID: controllerInstanceID,
                    trigger: trigger,
                    scope: scope.description,
                    action: "network_full",
                    refreshID: refreshID,
                    startupPassID: currentStartupPassID,
                    uiReleased: hasReleasedStartupUI,
                    startupPassActive: isStartupNetworkPassInFlight,
                    force: force,
                    mode: String(describing: mode)
                )
                result = try await service.syncActiveWindowFull(
                    from: window.from,
                    to: window.to,
                    reason: mode.activeWindowRequestReason
                )
            }
            updateServerCursor(for: scope, with: result.serverTime)
            noteReservationServerSyncCompleted()
            markScopeSuccess(scope)
            freshnessCoordinator?.markCompleted(freshnessScope)
            persistActiveWindowBoundsIfNeeded(scope: scope, window: window)
            MultiDeviceSyncTrace.activeWindowSync(
                reason: mode == .automatic ? "visible_live_\(resolvedSyncMode)" : "\(mode)_\(resolvedSyncMode)",
                decoded: result.rowCount,
                firstIDs: result.firstIDs,
                from: window.from,
                to: window.to,
                cursor: resolvedCursorUsed
            )
            ActiveWindowFreshnessTrace.markSuccess(
                source: allowStartupDelta ? "startup_delta" : String(describing: mode),
                scope: scope.description,
                cursorSaved: serverCursor(for: scope) != nil,
                autoFreshUntil: Date().addingTimeInterval(activeWindowAutoRefreshTTL)
            )
            StartupPolicyTrace.persisted(
                scope: scope.persistenceKey,
                cursorSaved: serverCursor(for: scope) != nil,
                lastSuccessSaved: syncStateByScope[scope]?.lastSuccessAt != nil
            )
            StartupTrace.activeWindow(
                controllerID: controllerInstanceID,
                trigger: trigger,
                scope: scope.description,
                action: "completed",
                refreshID: refreshID,
                startupPassID: currentStartupPassID,
                uiReleased: hasReleasedStartupUI,
                startupPassActive: isStartupNetworkPassInFlight,
                force: force,
                mode: String(describing: mode)
            )
        } catch {
            if error.isCancellationLike {
                markScopeCancelled(scope)
                freshnessCoordinator?.markFailed(freshnessScope, cooldown: 0)
                if mode == .automatic {
                    isAutoRefreshing = false
                } else if showsGlobalProgress {
                    isSyncing = false
                }
                return false
            }

            if mode == .startup || mode == .manual || mode == .automatic {
                lastAutoRefreshFailureAt = Date()
            }
            markScopeFailure(scope, cooldown: mode == .automatic || mode == .startup ? autoRefreshFailureCooldown : nil)
            freshnessCoordinator?.markFailed(freshnessScope)
            recordRefreshDecision(scope: scope, mode: mode, outcome: error.isOfflineLike ? "failed_offline" : "failed")
            if mode != .automatic {
                postRefreshFailureNotice(mode: mode, error: error)
            }
            if mode == .automatic {
                isAutoRefreshing = false
            } else if showsGlobalProgress {
                isSyncing = false
            }
            return false
        }

        if mode == .automatic {
            isAutoRefreshing = false
        } else if showsGlobalProgress {
            isSyncing = false
        }

        if mode != .automatic && showsGlobalProgress {
            postNotice(
                severity: .success,
                source: mode.noticeSource,
                title: "Reservations updated",
                requestReason: mode.activeWindowRequestReason
            )
        }

        return true
    }

    @discardableResult
    private func performTodayRefresh(
        context: ModelContext,
        mode: ReservationRefreshMode
    ) async -> Bool {
        // Legacy/private path retained for diagnostics and fallback only.
        // Normal Home/List/Review refresh must use performActiveWindowRefresh.
        let scope = todayScope()

        guard !hasActiveReservationRefresh else {
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "\(scope.description) skipped because another reservation refresh is active")
            return false
        }

        guard beginScope(scope, intent: mode.syncIntent) else {
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "\(scope.description) skipped because this scope is already in flight")
            return false
        }

        if mode == .automatic {
            isAutoRefreshing = true
        } else {
            isSyncing = true
        }
        clearScopedMessages(for: mode.noticeSource)

        do {
            // Service/repository are per operation so they use the current ModelContext.
            let repository = ReservationRepository(context: context)
            let service = ReservationSyncService(client: environment.apiClient, repository: repository)
            let result: ReservationSyncResult
            if mode == .automatic, let cursor = serverCursor(for: scope) {
                result = try await service.syncTodayChanges(
                    since: cursor,
                    reason: .autoTodayDelta
                )
            } else {
                result = try await service.syncTodayFull(reason: mode.requestReason)
            }
            updateServerCursor(for: scope, with: result.serverTime)
            noteReservationServerSyncCompleted()
            markScopeSuccess(scope)
        } catch {
            if error.isCancellationLike {
                markScopeCancelled(scope)
                if mode == .automatic {
                    isAutoRefreshing = false
                } else {
                    isSyncing = false
                }
                return false
            }

            if mode == .startup || mode == .manual || mode == .automatic {
                lastAutoRefreshFailureAt = Date()
            }
            markScopeFailure(scope, cooldown: mode == .automatic || mode == .startup ? autoRefreshFailureCooldown : nil)
            if mode != .automatic {
                postRefreshFailureNotice(mode: mode, error: error)
            }
            if mode == .automatic {
                isAutoRefreshing = false
            } else {
                isSyncing = false
            }
            return false
        }

        if mode == .automatic {
            isAutoRefreshing = false
        } else {
            isSyncing = false
        }

        if mode != .automatic {
            postNotice(
                severity: .success,
                source: mode.noticeSource,
                title: "Reservations updated",
                requestReason: mode.requestReason
            )
        }

        return true
    }

    // Intent: Legacy view action name; current implementation refreshes the active window.
    // Network: GET /managed-reservations?from=...&to=....
    func refreshReviewQueues(context: ModelContext) async {
        await requestReviewRefresh(context: context, source: .manual)
    }

    @discardableResult
    private func performScheduleWindowRefresh(
        context: ModelContext,
        force: Bool
    ) async -> Bool {
        // Legacy/private path retained for diagnostics and fallback only.
        // Schedule upcoming should normally render from the shared active-window cache.
        let scope = scheduleScope()

        if !force && isScopeFresh(scope, freshnessInterval: scheduleFreshnessInterval) {
            return true
        }

        guard !hasActiveReservationRefresh else {
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "\(scope.description) skipped because another reservation refresh is active")
            return false
        }

        guard beginScope(scope, intent: force ? .manual : .screenActive) else {
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "\(scope.description) skipped because this scope is already in flight")
            return false
        }

        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            let window = scheduleWindow()
            // Created per operation so schedule sync writes into this view's ModelContext.
            let repository = ReservationRepository(context: context)
            let service = ReservationSyncService(client: environment.apiClient, repository: repository)
            let result = try await service.syncScheduleWindowFull(
                from: window.from,
                to: window.to,
                reason: .scheduleWindow
            )
            updateServerCursor(for: scope, with: result.serverTime)
            noteReservationServerSyncCompleted()
            markScopeSuccess(scope)
            return true
        } catch {
            if error.isCancellationLike {
                markScopeCancelled(scope)
                return false
            }

            markScopeFailure(scope)
            postRefreshFailureNotice(mode: .schedule, error: error)
            return false
        }
    }

    @discardableResult
    private func performReviewQueuesRefresh(
        context: ModelContext,
        force: Bool
    ) async -> Bool {
        // Legacy/private path retained for diagnostics and fallback only.
        // Bookings Needs Review should normally filter the shared active-window cache.
        let scope = ReservationSyncScope.reviewQueues

        if !force && isScopeFresh(scope, freshnessInterval: reviewFreshnessInterval) {
            return true
        }

        guard !hasActiveReservationRefresh else {
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "\(scope.description) skipped because another reservation refresh is active")
            return false
        }

        guard beginScope(scope, intent: force ? .manual : .screenActive) else {
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "\(scope.description) skipped because this scope is already in flight")
            return false
        }

        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            // Created per operation so pending queue sync writes into this view's ModelContext.
            let repository = ReservationRepository(context: context)
            let service = ReservationSyncService(client: environment.apiClient, repository: repository)
            try await service.syncReviewQueues(reason: .reviewQueues)
            noteReservationServerSyncCompleted()
            markScopeSuccess(scope)
            return true
        } catch {
            if error.isCancellationLike {
                markScopeCancelled(scope)
                return false
            }

            markScopeFailure(scope)
            postRefreshFailureNotice(mode: .review, error: error)
            return false
        }
    }

    // MARK: - Local Cache Upsert

    // Intent: Upserts one server DTO into SwiftData cache without creating a mutation.
    // Rename note: A later cleanup should call this upsertServerReservationIntoCache.
    func save(_ reservation: ReservationDTO, context: ModelContext) {
        let repository = ReservationRepository(context: context)
        let service = ReservationSyncService(client: environment.apiClient, repository: repository)

        do {
            try service.saveReservation(reservation)
            markScopesTouched(after: reservation)
        } catch {
            postNotice(
                severity: .error,
                source: .mutation,
                title: "Could not save reservation locally",
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Restaurant Setup

    // Intent: Loads the lightweight setup row used by manual-create defaults and settings.
    // Network: GET /restaurant-setup.
    @discardableResult
    func loadRestaurantSetup(context: ModelContext? = nil, force: Bool = false) async throws -> RestaurantSetup {
        if !force,
           let restaurantSetupLoadedAt,
           Date().timeIntervalSince(restaurantSetupLoadedAt) < restaurantSetupFreshnessInterval {
            ReservationAPILogger.skip(reason: .scopeSkipFresh, message: "restaurant_setup skipped because cache is fresh")
            return restaurantSetup
        }

        guard !isLoadingRestaurantSetup else {
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "restaurant_setup skipped because request is already in flight")
            return restaurantSetup
        }

        isLoadingRestaurantSetup = true
        defer { isLoadingRestaurantSetup = false }

        do {
            StartupTrace.directAPI(
                caller: "ReservationsController.loadRestaurantSetup",
                reason: "restaurant_setup",
                controllerID: controllerInstanceID
            )
            let dto = try await environment.apiClient.fetchRestaurantSetup(reason: .restaurantSetup)
            let setup = RestaurantSetup(dto: dto)
            restaurantSetup = setup
            restaurantSetupLoadedAt = Date()
            return setup
        } catch {
            if error.isCancellationLike {
                throw error
            }

            postNotice(
                severity: .warning,
                source: .admin,
                title: setupFailureTitle(for: error),
                message: error.localizedDescription,
                requestReason: .restaurantSetup,
                errorCode: errorLogCode(error),
                developerDiagnostics: error.reservationAPIDeveloperDetail
            )
            throw error
        }
    }

    private func setupFailureTitle(for error: Error) -> String {
        if let apiError = error as? ReservationAPIError {
            switch apiError {
            case .missingCredentials, .unauthorized:
                return "Restaurant setup requires valid credentials"
            case .decodingFailure:
                return "Restaurant setup response could not be read"
            case .serverError(let statusCode, _) where statusCode == 404:
                return "Restaurant setup endpoint not found"
            default:
                return "Restaurant setup unavailable"
            }
        }
        return "Restaurant setup unavailable"
    }

    // Intent: Saves manager-editable setup fields.
    // Network: PATCH /restaurant-setup.
    @discardableResult
    func updateRestaurantSetup(request: RestaurantSetupUpdateRequest) async throws -> RestaurantSetup {
        guard !isSavingRestaurantSetup else {
            throw ReservationControllerError.actionAlreadyInProgress
        }

        isSavingRestaurantSetup = true
        defer { isSavingRestaurantSetup = false }

        do {
            let dto = try await environment.apiClient.updateRestaurantSetup(
                request,
                reason: .restaurantSetupPatch
            )
            let setup = RestaurantSetup(dto: dto)
            restaurantSetup = setup
            restaurantSetupLoadedAt = Date()
            postNotice(severity: .success, source: .admin, title: "Restaurant settings saved")
            return setup
        } catch {
            postNotice(
                severity: .error,
                source: .admin,
                title: "Restaurant settings did not save",
                message: error.localizedDescription,
                requestReason: .restaurantSetupPatch,
                errorCode: errorLogCode(error)
            )
            throw error
        }
    }

    // Intent: Reads backend weekly/special hours for manager settings.
    // Network: GET /restaurant-hours.
    @discardableResult
    func loadRestaurantHours(from: String? = nil, to: String? = nil) async throws -> RestaurantHoursDTO {
        guard !isLoadingRestaurantHours else {
            throw ReservationControllerError.actionAlreadyInProgress
        }

        isLoadingRestaurantHours = true
        defer { isLoadingRestaurantHours = false }

        return try await environment.apiClient.fetchRestaurantHours(
            from: from,
            to: to,
            reason: .restaurantHours
        )
    }

    // Intent: Saves backend weekly hours.
    // Network: PATCH /restaurant-hours.
    @discardableResult
    func updateRestaurantHours(request: WeeklyHoursUpdateRequest) async throws -> RestaurantHoursDTO {
        guard !isSavingRestaurantHours else {
            throw ReservationControllerError.actionAlreadyInProgress
        }

        isSavingRestaurantHours = true
        defer { isSavingRestaurantHours = false }

        do {
            let hours = try await environment.apiClient.updateRestaurantHours(
                request,
                reason: .restaurantHoursPatch
            )
            postNotice(severity: .success, source: .admin, title: "Weekly hours saved")
            return hours
        } catch {
            postNotice(
                severity: .error,
                source: .admin,
                title: "Weekly hours did not save",
                message: error.localizedDescription,
                requestReason: .restaurantHoursPatch,
                errorCode: errorLogCode(error)
            )
            throw error
        }
    }

    // Intent: Reads effective backend availability for one service date.
    // Network: GET /restaurant-day-availability?date=YYYY-MM-DD.
    @discardableResult
    func loadRestaurantDayAvailability(date: String) async throws -> RestaurantDayAvailabilityDTO {
        if let cached = dayAvailabilityCacheByDate[date],
           Date().timeIntervalSince(cached.loadedAt) < dateOperationsFreshnessInterval {
            ReservationAPILogger.skip(reason: .scopeSkipFresh, message: "restaurant_day_availability(\(date)) skipped because cache is fresh")
            return cached.value
        }

        if let task = dayAvailabilityTasksByDate[date] {
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "restaurant_day_availability(\(date)) skipped because request is already in flight")
            return try await task.value
        }

        isLoadingRestaurantDayAvailability = true
        let task = Task { [environment] in
            try await environment.apiClient.fetchRestaurantDayAvailability(
                date: date,
                reason: .restaurantDayAvailability
            )
        }
        dayAvailabilityTasksByDate[date] = task

        do {
            let availability = try await task.value
            dayAvailabilityCacheByDate[date] = (availability, Date())
            dayAvailabilityTasksByDate[date] = nil
            isLoadingRestaurantDayAvailability = false
            return availability
        } catch {
            dayAvailabilityTasksByDate[date] = nil
            isLoadingRestaurantDayAvailability = false
            throw error
        }
    }

    // Intent: Saves a manual availability override for one date.
    // Network: PATCH /restaurant-day-availability?date=YYYY-MM-DD.
    @discardableResult
    func updateRestaurantDayAvailability(
        date: String,
        request: RestaurantDayAvailabilityUpdateRequest
    ) async throws -> RestaurantDayAvailabilityDTO {
        guard !isSavingRestaurantDayAvailability else {
            throw ReservationControllerError.actionAlreadyInProgress
        }

        isSavingRestaurantDayAvailability = true
        defer { isSavingRestaurantDayAvailability = false }

        do {
            let availability = try await environment.apiClient.updateRestaurantDayAvailability(
                date: date,
                request: request,
                reason: .restaurantDayAvailabilityPatch
            )
            dayAvailabilityCacheByDate[date] = (availability, Date())
            availabilitySummaryByDate[date] = nil
            postNotice(severity: .success, source: .admin, title: "Today availability saved")
            return availability
        } catch {
            postNotice(
                severity: .error,
                source: .admin,
                title: "Availability did not save",
                message: error.localizedDescription,
                requestReason: .restaurantDayAvailabilityPatch,
                errorCode: errorLogCode(error)
            )
            throw error
        }
    }

    // Intent: Previews backend-computed slots for one service date.
    // Network: GET /reservation-slots?date=YYYY-MM-DD.
    @discardableResult
    func loadReservationSlots(date: String) async throws -> ReservationSlotsResponseDTO {
        if let cached = reservationSlotsCacheByDate[date],
           Date().timeIntervalSince(cached.loadedAt) < dateOperationsFreshnessInterval {
            ReservationAPILogger.skip(reason: .scopeSkipFresh, message: "reservation_slots(\(date)) skipped because cache is fresh")
            return cached.value
        }

        if let task = reservationSlotsTasksByDate[date] {
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "reservation_slots(\(date)) skipped because request is already in flight")
            return try await task.value
        }

        let task = Task { [environment] in
            try await environment.apiClient.fetchReservationSlots(
                date: date,
                reason: .reservationSlots
            )
        }
        reservationSlotsTasksByDate[date] = task

        do {
            let slots = try await task.value
            reservationSlotsCacheByDate[date] = (slots, Date())
            reservationSlotsTasksByDate[date] = nil
            return slots
        } catch {
            reservationSlotsTasksByDate[date] = nil
            throw error
        }
    }

    // Intent: Reads staff-blocked public slots for one service date.
    // Network: GET /restaurant-blocked-slots?date=YYYY-MM-DD.
    @discardableResult
    func loadRestaurantBlockedSlots(date: String) async throws -> RestaurantBlockedSlotsResponseDTO {
        if let cached = blockedSlotsCacheByDate[date],
           Date().timeIntervalSince(cached.loadedAt) < dateOperationsFreshnessInterval {
            ReservationAPILogger.skip(reason: .scopeSkipFresh, message: "restaurant_blocked_slots(\(date)) skipped because cache is fresh")
            return cached.value
        }

        if let task = blockedSlotsTasksByDate[date] {
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "restaurant_blocked_slots(\(date)) skipped because request is already in flight")
            return try await task.value
        }

        let task = Task { [environment] in
            try await environment.apiClient.fetchRestaurantBlockedSlots(
                date: date,
                reason: .restaurantBlockedSlots
            )
        }
        blockedSlotsTasksByDate[date] = task

        do {
            let blocked = try await task.value
            blockedSlotsCacheByDate[date] = (blocked, Date())
            blockedSlotsTasksByDate[date] = nil
            return blocked
        } catch {
            blockedSlotsTasksByDate[date] = nil
            throw error
        }
    }

    // MARK: - Home Availability Summary Cache

    func availabilitySummary(for date: String) -> ReservationAvailabilitySummary? {
        availabilitySummaryByDate[date]
    }

    func availabilitySummaryError(for date: String) -> String? {
        availabilitySummaryErrorsByDate[date]
    }

    func isAvailabilitySummaryLoading(date: String) -> Bool {
        availabilitySummaryLoadingDates.contains(date)
    }

    func cachedReservationSlots(date: String) -> ReservationSlotsResponseDTO? {
        reservationSlotsCacheByDate[date]?.value ?? availabilitySummaryByDate[date]?.slots
    }

    func cachedRestaurantDayAvailability(date: String) -> RestaurantDayAvailabilityDTO? {
        dayAvailabilityCacheByDate[date]?.value ?? availabilitySummaryByDate[date]?.availability
    }

    /// Unified summary bundle timestamp when the full availability summary exists.
    func availabilitySummaryLoadedAt(for date: String) -> Date? {
        availabilitySummaryByDate[date]?.loadedAt
    }

    /// Timestamp for restaurant day availability only when that endpoint (or summary bundle) was loaded.
    func restaurantDayAvailabilityLoadedAt(for date: String) -> Date? {
        if availabilitySummaryByDate[date] != nil {
            return availabilitySummaryByDate[date]?.loadedAt
        }
        return dayAvailabilityCacheByDate[date]?.loadedAt
    }

    /// Timestamp for reservation slots only when that endpoint (or summary bundle) was loaded.
    func reservationSlotsLoadedAt(for date: String) -> Date? {
        if availabilitySummaryByDate[date] != nil {
            return availabilitySummaryByDate[date]?.loadedAt
        }
        return reservationSlotsCacheByDate[date]?.loadedAt
    }

    /// Timestamp for blocked slots only when that endpoint (or summary bundle) was loaded.
    func blockedSlotsLoadedAt(for date: String) -> Date? {
        if availabilitySummaryByDate[date] != nil {
            return availabilitySummaryByDate[date]?.loadedAt
        }
        return blockedSlotsCacheByDate[date]?.loadedAt
    }

    func hasBlockedSlotsCache(for date: String) -> Bool {
        availabilitySummaryByDate[date] != nil || blockedSlotsCacheByDate[date] != nil
    }

    func invalidateAvailabilityCache(for date: String) {
        availabilitySummaryByDate[date] = nil
        dayAvailabilityCacheByDate[date] = nil
        reservationSlotsCacheByDate[date] = nil
        blockedSlotsCacheByDate[date] = nil
        availabilitySummaryErrorsByDate[date] = nil
        FreshnessTrace.log(
            key: "reservation_slots",
            date: date,
            action: "invalidate",
            reason: "mutation"
        )
    }

    func cachedRestaurantBlockedSlots(date: String) -> RestaurantBlockedSlotsResponseDTO? {
        if let cached = blockedSlotsCacheByDate[date]?.value {
            return cached
        }
        guard let summary = availabilitySummaryByDate[date] else { return nil }
        return RestaurantBlockedSlotsResponseDTO(
            success: true,
            date: date,
            data: summary.blockedSlots
        )
    }

    func scheduleAvailabilitySummary(date: String, force: Bool = false) {
        if !force,
           let summary = availabilitySummaryByDate[date],
           Date().timeIntervalSince(summary.loadedAt) < availabilitySummaryFreshnessInterval {
            return
        }

        if let previous = availabilitySummaryPendingDate, previous != date {
            DateLoadTrace.cancelled(date: previous, reason: "date_changed")
        }

        let delayMs = Int(availabilitySummaryDebounceInterval * 1000)
        DateLoadTrace.scheduled(date: date, type: "availability", delayMs: delayMs)

        availabilitySummaryPendingDate = date
        availabilitySummaryDebounceTask?.cancel()
        availabilitySummaryDebounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.availabilitySummaryDebounceInterval))
            guard !Task.isCancelled else { return }
            guard self.availabilitySummaryPendingDate == date else {
                DateLoadTrace.cancelled(date: date, reason: "date_changed")
                return
            }
            self.ensureAvailabilitySummary(date: date, force: force)
            self.availabilitySummaryDebounceTask = nil
        }
    }

    func ensureAvailabilitySummary(date: String, force: Bool = false) {
        let bundleScope = FreshnessScope.availabilityBundle(date: date)

        if !force,
           let summary = availabilitySummaryByDate[date],
           Date().timeIntervalSince(summary.loadedAt) < availabilitySummaryFreshnessInterval {
            freshnessCoordinator?.record(scope: bundleScope, decision: .useCache(reason: "fresh"))
            ReservationAPILogger.skip(reason: .scopeSkipFresh, message: "availability_summary(\(date)) skipped because cache is fresh")
            return
        }

        if availabilitySummaryTasksByDate[date] != nil {
            freshnessCoordinator?.record(scope: bundleScope, decision: .joinInFlight(reason: "in_flight"))
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "availability_summary(\(date)) skipped because request is already in flight")
            return
        }

        freshnessCoordinator?.record(scope: bundleScope, decision: .fetch(reason: force ? "forced" : "host_visible_stale"))
        freshnessCoordinator?.markInFlight(bundleScope)
        availabilitySummaryLoadingDates.insert(date)
        availabilitySummaryErrorsByDate[date] = nil
        let task = Task { [weak self] in
            guard let self else { return }
            await self.loadAvailabilitySummary(date: date)
        }
        availabilitySummaryTasksByDate[date] = task
    }

    func cancelAvailabilitySummary(date: String) {
        if availabilitySummaryPendingDate == date {
            availabilitySummaryPendingDate = nil
        }
        availabilitySummaryDebounceTask?.cancel()
        availabilitySummaryDebounceTask = nil
        DateLoadTrace.cancelled(date: date, reason: "date_changed")

        guard let task = availabilitySummaryTasksByDate[date] else { return }
        task.cancel()
        availabilitySummaryLoadingDates.remove(date)
        availabilitySummaryTasksByDate[date] = nil
        ReservationAPILogger.skip(
            reason: .scopeSkipInFlight,
            message: "availability_summary(\(date)) cancelled because Home is no longer active"
        )
    }

    private func loadAvailabilitySummary(date: String) async {
        let bundleScope = FreshnessScope.availabilityBundle(date: date)
        defer {
            availabilitySummaryLoadingDates.remove(date)
            availabilitySummaryTasksByDate[date] = nil
            // Guarantee the coordinator never leaks an in-flight marker. On success the
            // scope was already marked completed (fresh); this is a no-op there.
            freshnessCoordinator?.endInFlight(bundleScope)
            refreshHomeServicePresentation()
        }

        let started = ContinuousClock.now
        DateSwitchTrace.availabilityStart(date: date)
        // Availability completion only touches @Published in-memory dictionaries on the
        // MainActor; it never opens or reads a SwiftData ModelContext. This trace pins
        // that fact so the unsafeForcedSync warning can be excluded from this path.
        DateSwitchTrace.concurrency(context: "availability_completion", modelContextUsed: false)

        do {
            // Serialize availability reads so they do not race the active-window sync.
            let networkStarted = ContinuousClock.now
            let loadedAvailability = try await loadRestaurantDayAvailability(date: date)
            UIPressureTrace.phase(
                "date_availability_network",
                duration: networkStarted.duration(to: .now).pressureTraceTimeInterval,
                extra: "date=\(date)"
            )
            guard !Task.isCancelled else {
                DateLoadTrace.cancelled(date: date, reason: "cancelled")
                return
            }
            guard hostBoardSelectedDateKey == date else {
                DateLoadTrace.ignoredResponse(date: date, reason: "not_selected")
                return
            }

            let loadedSlots = try await loadReservationSlots(date: date)
            guard hostBoardSelectedDateKey == date else {
                DateLoadTrace.ignoredResponse(date: date, reason: "not_selected")
                return
            }

            let loadedBlocked = try await loadRestaurantBlockedSlots(date: date)
            guard hostBoardSelectedDateKey == date else {
                DateLoadTrace.ignoredResponse(date: date, reason: "not_selected")
                return
            }

            availabilitySummaryByDate[date] = ReservationAvailabilitySummary(
                availability: loadedAvailability,
                slots: loadedSlots,
                blockedSlots: loadedBlocked.data,
                loadedAt: Date()
            )
            availabilitySummaryErrorsByDate[date] = nil
            freshnessCoordinator?.markCompleted(bundleScope)
            let durationMs = Int(started.duration(to: .now).pressureTraceTimeInterval * 1000)
            DateSwitchTrace.availabilityPublish(date: date, durationMs: durationMs)
            DateLoadTrace.completed(date: date, type: "availability", durationMs: durationMs)
        } catch {
            if error.isCancellationLike {
                DateLoadTrace.cancelled(date: date, reason: "cancelled")
                return
            }
            guard hostBoardSelectedDateKey == date else {
                DateLoadTrace.ignoredResponse(date: date, reason: "not_selected")
                return
            }
            freshnessCoordinator?.markFailed(bundleScope, cooldown: 15)
            availabilitySummaryErrorsByDate[date] = error.isOfflineLike
                ? "Offline. Availability preview may be stale."
                : "Could not refresh availability preview."
        }
    }

    // Intent: Reads backend aggregate business metrics; does not scan local SwiftData.
    // Network: GET /reservation-analytics/summary.
    @discardableResult
    func loadReservationAnalyticsSummary(
        from: String? = nil,
        to: String? = nil
    ) async throws -> ReservationAnalyticsSummaryDTO {
        guard !isLoadingReservationAnalytics else {
            throw ReservationControllerError.actionAlreadyInProgress
        }

        isLoadingReservationAnalytics = true
        defer { isLoadingReservationAnalytics = false }

        return try await environment.apiClient.fetchReservationAnalyticsSummary(
            from: from,
            to: to,
            reason: .reservationAnalyticsSummary
        )
    }

    func isActionInProgress(for reservation: ReservationRecord) -> Bool {
        actionInProgressIDs.contains(reservation.remoteID)
            || reconcilingReservationIDs.contains(reservation.remoteID)
    }

    func isReconcilingReservation(_ reservation: ReservationRecord) -> Bool {
        reconcilingReservationIDs.contains(reservation.remoteID)
    }

    // MARK: - Manual Reservation Creation

    // Intent: Staff creates a call-in/manual reservation on the server.
    // Writes: Upserts the returned server DTO into SwiftData through MutationService.
    // Network: POST /managed-reservations.
    func createReservation(
        _ request: ReservationCreateRequest,
        context: ModelContext
    ) async throws -> ReservationDTO {
        try ensureMutationsAllowedOnline()

        guard !isCreatingReservation else {
            throw ReservationControllerError.actionAlreadyInProgress
        }

        isCreatingReservation = true
        errorMessage = nil
        noticeMessage = nil
        defer { isCreatingReservation = false }

        do {
            // Mutation service owns the server-first create and returned DTO cache upsert.
            let repository = ReservationRepository(context: context)
            let service = ReservationMutationService(client: environment.apiClient, repository: repository)
            let reservation = try await service.createReservation(request)
            markScopesTouched(after: reservation)
            MultiDeviceSyncTrace.manualCreateSuccess(
                remoteID: reservation.id,
                date: reservation.reservationDate,
                time: reservation.reservationTime,
                apiUpdatedAt: reservation.updatedAt
            )
            postNotice(severity: .success, source: .mutation, title: "Manual reservation created")
            return reservation
        } catch {
            if error.isCancellationLike {
                throw error
            }

            if error.isOfflineLike {
                postOfflineNotice(source: .mutation, requestReason: .mutationCreate, error: error)
            }

            errorMessage = "Manual reservation was not created. Please retry before relying on this reservation."
            postNotice(
                severity: .error,
                source: .mutation,
                title: "Create did not sync",
                message: "Manual reservation was not created. Please retry before relying on it."
            )
            throw error
        }
    }

    // Intent: Staff creates a call-in/manual reservation that is already accepted.
    // Network: POST /managed-reservations with status=confirmed.
    // Email: Does not call the confirmation-email endpoint.
    func createAcceptedManualReservation(
        _ request: ReservationCreateRequest,
        context: ModelContext
    ) async throws -> ReservationDTO {
        try ensureMutationsAllowedOnline()

        guard !isCreatingReservation else {
            throw ReservationControllerError.actionAlreadyInProgress
        }

        isCreatingReservation = true
        errorMessage = nil
        noticeMessage = nil
        defer { isCreatingReservation = false }

        do {
            let repository = ReservationRepository(context: context)
            let service = ReservationMutationService(client: environment.apiClient, repository: repository)
            let acceptedReservation = try await service.createReservation(request)
            markScopesTouched(after: acceptedReservation)
            MultiDeviceSyncTrace.manualCreateSuccess(
                remoteID: acceptedReservation.id,
                date: acceptedReservation.reservationDate,
                time: acceptedReservation.reservationTime,
                apiUpdatedAt: acceptedReservation.updatedAt
            )
            postNotice(
                severity: .success,
                source: .mutation,
                title: "Manual reservation added",
                message: "Created as confirmed. No email was sent."
            )
            return acceptedReservation
        } catch {
            if error.isCancellationLike {
                throw error
            }

            if error.isOfflineLike {
                postOfflineNotice(source: .mutation, requestReason: .mutationCreate, error: error)
            }

            errorMessage = "Manual reservation was not created. Please retry before relying on this reservation."
            postNotice(
                severity: .error,
                source: .mutation,
                title: "Create did not sync",
                message: "Manual reservation was not created. Please retry before relying on it."
            )
            throw error
        }
    }

    // MARK: - Reservation Mutation Actions

    // Intent: Generic server PATCH for reservation edits such as table, time, party, notes, or status.
    // Writes: Upserts the returned server DTO into SwiftData through MutationService.
    // Network: PATCH /managed-reservations/{id}.
    func updateReservation(
        id: Int,
        request: ReservationUpdateRequest,
        context: ModelContext,
        action: String = "edit"
    ) async throws -> ReservationDTO {
        try ensureMutationsAllowedOnline()

        guard !actionInProgressIDs.contains(id) else {
            throw ReservationControllerError.actionAlreadyInProgress
        }

        actionInProgressIDs.insert(id)
        defer { actionInProgressIDs.remove(id) }

        let repository = ReservationRepository(context: context)
        let service = ReservationMutationService(client: environment.apiClient, repository: repository)

        // Optimistic concurrency: attach the cached row version as expected_updated_at
        // when the caller did not already supply one. Omitted when the row is uncached.
        var request = request
        if request.expectedUpdatedAt == nil {
            request.expectedUpdatedAt = repository.rowVersion(forRemoteID: id)
        }
        MutationVersionTrace.log(
            action: action,
            reservationID: id,
            expectedUpdatedAt: request.expectedUpdatedAt
        )

        do {
            let reservation = try await service.updateReservation(id: id, request: request)
            markScopesTouched(after: reservation)
            postNotice(severity: .success, source: .mutation, title: "Reservation updated")
            return reservation
        } catch {
            if error.isCancellationLike {
                throw error
            }

            if error.isOfflineLike {
                postOfflineNotice(source: .mutation, requestReason: .mutationPatch, error: error)
            }

            // Staff-safe reconcile: 404 (already gone) and 409 (already changed /
            // invalid transition) refresh server truth instead of showing a misleading
            // "could not update". Uncertain network falls through to the block below.
            if await applyMutationReconcilePolicy(
                error: error,
                action: action,
                id: id,
                reservationDate: nil,
                context: context
            ) {
                throw error
            }

            if error.mayHaveReachedReservationServer {
                postNotice(
                    severity: .warning,
                    source: .mutation,
                    title: "Update may have reached the server. Checking reservation..."
                )
                let reconciled = await reconcileReservation(id: id, context: context)
                if reconciled == nil {
                    postMutationFailureNotice(
                        title: "Could not update reservation",
                        message: "Could not update reservation. Please try again."
                    )
                } else {
                    errorMessage = nil
                    postNotice(
                        severity: .warning,
                        source: .mutation,
                        title: "Server state refreshed",
                        message: "The app checked this reservation after an uncertain network failure."
                    )
                }
                throw error
            }

            errorMessage = "Could not update reservation. Please try again."
            postMutationFailureNotice(
                title: "Could not update reservation",
                message: "Could not update reservation. Please try again."
            )
            throw error
        }
    }

    // Intent: Staff changes reservation status without sending email.
    // Network: PATCH /managed-reservations/{id} with status.
    func updateStatus(
        reservation: ReservationRecord,
        status: ReservationStatus,
        context: ModelContext
    ) async {
        let previousStatus = reservation.status
        let previousSeatedAt = localSeatedAtByReservationID[reservation.remoteID]
        applyOptimisticStatusUpdate(
            reservation: reservation,
            status: status,
            context: context
        )

        do {
            let updated = try await updateReservation(
                id: reservation.remoteID,
                request: ReservationUpdateRequest(status: status),
                context: context,
                action: "status"
            )
            updateLocalSeatedTimestamp(after: updated)
        } catch {
            revertOptimisticStatusUpdate(
                reservation: reservation,
                previousStatus: previousStatus,
                previousSeatedAt: previousSeatedAt,
                context: context
            )
            if errorMessage == nil {
                errorMessage = "Update did not sync. Please retry or check the reservation before relying on this change."
            }
        }
    }

    // MARK: - Manual Confirmation Email

    // Intent: Records that staff created a manual Gmail/Mail draft.
    // Network: POST /managed-reservations/{id}/manual-email-log.
    // Email: Does not send email, change status, or mark confirmation_email_sent_at.
    func recordManualConfirmationDraftCreated(
        reservation: ReservationRecord,
        toEmail: String?,
        subject: String?,
        bodySnapshot: String?
    ) async throws -> ReservationManualEmailLogDTO {
        try await logManualConfirmationActivity(
            reservation: reservation,
            status: .draftCreated,
            toEmail: toEmail,
            subject: subject,
            bodySnapshot: bodySnapshot,
            errorMessage: nil,
            context: nil,
            reconcileAfterSuccess: false
        )
    }

    // Intent: Records staff-reported manual Gmail/Mail send activity.
    // Network: POST /managed-reservations/{id}/manual-email-log.
    // Email: Does not call POST /confirm and does not change reservation status.
    func recordManualConfirmationSent(
        reservation: ReservationRecord,
        toEmail: String?,
        subject: String?,
        bodySnapshot: String?,
        context: ModelContext
    ) async throws -> ReservationManualEmailLogDTO {
        try await logManualConfirmationActivity(
            reservation: reservation,
            status: .manualSent,
            toEmail: toEmail,
            subject: subject,
            bodySnapshot: bodySnapshot,
            errorMessage: nil,
            context: context,
            reconcileAfterSuccess: true
        )
    }

    // Intent: Records a real Mail/Gmail failure when iOS receives one.
    // Network: POST /managed-reservations/{id}/manual-email-log.
    func recordManualConfirmationFailed(
        reservation: ReservationRecord,
        toEmail: String?,
        subject: String?,
        bodySnapshot: String?,
        errorMessage: String?
    ) async throws -> ReservationManualEmailLogDTO {
        try await logManualConfirmationActivity(
            reservation: reservation,
            status: .manualFailed,
            toEmail: toEmail,
            subject: subject,
            bodySnapshot: bodySnapshot,
            errorMessage: errorMessage,
            context: nil,
            reconcileAfterSuccess: false
        )
    }

    private func logManualConfirmationActivity(
        reservation: ReservationRecord,
        status: ReservationManualEmailLogStatus,
        toEmail: String?,
        subject: String?,
        bodySnapshot: String?,
        errorMessage: String?,
        context: ModelContext?,
        reconcileAfterSuccess: Bool
    ) async throws -> ReservationManualEmailLogDTO {
        try ensureMutationsAllowedOnline()

        let id = reservation.remoteID
        guard !actionInProgressIDs.contains(id) else {
            throw ReservationControllerError.actionAlreadyInProgress
        }

        actionInProgressIDs.insert(id)
        defer { actionInProgressIDs.remove(id) }

        let request = ReservationManualEmailLogRequest(
            status: status,
            toEmail: Self.nonBlank(toEmail),
            subject: Self.nonBlank(subject),
            bodySnapshot: Self.nonBlank(bodySnapshot),
            provider: "manual_gmail",
            providerMessageId: nil,
            errorMessage: Self.nonBlank(errorMessage)
        )

        do {
            let log = try await environment.apiClient.logManualEmail(
                reservationID: id,
                request: request,
                reason: .manualEmailLog
            )

            switch status {
            case .draftCreated:
                break
            case .manualSent:
                latestEmailStatusByReservationID[id] = .sent
                if reconcileAfterSuccess, let context {
                    do {
                        let reconcileService = ReservationMutationService(
                            client: environment.apiClient,
                            repository: ReservationRepository(context: context)
                        )
                        let updated = try await reconcileService.reconcileReservation(id: id)
                        markScopesTouched(after: updated)
                    } catch {
                        postNotice(
                            severity: .warning,
                            source: .email,
                            title: "Manual confirmation recorded",
                            message: "The email log saved, but this device could not refresh the reservation timestamp yet.",
                            requestReason: .reconcileByID,
                            errorCode: errorLogCode(error),
                            developerDiagnostics: error.reservationAPIDeveloperDetail
                        )
                    }
                }
                postNotice(
                    severity: .success,
                    source: .email,
                    title: "Manual confirmation recorded",
                    message: "Staff-reported manual email activity was saved. Reservation status was not changed."
                )
            case .manualFailed:
                latestEmailStatusByReservationID[id] = .failed
                postNotice(
                    severity: .warning,
                    source: .email,
                    title: "Manual email failure recorded",
                    message: "Reservation status was not changed."
                )
            case .skipped:
                latestEmailStatusByReservationID[id] = .skipped
            }

            return log
        } catch {
            if error.isOfflineLike {
                postOfflineNotice(source: .email, requestReason: .manualEmailLog, error: error)
            }
            throw error
        }
    }

    private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Confirm With Email

    // Intent: Confirms reservation and asks backend to send/record confirmation email.
    // Network: POST /managed-reservations/{id}/confirm.
    // Rename note: A later cleanup should call this confirmReservationAndSendEmail.
    func confirmReservation(
        reservation: ReservationRecord,
        context: ModelContext
    ) async {
        guard ReservationEmailWorkflow.isBackendConfirmEmailEnabled else {
            postNotice(
                severity: .info,
                source: .email,
                title: "Backend email disabled",
                message: "Use Detail → More → Send confirmation draft for the manual pilot flow."
            )
            return
        }

        guard canStartMutationOnline() else { return }

        let id = reservation.remoteID

        guard !actionInProgressIDs.contains(id) else { return }

        actionInProgressIDs.insert(id)
        errorMessage = nil
        noticeMessage = nil
        defer { actionInProgressIDs.remove(id) }

        let repository = ReservationRepository(context: context)
        let service = ReservationMutationService(client: environment.apiClient, repository: repository)

        do {
            let response = try await service.confirmReservation(id: id)
            markScopesTouched(after: response.data)

            switch response.emailStatus {
            case .sent:
                latestEmailStatusByReservationID[id] = .sent
                postNotice(severity: .success, source: .email, title: "Reservation confirmed", message: "Confirmation email was recorded as sent.")
            case .alreadySent:
                latestEmailStatusByReservationID[id] = .alreadySent
                postNotice(severity: .info, source: .email, title: "Already confirmed", message: "Confirmation email was already recorded as sent.")
            case .failed:
                latestEmailStatusByReservationID[id] = .failed
                errorMessage = "Reservation confirmed, but email failed. Follow up manually."
                postNotice(severity: .warning, source: .email, title: "Email failed", message: "Reservation confirmed, but email failed. Follow up manually.")
            case .skipped:
                latestEmailStatusByReservationID[id] = .skipped
                postNotice(severity: .info, source: .email, title: "Email skipped", message: "No confirmation email sent: no guest email.")
            case .unknown:
                latestEmailStatusByReservationID[id] = .unknown
                postNotice(severity: .info, source: .email, title: "Reservation confirmed", message: "Check email status in details.")
            }
        } catch {
            if error.isCancellationLike {
                return
            }

            if error.isOfflineLike {
                postOfflineNotice(source: .mutation, requestReason: .mutationConfirm, error: error)
            }

            if await applyMutationReconcilePolicy(
                error: error,
                action: "confirm",
                id: id,
                reservationDate: reservation.reservationDate,
                context: context
            ) {
                return
            }

            if error.mayHaveReachedReservationServer {
                postNotice(
                    severity: .warning,
                    source: .mutation,
                    title: "Update may have reached the server. Checking reservation..."
                )
                let reconciled = await reconcileReservation(id: id, context: context)
                if reconciled != nil {
                    postNotice(
                        severity: .warning,
                        source: .mutation,
                        title: "Server state refreshed",
                        message: "The app checked this reservation after an uncertain confirmation failure."
                    )
                } else {
                    postMutationFailureNotice(
                        title: "Confirmation uncertain",
                        message: "Update may have reached the server. Please check details before relying on email status."
                    )
                }
                return
            }

            errorMessage = "Reservation was not confirmed. Confirmation email may not have been sent. Please retry or check details."
            postMutationFailureNotice(
                title: "Reservation was not confirmed",
                message: "Confirmation email may not have been sent. Retry or check details."
            )
        }
    }

    // MARK: - Hidden Reservations

    // Intent: Loads backend-hidden rows into the cache for the Hidden Reservations screen.
    // Network: GET /managed-reservations?include_hidden=1 across pages.
    @discardableResult
    func loadHiddenReservations(context: ModelContext, force: Bool = false) async throws -> [ReservationDTO] {
        let response = try await loadHiddenReservationsPage(context: context, page: 1, force: force)
        return response.data.filter { $0.isHidden == true }
    }

    @discardableResult
    func loadHiddenReservationsPage(
        context: ModelContext,
        page: Int,
        force: Bool = false
    ) async throws -> ReservationsResponse {
        guard capabilities.canViewHiddenReservations else {
            throw ReservationControllerError.permissionDenied
        }

        let scope = ReservationSyncScope.hiddenReservations

        if page == 1, !force && isScopeFresh(scope, freshnessInterval: scheduleFreshnessInterval) {
            return ReservationsResponse(
                success: true,
                serverTime: nil,
                page: 1,
                perPage: 100,
                total: 0,
                totalPages: 1,
                data: []
            )
        }

        guard beginScope(scope, intent: force ? .manual : .screenActive) else {
            ReservationAPILogger.skip(
                reason: .scopeSkipInFlight,
                message: "\(scope.description) skipped because this scope is already in flight"
            )
            return ReservationsResponse(
                success: true,
                serverTime: nil,
                page: page,
                perPage: 100,
                total: 0,
                totalPages: 1,
                data: []
            )
        }

        do {
            let response = try await fetchAndCacheHiddenReservationsPage(context: context, page: page)
            markScopeSuccess(scope)
            return response
        } catch {
            if error.isCancellationLike {
                markScopeCancelled(scope)
            } else {
                markScopeFailure(scope)
                if error.isOfflineLike {
                    postOfflineNotice(source: .admin, requestReason: .hiddenReservations, error: error)
                }
            }
            throw error
        }
    }

    private func fetchAndCacheHiddenReservationsPage(context: ModelContext, page: Int) async throws -> ReservationsResponse {
        let repository = ReservationRepository(context: context)
        let response = try await environment.apiClient.fetchReservations(
            page: page,
            perPage: 100,
            date: nil,
            from: nil,
            to: nil,
            status: nil,
            search: nil,
            includeHidden: true,
            reason: .hiddenReservations
        )

        if !response.data.isEmpty {
            try repository.upsert(response.data)
        }

        return response
    }

    // Intent: Generates a guest manage link for manual Gmail/Mail confirmation copy.
    // Network: POST /managed-reservations/{id}/guest-manage-link.
    // Email: Does not send email and does not mark email as sent.
    func generateGuestManageLink(
        reservation: ReservationRecord,
        announceNotice: Bool = true
    ) async throws -> ReservationGuestManageLinkDTO {
        guard capabilities.canGenerateGuestManageLinks else {
            throw ReservationControllerError.permissionDenied
        }

        try ensureMutationsAllowedOnline()

        let id = reservation.remoteID
        guard !actionInProgressIDs.contains(id) else {
            throw ReservationControllerError.actionAlreadyInProgress
        }

        actionInProgressIDs.insert(id)
        defer { actionInProgressIDs.remove(id) }

        do {
            let link = try await environment.apiClient.createGuestManageLink(
                id: id,
                reason: .guestManageLink
            )
            if announceNotice {
                postNotice(
                    severity: .success,
                    source: .email,
                    title: "Guest link ready",
                    message: "Copy it into the manual confirmation email."
                )
            }
            return link
        } catch {
            if error.isOfflineLike {
                postOfflineNotice(source: .email, requestReason: .guestManageLink, error: error)
            }
            postNotice(
                severity: .error,
                source: .email,
                title: "Guest link failed",
                message: "Could not generate a guest self-service link.",
                requestReason: .guestManageLink,
                errorCode: errorLogCode(error)
            )
            throw error
        }
    }

    // Intent: Developer/admin cleanup of hidden test/noise reservations only.
    // Network: DELETE /managed-reservations/{id}?force=1.
    func hardDeleteReservation(
        reservation: ReservationRecord,
        context: ModelContext,
        cleanupReason: String = "iOS admin test cleanup"
    ) async throws {
        guard capabilities.canHardDeleteReservations else {
            throw ReservationControllerError.permissionDenied
        }

        try ensureMutationsAllowedOnline()

        let id = reservation.remoteID
        let reservationDate = reservation.reservationDate
        guard !actionInProgressIDs.contains(id) else {
            throw ReservationControllerError.actionAlreadyInProgress
        }

        actionInProgressIDs.insert(id)
        defer { actionInProgressIDs.remove(id) }

        let repository = ReservationRepository(context: context)
        let service = ReservationMutationService(client: environment.apiClient, repository: repository)

        do {
            try await service.hardDeleteReservation(id: id)
            markScopesTouched(afterDeletingReservationDate: reservationDate)
            postNotice(
                severity: .success,
                source: .admin,
                title: "Test reservation deleted",
                message: cleanupReason
            )
        } catch {
            if error.isCancellationLike {
                throw error
            }
            if error.isOfflineLike {
                postOfflineNotice(source: .admin, requestReason: .hardDelete, error: error)
            }
            // 404 means another device already removed the row: treat as already gone,
            // drop the local cache copy, and show staff-safe copy instead of "not deleted".
            if await applyMutationReconcilePolicy(
                error: error,
                action: "delete",
                id: id,
                reservationDate: reservationDate,
                context: context
            ) {
                return
            }
            postNotice(
                severity: .error,
                source: .admin,
                title: "Permanent delete failed",
                message: "This test reservation was not deleted.",
                requestReason: .hardDelete,
                errorCode: errorLogCode(error)
            )
            throw error
        }
    }

    // Intent: Soft-hides a mistaken manual row on the server; no DELETE route is used.
    // Network: PATCH /managed-reservations/{id} with is_hidden=true.
    @discardableResult
    func hideWrongEntry(
        reservation: ReservationRecord,
        reason hiddenReason: String = "Wrong manual entry",
        context: ModelContext
    ) async throws -> ReservationDTO {
        try ensureMutationsAllowedOnline()

        let id = reservation.remoteID
        guard !actionInProgressIDs.contains(id) else {
            throw ReservationControllerError.actionAlreadyInProgress
        }

        actionInProgressIDs.insert(id)
        errorMessage = nil
        noticeMessage = nil
        defer { actionInProgressIDs.remove(id) }

        do {
            let repository = ReservationRepository(context: context)
            let service = ReservationMutationService(client: environment.apiClient, repository: repository)
            MutationVersionTrace.log(action: "hide", reservationID: id, expectedUpdatedAt: reservation.rowVersion)
            let hiddenReservation = try await service.updateReservation(
                id: id,
                request: ReservationUpdateRequest(
                    isHidden: true,
                    hiddenReason: hiddenReason,
                    expectedUpdatedAt: reservation.rowVersion
                )
            )
            markScopesTouched(after: hiddenReservation)
            postNotice(
                severity: .success,
                source: .mutation,
                title: "Reservation hidden",
                message: "Reservation hidden. It remains in backend history."
            )
            return hiddenReservation
        } catch {
            if error.isCancellationLike {
                throw error
            }
            if error.isOfflineLike {
                postOfflineNotice(source: .mutation, requestReason: .mutationPatch, error: error)
            }
            if await applyMutationReconcilePolicy(
                error: error,
                action: "hide",
                id: id,
                reservationDate: reservation.reservationDate,
                context: context
            ) {
                throw error
            }
            errorMessage = "Could not hide this entry. Please retry before relying on service lists."
            postMutationFailureNotice(
                title: "Hide did not sync",
                message: "Could not hide this entry. Please retry before relying on service lists."
            )
            throw error
        }
    }

    // Intent: Restores a backend-hidden row.
    // Network: PATCH /managed-reservations/{id} with is_hidden=false.
    @discardableResult
    func restoreHiddenReservation(
        reservation: ReservationRecord,
        context: ModelContext
    ) async throws -> ReservationDTO {
        try ensureMutationsAllowedOnline()

        let id = reservation.remoteID
        guard !actionInProgressIDs.contains(id) else {
            throw ReservationControllerError.actionAlreadyInProgress
        }

        actionInProgressIDs.insert(id)
        defer { actionInProgressIDs.remove(id) }

        do {
            let repository = ReservationRepository(context: context)
            let service = ReservationMutationService(client: environment.apiClient, repository: repository)
            MutationVersionTrace.log(action: "restore", reservationID: id, expectedUpdatedAt: reservation.rowVersion)
            let restoredReservation = try await service.updateReservation(
                id: id,
                request: ReservationUpdateRequest(
                    isHidden: false,
                    expectedUpdatedAt: reservation.rowVersion
                )
            )
            markScopesTouched(after: restoredReservation)
            postNotice(severity: .success, source: .mutation, title: "Reservation restored")
            return restoredReservation
        } catch {
            if error.isCancellationLike {
                throw error
            }
            if error.isOfflineLike {
                postOfflineNotice(source: .mutation, requestReason: .mutationPatch, error: error)
            }
            if await applyMutationReconcilePolicy(
                error: error,
                action: "restore",
                id: id,
                reservationDate: reservation.reservationDate,
                context: context
            ) {
                throw error
            }
            postMutationFailureNotice(
                title: "Restore did not sync",
                message: "Could not restore this reservation. Please retry."
            )
            throw error
        }
    }

    // MARK: - Import Failure Diagnostics

    // Intent: Shows managers/developers whether public form imports are failing.
    // Network: GET /managed-reservations/import-failures?page=1&per_page=1.
    func refreshImportFailureCount(reason: ReservationAPIRequestReason = .failureCount) async {
        await refreshImportFailureCountIfNeeded(force: false, reason: reason)
    }

    // Intent: Refreshes the failed-import count when capability and freshness allow.
    // Network: GET /managed-reservations/import-failures.
    func refreshImportFailureCountIfNeeded(
        force: Bool,
        reason: ReservationAPIRequestReason = .failureCount
    ) async {
        guard capabilities.canViewFailedImports else {
            importFailureCount = 0
            importFailureCountError = nil
            return
        }

        let scope = ReservationSyncScope.importFailureCount

        if !force && isScopeFresh(scope, freshnessInterval: importFailureCountFreshnessInterval) {
            return
        }

        guard !isCheckingImportFailureCount else { return }
        guard beginScope(scope, intent: force ? .manual : .screenActive) else {
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "\(scope.description) skipped because this scope is already in flight")
            return
        }

        isCheckingImportFailureCount = true
        importFailureCountError = nil
        defer { isCheckingImportFailureCount = false }

        let service = ImportFailureService(client: environment.apiClient)

        do {
            let response = try await service.fetchImportFailures(page: 1, perPage: 1, reason: reason)
            importFailureCount = response.total
            markScopeSuccess(scope)
        } catch {
            if error.isCancellationLike {
                markScopeCancelled(scope)
                return
            }

            markScopeFailure(scope, cooldown: importFailureCountFreshnessInterval)
            importFailureCountError = "Could not check form problems."
            postNotice(
                severity: .warning,
                source: .importFailures,
                title: "Form problem check failed",
                message: "The previous count is still shown.",
                requestReason: reason
            )
        }
    }

    // Intent: Developer/manager opens the full import failure list.
    // Network: GET /managed-reservations/import-failures.
    func fetchImportFailures(page: Int = 1, perPage: Int = 100) async throws -> ImportFailuresResponse {
        guard capabilities.canViewFailedImports else {
            throw ReservationControllerError.permissionDenied
        }

        let service = ImportFailureService(client: environment.apiClient)
        let response = try await service.fetchImportFailures(
            page: page,
            perPage: perPage,
            reason: .importFailuresFull
        )
        importFailureCount = response.total
        importFailureCountError = nil
        markScopeSuccess(.importFailureCount)
        return response
    }

    // MARK: - Reconcile Uncertain Mutations

    // Intent: After an uncertain mutation failure, fetch server truth for one reservation.
    // Writes: Upserts the server DTO into SwiftData if the GET succeeds.
    // Network: GET /managed-reservations/{id}.
    @discardableResult
    func reconcileReservation(id: Int, context: ModelContext) async -> ReservationDTO? {
        let scope = ReservationSyncScope.reservation(id: id)

        guard beginScope(scope, intent: .mutationReconcile) else {
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "\(scope.description) skipped because this scope is already in flight")
            return nil
        }

        reconcilingReservationIDs.insert(id)
        defer {
            reconcilingReservationIDs.remove(id)
        }

        do {
            let repository = ReservationRepository(context: context)
            let service = ReservationMutationService(client: environment.apiClient, repository: repository)
            let reservation = try await service.reconcileReservation(id: id)
            markScopeSuccess(scope)
            markScopesTouched(after: reservation)
            return reservation
        } catch {
            if error.isCancellationLike {
                markScopeCancelled(scope)
            } else {
                markScopeFailure(scope)
            }
            return nil
        }
    }

    // MARK: - Mutation Reconcile Policy Wiring

    /// Classifies a failed mutation into a staff-safe outcome and, for server-truth
    /// outcomes (already gone / already changed elsewhere), reconciles local cache and
    /// posts staff-safe copy. Returns true when the failure was fully handled here so
    /// the caller skips its generic "could not update" path.
    ///
    /// Emits [MUTATION_RECONCILE] via ReservationMutationReconcilePolicy.classify.
    /// The `.uncertainNeedsReconcile` outcome intentionally returns false so callers
    /// keep their existing uncertain-network reconcile flow.
    @discardableResult
    private func applyMutationReconcilePolicy(
        error: Error,
        action: String,
        id: Int,
        reservationDate: String?,
        context: ModelContext
    ) async -> Bool {
        let outcome = ReservationMutationReconcilePolicy.classify(
            error: error,
            action: action,
            reservationID: id
        )

        switch outcome {
        case .alreadyGone:
            removeLocalReservationAfterServerGone(
                id: id,
                reservationDate: reservationDate,
                context: context
            )
            errorMessage = nil
            postNotice(
                severity: .warning,
                source: .mutation,
                title: "Reservation already gone",
                message: MutationOutcome.copyAlreadyGone
            )
            return true

        case .alreadyChanged, .invalidTransition:
            _ = await reconcileReservation(id: id, context: context)
            errorMessage = nil
            postNotice(
                severity: .warning,
                source: .mutation,
                title: "Reservation changed elsewhere",
                message: MutationOutcome.copyAlreadyChanged
            )
            return true

        case .uncertainNeedsReconcile, .tableConflict, .failedStaffSafe, .success:
            // Uncertain network is handled by the caller's existing reconcile flow.
            // Table conflict is surfaced by the Floor Plan path. Generic failures fall
            // through to the caller's staff-safe failure notice.
            return false
        }
    }

    /// Cached row version (server updated_at ?? created_at) for an optimistic
    /// expected_updated_at guard. Returns nil when the row is not cached.
    func cachedReservationRowVersion(id: Int, context: ModelContext) -> String? {
        ReservationRepository(context: context).rowVersion(forRemoteID: id)
    }

    /// Removes a locally cached reservation after the server confirms it is gone (404),
    /// then marks affected scopes stale so the next read reflects server truth.
    private func removeLocalReservationAfterServerGone(
        id: Int,
        reservationDate: String?,
        context: ModelContext
    ) {
        let repository = ReservationRepository(context: context)
        try? repository.deleteReservation(remoteID: id)
        if let reservationDate {
            markScopesTouched(afterDeletingReservationDate: reservationDate)
        } else {
            let window = activeWindow()
            markScopeStale(.activeWindow(from: window.from, to: window.to))
        }
    }

    // MARK: - Notice Handling

    func clearErrorMessage() {
        errorMessage = nil
    }

    func clearNoticeMessage() {
        noticeMessage = nil
    }

    func clearImportFailureCountError() {
        importFailureCountError = nil
    }

    func dismissNotice(_ notice: AppNotice) {
        notices.removeAll { $0.id == notice.id }
    }

    func clearAllNotices() {
        notices.removeAll()
    }

    // MARK: - Developer Diagnostics

    // Intent: Developer/manager verifies backend reachability without mutating reservations.
    // Network: Uses read-only GET endpoints only.
    @discardableResult
    func runAdminFetchTest(_ test: AdminFetchTest, reservationID: Int? = nil) async -> AdminFetchTestResult {
        let startedAt = Date()

        do {
            let summary: String

            switch test {
            case .ping:
                let response = try await environment.apiClient.ping(reason: .ping)
                summary = response.message
            case .restaurantSetup:
                let setup = try await environment.apiClient.fetchRestaurantSetup(reason: .restaurantSetup)
                summary = "\(setup.businessName), slot interval \(setup.slotIntervalMinutes) min"
            case .restaurantHours:
                let hours = try await environment.apiClient.fetchRestaurantHours(
                    from: nil,
                    to: nil,
                    reason: .restaurantHours
                )
                summary = "\(hours.weeklyHours.count) weekly rows, \(hours.specialHours.count) special rows"
            case .restaurantDayAvailability:
                let availability = try await environment.apiClient.fetchRestaurantDayAvailability(
                    date: Date.reservationDateString(),
                    reason: .restaurantDayAvailability
                )
                summary = "\(availability.date) \(availability.isOpen ? "open" : "closed"), source \(availability.source)"
            case .reservationSlots:
                let slots = try await environment.apiClient.fetchReservationSlots(
                    date: Date.reservationDateString(),
                    reason: .reservationSlots
                )
                summary = "\(slots.slots.count) public slots, open=\(slots.isOpen)"
            case .reservationAnalyticsSummary:
                let analytics = try await environment.apiClient.fetchReservationAnalyticsSummary(
                    from: nil,
                    to: nil,
                    reason: .reservationAnalyticsSummary
                )
                summary = "\(analytics.summary?.reservationsCount ?? 0) reservations in summary"
            case .businessIntelligenceSummary:
                let window = scheduleWindow()
                let business = try await environment.apiClient.fetchBusinessIntelligenceSummary(
                    from: window.from,
                    to: window.to,
                    reason: .businessIntelligenceSummary
                )
                summary = "\(business.summary.totalReservations ?? 0) reservations in BI summary"
            case .guestIntelligence:
                let guestDay = try await environment.apiClient.fetchGuestIntelligence(
                    date: Date.reservationDateString(),
                    reason: .guestIntelligence
                )
                summary = "\(guestDay.items.count) guest intelligence items for \(guestDay.date)"
            case .intelligenceSystemStatus:
                let window = scheduleWindow()
                let status = try await environment.apiClient.fetchIntelligenceSystemStatus(
                    from: window.from,
                    to: window.to,
                    reason: .intelligenceSystemStatus
                )
                var parts = ["status=\(status.status)", "\(status.checks.count) checks"]
                if let msg = status.managerMessage { parts.append("mgr=\(msg.prefix(60))") }
                if let msg = status.developerMessage { parts.append("dev=\(msg.prefix(60))") }
                let ds = status.developerSummary
                if let v = ds.flamingoInboundTotal { parts.append("flamingo=\(v)") }
                if let v = ds.reservationIntakeTotal { parts.append("intake=\(v)") }
                if let v = ds.failedImports { parts.append("failed_imports=\(v)") }
                if let v = ds.duplicateImports { parts.append("dup_imports=\(v)") }
                if let v = ds.manualRowsWithoutFlamingoSource { parts.append("manual_no_src=\(v)") }
                if let v = ds.unexplainedMissing { parts.append("unexplained=\(v)") }
                if !status.warnings.isEmpty { parts.append("warnings=\(status.warnings.count)") }
                if !status.items.isEmpty { parts.append("items=\(status.items.count)") }
                summary = parts.joined(separator: " | ")
            case .startupToday:
                let response = try await environment.apiClient.fetchReservations(
                    page: 1,
                    perPage: 50,
                    date: Date.reservationDateString(),
                    from: nil,
                    to: nil,
                    status: nil,
                    search: nil,
                    includeHidden: false,
                    updatedSince: nil,
                    retryCount: 0,
                    reason: .startupToday
                )
                summary = "\(response.data.count) today rows, total \(response.total)"
            case .manualToday:
                let response = try await environment.apiClient.fetchReservations(
                    page: 1,
                    perPage: 50,
                    date: Date.reservationDateString(),
                    from: nil,
                    to: nil,
                    status: nil,
                    search: nil,
                    includeHidden: false,
                    updatedSince: nil,
                    retryCount: 1,
                    reason: .manualToday
                )
                summary = "\(response.data.count) today rows, total \(response.total)"
            case .failureCount:
                let response = try await environment.apiClient.fetchImportFailures(
                    page: 1,
                    perPage: 1,
                    reason: .failureCount
                )
                summary = "\(response.total) form problems"
            case .scheduleWindow:
                let window = scheduleWindow()
                let response = try await environment.apiClient.fetchReservations(
                    page: 1,
                    perPage: 100,
                    date: nil,
                    from: window.from,
                    to: window.to,
                    status: nil,
                    search: nil,
                    includeHidden: false,
                    updatedSince: nil,
                    retryCount: 1,
                    reason: .scheduleWindow
                )
                summary = "\(response.data.count) rows on first page, total \(response.total)"
            case .reviewQueues:
                let needsReview = try await environment.apiClient.fetchReservations(
                    page: 1,
                    perPage: 50,
                    date: nil,
                    from: nil,
                    to: nil,
                    status: .needsReview,
                    search: nil,
                    includeHidden: false,
                    updatedSince: nil,
                    retryCount: 0,
                    reason: .reviewQueues
                )
                let newRows = try await environment.apiClient.fetchReservations(
                    page: 1,
                    perPage: 50,
                    date: nil,
                    from: nil,
                    to: nil,
                    status: .new,
                    search: nil,
                    includeHidden: false,
                    updatedSince: nil,
                    retryCount: 0,
                    reason: .reviewQueues
                )
                summary = "\(needsReview.total) review, \(newRows.total) new"
            case .importFailuresFull:
                let response = try await environment.apiClient.fetchImportFailures(
                    page: 1,
                    perPage: 50,
                    reason: .importFailuresFull
                )
                summary = "\(response.data.count) rows, total \(response.total)"
            case .fetchByID:
                guard let reservationID else {
                    throw ReservationControllerError.missingReservationID
                }

                let reservation = try await environment.apiClient.fetchReservation(
                    id: reservationID,
                    retryCount: 0,
                    reason: .reconcileByID
                )
                summary = "#\(reservation.id) fetched"
            }

            let result = AdminFetchTestResult(
                test: test,
                succeeded: true,
                summary: summary,
                duration: Date().timeIntervalSince(startedAt)
            )
            postNotice(severity: .success, source: .admin, title: "\(test.title) passed", message: summary)
            return result
        } catch {
            let result = AdminFetchTestResult(
                test: test,
                succeeded: false,
                summary: error.localizedDescription,
                duration: Date().timeIntervalSince(startedAt)
            )
            postNotice(
                severity: .warning,
                source: .admin,
                title: "\(test.title) failed",
                message: error.localizedDescription,
                developerDiagnostics: error.reservationAPIDeveloperDetail
            )
            return result
        }
    }

    // MARK: - Private Sync Scope Helpers

    private func todayScope() -> ReservationSyncScope {
        .today(date: Date.reservationDateString())
    }

    private func activeWindow() -> (from: String, to: String) {
        Self.normalizedActiveWindow(
            bookingWindowDays: activeWindowBookingWindowDays(),
            referenceDate: Date()
        )
    }

    private func activeWindowBookingWindowDays() -> Int {
        if let persistedActiveWindowBounds {
            return max(persistedActiveWindowBounds.bookingWindowDays, 30)
        }
        return max(restaurantSetup.bookingWindowDays, 30)
    }

    private static func normalizedActiveWindow(
        bookingWindowDays: Int,
        referenceDate: Date
    ) -> (from: String, to: String) {
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
        let to = calendar.date(
            byAdding: .day,
            value: max(bookingWindowDays, 30),
            to: referenceDate
        ) ?? referenceDate
        return (from.reservationDateString(), to.reservationDateString())
    }

    private func activeWindowScope() -> ReservationSyncScope {
        let window = activeWindow()
        return .activeWindow(from: window.from, to: window.to)
    }

    private func scheduleWindow() -> (from: String, to: String) {
        // Date-keyed scope stays stable for a service day; it does not include
        // wall-clock time, so simple tab switching will hit freshness guards.
        let from = Date()
        let to = Calendar.current.date(byAdding: .day, value: 30, to: from) ?? from
        return (from.reservationDateString(), to.reservationDateString())
    }

    private func cancelledReservationsWindow() -> (from: String, to: String) {
        let now = Date()
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let to = calendar.date(byAdding: .day, value: 60, to: now) ?? now
        return (from.reservationDateString(), to.reservationDateString())
    }

    private func scheduleScope() -> ReservationSyncScope {
        let window = scheduleWindow()
        return .scheduleWindow(from: window.from, to: window.to)
    }

    private func serverCursor(for scope: ReservationSyncScope) -> String? {
        guard let cursor = serverCursorByScope[scope]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cursor.isEmpty else {
            return nil
        }
        return cursor
    }

    private func updateServerCursor(for scope: ReservationSyncScope, with serverTime: String?) {
        guard let serverTime = serverTime?.trimmingCharacters(in: .whitespacesAndNewlines),
              !serverTime.isEmpty else {
            return
        }
        serverCursorByScope[scope] = serverTime
        persistSyncMetadata()
        publishOperationState()
    }

    private func allowManualAttempt(for scope: ReservationSyncScope) -> Bool {
        let now = Date()
        if let lastAttempt = manualAttemptByScope[scope],
           now.timeIntervalSince(lastAttempt) < manualRefreshCooldown {
            return false
        }

        manualAttemptByScope[scope] = now
        return true
    }

    private func isScopeInFailureCooldown(_ scope: ReservationSyncScope) -> Bool {
        guard let cooldownUntil = syncStateByScope[scope]?.cooldownUntil else {
            return false
        }
        return cooldownUntil > Date()
    }

    private func isScopeFresh(_ scope: ReservationSyncScope, freshnessInterval: TimeInterval) -> Bool {
        guard let lastSuccessAt = syncStateByScope[scope]?.lastSuccessAt else {
            return false
        }

        return Date().timeIntervalSince(lastSuccessAt) < freshnessInterval
    }

    /// Maps the current active-window reservation scope to the shared coordinator scope.
    private func freshnessActiveWindowScope() -> FreshnessScope {
        let window = activeWindow()
        return .activeWindow(from: window.from, to: window.to)
    }

    /// Mirrors an active-window decision into the shared FreshnessCoordinator log so all
    /// surfaces read one [FRESHNESS_COORDINATOR] vocabulary. No-op when no coordinator
    /// is injected (e.g. unit tests / intro warmup).
    private func recordActiveWindowFreshness(_ decision: FreshnessDecision) {
        freshnessCoordinator?.record(scope: freshnessActiveWindowScope(), decision: decision)
    }

    private func beginScope(_ scope: ReservationSyncScope, intent: ReservationSyncIntent? = nil) -> Bool {
        var state = syncStateByScope[scope] ?? SyncScopeState()
        if state.isInFlight {
            return false
        }

        let now = Date()
        state.isInFlight = true
        state.lastAttemptAt = now
        syncStateByScope[scope] = state
        activeSyncIntentByScope[scope] = intent
        publishSyncScopeSnapshots()
        return true
    }

    private func markScopeSuccess(_ scope: ReservationSyncScope) {
        var state = syncStateByScope[scope] ?? SyncScopeState()
        let now = Date()
        state.isInFlight = false
        state.lastSuccessAt = now
        state.cooldownUntil = nil
        syncStateByScope[scope] = state
        activeSyncIntentByScope[scope] = nil
        persistSyncMetadata()
        publishSyncScopeSnapshots()
    }

    private func markScopeFailure(_ scope: ReservationSyncScope, cooldown: TimeInterval? = nil) {
        var state = syncStateByScope[scope] ?? SyncScopeState()
        let now = Date()
        state.isInFlight = false
        state.lastFailureAt = now
        state.cooldownUntil = cooldown.map { now.addingTimeInterval($0) }
        syncStateByScope[scope] = state
        activeSyncIntentByScope[scope] = nil
        publishSyncScopeSnapshots()
    }

    private func markScopeCancelled(_ scope: ReservationSyncScope) {
        var state = syncStateByScope[scope] ?? SyncScopeState()
        state.isInFlight = false
        syncStateByScope[scope] = state
        activeSyncIntentByScope[scope] = nil
        publishSyncScopeSnapshots()
    }

    private func markScopeStale(_ scope: ReservationSyncScope) {
        var state = syncStateByScope[scope] ?? SyncScopeState()
        state.lastSuccessAt = nil
        state.cooldownUntil = nil
        syncStateByScope[scope] = state
        publishSyncScopeSnapshots()
    }

    private func markScopeRecentlyTouched(_ scope: ReservationSyncScope) {
        var state = syncStateByScope[scope] ?? SyncScopeState()
        if !state.isInFlight {
            state.lastSuccessAt = Date()
            state.cooldownUntil = nil
        }
        syncStateByScope[scope] = state
        publishSyncScopeSnapshots()
    }

    private func markScopesTouched(after reservation: ReservationDTO) {
        invalidateAvailabilityCache(for: reservation.reservationDate)

        let today = Date.reservationDateString()
        if reservation.reservationDate == today {
            markScopeRecentlyTouched(.today(date: today))
        }

        let activeWindow = activeWindow()
        if reservation.reservationDate >= activeWindow.from && reservation.reservationDate <= activeWindow.to {
            markScopeRecentlyTouched(.activeWindow(from: activeWindow.from, to: activeWindow.to))
        }

        let window = scheduleWindow()
        if reservation.reservationDate >= window.from && reservation.reservationDate <= window.to {
            markScopeStale(.scheduleWindow(from: window.from, to: window.to))
        }

        markScopeStale(.reviewQueues)

        if reservation.isHidden == true {
            markScopeStale(.hiddenReservations)
        }
    }

    private func markScopesTouched(afterDeletingReservationDate reservationDate: String) {
        invalidateAvailabilityCache(for: reservationDate)

        if reservationDate == Date.reservationDateString() {
            markScopeStale(.today(date: reservationDate))
        }

        let activeWindow = activeWindow()
        if reservationDate >= activeWindow.from && reservationDate <= activeWindow.to {
            markScopeStale(.activeWindow(from: activeWindow.from, to: activeWindow.to))
        }

        let window = scheduleWindow()
        if reservationDate >= window.from && reservationDate <= window.to {
            markScopeStale(.scheduleWindow(from: window.from, to: window.to))
        }

        markScopeStale(.reviewQueues)
    }

    private func publishSyncScopeSnapshots() {
        syncScopeSnapshots = syncStateByScope
            .map { SyncScopeSnapshot(scope: $0.key, state: $0.value) }
            .sorted { $0.scope.description < $1.scope.description }
        publishOperationState()
    }

    private func publishOperationState() {
        operationState = ReservationOperationState(
            activeSyncIntents: activeSyncIntentByScope,
            isSyncing: isSyncing,
            isAutoRefreshing: isAutoRefreshing,
            mutatingReservationIDs: actionInProgressIDs,
            reconcilingReservationIDs: reconcilingReservationIDs,
            isCreatingReservation: isCreatingReservation,
            isCheckingImportFailureCount: isCheckingImportFailureCount,
            lastNetworkUnavailableAt: lastOfflineNoticeAt,
            serverCursors: serverCursorByScope,
            latestRefreshDecision: latestRefreshDecision
        )
        refreshStaffStatusDotStyle()
    }

    private var isStaffNetworkActivityInFlight: Bool {
        isStartupNetworkPassInFlight
            || operationState.isSyncing
            || operationState.isAutoRefreshing
            || !operationState.activeSyncIntents.isEmpty
            || operationState.isCreatingReservation
            || operationState.isCheckingImportFailureCount
            || operationState.hasUncertainMutationReconcileInProgress
    }

    func refreshHomeServicePresentation(
        hostOperationalLoading: Bool = false,
        now: Date = Date()
    ) {
        publishStartupBackgroundWorkState()
        let presentation = HomeServiceStatusPresenter.resolve(
            isNetworkDegraded: isNetworkDegraded,
            isReservationRefreshInFlight: isReservationNetworkRefreshInFlight,
            hasVisibleCache: localCacheStoreHasReservations || hasReleasedStartupUI,
            startupNetworkPassError: startupNetworkPassError,
            cacheTrustSource: cacheTrustSource,
            lastSyncedAt: lastSyncedAt,
            lastFreshnessCheckedAt: lastFreshnessCheckedAt,
            startupBackgroundWorkState: startupBackgroundWorkState,
            hostOperationalLoading: hostOperationalLoading,
            now: now
        )
        if homeServiceStatusPresentation != presentation {
            homeServiceStatusPresentation = presentation
            #if DEBUG
            StartupPolicyTrace.headerPresentation(presentation)
            StartupPolicyTrace.homeStatus(presentation)
            #endif
        }

        let resolved = TryzubStaffStatusResolver.resolve(
            isNetworkDegraded: isNetworkDegraded,
            isNetworkActivityInFlight: isStaffNetworkActivityInFlight,
            lastSyncedAt: lastSyncedAt,
            lastFreshnessCheckedAt: lastFreshnessCheckedAt,
            cacheTrustSource: cacheTrustSource,
            pendingReviewCount: pendingReviewAttentionCount,
            now: now
        )

        if staffStatusDotStyle != resolved {
            staffStatusDotStyle = resolved
        }

        scheduleStaffStatusBoundaryTask(now: now)
    }

    private func refreshStaffStatusDotStyle(now: Date = Date()) {
        refreshHomeServicePresentation(now: now)
    }

    private func publishStartupBackgroundWorkState() {
        let resolved: StartupBackgroundWorkState
        if !hasReleasedStartupUI {
            resolved = .checkingSavedData
        } else if isStartupNetworkPassInFlight || isBackgroundReservationFreshnessCheckInFlight {
            resolved = .checkingFreshness
        } else if isLoadingRestaurantSetup {
            resolved = .updatingServiceSetup
        } else if isLoadingHostTodayAvailabilityBundle() {
            resolved = .loadingTodayOperations
        } else {
            resolved = .ready
        }

        if startupBackgroundWorkState != resolved {
            startupBackgroundWorkState = resolved
        }
    }

    private func isLoadingHostTodayAvailabilityBundle() -> Bool {
        guard let dateKey = hostBoardSelectedDateKey else { return false }
        guard dateKey == Date.reservationDateString() else { return false }
        return isAvailabilitySummaryLoading(date: dateKey)
    }

    private func scheduleStaffStatusBoundaryTask(now: Date = Date()) {
        staffStatusBoundaryTask?.cancel()

        var nextWake: Date?

        if !isNetworkDegraded,
           !isStaffNetworkActivityInFlight,
           pendingReviewAttentionCount == 0 {
            let trustReference: Date? = switch cacheTrustSource {
            case .serverSync:
                lastSyncedAt ?? lastFreshnessCheckedAt
            case .freshnessCheck:
                lastFreshnessCheckedAt ?? lastSyncedAt
            case .unknown:
                lastFreshnessCheckedAt ?? lastSyncedAt
            }
            if let trustReference {
                let staleAt = trustReference.addingTimeInterval(TryzubStaffStatusResolver.staleSyncThreshold)
                if staleAt > now {
                    nextWake = staleAt
                }
            }
        }

        if let lastOffline = lastOfflineNoticeAt {
            let offlineClearAt = lastOffline.addingTimeInterval(offlineNoticeCooldown)
            if offlineClearAt > now {
                nextWake = min(nextWake ?? offlineClearAt, offlineClearAt)
            }
        }

        guard let wake = nextWake else { return }

        let delay = wake.timeIntervalSince(now)
        guard delay > 0.05 else {
            refreshStaffStatusDotStyle()
            return
        }

        staffStatusBoundaryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.refreshStaffStatusDotStyle()
            }
        }
    }

    private func recordRefreshDecision(
        scope: ReservationSyncScope,
        mode: ReservationRefreshMode,
        outcome: String
    ) {
        latestRefreshDecision = ReservationRefreshDecision(
            scope: scope,
            intent: mode.syncIntent,
            outcome: outcome,
            cursor: serverCursor(for: scope),
            createdAt: Date()
        )
        publishOperationState()
    }

    // MARK: - Private Notice / Error Helpers

    private func postRefreshFailureNotice(mode: ReservationRefreshMode, error: Error) {
        if error.isOfflineLike {
            postOfflineNotice(source: mode.noticeSource, requestReason: mode.requestReason, error: error)
            return
        }

        postNotice(
            severity: mode.noticeSeverity,
            source: mode.noticeSource,
            title: mode.failureTitle,
            message: mode.failureMessage,
            requestReason: mode.requestReason,
            errorCode: errorLogCode(error),
            developerDiagnostics: error.reservationAPIDeveloperDetail
        )
    }

    private func postOfflineNotice(
        source: AppNoticeSource,
        requestReason: ReservationAPIRequestReason?,
        error: Error
    ) {
        let now = Date()
        if let lastOfflineNoticeAt,
           now.timeIntervalSince(lastOfflineNoticeAt) < offlineNoticeCooldown {
            return
        }

        lastOfflineNoticeAt = now
        publishOperationState()
        notices.removeAll {
            $0.title == "Offline — showing saved reservations."
        }
        postNotice(
            severity: .warning,
            source: source,
            title: "Offline — showing saved reservations.",
            message: "You can keep viewing saved reservations. Saving changes needs internet.",
            requestReason: requestReason,
            errorCode: errorLogCode(error),
            developerDiagnostics: error.reservationAPIDeveloperDetail
        )
    }

    private func ensureMutationsAllowedOnline() throws {
        guard !isNetworkDegraded else {
            postMutationBlockedOfflineNotice()
            throw ReservationControllerError.networkUnavailable
        }
    }

    private func canStartMutationOnline() -> Bool {
        guard !isNetworkDegraded else {
            postMutationBlockedOfflineNotice()
            return false
        }
        return true
    }

    func seatedElapsedMinutes(for reservation: ReservationRecord, now: Date = Date()) -> Int? {
        guard let seatedAt = seatedAt(for: reservation) else {
            return nil
        }

        return max(0, Int(now.timeIntervalSince(seatedAt))) / 60
    }

    func seatedDurationDotStyle(for reservation: ReservationRecord, now: Date = Date()) -> TryzubStaffStatusDotStyle? {
        guard let minutes = seatedElapsedMinutes(for: reservation, now: now) else {
            return nil
        }
        return TryzubSeatedDurationResolver.dotStyle(elapsedMinutes: minutes)
    }

    func seatedDurationText(for reservation: ReservationRecord, now: Date = Date()) -> String? {
        guard let seatedAt = seatedAt(for: reservation) else {
            return nil
        }

        let elapsed = max(0, Int(now.timeIntervalSince(seatedAt)))
        let minutes = elapsed / 60
        if minutes < 1 {
            return "Seated just now"
        }
        if minutes < 60 {
            return "Seated \(minutes)m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return String(format: "Seated %dh %02dm", hours, remainingMinutes)
    }

    private func seatedAt(for reservation: ReservationRecord) -> Date? {
        guard reservation.statusValue == .seated else {
            return nil
        }

        return localSeatedAtByReservationID[reservation.remoteID] ?? seatedTimestampFallback(for: reservation)
    }

    private func seatedTimestampFallback(for reservation: ReservationRecord) -> Date? {
        guard let value = reservation.apiUpdatedAt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return ReservationFormatters.serverDateTime.date(from: value)
            ?? ReservationFormatters.serverDateMinute.date(from: value)
    }

    private func applyOptimisticStatusUpdate(
        reservation: ReservationRecord,
        status: ReservationStatus,
        context: ModelContext
    ) {
        reservation.status = status.rawValue
        if status == .seated {
            localSeatedAtByReservationID[reservation.remoteID] = Date()
            persistLocalSeatedTimestamps()
        } else if localSeatedAtByReservationID[reservation.remoteID] != nil {
            localSeatedAtByReservationID[reservation.remoteID] = nil
            persistLocalSeatedTimestamps()
        }
        try? context.save()
    }

    private func revertOptimisticStatusUpdate(
        reservation: ReservationRecord,
        previousStatus: String,
        previousSeatedAt: Date?,
        context: ModelContext
    ) {
        reservation.status = previousStatus
        if let previousSeatedAt {
            localSeatedAtByReservationID[reservation.remoteID] = previousSeatedAt
        } else {
            localSeatedAtByReservationID[reservation.remoteID] = nil
        }
        persistLocalSeatedTimestamps()
        try? context.save()
    }

    private func updateLocalSeatedTimestamp(after reservation: ReservationDTO) {
        if reservation.status == .seated {
            if localSeatedAtByReservationID[reservation.id] == nil {
                localSeatedAtByReservationID[reservation.id] = Date()
                persistLocalSeatedTimestamps()
            }
        } else if localSeatedAtByReservationID[reservation.id] != nil {
            localSeatedAtByReservationID[reservation.id] = nil
            persistLocalSeatedTimestamps()
        }
    }

    private func persistLocalSeatedTimestamps() {
        let raw = Dictionary(
            uniqueKeysWithValues: localSeatedAtByReservationID.map { (String($0.key), $0.value.timeIntervalSince1970) }
        )
        UserDefaults.standard.set(raw, forKey: localSeatedTimestampsKey)
    }

    private static func loadLocalSeatedTimestamps() -> [Int: Date] {
        guard let raw = UserDefaults.standard.dictionary(forKey: "tryzub.localSeatedTimestamps") as? [String: TimeInterval] else {
            return [:]
        }
        return raw.reduce(into: [Int: Date]()) { result, pair in
            guard let id = Int(pair.key), pair.value.isFinite else { return }
            result[id] = Date(timeIntervalSince1970: pair.value)
        }
    }

    private func postMutationBlockedOfflineNotice() {
        postNotice(
            severity: .warning,
            source: .mutation,
            title: "Offline — showing saved reservations.",
            message: "Edits require internet. Try again when the connection returns."
        )
    }

    private func postMutationFailureNotice(title: String, message: String) {
        errorMessage = message
        postNotice(
            severity: .error,
            source: .mutation,
            title: title,
            message: message
        )
    }

    private func postNotice(
        severity: AppNoticeSeverity,
        source: AppNoticeSource,
        title: String,
        message: String? = nil,
        requestReason: ReservationAPIRequestReason? = nil,
        errorCode: String? = nil,
        developerDiagnostics: String? = nil
    ) {
        let notice = AppNotice(
            severity: severity,
            source: source,
            title: title,
            message: message,
            requestReason: requestReason,
            errorCode: errorCode,
            developerDiagnostics: capabilities.canViewDeveloperDiagnostics ? developerDiagnostics : nil
        )
        notices.insert(notice, at: 0)
        if notices.count > 20 {
            notices.removeLast(notices.count - 20)
        }
    }

    private func clearScopedMessages(for source: AppNoticeSource) {
        errorMessage = nil
        noticeMessage = nil
        notices.removeAll { $0.source == source && $0.severity != .error }
    }

    private func errorLogCode(_ error: Error) -> String? {
        if let apiError = error as? ReservationAPIError {
            return apiError.logValue
        }
        if let urlError = error as? URLError {
            return "\(urlError.errorCode)"
        }
        return nil
    }
}

#if DEBUG
extension ReservationsController {
    static func preview(environment: AppEnvironment) -> ReservationsController {
        ReservationsController(environment: environment, traceSource: "preview")
    }
}
#endif

// MARK: - Controller Support Types

private enum ReservationControllerError: LocalizedError {
    case actionAlreadyInProgress
    case permissionDenied
    case missingReservationID
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .actionAlreadyInProgress:
            return "Another update is already in progress for this reservation."
        case .permissionDenied:
            return "This account cannot use this admin tool."
        case .missingReservationID:
            return "Enter a reservation ID first."
        case .networkUnavailable:
            return "Could not save. Check the connection and try again."
        }
    }
}

struct ReservationOperationState: Equatable {
    var activeSyncIntents: [ReservationSyncScope: ReservationSyncIntent] = [:]
    var isSyncing = false
    var isAutoRefreshing = false
    var mutatingReservationIDs: Set<Int> = []
    var reconcilingReservationIDs: Set<Int> = []
    var isCreatingReservation = false
    var isCheckingImportFailureCount = false
    var lastNetworkUnavailableAt: Date?
    var serverCursors: [ReservationSyncScope: String] = [:]
    var latestRefreshDecision: ReservationRefreshDecision?

    var isStartupSyncing: Bool {
        activeSyncIntents.values.contains(.startup)
    }

    var isManualRefreshInProgress: Bool {
        activeSyncIntents.values.contains(.manual)
    }

    var isQuietAutoRefreshInProgress: Bool {
        isAutoRefreshing || activeSyncIntents.values.contains(.automatic)
    }

    var hasReservationMutationInProgress: Bool {
        !mutatingReservationIDs.isEmpty || isCreatingReservation
    }

    var hasUncertainMutationReconcileInProgress: Bool {
        !reconcilingReservationIDs.isEmpty
    }
}

struct ReservationRefreshDecision: Equatable {
    let scope: ReservationSyncScope
    let intent: ReservationSyncIntent
    let outcome: String
    let cursor: String?
    let createdAt: Date
}

struct ReservationAvailabilitySummary {
    let availability: RestaurantDayAvailabilityDTO
    let slots: ReservationSlotsResponseDTO
    let blockedSlots: [RestaurantBlockedSlotDTO]
    let loadedAt: Date
}

enum ReservationSyncIntent: Equatable {
    case startup
    case manual
    case automatic
    case screenActive
    case mutationReconcile
    case diagnostics
}

struct PersistedActiveWindowBounds: Codable, Equatable {
    let from: String
    let to: String
    let bookingWindowDays: Int
}

enum ReservationSyncScope: Hashable, CustomStringConvertible {
    case today(date: String)
    case activeWindow(from: String, to: String)
    case scheduleWindow(from: String, to: String)
    case cancelledWindow(from: String, to: String)
    case hiddenReservations
    case reviewQueues
    case importFailureCount
    case reservation(id: Int)

    var description: String {
        switch self {
        case .today(let date):
            return "today(\(date))"
        case .activeWindow(let from, let to):
            return "active_window(\(from)...\(to))"
        case .scheduleWindow(let from, let to):
            return "schedule(\(from)...\(to))"
        case .cancelledWindow(let from, let to):
            return "cancelled(\(from)...\(to))"
        case .hiddenReservations:
            return "hidden_reservations"
        case .reviewQueues:
            return "review_queues"
        case .importFailureCount:
            return "failure_count"
        case .reservation(let id):
            return "reservation(\(id))"
        }
    }

    /// Stable UserDefaults key for cursor/freshness metadata. Matches `description` format.
    var persistenceKey: String { description }

    init?(persistenceKey: String) {
        switch persistenceKey {
        case "hidden_reservations":
            self = .hiddenReservations
            return
        case "review_queues":
            self = .reviewQueues
            return
        case "failure_count":
            self = .importFailureCount
            return
        default:
            break
        }

        if persistenceKey.hasPrefix("today("), persistenceKey.hasSuffix(")") {
            let date = String(persistenceKey.dropFirst(6).dropLast())
            self = .today(date: date)
            return
        }

        if persistenceKey.hasPrefix("active_window("), persistenceKey.hasSuffix(")") {
            let inner = persistenceKey.dropFirst("active_window(".count).dropLast()
            guard let range = inner.range(of: "...") else { return nil }
            let from = String(inner[..<range.lowerBound])
            let to = String(inner[range.upperBound...])
            self = .activeWindow(from: from, to: to)
            return
        }

        if persistenceKey.hasPrefix("schedule("), persistenceKey.hasSuffix(")") {
            let inner = persistenceKey.dropFirst("schedule(".count).dropLast()
            guard let range = inner.range(of: "...") else { return nil }
            let from = String(inner[..<range.lowerBound])
            let to = String(inner[range.upperBound...])
            self = .scheduleWindow(from: from, to: to)
            return
        }

        if persistenceKey.hasPrefix("cancelled("), persistenceKey.hasSuffix(")") {
            let inner = persistenceKey.dropFirst("cancelled(".count).dropLast()
            guard let range = inner.range(of: "...") else { return nil }
            let from = String(inner[..<range.lowerBound])
            let to = String(inner[range.upperBound...])
            self = .cancelledWindow(from: from, to: to)
            return
        }

        if persistenceKey.hasPrefix("reservation("), persistenceKey.hasSuffix(")") {
            let idString = String(persistenceKey.dropFirst(12).dropLast())
            guard let id = Int(idString) else { return nil }
            self = .reservation(id: id)
            return
        }

        return nil
    }
}

struct SyncScopeState {
    var lastAttemptAt: Date?
    var lastSuccessAt: Date?
    var lastFailureAt: Date?
    var isInFlight = false
    var cooldownUntil: Date?
}

struct SyncScopeSnapshot: Identifiable, Equatable {
    let scope: ReservationSyncScope
    let lastAttemptAt: Date?
    let lastSuccessAt: Date?
    let lastFailureAt: Date?
    let isInFlight: Bool
    let cooldownUntil: Date?

    var id: String { scope.description }

    init(scope: ReservationSyncScope, state: SyncScopeState) {
        self.scope = scope
        self.lastAttemptAt = state.lastAttemptAt
        self.lastSuccessAt = state.lastSuccessAt
        self.lastFailureAt = state.lastFailureAt
        self.isInFlight = state.isInFlight
        self.cooldownUntil = state.cooldownUntil
    }
}

private enum ReservationRefreshMode {
    case startup
    case manual
    case automatic
    case schedule
    case review

    var failureTitle: String {
        switch self {
        case .startup:
            return "Showing saved data"
        case .manual:
            return "Could not refresh"
        case .automatic:
            return "Could not refresh automatically"
        case .schedule:
            return "Could not refresh schedule"
        case .review:
            return "Could not refresh new bookings"
        }
    }

    var failureMessage: String {
        switch self {
        case .startup:
            return "Offline. Showing saved data."
        case .manual:
            return "Could not refresh. Showing saved data."
        case .automatic:
            return "The app will try again later."
        case .schedule:
            return "Could not refresh the schedule. You can keep viewing saved reservations."
        case .review:
            return "Could not refresh new bookings. You can keep viewing saved reservations."
        }
    }

    var noticeSource: AppNoticeSource {
        switch self {
        case .startup:
            return .startup
        case .manual:
            return .manualToday
        case .automatic:
            return .autoToday
        case .schedule:
            return .schedule
        case .review:
            return .review
        }
    }

    var noticeSeverity: AppNoticeSeverity {
        switch self {
        case .automatic, .startup, .manual, .schedule, .review:
            return .warning
        }
    }

    var requestReason: ReservationAPIRequestReason {
        switch self {
        case .startup:
            return .startupToday
        case .manual:
            return .manualToday
        case .automatic:
            return .autoToday
        case .schedule:
            return .scheduleWindow
        case .review:
            return .reviewQueues
        }
    }

    var activeWindowRequestReason: ReservationAPIRequestReason {
        switch self {
        case .startup, .manual, .schedule, .review:
            return .activeWindow
        case .automatic:
            return .activeWindowDelta
        }
    }

    var syncIntent: ReservationSyncIntent {
        switch self {
        case .startup:
            return .startup
        case .manual:
            return .manual
        case .automatic:
            return .automatic
        case .schedule, .review:
            return .screenActive
        }
    }
}

enum AdminFetchTest: String, CaseIterable, Identifiable {
    case ping
    case restaurantSetup
    case restaurantHours
    case restaurantDayAvailability
    case reservationSlots
    case reservationAnalyticsSummary
    case businessIntelligenceSummary
    case guestIntelligence
    case intelligenceSystemStatus
    case startupToday
    case manualToday
    case failureCount
    case scheduleWindow
    case reviewQueues
    case importFailuresFull
    case fetchByID

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ping:
            return "Test ping"
        case .restaurantSetup:
            return "Test restaurant_setup"
        case .restaurantHours:
            return "Test restaurant_hours"
        case .restaurantDayAvailability:
            return "Test restaurant_day_availability"
        case .reservationSlots:
            return "Test reservation_slots"
        case .reservationAnalyticsSummary:
            return "Test reservation_analytics_summary"
        case .businessIntelligenceSummary:
            return "Test business_intelligence_summary"
        case .guestIntelligence:
            return "Test guest_intelligence"
        case .intelligenceSystemStatus:
            return "Test intelligence_system_status"
        case .startupToday:
            return "Test startup_today"
        case .manualToday:
            return "Test manual_today"
        case .failureCount:
            return "Test failure_count"
        case .scheduleWindow:
            return "Test schedule_window"
        case .reviewQueues:
            return "Test review_queues"
        case .importFailuresFull:
            return "Test import_failures_full"
        case .fetchByID:
            return "Test fetch by ID"
        }
    }
}

struct AdminFetchTestResult: Identifiable, Equatable {
    let id = UUID()
    let test: AdminFetchTest
    let succeeded: Bool
    let summary: String
    let duration: TimeInterval

    var durationText: String {
        String(format: "%.2fs", duration)
    }
}
