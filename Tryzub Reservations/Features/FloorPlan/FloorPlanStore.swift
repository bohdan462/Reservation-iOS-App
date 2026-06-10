//
//  FloorPlanStore.swift
//  Tryzub Reservations
//

import Foundation
import SwiftData

enum FloorPlanLayoutSaveState: Equatable {
    case idle
    case saving
    case saved
    case failed(String)
}

@MainActor
final class FloorPlanStore: ObservableObject {
    @Published private(set) var viewState: FloorPlanViewState = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var conflict: FloorPlanConflictViewState?
    @Published private(set) var layoutTables: [RestaurantTableDTO] = []
    @Published private(set) var isSavingLayout = false
    @Published private(set) var layoutSaveState: FloorPlanLayoutSaveState = .idle
    @Published private(set) var isAssigning = false

    private let service: any FloorPlanServiceProtocol
    private var cacheByDate: [String: FloorPlanResponseDTO] = [:]
    private var lastCheckedAtByDate: [String: Date] = [:]
    private var selectedDate: String = Date().reservationDateString()
    private var activeLoadGeneration = 0
    private var loadTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?
    private let autoRefreshInterval: TimeInterval = 60

    init(service: any FloorPlanServiceProtocol) {
        self.service = service
    }

    convenience init(apiClient: any ReservationsAPIClientProtocol) {
        self.init(service: FloorPlanService(client: apiClient))
    }

    deinit {
        loadTask?.cancel()
        autoRefreshTask?.cancel()
    }

    // MARK: - Load

