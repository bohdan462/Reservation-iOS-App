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
        didSet { refreshStaffStatusDotStyle() }
    }

    // Staff-facing live/sync indicator for Home and Bookings headers.
    @Published private(set) var staffStatusDotStyle: TryzubStaffStatusDotStyle = .yellowStatic

    // Short staff-facing notices for refreshes, mutations, and diagnostics.
    @Published private(set) var notices: [AppNotice] = []
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published var importFailureCount: Int = 0
    @Published var importFailureCountError: String?
    @Published private(set) var restaurantSetup: RestaurantSetup = .default
    @Published private(set) var isLoadingRestaurantSetup = false
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
    @Published private(set) var availabilitySummaryLoadingDates: Set<String> = []
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
    private var lastOfflineNoticeAt: Date?
    private var pendingReviewAttentionCount = 0
    private var staffStatusBoundaryTask: Task<Void, Never>?
    private let networkPathMonitor = NetworkPathMonitor()
    @Published private(set) var isNetworkPathSatisfied = true

    // MARK: - Refresh Timing

    private let autoRefreshInterval: TimeInterval = 60
    private let autoRefreshFailureCooldown: TimeInterval = 180
    private let manualRefreshCooldown: TimeInterval = 8
    private let scheduleFreshnessInterval: TimeInterval = 300
    private let reviewFreshnessInterval: TimeInterval = 120
    private let importFailureCountFreshnessInterval: TimeInterval = 300
    private let offlineNoticeCooldown: TimeInterval = 60
    private let availabilitySummaryFreshnessInterval: TimeInterval = 180
    private let restaurantSetupFreshnessInterval: TimeInterval = 300
    private let dateOperationsFreshnessInterval: TimeInterval = 180

    // MARK: - Dependencies

    let environment: AppEnvironment

    var capabilities: AppCapabilities {
        environment.capabilities
    }

    var hasActiveMutation: Bool {
        !actionInProgressIDs.isEmpty || isCreatingReservation
    }

    private var hasActiveReservationRefresh: Bool {
        isSyncing || isAutoRefreshing
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

    private var hasAttemptedInitialLoad = false
    private let localSeatedTimestampsKey = "tryzub.localSeatedTimestamps"

    // MARK: - Initialization

    init(environment: AppEnvironment) {
        self.environment = environment
        self.localSeatedAtByReservationID = Self.loadLocalSeatedTimestamps()
        networkPathMonitor.start { [weak self] isSatisfied in
            self?.applyNetworkPathStatus(isSatisfied)
        }
    }

    deinit {
        networkPathMonitor.stop()
    }

    func prepareForLogout() {
        cancelOwnedTasksForSessionEnd()
        notices.removeAll()
        errorMessage = nil
        noticeMessage = nil
        hasAttemptedInitialLoad = false
        startupPresentationState = .checkingCache
        startupNetworkPassError = nil
        localCacheStoreHasReservations = false
        hasReleasedStartupUI = false
    }

    func releaseStartupUI() {
        hasReleasedStartupUI = true
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
        staffStatusBoundaryTask?.cancel()
        staffStatusBoundaryTask = nil
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
        guard !hasAttemptedInitialLoad else { return true }
        hasAttemptedInitialLoad = true

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

        return await performActiveWindowRefresh(context: context, mode: .startup, force: true)
    }

    // Intent: Cache-first entrance. Shows tabs immediately when SwiftData has reservations.
    func beginStartupPresentation(context: ModelContext) async {
        if case .failedNoCache = startupPresentationState {
            hasAttemptedInitialLoad = false
        }

        startupPresentationState = .checkingCache
        startupNetworkPassError = nil

        await hydrateCacheMetadata(context: context)
        let hasCache = Self.hasUsableCachedReservations(in: context)

        if hasCache {
            localCacheStoreHasReservations = true
            hasReleasedStartupUI = true
            startupPresentationState = .showingCachedDataRefreshing
            Task { @MainActor in
                _ = await self.performStartupNetworkPass(context: context)
            }
            return
        }

        startupPresentationState = .emptyCacheLoadingNetwork
        let refreshSucceeded = await performStartupNetworkPass(context: context)

        if Self.hasUsableCachedReservations(in: context) {
            startupPresentationState = .ready
            return
        }

        if refreshSucceeded {
            startupPresentationState = .ready
            return
        }

        startupPresentationState = .failedNoCache(
            startupNetworkPassError ?? "Could not load reservations. Check your connection and try again."
        )
    }

    // Intent: Runs the cold-start sync pass without blocking the launch splash.
    // Network: GET active window, then GET restaurant-setup (serialized by the API client).
    @discardableResult
    func performStartupNetworkPass(context: ModelContext) async -> Bool {
        guard !isStartupNetworkPassInFlight else { return false }
        isStartupNetworkPassInFlight = true
        defer {
            isStartupNetworkPassInFlight = false
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

        _ = try? await loadRestaurantSetup(context: context)
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

    func noteStartupWindowQueryDelivered(rowCount: Int) {
        guard startupPresentationState == .loadingSavedReservations else { return }
        guard rowCount > 0 else { return }
        releaseStartupUI()
    }

    private func hydrateCacheMetadata(context: ModelContext) async {
        do {
            let repository = ReservationRepository(context: context)
            if let latestLocalSyncDate = try repository.latestLocalSyncDate() {
                lastSyncedAt = latestLocalSyncDate
            }
        } catch {
            // Cache metadata is optional for presentation; startup refresh may still proceed.
        }
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
        lastSyncedAt = Date()
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
        lastSyncedAt = Date()
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
        isAppActive: Bool
    ) async {
        guard isAppActive else {
            ReservationAPILogger.skip(reason: .autoSkipInactive, message: "app is not active")
            return
        }

        guard !isInteractionActive else {
            ReservationAPILogger.skip(reason: .autoSkipBusy, message: "host interaction is active")
            return
        }

        guard !hasActiveReservationRefresh,
              !hasActiveMutation,
              !isCheckingImportFailureCount else {
            ReservationAPILogger.skip(reason: .autoSkipBusy, message: "controller is busy")
            return
        }

        let scope = activeWindowScope()
        let now = Date()

        if let lastAttempt = lastAutoRefreshAttemptAt,
           now.timeIntervalSince(lastAttempt) < autoRefreshInterval {
            ReservationAPILogger.skip(reason: .autoSkipBusy, message: "auto-refresh interval has not passed")
            return
        }

        if let lastFailure = lastAutoRefreshFailureAt,
           now.timeIntervalSince(lastFailure) < autoRefreshFailureCooldown {
            ReservationAPILogger.skip(reason: .autoSkipCooldown, message: "auto-refresh failure cooldown active")
            return
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
        force: Bool
    ) async -> Bool {
        let window = activeWindow()
        let scope = ReservationSyncScope.activeWindow(from: window.from, to: window.to)

        if !force,
           mode != .automatic,
           isScopeFresh(scope, freshnessInterval: mode == .review ? reviewFreshnessInterval : scheduleFreshnessInterval) {
            recordRefreshDecision(scope: scope, mode: mode, outcome: "skipped_fresh")
            ReservationAPILogger.skip(reason: .scopeSkipFresh, message: "\(scope.description) skipped because cache is fresh")
            return true
        }

        guard !hasActiveReservationRefresh else {
            recordRefreshDecision(scope: scope, mode: mode, outcome: "skipped_busy")
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "\(scope.description) skipped because another reservation refresh is active")
            return mode == .automatic
        }

        guard beginScope(scope, intent: mode.syncIntent) else {
            recordRefreshDecision(scope: scope, mode: mode, outcome: "skipped_in_flight")
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "\(scope.description) skipped because this scope is already in flight")
            return mode == .automatic
        }

        let showsGlobalProgress = force || mode == .startup || mode == .manual
        if mode == .automatic {
            isAutoRefreshing = true
        } else if showsGlobalProgress {
            isSyncing = true
        }
        clearScopedMessages(for: mode.noticeSource)

        do {
            let repository = ReservationRepository(context: context)
            let service = ReservationSyncService(client: environment.apiClient, repository: repository)
            let result: ReservationSyncResult
            if mode == .automatic, let cursor = serverCursor(for: scope) {
                recordRefreshDecision(scope: scope, mode: mode, outcome: "delta")
                result = try await service.syncActiveWindowChanges(
                    from: window.from,
                    to: window.to,
                    since: cursor,
                    reason: .activeWindowDelta
                )
            } else {
                recordRefreshDecision(scope: scope, mode: mode, outcome: "full")
                result = try await service.syncActiveWindowFull(
                    from: window.from,
                    to: window.to,
                    reason: mode.activeWindowRequestReason
                )
            }
            updateServerCursor(for: scope, with: result.serverTime)
            lastSyncedAt = Date()
            markScopeSuccess(scope)
        } catch {
            if error.isCancellationLike {
                markScopeCancelled(scope)
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
            lastSyncedAt = Date()
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
            lastSyncedAt = Date()
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
            lastSyncedAt = Date()
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

    func ensureAvailabilitySummary(date: String, force: Bool = false) {
        if !force,
           let summary = availabilitySummaryByDate[date],
           Date().timeIntervalSince(summary.loadedAt) < availabilitySummaryFreshnessInterval {
            ReservationAPILogger.skip(reason: .scopeSkipFresh, message: "availability_summary(\(date)) skipped because cache is fresh")
            return
        }

        if availabilitySummaryTasksByDate[date] != nil {
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "availability_summary(\(date)) skipped because request is already in flight")
            return
        }

        availabilitySummaryLoadingDates.insert(date)
        availabilitySummaryErrorsByDate[date] = nil
        let task = Task { [weak self] in
            guard let self else { return }
            await self.loadAvailabilitySummary(date: date)
        }
        availabilitySummaryTasksByDate[date] = task
    }

    func cancelAvailabilitySummary(date: String) {
        guard let task = availabilitySummaryTasksByDate[date] else { return }
        task.cancel()
        ReservationAPILogger.skip(
            reason: .scopeSkipInFlight,
            message: "availability_summary(\(date)) cancelled because Home is no longer active"
        )
    }

    private func loadAvailabilitySummary(date: String) async {
        defer {
            availabilitySummaryLoadingDates.remove(date)
            availabilitySummaryTasksByDate[date] = nil
        }

        do {
            // Serialize availability reads so they do not race the active-window sync.
            let loadedAvailability = try await loadRestaurantDayAvailability(date: date)
            let loadedSlots = try await loadReservationSlots(date: date)
            let loadedBlocked = try await loadRestaurantBlockedSlots(date: date)
            availabilitySummaryByDate[date] = ReservationAvailabilitySummary(
                availability: loadedAvailability,
                slots: loadedSlots,
                blockedSlots: loadedBlocked.data,
                loadedAt: Date()
            )
            availabilitySummaryErrorsByDate[date] = nil
        } catch {
            if error.isCancellationLike {
                return
            }
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
        context: ModelContext
    ) async throws -> ReservationDTO {
        try ensureMutationsAllowedOnline()

        guard !actionInProgressIDs.contains(id) else {
            throw ReservationControllerError.actionAlreadyInProgress
        }

        actionInProgressIDs.insert(id)
        defer { actionInProgressIDs.remove(id) }

        let repository = ReservationRepository(context: context)
        let service = ReservationMutationService(client: environment.apiClient, repository: repository)

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
        do {
            let updated = try await updateReservation(
                id: reservation.remoteID,
                request: ReservationUpdateRequest(status: status),
                context: context
            )
            updateLocalSeatedTimestamp(after: updated)
        } catch {
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
            if error.isOfflineLike {
                postOfflineNotice(source: .admin, requestReason: .hardDelete, error: error)
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
            let hiddenReservation = try await service.updateReservation(
                id: id,
                request: ReservationUpdateRequest(isHidden: true, hiddenReason: hiddenReason)
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
            if error.isOfflineLike {
                postOfflineNotice(source: .mutation, requestReason: .mutationPatch, error: error)
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
            let restoredReservation = try await service.updateReservation(
                id: id,
                request: ReservationUpdateRequest(isHidden: false)
            )
            markScopesTouched(after: restoredReservation)
            postNotice(severity: .success, source: .mutation, title: "Reservation restored")
            return restoredReservation
        } catch {
            if error.isOfflineLike {
                postOfflineNotice(source: .mutation, requestReason: .mutationPatch, error: error)
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
        let now = Date()
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let bookingWindowDays = max(restaurantSetup.bookingWindowDays, 30)
        let to = calendar.date(byAdding: .day, value: bookingWindowDays, to: now) ?? now
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

    private func refreshStaffStatusDotStyle(now: Date = Date()) {
        let resolved = TryzubStaffStatusResolver.resolve(
            isNetworkDegraded: isNetworkDegraded,
            isNetworkActivityInFlight: isStaffNetworkActivityInFlight,
            lastSyncedAt: lastSyncedAt,
            pendingReviewCount: pendingReviewAttentionCount,
            now: now
        )

        if staffStatusDotStyle != resolved {
            staffStatusDotStyle = resolved
        }

        scheduleStaffStatusBoundaryTask(now: now)
    }

    private func scheduleStaffStatusBoundaryTask(now: Date = Date()) {
        staffStatusBoundaryTask?.cancel()

        var nextWake: Date?

        if !isNetworkDegraded,
           !isStaffNetworkActivityInFlight,
           pendingReviewAttentionCount == 0,
           let lastSyncedAt {
            let staleAt = lastSyncedAt.addingTimeInterval(TryzubStaffStatusResolver.staleSyncThreshold)
            if staleAt > now {
                nextWake = staleAt
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
            message: "Cached reservations remain visible. Edits require internet.",
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
            return "Edits require internet. Showing saved reservations."
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
            return "Refresh failed"
        case .automatic:
            return "Auto refresh failed"
        case .schedule:
            return "Schedule refresh failed"
        case .review:
            return "Review refresh failed"
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
            return "Could not refresh the schedule. Cached reservations remain visible."
        case .review:
            return "Could not refresh review queues. Cached reservations remain visible."
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
