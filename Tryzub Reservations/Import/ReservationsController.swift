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
    @Published private(set) var lastSyncedAt: Date?

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

    // MARK: - Sync State

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

    // MARK: - Refresh Timing

    private let autoRefreshInterval: TimeInterval = 60
    private let autoRefreshFailureCooldown: TimeInterval = 180
    private let manualRefreshCooldown: TimeInterval = 8
    private let scheduleFreshnessInterval: TimeInterval = 300
    private let reviewFreshnessInterval: TimeInterval = 120
    private let importFailureCountFreshnessInterval: TimeInterval = 300
    private let offlineNoticeCooldown: TimeInterval = 60
    private let availabilitySummaryFreshnessInterval: TimeInterval = 180

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

    private var hasAttemptedInitialLoad = false

    // MARK: - Initialization

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    // MARK: - App / Screen Lifecycle

    // Intent: App starts with cached reservations visible, then refreshes today's cache.
    // Called by: ReservationsListView root task.
    // Network: GET /managed-reservations?date=today when refresh proceeds.
    func loadIfNeeded(context: ModelContext) async {
        guard !hasAttemptedInitialLoad else { return }
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

        await performActiveWindowRefresh(context: context, mode: .startup, force: true)
    }

    // MARK: - Legacy Refresh Entry Points

    // Intent: Refreshes the schedule window cache, not every historical reservation.
    // Rename note: A later cleanup should call this refreshScheduleWindowCache.
    func refreshScheduleWindowCache(context: ModelContext) async {
        await requestScheduleRefresh(context: context, source: .manual)
    }

    // MARK: - Today Sync

    // Intent: Staff manually refreshes today's reservation cache.
    // Called by: Today pull-to-refresh and toolbar refresh.
    // Network: GET /managed-reservations?date=today.
    @discardableResult
    func refreshDashboard(context: ModelContext) async -> Bool {
        await requestManualTodayRefresh(context: context, source: .manual)
    }

    // Intent: Runs staff-requested today refresh with busy/cooldown guards.
    // Writes: SwiftData through ReservationSyncService.
    // Network: GET /managed-reservations?date=today.
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
        isAllScope: Bool
    ) async throws -> ReservationsResponse {
        guard isAllScope else {
            ReservationAPILogger.skip(
                reason: .scheduleAllBlocked,
                message: "schedule_all_page blocked because Schedule scope is not All"
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

        let repository = ReservationRepository(context: context)
        try repository.upsert(response.data)
        lastSyncedAt = Date()
        return response
    }

    // MARK: - Pending Review Sync

    // Intent: Pending/Review screen became visible; refresh only when cached queue is stale.
    // Network: GET /managed-reservations?status=new and status=needs_review.
    func reviewBecameActive(context: ModelContext) async {
        let scope = activeWindowScope()
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
        let window = cancelledReservationsWindow()
        let scope = ReservationSyncScope.cancelledWindow(from: window.from, to: window.to)

        if !force && isScopeFresh(scope, freshnessInterval: scheduleFreshnessInterval) {
            return []
        }

        guard beginScope(scope, intent: force ? .manual : .screenActive) else {
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "\(scope.description) skipped because this scope is already in flight")
            return []
        }

        do {
            let rows = try await environment.apiClient.fetchAllReservations(
                perPage: 100,
                date: nil,
                from: window.from,
                to: window.to,
                status: .cancelled,
                search: nil,
                includeHidden: false,
                reason: .cancelledReservations
            )
            let repository = ReservationRepository(context: context)
            try repository.upsert(rows)
            markScopeSuccess(scope)
            return rows
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

    // Intent: Legacy view action for refreshing the pending review queues.
    // Network: GET /managed-reservations?status=new and status=needs_review.
    func refreshReviewQueues(context: ModelContext) async {
        await requestReviewRefresh(context: context, source: .manual)
    }

    @discardableResult
    private func performScheduleWindowRefresh(
        context: ModelContext,
        force: Bool
    ) async -> Bool {
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
    func loadRestaurantSetup(context: ModelContext? = nil) async throws -> RestaurantSetup {
        guard !isLoadingRestaurantSetup else {
            return restaurantSetup
        }

        isLoadingRestaurantSetup = true
        defer { isLoadingRestaurantSetup = false }

        do {
            let dto = try await environment.apiClient.fetchRestaurantSetup(reason: .restaurantSetup)
            let setup = RestaurantSetup(dto: dto)
            restaurantSetup = setup
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
        guard !isLoadingRestaurantDayAvailability else {
            throw ReservationControllerError.actionAlreadyInProgress
        }

        isLoadingRestaurantDayAvailability = true
        defer { isLoadingRestaurantDayAvailability = false }

        return try await environment.apiClient.fetchRestaurantDayAvailability(
            date: date,
            reason: .restaurantDayAvailability
        )
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
        try await environment.apiClient.fetchReservationSlots(
            date: date,
            reason: .reservationSlots
        )
    }

    // Intent: Reads staff-blocked public slots for one service date.
    // Network: GET /restaurant-blocked-slots?date=YYYY-MM-DD.
    @discardableResult
    func loadRestaurantBlockedSlots(date: String) async throws -> RestaurantBlockedSlotsResponseDTO {
        try await environment.apiClient.fetchRestaurantBlockedSlots(
            date: date,
            reason: .restaurantBlockedSlots
        )
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
            async let availability = environment.apiClient.fetchRestaurantDayAvailability(
                date: date,
                reason: .restaurantDayAvailability
            )
            async let slots = environment.apiClient.fetchReservationSlots(
                date: date,
                reason: .reservationSlots
            )
            async let blocked = environment.apiClient.fetchRestaurantBlockedSlots(
                date: date,
                reason: .restaurantBlockedSlots
            )

            let (loadedAvailability, loadedSlots, loadedBlocked) = try await (availability, slots, blocked)
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
            _ = try await updateReservation(
                id: reservation.remoteID,
                request: ReservationUpdateRequest(status: status),
                context: context
            )
        } catch {
            if errorMessage == nil {
                errorMessage = "Update did not sync. Please retry or check the reservation before relying on this change."
            }
        }
    }

    // MARK: - Confirm With Email

    // Intent: Confirms reservation and asks backend to send/record confirmation email.
    // Network: POST /managed-reservations/{id}/confirm.
    // Rename note: A later cleanup should call this confirmReservationAndSendEmail.
    func confirmReservation(
        reservation: ReservationRecord,
        context: ModelContext
    ) async {
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
    // Network: GET /managed-reservations?include_hidden=1.
    @discardableResult
    func loadHiddenReservations(context: ModelContext) async throws -> [ReservationDTO] {
        guard capabilities.canViewHiddenReservations else {
            throw ReservationControllerError.permissionDenied
        }

        let reservations = try await environment.apiClient.fetchAllReservations(
            perPage: 100,
            date: nil,
            from: nil,
            to: nil,
            status: nil,
            search: nil,
            includeHidden: true,
            reason: .hiddenReservations
        )
        let repository = ReservationRepository(context: context)
        try repository.upsert(reservations)
        return reservations.filter { $0.isHidden == true }
    }

    // Intent: Generates a guest manage link for manual Gmail/Mail confirmation copy.
    // Network: POST /managed-reservations/{id}/guest-manage-link.
    // Email: Does not send email and does not mark email as sent.
    func generateGuestManageLink(reservation: ReservationRecord) async throws -> ReservationGuestManageLinkDTO {
        guard capabilities.canGenerateGuestManageLinks else {
            throw ReservationControllerError.permissionDenied
        }

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
            postNotice(
                severity: .success,
                source: .email,
                title: "Manage link ready",
                message: "Copy it into the manual confirmation email."
            )
            return link
        } catch {
            postNotice(
                severity: .error,
                source: .email,
                title: "Manage link failed",
                message: "Could not generate a guest manage link.",
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
                summary = "#\(reservation.id) \(reservation.guestName)"
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

    private func isScopeFresh(_ scope: ReservationSyncScope, freshnessInterval: TimeInterval) -> Bool {
        guard let state = syncStateByScope[scope] else {
            return false
        }

        if let cooldownUntil = state.cooldownUntil,
           cooldownUntil > Date() {
            return true
        }

        guard let lastSuccessAt = state.lastSuccessAt else {
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
            $0.title == "You're offline. Showing saved data."
        }
        postNotice(
            severity: .warning,
            source: source,
            title: "You're offline. Showing saved data.",
            message: "Cached reservations remain visible. Pull to refresh when the connection returns.",
            requestReason: requestReason,
            errorCode: errorLogCode(error),
            developerDiagnostics: error.reservationAPIDeveloperDetail
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

    var errorDescription: String? {
        switch self {
        case .actionAlreadyInProgress:
            return "Another update is already in progress for this reservation."
        case .permissionDenied:
            return "This account cannot use this admin tool."
        case .missingReservationID:
            return "Enter a reservation ID first."
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
