//
//  ReservationsController.swift
//  Tryzub Reservations
//

import Foundation
import SwiftData

@MainActor
final class ReservationsController: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var actionInProgressIDs: Set<Int> = []
    @Published private(set) var isCreatingReservation = false
    @Published private(set) var isCheckingImportFailureCount = false
    @Published private(set) var lastSyncedAt: Date?
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published var importFailureCount: Int = 0
    @Published var importFailureCountError: String?

    let environment: AppEnvironment

    var capabilities: AppCapabilities {
        environment.capabilities
    }

    private let automaticRefreshInterval: TimeInterval = 300
    private var hasAttemptedInitialLoad = false

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func loadIfNeeded(context: ModelContext) async {
        guard !hasAttemptedInitialLoad else { return }
        hasAttemptedInitialLoad = true

        do {
            let repository = ReservationRepository(context: context)
            if let latestLocalSyncDate = try repository.latestLocalSyncDate(),
               Date().timeIntervalSince(latestLocalSyncDate) < automaticRefreshInterval {
                lastSyncedAt = latestLocalSyncDate
                await refreshImportFailureCount()
                return
            }
        } catch {
            errorMessage = "Could not check local reservation cache."
        }

        await refreshDashboard(context: context)
    }

    func refreshAll(context: ModelContext) async {
        guard !isSyncing else { return }

        isSyncing = true
        errorMessage = nil

        defer {
            isSyncing = false
        }

        do {
            let repository = ReservationRepository(context: context)
            let service = ReservationSyncService(client: environment.apiClient, repository: repository)
            try await service.syncAllReservations()
            await refreshImportFailureCount()
            lastSyncedAt = Date()
        } catch {
            errorMessage = "Could not refresh reservations. Showing last saved data. Tap Refresh to try again."
        }
    }

    func refreshDashboard(context: ModelContext) async {
        guard !isSyncing else { return }

        isSyncing = true
        errorMessage = nil

        defer {
            isSyncing = false
        }

        do {
            let repository = ReservationRepository(context: context)
            let service = ReservationSyncService(client: environment.apiClient, repository: repository)
            try await service.syncToday()
            lastSyncedAt = Date()
        } catch {
            errorMessage = "Could not refresh today's reservations. Showing last saved data. Tap Refresh to try again."
            return
        }

        await refreshImportFailureCount()
    }

    func refreshToday(context: ModelContext) async {
        await syncFiltered(context: context) { try await $0.syncToday() }
    }

    func refreshUpcoming(context: ModelContext) async {
        await syncFiltered(context: context) { try await $0.syncUpcoming() }
    }

    func refreshNeedsReview(context: ModelContext) async {
        await syncFiltered(context: context) { try await $0.syncNeedsReview() }
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

    func refreshImportFailureCount() async {
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
            let response = try await service.fetchImportFailures(page: 1, perPage: 1)
            importFailureCount = response.total
        } catch {
            importFailureCountError = "Could not check form problems."
        }
    }

    private func syncFiltered(
        context: ModelContext,
        operation: (ReservationSyncService) async throws -> Void
    ) async {
        guard !isSyncing else { return }

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

    var errorDescription: String? {
        "Another update is already in progress for this reservation."
    }
}
