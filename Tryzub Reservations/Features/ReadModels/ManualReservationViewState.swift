//
//  ManualReservationViewState.swift
//  Tryzub Reservations
//

import Foundation

struct ReservationSlotState: Equatable, Identifiable {
    let id: String
    let displayTime: String
    let value: String
    let isBlocked: Bool
}

struct ManualReservationFormViewState: Equatable {
    let selectedDate: Date
    let selectedDateKey: String
    let availableTimes: [ReservationSlotState]
    let availabilityFreshness: ScreenFreshnessState
    let slotsFreshness: ScreenFreshnessState
    let isLoadingTimes: Bool
    let statusLine: String?
    let canSubmit: Bool
    let warning: String?
    let isClosed: Bool
    let slotsError: String?
}

@MainActor
final class ManualReservationFacade: ObservableObject {
    @Published private(set) var viewState: ManualReservationFormViewState?
    @Published private(set) var dayAvailability: RestaurantDayAvailabilityDTO?
    @Published private(set) var suggestedSlots: ReservationSlotsResponseDTO?
    @Published private(set) var blockedSlotValues: Set<String> = []
    @Published private(set) var isLoadingPublicSlots = false
    @Published private(set) var publicSlotsError: String?

    private var preparedDateKey: String?
    private var loadingDateKey: String?
    private var lastViewStateKey: String?
    private var loadTask: Task<Void, Never>?

    func prepare(
        date: Date,
        controller: ReservationsController,
        canSubmit: Bool,
        blockingWarning: String?,
        force: Bool = false
    ) {
        let dateKey = date.reservationDateString()
        let now = Date()
        let availabilityState = ReservationAvailabilityFacade.dayState(
            controller: controller,
            date: dateKey,
            now: now
        )

        applyAvailabilityState(availabilityState)

        FacadeTrace.event(
            surface: "manual_add",
            name: "prepare",
            extra: "date=\(dateKey) availability=\(freshnessLabel(availabilityState.availabilityFreshness)) slots=\(freshnessLabel(availabilityState.slotsFreshness))"
        )

        let viewStateKey = [
            dateKey,
            freshnessLabel(availabilityState.availabilityFreshness),
            freshnessLabel(availabilityState.slotsFreshness),
            "\(canSubmit)",
            blockingWarning ?? "",
            "\(availabilityState.slots?.slots.count ?? -1)"
        ].joined(separator: "|")
        if lastViewStateKey != viewStateKey {
            lastViewStateKey = viewStateKey
            viewState = ManualReservationViewStateBuilder.build(
                date: date,
                availabilityState: availabilityState,
                canSubmit: canSubmit,
                blockingWarning: blockingWarning,
                slotsError: publicSlotsError
            )
            FormTrace.event(
                surface: "manual_add",
                name: "view_state_rebuild",
                extra: "reason=prepare date=\(dateKey)"
            )
        }

        if !force, availabilityState.hasFreshAvailabilityBundle {
            loadingDateKey = nil
            traceLoadedState(availabilityState)
            if let checkedAt = availabilityState.slotsFreshness.lastCheckedAt {
                FreshnessTrace.log(
                    key: "reservation_slots",
                    date: dateKey,
                    action: "use_cached",
                    reason: AvailabilityLoadReason.manualAddOpen.rawValue,
                    age: now.timeIntervalSince(checkedAt)
                )
            } else {
                FreshnessTrace.log(
                    key: "reservation_slots",
                    date: dateKey,
                    action: "use_cached",
                    reason: AvailabilityLoadReason.manualAddOpen.rawValue
                )
            }
            preparedDateKey = dateKey
            return
        }

        if controller.isAvailabilitySummaryLoading(date: dateKey) {
            beginVisibleLoad(dateKey: dateKey)
            FreshnessTrace.log(
                key: "reservation_slots",
                date: dateKey,
                action: "skip",
                reason: "in_flight",
                caller: AvailabilityLoadReason.manualAddOpen.rawValue
            )
            preparedDateKey = dateKey
            observeLoadCompletion(dateKey: dateKey, controller: controller)
            return
        }

        guard force || preparedDateKey != dateKey else { return }

        preparedDateKey = dateKey
        beginVisibleLoad(dateKey: dateKey)
        ReservationAvailabilityFacade.prepare(
            controller: controller,
            date: dateKey,
            reason: .manualAddOpen,
            force: force,
            caller: AvailabilityLoadReason.manualAddOpen.rawValue
        )

        observeLoadCompletion(dateKey: dateKey, controller: controller)
    }

    func forceRefresh(
        date: Date,
        controller: ReservationsController,
        canSubmit: Bool,
        blockingWarning: String?
    ) {
        prepare(
            date: date,
            controller: controller,
            canSubmit: canSubmit,
            blockingWarning: blockingWarning,
            force: true
        )
    }

    func cancelLoads() {
        loadTask?.cancel()
        loadTask = nil
    }

