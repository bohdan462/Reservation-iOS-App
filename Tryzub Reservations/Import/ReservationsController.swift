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
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published var importFailureCount: Int = 0
    @Published var importFailureCountError: String?
    
    private var lastAutoRefreshAttemptAt: Date?
    private var lastAutoRefreshFailureAt: Date?

    private let autoRefreshInterval: TimeInterval = 90
    private let autoRefreshFailureCooldown: TimeInterval = 120

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
            errorMessage = "Could not check local reservation cache."
        }

        await refreshDashboard(context: context, mode: .startup)
    }

    func refreshAll(context: ModelContext) async {
        guard !hasActiveReservationRefresh else { return }

        isSyncing = true
        errorMessage = nil
        var didRefreshReservations = false

        do {
            let repository = ReservationRepository(context: context)
            let service = ReservationSyncService(client: environment.apiClient, repository: repository)
            try await service.syncAllReservations(reason: .scheduleAll)
            lastSyncedAt = Date()
            didRefreshReservations = true
        } catch {
            errorMessage = "Could not refresh reservations. Showing last saved data. Tap Refresh to try again."
        }

        isSyncing = false
        if didRefreshReservations {
            await refreshImportFailureCount(reason: .failureCount)
        }
    }

    func refreshDashboard(context: ModelContext) async {
        await refreshDashboard(context: context, mode: .manual)
    }

//    func autoRefreshDashboardIfAllowed(
//        context: ModelContext,
//        isInteractionActive: Bool,
//        isAppActive: Bool
//    ) async {
//        guard isAppActive else {
//            ReservationAPILogger.skip(reason: .autoSkipInactive, message: "app is not active")
//            return
//        }
//
//        guard !isInteractionActive else {
//            ReservationAPILogger.skip(reason: .autoSkipBusy, message: "host interaction is active")
//            return
//        }
//
//        guard !hasActiveReservationRefresh, !hasActiveMutation, !isCheckingImportFailureCount else {
//            ReservationAPILogger.skip(reason: .autoSkipBusy, message: "controller is busy")
//            return
//        }
//
//        await refreshDashboard(context: context, mode: .automatic)
//    }
    
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

        let now = Date()

        if let lastAttempt = lastAutoRefreshAttemptAt,
           now.timeIntervalSince(lastAttempt) < autoRefreshInterval {
            ReservationAPILogger.skip(reason: .autoSkipBusy, message: "auto-refresh interval has not passed")
            return
        }

        if let lastFailure = lastAutoRefreshFailureAt,
           now.timeIntervalSince(lastFailure) < autoRefreshFailureCooldown {
            ReservationAPILogger.skip(reason: .autoSkipBusy, message: "auto-refresh failure cooldown is active")
            return
        }

        lastAutoRefreshAttemptAt = now

        await refreshDashboard(context: context, mode: .automatic)

        // If refreshDashboard does not throw, you need another way to know whether it failed.
    }

    private func refreshDashboard(
        context: ModelContext,
        mode: ReservationRefreshMode
    ) async {
        guard !hasActiveReservationRefresh else { return }

        if mode == .automatic {
            isAutoRefreshing = true
        } else {
            isSyncing = true
        }
        errorMessage = nil

        do {
            let repository = ReservationRepository(context: context)
            let service = ReservationSyncService(client: environment.apiClient, repository: repository)
            try await service.syncToday(reason: mode.requestReason)
            lastSyncedAt = Date()
        } catch {
            errorMessage = mode.failureMessage
            if mode == .automatic {
                isAutoRefreshing = false
            } else {
                isSyncing = false
            }
            return
        }

        if mode == .automatic {
            isAutoRefreshing = false
        } else {
            isSyncing = false
        }

        await refreshImportFailureCount(reason: .failureCount)
    }

    func refreshReviewQueues(context: ModelContext) async {
        await syncFiltered(context: context) { try await $0.syncReviewQueues(reason: .reviewQueues) }
        await refreshImportFailureCount(reason: .failureCount)
    }

    func save(_ reservation: ReservationDTO, context: ModelContext) {
        let repository = ReservationRepository(context: context)
        let service = ReservationSyncService(client: environment.apiClient, repository: repository)

        do {
            try service.saveReservation(reservation)
        } catch {
            errorMessage = error.localizedDescription
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
            noticeMessage = "Manual reservation created."
            return reservation
        } catch {
            errorMessage = "Manual reservation was not created. Please retry before relying on this reservation."
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
            noticeMessage = "Reservation updated."
            return reservation
        } catch {
            errorMessage = "Update did not sync. Please retry or check the reservation before relying on this change."
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

            switch response.emailStatus {
            case .sent:
                noticeMessage = "Reservation confirmed. Email sent."
            case .alreadySent:
                noticeMessage = "Reservation was already confirmed. Confirmation email was already sent."
            case .failed:
                errorMessage = "Reservation confirmed, but confirmation email failed. Follow up manually."
            case .skipped:
                noticeMessage = response.message ?? "Reservation confirmed. Email was skipped."
            case .unknown:
                noticeMessage = "Reservation confirmed. Check email status in details."
            }
        } catch {
            errorMessage = "Reservation was not confirmed. Confirmation email may not have been sent. Please retry or check details."
        }
    }

    func refreshImportFailureCount(reason: ReservationAPIRequestReason = .failureCount) async {
        guard capabilities.canViewFailedImports else {
            importFailureCount = 0
            importFailureCountError = nil
            return
        }

        guard !isCheckingImportFailureCount else { return }

        isCheckingImportFailureCount = true
        importFailureCountError = nil
        defer { isCheckingImportFailureCount = false }

        let service = ImportFailureService(client: environment.apiClient)

        do {
            let response = try await service.fetchImportFailures(page: 1, perPage: 1, reason: reason)
            importFailureCount = response.total
        } catch {
            importFailureCountError = "Could not check form problems."
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
        return response
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

    private func syncFiltered(
        context: ModelContext,
        operation: (ReservationSyncService) async throws -> Void
    ) async {
        guard !hasActiveReservationRefresh else { return }

        isSyncing = true
        errorMessage = nil

        defer {
            isSyncing = false
        }

        do {
            let repository = ReservationRepository(context: context)
            let service = ReservationSyncService(client: environment.apiClient, repository: repository)
            try await operation(service)
            lastSyncedAt = Date()
        } catch {
            errorMessage = "Could not refresh reservations. Showing last saved data. Tap Refresh to try again."
        }
    }
}

private enum ReservationControllerError: LocalizedError {
    case actionAlreadyInProgress
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .actionAlreadyInProgress:
            return "Another update is already in progress for this reservation."
        case .permissionDenied:
            return "This account cannot view form problems."
        }
    }
}

private enum ReservationRefreshMode {
    case startup
    case manual
    case automatic

    var failureMessage: String {
        switch self {
        case .startup:
            return "Could not refresh today's reservations. Showing last saved data."
        case .manual:
            return "Could not refresh today's reservations. Showing last saved data. Tap Refresh to try again."
        case .automatic:
            return "Automatic refresh could not reach the server. Showing last saved data."
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
        }
    }
}
