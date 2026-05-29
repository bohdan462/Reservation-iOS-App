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
    @Published private(set) var isSyncing = false

    // Tracks the quiet host-board loop that keeps today's cache warm.
    @Published private(set) var isAutoRefreshing = false

    // Remote reservation IDs currently being patched or confirmed.
    @Published private(set) var actionInProgressIDs: Set<Int> = []

    // True while a call-in/manual reservation is being created on the server.
    @Published private(set) var isCreatingReservation = false
    @Published private(set) var isCheckingImportFailureCount = false

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

    // MARK: - Sync State

    private var lastAutoRefreshAttemptAt: Date?
    private var lastAutoRefreshFailureAt: Date?
    private var manualAttemptByScope: [ReservationSyncScope: Date] = [:]
    private var syncStateByScope: [ReservationSyncScope: SyncScopeState] = [:]

    // MARK: - Refresh Timing

    private let autoRefreshInterval: TimeInterval = 60
    private let autoRefreshFailureCooldown: TimeInterval = 180
    private let manualRefreshCooldown: TimeInterval = 8
    private let scheduleFreshnessInterval: TimeInterval = 300
    private let reviewFreshnessInterval: TimeInterval = 120
    private let importFailureCountFreshnessInterval: TimeInterval = 300

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

        await performTodayRefresh(context: context, mode: .startup)
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
        let scope = todayScope()

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

        return await performTodayRefresh(context: context, mode: source == .startup ? .startup : .manual)
    }

    // MARK: - Schedule Sync

    // Intent: Schedule tab became visible; refresh only if the schedule cache is stale.
    // Network: GET /managed-reservations?from=...&to=... when stale.
    func scheduleBecameActive(context: ModelContext) async {
        let scope = scheduleScope()
        guard !isScopeFresh(scope, freshnessInterval: scheduleFreshnessInterval) else { return }
        await performScheduleWindowRefresh(context: context, force: false)
    }

    // Intent: Staff manually refreshes the schedule window.
    // Network: GET /managed-reservations?from=...&to=...
    @discardableResult
    func requestScheduleRefresh(
        context: ModelContext,
        source: ReservationSyncIntent = .manual
    ) async -> Bool {
        await performScheduleWindowRefresh(context: context, force: source == .manual)
    }

    // Intent: Schedule All mode pages historical rows on demand without replacing local cache.
    // Network: GET /managed-reservations?page=...&per_page=100.
    func loadScheduleAllPage(
        context: ModelContext,
        page: Int,
        search: String?
    ) async throws -> ReservationsResponse {
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
        let scope = ReservationSyncScope.reviewQueues
        guard !isScopeFresh(scope, freshnessInterval: reviewFreshnessInterval) else { return }
        await performReviewQueuesRefresh(context: context, force: false)
    }

    // Intent: Staff manually refreshes the pending review queue.
    // Network: GET /managed-reservations?status=new and status=needs_review.
    @discardableResult
    func requestReviewRefresh(
        context: ModelContext,
        source: ReservationSyncIntent = .manual
    ) async -> Bool {
        await performReviewQueuesRefresh(context: context, force: source == .manual)
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

        let scope = todayScope()
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

        let didRefresh = await performTodayRefresh(context: context, mode: .automatic)
        if !didRefresh {
            lastAutoRefreshFailureAt = Date()
            markScopeFailure(scope, cooldown: autoRefreshFailureCooldown)
        }
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

        guard beginScope(scope) else {
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
            try await service.syncToday(reason: mode.requestReason)
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
            postRefreshFailureNotice(mode: mode, error: error)
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

        await refreshImportFailureCountIfNeeded(force: false, reason: .failureCount)
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

        guard beginScope(scope) else {
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
            try await service.syncScheduleWindow(
                from: window.from,
                to: window.to,
                reason: .scheduleWindow
            )
            lastSyncedAt = Date()
            markScopeSuccess(scope)
            await refreshImportFailureCountIfNeeded(force: false, reason: .failureCount)
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

        guard beginScope(scope) else {
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
            await refreshImportFailureCountIfNeeded(force: false, reason: .failureCount)
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
            postNotice(
                severity: .warning,
                source: .admin,
                title: "Restaurant setup unavailable",
                message: "Using saved defaults until the setup endpoint responds.",
                requestReason: .restaurantSetup,
                errorCode: errorLogCode(error)
            )
            throw error
        }
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
                let reconciled = await reconcileReservation(id: id, context: context)
                postMutationFailureNotice(
                    title: reconciled == nil ? "Update may be unsynced" : "Server state refreshed",
                    message: reconciled == nil
                        ? "Please retry or check the reservation before relying on this change."
                        : "The app refreshed this reservation after an uncertain network failure."
                )
                throw error
            }

            errorMessage = "Update did not sync. Please retry or check the reservation before relying on this change."
            postMutationFailureNotice(
                title: "Update did not sync",
                message: "Please retry or check the reservation before relying on this change."
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
                        message: "Please retry or check details before relying on email status."
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
        guard beginScope(scope) else {
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

        guard beginScope(scope) else {
            ReservationAPILogger.skip(reason: .scopeSkipInFlight, message: "\(scope.description) skipped because this scope is already in flight")
            return nil
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
            postNotice(severity: .warning, source: .admin, title: "\(test.title) failed", message: error.localizedDescription)
            return result
        }
    }

    // MARK: - Private Sync Scope Helpers

    private func todayScope() -> ReservationSyncScope {
        .today(date: Date.reservationDateString())
    }

    private func scheduleWindow() -> (from: String, to: String) {
        let from = Date()
        let to = Calendar.current.date(byAdding: .day, value: 30, to: from) ?? from
        return (from.reservationDateString(), to.reservationDateString())
    }

    private func scheduleScope() -> ReservationSyncScope {
        let window = scheduleWindow()
        return .scheduleWindow(from: window.from, to: window.to)
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

    private func beginScope(_ scope: ReservationSyncScope) -> Bool {
        var state = syncStateByScope[scope] ?? SyncScopeState()
        if state.isInFlight {
            return false
        }

        let now = Date()
        state.isInFlight = true
        state.lastAttemptAt = now
        syncStateByScope[scope] = state
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
        publishSyncScopeSnapshots()
    }

    private func markScopeFailure(_ scope: ReservationSyncScope, cooldown: TimeInterval? = nil) {
        var state = syncStateByScope[scope] ?? SyncScopeState()
        let now = Date()
        state.isInFlight = false
        state.lastFailureAt = now
        state.cooldownUntil = cooldown.map { now.addingTimeInterval($0) }
        syncStateByScope[scope] = state
        publishSyncScopeSnapshots()
    }

    private func markScopeCancelled(_ scope: ReservationSyncScope) {
        var state = syncStateByScope[scope] ?? SyncScopeState()
        state.isInFlight = false
        syncStateByScope[scope] = state
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

        let window = scheduleWindow()
        if reservation.reservationDate >= window.from && reservation.reservationDate <= window.to {
            markScopeStale(.scheduleWindow(from: window.from, to: window.to))
        }

        markScopeStale(.reviewQueues)
    }

    private func publishSyncScopeSnapshots() {
        syncScopeSnapshots = syncStateByScope
            .map { SyncScopeSnapshot(scope: $0.key, state: $0.value) }
            .sorted { $0.scope.description < $1.scope.description }
    }

    // MARK: - Private Notice / Error Helpers

    private func postRefreshFailureNotice(mode: ReservationRefreshMode, error: Error) {
        postNotice(
            severity: mode.noticeSeverity,
            source: mode.noticeSource,
            title: mode.failureTitle,
            message: mode.failureMessage,
            requestReason: mode.requestReason,
            errorCode: errorLogCode(error)
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
        errorCode: String? = nil
    ) {
        let notice = AppNotice(
            severity: severity,
            source: source,
            title: title,
            message: message,
            requestReason: requestReason,
            errorCode: errorCode
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
            return "This account cannot view form problems."
        case .missingReservationID:
            return "Enter a reservation ID first."
        }
    }
}

enum ReservationSyncIntent {
    case startup
    case manual
    case automatic
    case screenActive
    case mutationReconcile
    case diagnostics
}

enum ReservationSyncScope: Hashable, CustomStringConvertible {
    case today(date: String)
    case scheduleWindow(from: String, to: String)
    case reviewQueues
    case importFailureCount
    case reservation(id: Int)

    var description: String {
        switch self {
        case .today(let date):
            return "today(\(date))"
        case .scheduleWindow(let from, let to):
            return "schedule(\(from)...\(to))"
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
            return "The server did not respond. Cached remain visible."
        case .manual:
            return "Could not reach the server. Cached reservations remain visible."
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
}

enum AdminFetchTest: String, CaseIterable, Identifiable {
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