    func load(date: String) {
        selectedDate = date
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.refresh(date: date, force: false)
        }
    }

    func refresh(date: String? = nil, force: Bool = true) async {
        let targetDate = date ?? selectedDate
        selectedDate = targetDate
        activeLoadGeneration += 1
        let generation = activeLoadGeneration

        if !force, cacheByDate[targetDate] != nil {
            applyCached(date: targetDate)
            errorMessage = nil
            return
        }

        isLoading = true
        defer {
            if generation == activeLoadGeneration {
                isLoading = false
            }
        }

        errorMessage = nil
        FloorPlanTrace.event(name: "load_started", extra: "date=\(targetDate)")

        do {
            let response = try await service.getFloorPlan(date: targetDate)
            guard !Task.isCancelled else { return }
            guard generation == activeLoadGeneration, selectedDate == targetDate else { return }

            cacheByDate[targetDate] = response
            lastCheckedAtByDate[targetDate] = Date()
            viewState = FloorPlanViewStateBuilder.build(
                response: response,
                selectedDate: targetDate,
                lastCheckedAt: lastCheckedAtByDate[targetDate]
            )
            FloorPlanTrace.event(
                name: "load_completed",
                extra: "date=\(targetDate) tables=\(response.tables.count) reservations=\(response.reservations.count) assignments=\(response.assignments.count)"
            )
        } catch let error as FloorPlanError {
            guard !Task.isCancelled else { return }
            guard generation == activeLoadGeneration, selectedDate == targetDate else { return }
            errorMessage = staffMessage(for: error)
        } catch {
            guard !Task.isCancelled else { return }
            guard generation == activeLoadGeneration, selectedDate == targetDate else { return }
            if !error.isCancellationLike {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Assignment

    func assign(
        reservationID: Int,
        tableKeys: [String],
        controller: ReservationsController?,
        context: ModelContext?
    ) async {
        await mutateAssignment(
            reservationID: reservationID,
            tableKeys: tableKeys,
            controller: controller,
            context: context
        )
    }

    func clearAssignment(
        reservationID: Int,
        controller: ReservationsController?,
        context: ModelContext?
    ) async {
        await mutateAssignment(
            reservationID: reservationID,
            tableKeys: [],
            controller: controller,
            context: context
        )
    }

    private func mutateAssignment(
        reservationID: Int,
        tableKeys: [String],
        controller: ReservationsController?,
        context: ModelContext?
    ) async {
        guard !isAssigning else { return }
        isAssigning = true
        defer { isAssigning = false }
        conflict = nil
        errorMessage = nil
        FloorPlanTrace.event(
            name: "assign_started",
            extra: "reservation=\(reservationID) tableKeys=\(tableKeys.joined(separator: ","))"
        )

        do {
            let response = try await service.patchReservationTables(
                reservationID: reservationID,
                tableKeys: tableKeys
            )
            if let reservation = response.reservation,
               let controller,
               let context {
                controller.save(reservation, context: context)
            }
            FloorPlanTrace.event(name: "assign_completed", extra: "reservation=\(reservationID)")
            await refresh(date: selectedDate, force: true)
        } catch let error as FloorPlanError {
            switch error {
            case let .assignmentConflict(conflicts):
                let message = FloorPlanConflictCopy.summary(
                    for: conflicts,
                    tables: viewState.tables
                )
                conflict = FloorPlanConflictViewState(conflicts: conflicts, message: message)
                FloorPlanTrace.event(
                    name: "assign_conflict",
                    extra: "reservation=\(reservationID) conflicts=\(conflicts.count)"
                )
            default:
                errorMessage = staffMessage(for: error)
            }
        } catch {
            if !error.isCancellationLike {
                errorMessage = error.localizedDescription
            }
        }
    }

    func dismissConflict() {
        conflict = nil
    }

    // MARK: - Layout

    func loadLayout() async {
        do {
            let tables = try await service.getRestaurantTables()
            layoutTables = tables.sorted { $0.sortOrder < $1.sortOrder }
            FloorPlanTrace.event(
                name: "layout_load_completed",
                extra: "tables=\(tables.count)"
            )
        } catch let error as FloorPlanError {
            errorMessage = staffMessage(for: error)
        } catch {
            if !error.isCancellationLike {
                errorMessage = error.localizedDescription
            }
        }
    }

    func resetLayoutSaveState() {
        layoutSaveState = .idle
    }

    func saveLayout(_ tables: [RestaurantTableDTO]) async -> Bool {
        guard !isSavingLayout else { return false }
        isSavingLayout = true
        layoutSaveState = .saving
        defer { isSavingLayout = false }

        let activeCount = tables.filter(\.isActive).count
        FloorPlanTrace.event(
            name: "layout_save_started",
            extra: "tables=\(tables.count) active=\(activeCount)"
        )

        do {
            let saved = try await service.putRestaurantTables(tables)
            layoutTables = saved.sorted { $0.sortOrder < $1.sortOrder }
            await refresh(date: selectedDate, force: true)
            layoutSaveState = .saved
            FloorPlanTrace.event(
                name: "layout_save_completed",
                extra: "tables=\(saved.count) active=\(saved.filter(\.isActive).count)"
            )
            return true
        } catch {
            guard !error.isCancellationLike else {
                layoutSaveState = .idle
                return false
            }
            let message = FloorPlanLayoutSaveCopy.failureMessage(for: error)
            layoutSaveState = .failed(message)
            FloorPlanTrace.event(
                name: "layout_save_failed",
                extra: "message=\(message)"
            )
            return false
        }
    }

    // MARK: - Auto Refresh

    func setAutoRefreshActive(_ isActive: Bool) {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        guard isActive, viewState.isToday else { return }

        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.autoRefreshInterval ?? 60))
                guard !Task.isCancelled else { return }
                await self?.refresh(force: true)
            }
        }
    }

    // MARK: - Helpers

    private func applyCached(date: String) {
        guard let response = cacheByDate[date] else { return }
        viewState = FloorPlanViewStateBuilder.build(
            response: response,
            selectedDate: date,
            lastCheckedAt: lastCheckedAtByDate[date]
        )
    }

    private func staffMessage(for error: FloorPlanError) -> String {
        switch error {
        case let .assignmentConflict(conflicts):
            return FloorPlanConflictCopy.summary(for: conflicts, tables: viewState.tables)
        case let .network(error):
            return error.localizedDescription
        case let .decoding(error):
            return error.localizedDescription
        case let .serverMessage(message):
            return message
        }
    }
}