    // MARK: - Private

    private func applyAvailabilityState(_ state: AvailabilityDayState) {
        dayAvailability = state.availability
        suggestedSlots = state.slots
        blockedSlotValues = state.blockedSlotValues
        isLoadingPublicSlots = (state.isLoading || loadingDateKey == state.date)
            && state.slots == nil
            && state.availability?.isOpen != false
    }

    private func observeLoadCompletion(dateKey: String, controller: ReservationsController) {
        loadTask?.cancel()
        loadTask = Task {
            var attempts = 0
            while !Task.isCancelled {
                guard preparedDateKey == dateKey else {
                    WorkflowCleanupTrace.log(
                        "MANUAL_TIME_SLOT_TRACE",
                        fields: [
                            "date": dateKey,
                            "state": "ignored",
                            "reason": "selected_date_changed"
                        ]
                    )
                    break
                }

                let state = ReservationAvailabilityFacade.dayState(
                    controller: controller,
                    date: dateKey
                )
                applyAvailabilityState(state)

                if hasConfirmedSlotResult(state) {
                    publicSlotsError = state.errorMessage
                    loadingDateKey = nil
                    applyAvailabilityState(state)
                    traceLoadedState(state)
                    break
                }

                if !state.isLoading, attempts >= 60 {
                    publicSlotsError = "Could not verify open times for this date."
                    loadingDateKey = nil
                    isLoadingPublicSlots = false
                    break
                }

                attempts += 1
                try? await Task.sleep(for: .milliseconds(200))
            }
            loadTask = nil
        }
    }

    private func beginVisibleLoad(dateKey: String) {
        if let loadingDateKey, loadingDateKey != dateKey {
            WorkflowCleanupTrace.log(
                "MANUAL_TIME_SLOT_TRACE",
                fields: [
                    "date": loadingDateKey,
                    "state": "ignored",
                    "reason": "selected_date_changed"
                ]
            )
        }
        loadingDateKey = dateKey
        publicSlotsError = nil
        isLoadingPublicSlots = true
        WorkflowCleanupTrace.log(
            "MANUAL_TIME_SLOT_TRACE",
            fields: [
                "date": dateKey,
                "state": "loading",
                "source": "cache_or_network"
            ]
        )
    }

    private func hasConfirmedSlotResult(_ state: AvailabilityDayState) -> Bool {
        state.slots != nil || state.availability?.isOpen == false || state.errorMessage != nil
    }

    private func traceLoadedState(_ state: AvailabilityDayState) {
        if let slots = state.slots {
            if slots.slots.isEmpty {
                WorkflowCleanupTrace.log(
                    "MANUAL_TIME_SLOT_TRACE",
                    fields: [
                        "date": state.date,
                        "state": "empty",
                        "reason": "backend_confirmed_empty"
                    ]
                )
            } else {
                WorkflowCleanupTrace.log(
                    "MANUAL_TIME_SLOT_TRACE",
                    fields: [
                        "date": state.date,
                        "state": "loaded",
                        "slots": "\(slots.slots.count)",
                        "source": "restaurant_setup"
                    ]
                )
            }
        } else if state.availability?.isOpen == false {
            WorkflowCleanupTrace.log(
                "MANUAL_TIME_SLOT_TRACE",
                fields: [
                    "date": state.date,
                    "state": "empty",
                    "reason": "backend_confirmed_empty"
                ]
            )
        }
    }

    private func freshnessLabel(_ freshness: ScreenFreshnessState) -> String {
        switch freshness {
        case .fresh: return "fresh"
        case .stale: return "stale"
        case .loading: return "loading"
        case .unavailable: return "unavailable"
        }
    }
}

enum ManualReservationViewStateBuilder {
    static func build(
        date: Date,
        availabilityState: AvailabilityDayState,
        canSubmit: Bool,
        blockingWarning: String?,
        slotsError: String?
    ) -> ManualReservationFormViewState {
        let slotStates = (availabilityState.slots?.slots ?? []).map { slot in
            let value = shortSlotValue(slot.value)
            return ReservationSlotState(
                id: value,
                displayTime: slot.label,
                value: value,
                isBlocked: availabilityState.blockedSlotValues.contains(value)
            )
        }

        return ManualReservationFormViewState(
            selectedDate: date,
            selectedDateKey: date.reservationDateString(),
            availableTimes: slotStates,
            availabilityFreshness: availabilityState.availabilityFreshness,
            slotsFreshness: availabilityState.slotsFreshness,
            isLoadingTimes: availabilityState.isLoading && !availabilityState.hasUsableSlots,
            statusLine: availabilityState.statusLine,
            canSubmit: canSubmit && blockingWarning == nil,
            warning: blockingWarning ?? slotsError,
            isClosed: availabilityState.isClosed,
            slotsError: slotsError
        )
    }

    private static func shortSlotValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5 else { return trimmed }
        return String(trimmed.prefix(5))
    }
}
