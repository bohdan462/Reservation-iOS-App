//
//  ReservationsController.swift
//  Tryzub Reservations
//

import Foundation
import SwiftData

@MainActor
final class ReservationsController: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var isAutoRefreshing = false
    @Published private(set) var actionInProgressIDs: Set<Int> = []
    @Published private(set) var isCreatingReservation = false
    @Published private(set) var isCheckingImportFailureCount = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var notices: [AppNotice] = []
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published var importFailureCount: Int = 0
    @Published var importFailureCountError: String?
    @Published private(set) var syncScopeSnapshots: [SyncScopeSnapshot] = []
    
    private var lastAutoRefreshAttemptAt: Date?
    private var lastAutoRefreshFailureAt: Date?
    private var manualAttemptByScope: [ReservationSyncScope: Date] = [:]
    private var syncStateByScope: [ReservationSyncScope: SyncScopeState] = [:]

    private let autoRefreshInterval: TimeInterval = 60
    private let autoRefreshFailureCooldown: TimeInterval = 180
    private let manualRefreshCooldown: TimeInterval = 8
    private let scheduleFreshnessInterval: TimeInterval = 300
    private let reviewFreshnessInterval: TimeInterval = 120
    private let importFailureCountFreshnessInterval: TimeInterval = 300

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

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func loadIfNeeded(context: ModelContext) async {
        guard !hasAttemptedInitialLoad else { return }
        hasAttemptedInitialLoad = true

        do {
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

    func refreshAll(context: ModelContext) async {
        await requestScheduleRefresh(context: context, source: .manual)
    }

    @discardableResult
    func refreshDashboard(context: ModelContext) async -> Bool {
        await requestManualTodayRefresh(context: context, source: .manual)
    }

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

    func scheduleBecameActive(context: ModelContext) async {
        let scope = scheduleScope()
        guard !isScopeFresh(scope, freshnessInterval: scheduleFreshnessInterval) else { return }
        await performScheduleWindowRefresh(context: context, force: false)
    }

    @discardableResult
    func requestScheduleRefresh(
        context: ModelContext,
        source: ReservationSyncIntent = .manual
    ) async -> Bool {
        await performScheduleWindowRefresh(context: context, force: source == .manual)
    }

    func reviewBecameActive(context: ModelContext) async {
        let scope = ReservationSyncScope.reviewQueues
        guard !isScopeFresh(scope, freshnessInterval: reviewFreshnessInterval) else { return }
        await performReviewQueuesRefresh(context: context, force: false)
    }

    @discardableResult
    func requestReviewRefresh(
        context: ModelContext,
        source: ReservationSyncIntent = .manual
    ) async -> Bool {
        await performReviewQueuesRefresh(context: context, force: source == .manual)
    }

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

    func isActionInProgress(for reservation: ReservationRecord) -> Bool {
        actionInProgressIDs.contains(reservation.remoteID)
    }

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
                postNotice(severity: .success, source: .email, title: "Reservation confirmed", message: "Confirmation email recorded as sent.")
            case .alreadySent:
                postNotice(severity: .info, source: .email, title: "Already confirmed", message: "Confirmation email was already recorded as sent.")
            case .failed:
                errorMessage = "Reservation confirmed, but confirmation email failed. Follow up manually."
                postNotice(severity: .warning, source: .email, title: "Email failed", message: "Reservation confirmed, but staff should follow up manually.")
            case .skipped:
                postNotice(severity: .info, source: .email, title: "Email skipped", message: response.message)
            case .unknown:
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

    func refreshImportFailureCount(reason: ReservationAPIRequestReason = .failureCount) async {
        await refreshImportFailureCountIfNeeded(force: false, reason: reason)
    }

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
            return "Auto-refresh failed"
        case .schedule:
            return "Schedule refresh failed"
        case .review:
            return "Review refresh failed"
        }
    }

    var failureMessage: String {
        switch self {
        case .startup:
            return "The server did not respond. Cached reservations remain visible."
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
