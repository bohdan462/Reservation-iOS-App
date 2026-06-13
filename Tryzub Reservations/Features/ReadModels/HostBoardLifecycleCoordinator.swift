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
        controller: ReservationsController,
        guestIntelligenceStore: GuestIntelligenceStore,
        floorPlanStore: FloorPlanStore
    ) {
        let visibilityChanged = lastEmittedVisible != isVisible
        let dateChanged = lastEmittedDate != date && lastEmittedDate != nil

        if !isVisible {
            if lastEmittedVisible == true {
                lastEmittedVisible = false
                log(event: "hidden", date: date)
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
            prepareIfReady(
                date: date,
                shouldDefer: shouldDefer,
                controller: controller,
                guestIntelligenceStore: guestIntelligenceStore,
                floorPlanStore: floorPlanStore
            )
            return
        } else {
            event = "noop"
        }

        lastEmittedDate = date
        lastEmittedVisible = true
        log(event: event, date: date)

        if event == "noop" { return }
        prepareIfReady(
            date: date,
            shouldDefer: shouldDefer,
            controller: controller,
            guestIntelligenceStore: guestIntelligenceStore,
            floorPlanStore: floorPlanStore
        )
    }

    // MARK: - Coordination

    private func prepareIfReady(
        date: String,
        shouldDefer: Bool,
        controller: ReservationsController,
        guestIntelligenceStore: GuestIntelligenceStore,
        floorPlanStore: FloorPlanStore
    ) {
        // Floor plan is canonical for Host Intelligence and must start as soon as Host
        // is visible — never wait for startup deferral, availability, or guest intel.
        scheduleFloorPlanIfNeeded(date: date, floorPlanStore: floorPlanStore)

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

    private func scheduleFloorPlanIfNeeded(date: String, floorPlanStore: FloorPlanStore) {
        if floorPlanStore.isLoading(date: date) {
            log(event: "skip_floor_plan", date: date, reason: "in_flight")
        } else if floorPlanStore.hasCachedLayout(for: date) {
            log(event: "skip_floor_plan", date: date, reason: "fresh")
        } else {
            log(event: "schedule_floor_plan", date: date, reason: "host_visible")
            floorPlanStore.load(date: date)
        }
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
