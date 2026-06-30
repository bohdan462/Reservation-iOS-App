//
//  HostBoardLifecycleCoordinator.swift
//  Tryzub Reservations
//
//  Stateful lifecycle coordinator for the Host Board.
//  Provides a single typed lifecycle path instead of multiple independent
//  .task(id:) pipelines each owning network decisions.
//
//  Designed as a @StateObject — use a no-arg init and call handle() each time
//  the trigger key changes. The controller and stores are passed per-call (not
//  stored as properties) to stay compatible with @EnvironmentObject injection.
//
//  Trace format: [HOST_LIFECYCLE] event=... date=...
//

import Foundation
import OSLog

@MainActor
final class HostBoardLifecycleCoordinator: ObservableObject {

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "HostBoardLifecycle"
    )

    // MARK: - Private state

    private var lastEmittedDate: String?
    private var lastEmittedVisible: Bool?
    private var pendingFloorPlanDate: String?
    private var floorPlanDebounceTask: Task<Void, Never>?
    private var pendingOptionalWorkDate: String?
    private var optionalWorkIdleTask: Task<Void, Never>?

    // MARK: - Init

    init() {}

    // MARK: - Lifecycle entry point

    /// Call this from a single .task(id: lifecycleKey) in HostBoardView.
    /// It determines whether this is a visibility change, date change, or hide event,
    /// routes work accordingly, and emits the appropriate traces.
    func handle(
        isVisible: Bool,
        date: String,
        shouldDefer: Bool,
        lastStaffInteractionAt: Date,
        controller: ReservationsController,
        guestIntelligenceStore: GuestIntelligenceStore,
        floorPlanStore: FloorPlanStore
    ) {
        let visibilityChanged = lastEmittedVisible != isVisible
        let dateChanged = lastEmittedDate != date && lastEmittedDate != nil
        let isInitialVisibleLoad = isVisible && lastEmittedVisible == nil && lastEmittedDate == nil

        if !isVisible {
            if lastEmittedVisible == true {
                lastEmittedVisible = false
                log(event: "hidden", date: date)
                cancelPendingOptionalWork(reason: "hidden")
                cancelPendingFloorPlan(reason: "hidden")
                controller.cancelAvailabilitySummary(date: date)
                guestIntelligenceStore.cancelScheduledLoad()
            }
            return
        }

        // Became visible or date changed.
        let event: String
        if visibilityChanged && (lastEmittedVisible ?? false) == false {
            event = "visible"
        } else if dateChanged {
            let old = lastEmittedDate ?? ""
            lastEmittedDate = date
            lastEmittedVisible = true
            log(event: "date_changed", date: date, oldDate: old)
            if old != date {
                cancelPendingOptionalWork(reason: "date_changed")
                cancelPendingFloorPlan(reason: "date_changed")
                controller.cancelAvailabilitySummary(date: old)
            }
            prepareIfReady(
                date: date,
                shouldDefer: shouldDefer,
                controller: controller,
                guestIntelligenceStore: guestIntelligenceStore,
                floorPlanStore: floorPlanStore,
                debounceFloorPlan: true,
                gateOptionalWork: true,
                lastStaffInteractionAt: lastStaffInteractionAt
            )
            return
        } else {
            event = "noop"
        }

        lastEmittedDate = date
        lastEmittedVisible = true
        log(event: event, date: date)

        if event == "noop" {
            guard !shouldDefer else { return }
            log(event: "noop_prepare_after_deferral", date: date)
        }
        prepareIfReady(
            date: date,
            shouldDefer: shouldDefer,
            controller: controller,
            guestIntelligenceStore: guestIntelligenceStore,
            floorPlanStore: floorPlanStore,
            debounceFloorPlan: false,
            gateOptionalWork: !isInitialVisibleLoad,
            lastStaffInteractionAt: lastStaffInteractionAt
        )
    }

    // MARK: - Coordination

    private func prepareIfReady(
        date: String,
        shouldDefer: Bool,
        controller: ReservationsController,
        guestIntelligenceStore: GuestIntelligenceStore,
        floorPlanStore: FloorPlanStore,
        debounceFloorPlan: Bool,
        gateOptionalWork: Bool,
        lastStaffInteractionAt: Date
    ) {
        if gateOptionalWork,
           !StaffInteractionIdleGate.isIdle(since: lastStaffInteractionAt) {
            scheduleOptionalWorkAfterIdle(
                date: date,
                shouldDefer: shouldDefer,
                controller: controller,
                guestIntelligenceStore: guestIntelligenceStore,
                floorPlanStore: floorPlanStore,
                lastStaffInteractionAt: lastStaffInteractionAt
            )
            return
        }

        cancelPendingOptionalWork(reason: "run_now")

        // Floor plan is canonical for Host Intelligence and must start as soon as Host
        // is visible — never wait for startup deferral, availability, or guest intel.
        scheduleFloorPlanIfNeeded(
            date: date,
            floorPlanStore: floorPlanStore,
            debounce: debounceFloorPlan
        )

        guard !shouldDefer else {
            log(event: "deferred", date: date, reason: "optional_startup_loads")
            return
        }

        // Availability: skip if already loading or fresh.
        if controller.isAvailabilitySummaryLoading(date: date) {
            log(event: "skip_availability", date: date, reason: "in_flight")
        } else if controller.availabilitySummary(for: date) != nil {
            log(event: "skip_availability", date: date, reason: "fresh")
        } else {
            log(event: "schedule_availability", date: date)
            ReservationAvailabilityFacade.prepare(
                controller: controller,
                date: date,
                reason: .hostBoardVisible
            )
        }

        // Guest intelligence: skip if already loading or fresh.
        if guestIntelligenceStore.isLoading(dateKey: date) {
            log(event: "skip_guest_intel", date: date, reason: "in_flight")
        } else if guestIntelligenceStore.hasDateSummaryLoaded(dateKey: date) {
            log(event: "skip_guest_intel", date: date, reason: "fresh")
        } else {
            log(event: "schedule_guest_intel", date: date)
            guestIntelligenceStore.scheduleLoad(dateKey: date)
        }
    }

    private func scheduleOptionalWorkAfterIdle(
        date: String,
        shouldDefer: Bool,
        controller: ReservationsController,
        guestIntelligenceStore: GuestIntelligenceStore,
        floorPlanStore: FloorPlanStore,
        lastStaffInteractionAt: Date
    ) {
        if let pendingOptionalWorkDate, pendingOptionalWorkDate != date {
            StaffInteractionIdleGate.trace(
                work: "host_optional_work",
                decision: "skip",
                reason: "date_changed",
                lastInteractionAt: lastStaffInteractionAt
            )
        }

        let delay = StaffInteractionIdleGate.remainingDelay(since: lastStaffInteractionAt)
        pendingOptionalWorkDate = date
        optionalWorkIdleTask?.cancel()
        StaffInteractionIdleGate.trace(
            work: "host_optional_work",
            decision: "schedule_after_idle",
            reason: "user_active",
            lastInteractionAt: lastStaffInteractionAt,
            delay: delay
        )

        optionalWorkIdleTask = Task { @MainActor [weak self, weak controller, weak guestIntelligenceStore, weak floorPlanStore] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled,
                  let self,
                  let controller,
                  let guestIntelligenceStore,
                  let floorPlanStore else {
                return
            }
            guard self.pendingOptionalWorkDate == date,
                  self.lastEmittedDate == date,
                  self.lastEmittedVisible == true,
                  StaffInteractionIdleGate.isIdle(since: lastStaffInteractionAt) else {
                StaffInteractionIdleGate.trace(
                    work: "host_optional_work",
                    decision: "skip",
                    reason: "user_active",
                    lastInteractionAt: lastStaffInteractionAt
                )
                return
            }

            self.pendingOptionalWorkDate = nil
            self.optionalWorkIdleTask = nil
            StaffInteractionIdleGate.trace(
                work: "host_optional_work",
                decision: "run",
                reason: "idle",
                lastInteractionAt: lastStaffInteractionAt
            )
            self.prepareIfReady(
                date: date,
                shouldDefer: shouldDefer,
                controller: controller,
                guestIntelligenceStore: guestIntelligenceStore,
                floorPlanStore: floorPlanStore,
                debounceFloorPlan: true,
                gateOptionalWork: false,
                lastStaffInteractionAt: lastStaffInteractionAt
            )
        }
    }

    private func scheduleFloorPlanIfNeeded(
        date: String,
        floorPlanStore: FloorPlanStore,
        debounce: Bool
    ) {
        if floorPlanStore.isLoading(date: date) {
            cancelPendingFloorPlan(reason: "in_flight")
            log(event: "skip_floor_plan", date: date, reason: "in_flight")
        } else if floorPlanStore.hasCachedLayout(for: date) {
            cancelPendingFloorPlan(reason: "fresh")
            log(event: "skip_floor_plan", date: date, reason: "fresh")
        } else if debounce {
            scheduleDebouncedFloorPlan(date: date, floorPlanStore: floorPlanStore)
        } else {
            cancelPendingFloorPlan(reason: "immediate_load")
            log(event: "schedule_floor_plan", date: date, reason: "host_visible")
            floorPlanStore.load(date: date)
        }
    }

    private func scheduleDebouncedFloorPlan(date: String, floorPlanStore: FloorPlanStore) {
        if let pendingFloorPlanDate, pendingFloorPlanDate != date {
            log(event: "cancel_floor_plan", date: pendingFloorPlanDate, reason: "date_changed")
        }

        pendingFloorPlanDate = date
        floorPlanDebounceTask?.cancel()
        log(event: "schedule_floor_plan", date: date, reason: "host_date_changed_debounced")

        floorPlanDebounceTask = Task { @MainActor [weak self, weak floorPlanStore] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled,
                  let self,
                  let floorPlanStore else {
                return
            }
            guard self.pendingFloorPlanDate == date,
                  self.lastEmittedDate == date,
                  self.lastEmittedVisible == true else {
                self.log(event: "skip_floor_plan", date: date, reason: "date_changed")
                return
            }

            self.pendingFloorPlanDate = nil
            self.floorPlanDebounceTask = nil
            self.log(event: "schedule_floor_plan", date: date, reason: "host_date_stable")
            floorPlanStore.load(date: date)
        }
    }

    private func cancelPendingFloorPlan(reason: String) {
        guard let pendingFloorPlanDate else { return }
        log(event: "cancel_floor_plan", date: pendingFloorPlanDate, reason: reason)
        self.pendingFloorPlanDate = nil
        floorPlanDebounceTask?.cancel()
        floorPlanDebounceTask = nil
    }

    private func cancelPendingOptionalWork(reason: String) {
        guard let pendingOptionalWorkDate else { return }
        log(event: "cancel_optional_work", date: pendingOptionalWorkDate, reason: reason)
        self.pendingOptionalWorkDate = nil
        optionalWorkIdleTask?.cancel()
        optionalWorkIdleTask = nil
    }

    // MARK: - Tracing

    private func log(
        event: String,
        date: String,
        oldDate: String? = nil,
        reason: String? = nil
    ) {
        #if DEBUG
        var line = "[HOST_LIFECYCLE] event=\(event) date=\(date)"
        if let old = oldDate { line += " old=\(old)" }
        if let reason { line += " reason=\(reason)" }
        HostBoardLifecycleCoordinator.logger.debug("\(line, privacy: .public)")
        #endif
    }
}
