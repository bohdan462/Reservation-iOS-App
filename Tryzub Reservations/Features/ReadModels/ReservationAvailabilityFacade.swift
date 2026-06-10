//
//  ReservationAvailabilityFacade.swift
//  Tryzub Reservations
//

import Foundation

// MARK: - Availability Facade

@MainActor
enum ReservationAvailabilityFacade {
    static func dayState(
        controller: ReservationsController,
        date: String,
        policy: DataFreshnessPolicy = .standard,
        now: Date = Date()
    ) -> AvailabilityDayState {
        let summary = controller.availabilitySummary(for: date)
        let availability = summary?.availability ?? controller.cachedRestaurantDayAvailability(date: date)
        let slots = summary?.slots ?? controller.cachedReservationSlots(date: date)
        let blocked = blockedSlotValues(controller: controller, date: date, summary: summary)

        let availabilityLoadedAt = availability != nil
            ? controller.restaurantDayAvailabilityLoadedAt(for: date)
            : nil
        let slotsLoadedAt = slots != nil
            ? controller.reservationSlotsLoadedAt(for: date)
            : nil
        let blockedLoadedAt = controller.hasBlockedSlotsCache(for: date)
            ? controller.blockedSlotsLoadedAt(for: date)
            : nil

        let isLoading = controller.isAvailabilitySummaryLoading(date: date)
        let errorMessage = controller.availabilitySummaryError(for: date)

        let availabilityFreshness = ScreenFreshnessState.from(
            loadedAt: availabilityLoadedAt,
            ttl: policy.availabilityTTL,
            now: now,
            isLoading: isLoading && availability == nil,
            unavailableReason: availability == nil && errorMessage != nil ? errorMessage : nil
        )
        let slotsFreshness = ScreenFreshnessState.from(
            loadedAt: slotsLoadedAt,
            ttl: policy.slotsTTL,
            now: now,
            isLoading: isLoading && slots == nil
        )
        let blockedFreshness = ScreenFreshnessState.from(
            loadedAt: blockedLoadedAt,
            ttl: policy.blockedSlotsTTL,
            now: now,
            isLoading: isLoading && !controller.hasBlockedSlotsCache(for: date) && slots != nil
        )

        let statusLine = slotsFreshness.statusLine(now: now)
            ?? availabilityFreshness.statusLine(now: now)

        return AvailabilityDayState(
            date: date,
            availability: availability,
            slots: slots,
            blockedSlotValues: blocked,
            availabilityFreshness: availabilityFreshness,
            slotsFreshness: slotsFreshness,
            blockedFreshness: blockedFreshness,
            isLoading: isLoading,
            errorMessage: errorMessage,
            statusLine: statusLine
        )
    }

    static func prepare(
        controller: ReservationsController,
        date: String,
        reason: AvailabilityLoadReason,
        force: Bool = false,
        policy: DataFreshnessPolicy = .standard,
        now: Date = Date(),
        caller: String? = nil
    ) {
        let state = dayState(controller: controller, date: date, policy: policy, now: now)

        if !force, state.hasFreshAvailabilityBundle {
            if let checkedAt = state.slotsFreshness.lastCheckedAt {
                FreshnessTrace.log(
                    key: "reservation_slots",
                    date: date,
                    action: "use_cached",
                    reason: reason.rawValue,
                    caller: caller,
                    age: now.timeIntervalSince(checkedAt)
                )
            } else {
                FreshnessTrace.log(
                    key: "reservation_slots",
                    date: date,
                    action: "use_cached",
                    reason: reason.rawValue,
                    caller: caller
                )
            }
            FreshnessTrace.log(
                key: "restaurant_day_availability",
                date: date,
                action: "skip",
                reason: "fresh"
            )
            return
        }

        if controller.isAvailabilitySummaryLoading(date: date) {
            FreshnessTrace.log(
                key: "reservation_slots",
                date: date,
                action: "skip",
                reason: "in_flight",
                caller: caller
            )
            return
        }

        if let checkedAt = state.slotsFreshness.lastCheckedAt {
            FreshnessTrace.log(
                key: "reservation_slots",
                date: date,
                action: "fetch",
                reason: force ? "manual_refresh" : "stale",
                caller: caller,
                age: now.timeIntervalSince(checkedAt)
            )
        } else {
            FreshnessTrace.log(
                key: "reservation_slots",
                date: date,
                action: "fetch",
                reason: reason.rawValue,
                caller: caller
            )
        }

        if date == controller.hostBoardSelectedDateKey {
            controller.ensureAvailabilitySummary(date: date, force: force)
        } else {
            startDirectLoad(controller: controller, date: date)
        }
    }

    static func forceRefresh(
        controller: ReservationsController,
        date: String
    ) {
        prepare(
            controller: controller,
            date: date,
            reason: .manualRefresh,
            force: true
        )
    }

    // MARK: - Private

    private static func blockedSlotValues(
        controller: ReservationsController,
        date: String,
        summary: ReservationAvailabilitySummary?
    ) -> Set<String> {
        if let summary {
            return Set(summary.blockedSlots.map { shortSlotValue($0.slotTime) })
        }
        guard let blocked = controller.cachedRestaurantBlockedSlots(date: date) else { return [] }
        return Set(blocked.data.map { shortSlotValue($0.slotTime) })
    }

    private static func shortSlotValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5 else { return trimmed }
        return String(trimmed.prefix(5))
    }

    private static func startDirectLoad(controller: ReservationsController, date: String) {
        Task {
            do {
                let availability = try await controller.loadRestaurantDayAvailability(date: date)
                guard !Task.isCancelled else { return }

                if !availability.isOpen {
                    _ = try? await controller.loadRestaurantBlockedSlots(date: date)
                    return
                }

                _ = try? await controller.loadReservationSlots(date: date)
                _ = try? await controller.loadRestaurantBlockedSlots(date: date)
            } catch {
                guard !error.isCancellationLike else { return }
            }
        }
    }
}
