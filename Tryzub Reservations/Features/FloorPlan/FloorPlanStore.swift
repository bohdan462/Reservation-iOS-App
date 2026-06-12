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

    // Optional coordinator for cross-store dedup. Set by the owning view hierarchy.
    // When nil, FloorPlanStore uses its own cacheByDate check only.
    var freshnessCoordinator: FreshnessCoordinator?

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

    func refresh(date: String? = nil, force: Bool = true, allowDuringSave: Bool = false) async {
        // While a layout save is in flight, suppress any competing/automatic floor
        // refresh. Only the save's own post-success refresh (allowDuringSave) may run.
        // This prevents the observed overlap where a `floor_plan` GET raced the failing
        // `restaurant_tables_put` PUT.
        if isSavingLayout && !allowDuringSave {
            FloorPlanTrace.event(name: "refresh_suppressed", extra: "reason=layout_save_in_flight")
            return
        }

        let targetDate = date ?? selectedDate
        selectedDate = targetDate
        activeLoadGeneration += 1
        let generation = activeLoadGeneration

        // Ask the shared freshness coordinator before checking local cacheByDate.
        // This prevents duplicate floor-plan fetches when multiple surfaces trigger
        // load for the same date within the TTL window.
        let scope = FreshnessScope.floorPlan(date: targetDate)
        if !force, let coordinator = freshnessCoordinator {
            let decision = coordinator.decide(scope: scope)
            switch decision {
            case .useCache:
                if cacheByDate[targetDate] != nil {
                    applyCached(date: targetDate)
                    errorMessage = nil
                    return
                }
                // Coordinator says fresh but local cache is empty (relaunch):
                // fall through to fetch.
            case .joinInFlight:
                return
            case .blockedByCooldown:
                return
            case .fetch:
                break
            }
        } else if !force, cacheByDate[targetDate] != nil {
            // Fallback when no coordinator is wired yet.
            applyCached(date: targetDate)
            errorMessage = nil
            return
        }

        isLoading = true
        freshnessCoordinator?.markInFlight(scope)
        defer {
            if generation == activeLoadGeneration {
                isLoading = false
            }
        }

        errorMessage = nil
        FloorPlanTrace.event(name: "load_started", extra: "date=\(targetDate)")

        do {
            let response = try await service.getFloorPlan(date: targetDate)
            guard !Task.isCancelled else {
                freshnessCoordinator?.markFailed(scope, cooldown: 0)
                return
            }
            guard generation == activeLoadGeneration, selectedDate == targetDate else {
                freshnessCoordinator?.markFailed(scope, cooldown: 0)
                return
            }

            cacheByDate[targetDate] = response
            lastCheckedAtByDate[targetDate] = Date()
            freshnessCoordinator?.markCompleted(scope)
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
            freshnessCoordinator?.markFailed(scope)
            errorMessage = staffMessage(for: error)
        } catch {
            guard !Task.isCancelled else { return }
            guard generation == activeLoadGeneration, selectedDate == targetDate else { return }
            if !error.isCancellationLike {
                freshnessCoordinator?.markFailed(scope)
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
        // Backend Floor Plan assignment is canonical.
        // This endpoint enforces backend table conflict rules.
        // Legacy table_name PATCH does not.
        TableAssignmentTrace.canonicalFloorPlan(
            reservationID: reservationID,
            tableKeys: tableKeys
        )

        let expectedUpdatedAt: String?
        if let controller, let context {
            expectedUpdatedAt = controller.cachedReservationRowVersion(id: reservationID, context: context)
        } else {
            expectedUpdatedAt = nil
        }
        MutationVersionTrace.log(
            action: "table_assignment",
            reservationID: reservationID,
            expectedUpdatedAt: expectedUpdatedAt
        )

        do {
            let response = try await service.patchReservationTables(
                reservationID: reservationID,
                tableKeys: tableKeys,
                expectedUpdatedAt: expectedUpdatedAt
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
                ReservationMutationReconcilePolicy.traceTableConflict(
                    reservationID: reservationID,
                    source: "floor_plan"
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

        let keys = tables.map(\.tableKey).joined(separator: ",")
        let maxX = tables.map { $0.x + $0.widthUnits }.max() ?? 0
        let maxY = tables.map { $0.y + $0.heightUnits }.max() ?? 0
        FloorPlanTrace.event(
            name: "layout_save_payload",
            extra: "tables=\(tables.count) keys=[\(keys)] active=\(activeCount) bounds=\(maxX)x\(maxY)"
        )
        // FloorPlanStore is @MainActor and the save path builds a value-type payload and
        // calls the network service; it never opens a SwiftData ModelContext.
        DateSwitchTrace.concurrencyPhase(
            context: "floor_layout_save",
            phase: "payload_built",
            detail: "modelContextUsed=false"
        )

        do {
            let saved = try await service.putRestaurantTables(tables)
            layoutTables = saved.sorted { $0.sortOrder < $1.sortOrder }
            DateSwitchTrace.concurrencyPhase(
                context: "floor_layout_save",
                phase: "refresh_after_success",
                detail: "onlyOnSuccess=true mainActor=true"
            )
            await refresh(date: selectedDate, force: true, allowDuringSave: true)
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
            DateSwitchTrace.concurrencyPhase(
                context: "floor_layout_save",
                phase: "publish_error",
                detail: "mainActor=true modelContextUsed=false"
            )
            if case let .serverValidation(code, status, backendMessage) = (error as? FloorPlanError) {
                FloorPlanTrace.event(
                    name: "layout_save_failed",
                    extra: "code=\(code) status=\(status) backendMessage=\"\(backendMessage)\""
                )
            } else {
                FloorPlanTrace.event(
                    name: "layout_save_failed",
                    extra: "message=\(message)"
                )
            }
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

    // MARK: - Canonical Assignment Lookup (for Detail/Host migration)

    /// Returns a `tableKey` for a given human-readable table name/label.
    /// Checks the current floor plan view state first, then the layout tables fallback.
    /// Returns nil when no backend layout is available (caller should use legacy path).
    func tableKey(forLabel label: String) -> String? {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let match = viewState.tables.first(where: {
            $0.label.lowercased() == normalized || $0.tableKey.lowercased() == normalized
        }) {
            return match.tableKey
        }
        if let match = layoutTables.first(where: {
            $0.label.lowercased() == normalized || $0.tableKey.lowercased() == normalized
        }) {
            return match.tableKey
        }
        return nil
    }

    /// True when a backend floor layout is available and canonical assignment can be used.
    var hasBackendLayout: Bool {
        viewState.hasTables || !layoutTables.isEmpty
    }

    /// Typed capacity summary built from the backend floor layout.
    /// Service Intelligence and BookingLoadAnalyzer should prefer this over free-form text.
    var capacitySummary: TableCapacitySummary {
        let tables = viewState.tables.isEmpty ? layoutTables : viewState.tables
        let summary = TableCapacitySummary.build(from: tables)
        TableCapacityTrace.summary(summary)
        return summary
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
        case let .serverValidation(_, _, message):
            return message
        }
    }
}
