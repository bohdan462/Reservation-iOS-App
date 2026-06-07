//
//  RestaurantSettingsStore.swift
//  Tryzub Reservations
//

import SwiftUI

@MainActor
final class RestaurantSettingsStore: ObservableObject {
    // MARK: - Published State

    @Published private(set) var setup: RestaurantSetup = .default
    @Published private(set) var weeklyHours: RestaurantHoursDTO?
    @Published private(set) var selectedDateAvailability: RestaurantDayAvailabilityDTO?
    @Published private(set) var analyticsSummary: ReservationAnalyticsSummaryDTO?

    @Published var selectedAvailabilityDate = Date()
    @Published private(set) var selectedDateSlots: ReservationSlotsResponseDTO?
    @Published private(set) var selectedDateBlockedSlots: [RestaurantBlockedSlotDTO] = []

    @Published private(set) var setupLoading = false
    @Published private(set) var setupSaving = false
    @Published private(set) var setupError: String?

    @Published private(set) var weeklyHoursLoading = false
    @Published private(set) var weeklyHoursSaving = false
    @Published private(set) var weeklyHoursError: String?

    @Published private(set) var dayAvailabilityLoading = false
    @Published private(set) var dayAvailabilitySaving = false
    @Published private(set) var dayAvailabilityError: String?

    @Published private(set) var blockedSlotsLoading = false
    @Published private(set) var blockedSlotsSaving = false
    @Published private(set) var blockedSlotsError: String?

    @Published private(set) var slotPreviewLoading = false
    @Published private(set) var slotPreviewError: String?

    @Published private(set) var analyticsLoading = false
    @Published private(set) var analyticsError: String?

    // MARK: - Dependencies

    private let apiClient: any ReservationsAPIClientProtocol
    private let dateOperationsFreshnessInterval: TimeInterval = 120
    private var availabilityByDate: [String: RestaurantDayAvailabilityDTO] = [:]
    private var availabilityLoadedAtByDate: [String: Date] = [:]
    private var slotsByDate: [String: ReservationSlotsResponseDTO] = [:]
    private var slotsLoadedAtByDate: [String: Date] = [:]
    private var blockedSlotsByDate: [String: RestaurantBlockedSlotsResponseDTO] = [:]
    private var blockedSlotsLoadedAtByDate: [String: Date] = [:]
    private var dateOperationsLoadedAtByDate: [String: Date] = [:]

    // MARK: - Lifecycle

    init(apiClient: any ReservationsAPIClientProtocol) {
        self.apiClient = apiClient
    }

    // MARK: - Setup

    @discardableResult
    func loadRestaurantSetup() async throws -> RestaurantSetup {
        guard !setupLoading else { return setup }

        setupLoading = true
        setupError = nil
        defer { setupLoading = false }

        do {
            let dto = try await apiClient.fetchRestaurantSetup(reason: .restaurantSetup)
            let loadedSetup = RestaurantSetup(dto: dto)
            setup = loadedSetup
            return loadedSetup
        } catch {
            setupError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func saveRestaurantSetup() async throws -> RestaurantSetup {
        try await saveRestaurantSetup(
            request: RestaurantSetupUpdateRequest(
                businessName: setup.businessName,
                timezone: setup.timezone,
                defaultPartySize: setup.defaultPartySize,
                bookingWindowDays: setup.bookingWindowDays,
                slotIntervalMinutes: setup.slotIntervalMinutes,
                maxOnlinePartySize: setup.maxOnlinePartySize,
                largePartyReviewThreshold: setup.largePartyReviewThreshold,
                sameDayBookingEnabled: setup.sameDayBookingEnabled,
                minimumLeadTimeMinutes: setup.minimumLeadTimeMinutes,
                callInPlaceholderEmail: setup.callInPlaceholderEmail,
                fromEmail: setup.fromEmail,
                replyToEmail: setup.replyToEmail
            )
        )
    }

    @discardableResult
    func saveRestaurantSetup(request: RestaurantSetupUpdateRequest) async throws -> RestaurantSetup {
        guard !setupSaving else { throw SettingsValidationError(message: "Another settings action is already in progress.") }

        setupSaving = true
        setupError = nil
        defer { setupSaving = false }

        do {
            let dto = try await apiClient.updateRestaurantSetup(request, reason: .restaurantSetupPatch)
            let savedSetup = RestaurantSetup(dto: dto)
            setup = savedSetup
            return savedSetup
        } catch {
            setupError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Weekly Hours

    @discardableResult
    func loadRestaurantHours() async throws -> RestaurantHoursDTO {
        guard !weeklyHoursLoading else {
            if let weeklyHours { return weeklyHours }
            throw SettingsValidationError(message: "Restaurant hours are already loading.")
        }

        weeklyHoursLoading = true
        weeklyHoursError = nil
        defer { weeklyHoursLoading = false }

        do {
            let loadedHours = try await apiClient.fetchRestaurantHours(
                from: nil,
                to: nil,
                reason: .restaurantHours
            )
            weeklyHours = loadedHours
            return loadedHours
        } catch {
            weeklyHoursError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func saveRestaurantHours() async throws -> RestaurantHoursDTO {
        let request = WeeklyHoursUpdateRequest(
            weeklyHours: (weeklyHours?.weeklyHours ?? []).map {
                WeeklyHourUpdateDTO(
                    weekday: $0.weekday,
                    isOpen: $0.isOpen,
                    openTime: $0.openTime,
                    closeTime: $0.closeTime
                )
            }
        )
        return try await saveRestaurantHours(request: request)
    }

    @discardableResult
    func saveRestaurantHours(request: WeeklyHoursUpdateRequest) async throws -> RestaurantHoursDTO {
        guard !weeklyHoursSaving else { throw SettingsValidationError(message: "Weekly hours are already saving.") }

        weeklyHoursSaving = true
        weeklyHoursError = nil
        defer { weeklyHoursSaving = false }

        do {
            _ = try await apiClient.updateRestaurantHours(request, reason: .restaurantHoursPatch)
            let refreshedHours = try await apiClient.fetchRestaurantHours(
                from: nil,
                to: nil,
                reason: .restaurantHours
            )
            weeklyHours = refreshedHours
            await refreshDateOperations(date: selectedAvailabilityDate.reservationDateString(), force: true)
            return refreshedHours
        } catch {
            weeklyHoursError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Day Availability

    @discardableResult
    func loadDayAvailability(date: String, force: Bool = false) async throws -> RestaurantDayAvailabilityDTO {
        selectedAvailabilityDate = Self.date(from: date) ?? selectedAvailabilityDate
        if !force,
           let cached = availabilityByDate[date],
           isFresh(availabilityLoadedAtByDate[date]) {
            selectedDateAvailability = cached
            return cached
        }

        guard !dayAvailabilityLoading else {
            if let selectedDateAvailability { return selectedDateAvailability }
            throw SettingsValidationError(message: "Availability is already loading.")
        }

        dayAvailabilityLoading = true
        dayAvailabilityError = nil
        defer { dayAvailabilityLoading = false }

        do {
            let availability = try await apiClient.fetchRestaurantDayAvailability(
                date: date,
                reason: .restaurantDayAvailability
            )
            selectedDateAvailability = availability
            availabilityByDate[date] = availability
            availabilityLoadedAtByDate[date] = Date()
            return availability
        } catch {
            if !error.isCancellationLike {
                dayAvailabilityError = error.localizedDescription
            }
            throw error
        }
    }

    @discardableResult
    func saveDayAvailability(date: String) async throws -> RestaurantDayAvailabilityDTO {
        guard let availability = selectedDateAvailability else {
            throw SettingsValidationError(message: "Availability has not loaded yet.")
        }

        return try await saveDayAvailability(
            date: date,
            request: RestaurantDayAvailabilityUpdateRequest(
                isOpen: availability.isOpen,
                openTime: availability.openTime,
                closeTime: availability.closeTime,
                reason: availability.reason
            )
        )
    }

    @discardableResult
    func saveDayAvailability(
        date: String,
        request: RestaurantDayAvailabilityUpdateRequest
    ) async throws -> RestaurantDayAvailabilityDTO {
        guard !dayAvailabilitySaving else { throw SettingsValidationError(message: "Availability is already saving.") }

        dayAvailabilitySaving = true
        dayAvailabilityError = nil
        defer { dayAvailabilitySaving = false }

        do {
            let saved = try await apiClient.updateRestaurantDayAvailability(
                date: date,
                request: request,
                reason: .restaurantDayAvailabilityPatch
            )
            selectedDateAvailability = saved
            availabilityByDate[date] = saved
            availabilityLoadedAtByDate[date] = Date()
            _ = try? await loadReservationSlots(date: date, force: true)
            _ = try? await loadBlockedSlots(date: date, force: true)
            return saved
        } catch {
            dayAvailabilityError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Slots

    @discardableResult
    func loadReservationSlots(date: String, force: Bool = false) async throws -> ReservationSlotsResponseDTO {
        if !force,
           let cached = slotsByDate[date],
           isFresh(slotsLoadedAtByDate[date]) {
            selectedDateSlots = cached
            return cached
        }

        slotPreviewLoading = true
        slotPreviewError = nil
        defer { slotPreviewLoading = false }

        do {
            let slots = try await apiClient.fetchReservationSlots(date: date, reason: .reservationSlots)
            selectedDateSlots = slots
            slotsByDate[date] = slots
            slotsLoadedAtByDate[date] = Date()
            return slots
        } catch {
            // A cancelled request (tab switch / re-entry) is not a real failure;
            // keep the previous preview instead of flashing a scary error.
            if !error.isCancellationLike {
                slotPreviewError = error.localizedDescription
            }
            throw error
        }
    }

    // MARK: - Blocked Slots

    @discardableResult
    func loadBlockedSlots(date: String, force: Bool = false) async throws -> RestaurantBlockedSlotsResponseDTO {
        if !force,
           let cached = blockedSlotsByDate[date],
           isFresh(blockedSlotsLoadedAtByDate[date]) {
            selectedDateBlockedSlots = cached.data
            return cached
        }

        blockedSlotsLoading = true
        blockedSlotsError = nil
        defer { blockedSlotsLoading = false }

        do {
            let response = try await apiClient.fetchRestaurantBlockedSlots(
                date: date,
                reason: .restaurantBlockedSlots
            )
            selectedDateBlockedSlots = response.data
            blockedSlotsByDate[date] = response
            blockedSlotsLoadedAtByDate[date] = Date()
            return response
        } catch {
            if !error.isCancellationLike {
                blockedSlotsError = error.localizedDescription
            }
            throw error
        }
    }

    func blockSlots(date: String, slots: [String], reason: String?) async throws {
        guard !slots.isEmpty else {
            throw SettingsValidationError(message: "Choose at least one public slot to block.")
        }
        guard !blockedSlotsSaving else { throw SettingsValidationError(message: "Blocked slots are already saving.") }

        blockedSlotsSaving = true
        blockedSlotsError = nil
        defer { blockedSlotsSaving = false }

        do {
            _ = try await apiClient.createRestaurantBlockedSlots(
                date: date,
                slots: slots,
                reason: reason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
                requestReason: .restaurantBlockedSlotsCreate
            )
            _ = try await loadBlockedSlots(date: date, force: true)
            _ = try await loadReservationSlots(date: date, force: true)
        } catch {
            blockedSlotsError = error.localizedDescription
            throw error
        }
    }

    func unblockSlots(date: String, slots: [String]) async throws {
        guard !slots.isEmpty else {
            throw SettingsValidationError(message: "Choose at least one blocked slot to unblock.")
        }
        guard !blockedSlotsSaving else { throw SettingsValidationError(message: "Blocked slots are already saving.") }

        blockedSlotsSaving = true
        blockedSlotsError = nil
        defer { blockedSlotsSaving = false }

        do {
            _ = try await apiClient.deleteRestaurantBlockedSlots(
                date: date,
                slots: slots,
                reason: .restaurantBlockedSlotsDelete
            )
            _ = try await loadBlockedSlots(date: date, force: true)
            _ = try await loadReservationSlots(date: date, force: true)
        } catch {
            blockedSlotsError = error.localizedDescription
            throw error
        }
    }

    func unblockAllSlots(date: String) async throws {
        guard !blockedSlotsSaving else { throw SettingsValidationError(message: "Blocked slots are already saving.") }

        blockedSlotsSaving = true
        blockedSlotsError = nil
        defer { blockedSlotsSaving = false }

        do {
            _ = try await apiClient.deleteAllRestaurantBlockedSlots(
                date: date,
                reason: .restaurantBlockedSlotsDelete
            )
            _ = try await loadBlockedSlots(date: date, force: true)
            _ = try await loadReservationSlots(date: date, force: true)
        } catch {
            blockedSlotsError = error.localizedDescription
            throw error
        }
    }

    func refreshDateOperations(date: String, force: Bool = false) async {
        selectedAvailabilityDate = Self.date(from: date) ?? selectedAvailabilityDate
        _ = try? await loadDayAvailability(date: date, force: force)
        _ = try? await loadReservationSlots(date: date, force: force)
        _ = try? await loadBlockedSlots(date: date, force: force)
        dateOperationsLoadedAtByDate[date] = Date()
    }

    // Store-owned loading: the controller owns the request lifecycle so SwiftUI
    // view re-computation cannot cancel an in-flight load and leave spinners stuck.
    // The view only asks the store to ensure the date is loaded.
    private var dateOperationsTask: Task<Void, Never>?
    private var loadedDateOperationsKey: String?

    func ensureDateOperations(date: String, force: Bool = false) {
        if !force,
           loadedDateOperationsKey == date,
           dateOperationsTask == nil,
           isFresh(dateOperationsLoadedAtByDate[date]) {
            return
        }
        dateOperationsTask?.cancel()
        dateOperationsTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshDateOperations(date: date, force: force)
            if !Task.isCancelled {
                self.loadedDateOperationsKey = date
            }
            self.dateOperationsTask = nil
        }
    }

    // MARK: - Analytics

    @discardableResult
    func loadReservationAnalyticsSummary(from: String?, to: String?) async throws -> ReservationAnalyticsSummaryDTO {
        guard !analyticsLoading else {
            if let analyticsSummary { return analyticsSummary }
            throw SettingsValidationError(message: "Analytics are already loading.")
        }

        analyticsLoading = true
        analyticsError = nil
        defer { analyticsLoading = false }

        do {
            let summary = try await apiClient.fetchReservationAnalyticsSummary(
                from: from,
                to: to,
                reason: .reservationAnalyticsSummary
            )
            analyticsSummary = summary
            return summary
        } catch {
            analyticsError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Private Helpers

    private func isFresh(_ loadedAt: Date?) -> Bool {
        guard let loadedAt else { return false }
        return Date().timeIntervalSince(loadedAt) < dateOperationsFreshnessInterval
    }

    private static func date(from value: String) -> Date? {
        ReservationFormatters.reservationDateKey.date(from: value)
    }
}

// MARK: - Restaurant Setup UI Helpers

extension RestaurantSetup {
    func suggestedServiceDates(
        starting startDate: Date = Date(),
        count: Int = 10,
        calendar: Calendar = .current
    ) -> [Date] {
        let cappedCount = min(max(count, 1), max(bookingWindowDays, 1))
        return (0..<cappedCount).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startDate)
                .map { calendar.startOfDay(for: $0) }
        }
    }

    func defaultServiceSlot(now: Date = Date(), calendar: Calendar = .current) -> (date: Date, time: Date, partySize: Int) {
        let serviceDate = calendar.startOfDay(for: now)
        let time = suggestedTimes(for: serviceDate, now: now, calendar: calendar).first
            ?? calendar.date(bySettingHour: 18, minute: 0, second: 0, of: serviceDate)
            ?? serviceDate

        return (serviceDate, time, max(defaultPartySize, 1))
    }

    func suggestedTimes(
        for serviceDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Date] {
        let interval = max(slotIntervalMinutes, 15)
        let serviceMinutes = stride(from: 16 * 60 + 30, through: 21 * 60 + 30, by: interval)
        return serviceMinutes.compactMap { minutes in
            guard let slot = calendar.date(
                bySettingHour: minutes / 60,
                minute: minutes % 60,
                second: 0,
                of: serviceDate
            ) else {
                return nil
            }

            if calendar.isDate(slot, inSameDayAs: now),
               slot.timeIntervalSince(now) < TimeInterval(minimumLeadTimeMinutes * 60) {
                return nil
            }

            return slot
        }
    }

    var formattedUpdatedAt: String? {
        guard let updatedAt,
              let date = ReservationFormatters.serverDateTime.date(from: updatedAt) else {
            return updatedAt
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
// MARK: - Restaurant Settings

struct RestaurantSettingsView: View {
    @EnvironmentObject private var controller: ReservationsController
    @ObservedObject var settingsStore: RestaurantSettingsStore

    @State private var draft = RestaurantSetupDraft(setup: .default)
    @State private var savedDraft = RestaurantSetupDraft(setup: .default)
    @State private var setup = RestaurantSetup.default
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var didLoadInitialDraft = false
    @AppStorage(ReservationTableOptionsStore.storageKey) private var tableOptionsRawValue = ReservationTableOptionsStore.defaultRawValue

    private var hasChanges: Bool {
        draft != savedDraft
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let errorMessage {
                    SettingsNoticeCard(message: errorMessage, tint: .red)
                } else if let successMessage {
                    SettingsNoticeCard(message: successMessage, tint: .green, systemImage: "checkmark.circle")
                }

                RestaurantSettingsHeader(setup: setup)

                SettingsCard(title: "Restaurant Identity", systemImage: "building.2") {
                    SettingsTextField(title: "Business name", text: $draft.businessName)
                        .textInputAutocapitalization(.words)

                    SettingsTextField(title: "Timezone", text: $draft.timezone)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SettingsHelperText("Use an IANA timezone like America/Chicago.")
                }

                SettingsCard(title: "Reservation Policy", systemImage: "calendar") {
                    SettingsNumberField(title: "Default party size", text: $draft.defaultPartySize)
                    SettingsNumberField(title: "Booking window days", text: $draft.bookingWindowDays)
                    SettingsNumberField(title: "Max online party size", text: $draft.maxOnlinePartySize)
                    SettingsNumberField(title: "Large party review threshold", text: $draft.largePartyReviewThreshold)
                    SettingsNumberField(title: "Minimum lead time minutes", text: $draft.minimumLeadTimeMinutes)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Slot interval")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        Picker("Slot interval", selection: $draft.slotIntervalMinutes) {
                            ForEach(["15", "30", "45", "60"], id: \.self) { value in
                                Text("\(value) min").tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Toggle("Same-day booking enabled", isOn: $draft.sameDayBookingEnabled)
                        .font(.subheadline.weight(.medium))

                    SettingsHelperText("Booking window is how far ahead guests can book. Large party threshold marks reservations for review. Minimum lead time controls how soon before service online bookings are allowed.")
                }

                SettingsCard(title: "Table Names", systemImage: "table.furniture") {
                    SettingsTextEditor(
                        title: "iOS-local table list",
                        text: $tableOptionsRawValue,
                        minHeight: 92
                    )
                    SettingsHelperText("Temporary local list for Assign Table chips. Use one table per line or comma-separated names. Backend restaurant setup does not yet expose table_names.")
                }

                SettingsCard(title: "Email Identity", systemImage: "envelope") {
                    SettingsTextField(title: "Call-in placeholder email", text: $draft.callInPlaceholderEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SettingsTextField(title: "From email", text: $draft.fromEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SettingsTextField(title: "Reply-to email", text: $draft.replyToEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SettingsHelperText("Email sending setup is handled separately after domain/DNS confirmation.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, hasChanges ? 112 : 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Restaurant Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await load(forceDraftUpdate: true)
                    }
                } label: {
                    if settingsStore.setupLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(settingsStore.setupLoading || isSaving)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if hasChanges {
                SettingsSaveBar(
                    title: "Save",
                    isSaving: isSaving || settingsStore.setupSaving,
                    onCancel: resetDraft,
                    onSave: { Task { await save() } }
                )
            }
        }
        .task {
            await load(forceDraftUpdate: !didLoadInitialDraft)
        }
    }

    private func load(forceDraftUpdate: Bool) async {
        errorMessage = nil
        successMessage = nil
        do {
            let loadedSetup = try await settingsStore.loadRestaurantSetup()
            setup = loadedSetup
            if forceDraftUpdate || !didLoadInitialDraft {
                draft = RestaurantSetupDraft(setup: loadedSetup)
                savedDraft = draft
                didLoadInitialDraft = true
            }
        } catch {
            errorMessage = error.localizedDescription
            setup = settingsStore.setup
            if !didLoadInitialDraft {
                draft = RestaurantSetupDraft(setup: settingsStore.setup)
                savedDraft = draft
                didLoadInitialDraft = true
            }
        }
    }

    private func resetDraft() {
        draft = savedDraft
        errorMessage = nil
        successMessage = nil
        ReservationHaptics.selection()
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        successMessage = nil

        defer {
            isSaving = false
        }

        do {
            let request = try draft.updateRequest()
            let saved = try await settingsStore.saveRestaurantSetup(request: request)
            _ = try? await controller.loadRestaurantSetup(force: true)
            setup = saved
            draft = RestaurantSetupDraft(setup: saved)
            savedDraft = draft
            successMessage = "Restaurant settings saved."
            ReservationHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
            ReservationHaptics.warning()
        }
    }
}

// MARK: - Today Availability

struct TodayAvailabilityView: View {
    @ObservedObject var settingsStore: RestaurantSettingsStore

    @State private var availability: RestaurantDayAvailabilityDTO?
    @State private var isOpen = true
    @State private var openTime = "16:30"
    @State private var closeTime = "21:30"
    @State private var reason = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let dateKey = Date.reservationDateString()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let errorMessage {
                    SettingsNoticeCard(message: errorMessage, tint: .red)
                }

                SettingsCard(title: "Today", systemImage: "calendar") {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(todayDisplayText)
                                .font(.title3.weight(.semibold))
                            Text(dateKey)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        SettingsStatusBadge(title: DayAvailabilityPresenter.sourceTitle(availability?.source), tint: .secondary)
                        SettingsStatusBadge(title: isOpen ? "Open" : "Closed", tint: isOpen ? .green : .red)
                    }

                    SettingsKeyValueGrid(items: [
                        ("Hours", isOpen ? "\(openTime)-\(closeTime)" : "Closed"),
                        ("Last bookable", isOpen ? (WeeklyHoursPresenter.lastBookableText(closeTime: closeTime) ?? "-") : "Closed")
                    ])
                }

                SettingsCard(title: "Controls", systemImage: "slider.horizontal.3") {
                    Toggle("Accepting reservations today", isOn: $isOpen)
                        .font(.subheadline.weight(.medium))

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            SettingsTextField(title: "Open time", text: $openTime, prompt: "16:30")
                                .disabled(!isOpen)
                                .opacity(isOpen ? 1 : 0.45)

                            SettingsTextField(title: "Close time", text: $closeTime, prompt: "21:30")
                                .disabled(!isOpen)
                                .opacity(isOpen ? 1 : 0.45)
                        }

                        VStack(spacing: 10) {
                            SettingsTextField(title: "Open time", text: $openTime, prompt: "16:30")
                                .disabled(!isOpen)
                                .opacity(isOpen ? 1 : 0.45)

                            SettingsTextField(title: "Close time", text: $closeTime, prompt: "21:30")
                                .disabled(!isOpen)
                                .opacity(isOpen ? 1 : 0.45)
                        }
                    }

                    SettingsTextField(title: "Reason", text: $reason, prompt: "Short hours")

                    if let availability {
                        SettingsKeyValueGrid(items: [
                            ("Slot interval", "\(availability.slotIntervalMinutes) min"),
                            ("Max online party", "\(availability.maxOnlinePartySize)"),
                            ("Lead time", "\(availability.minimumLeadTimeMinutes) min")
                        ])
                    }
                }

                SettingsCard(title: "Slot Preview", systemImage: "clock") {
                    SlotPreviewView(
                        slots: settingsStore.selectedDateSlots,
                        isLoading: settingsStore.slotPreviewLoading || isLoading,
                        errorMessage: settingsStore.slotPreviewError,
                        blockedCount: settingsStore.selectedDateBlockedSlots.count,
                        onRetry: { Task { await load() } }
                    )

                    SettingsHelperText("Public website uses these backend slots when available.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 112)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Today Availability")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load(force: true) }
                } label: {
                    if isLoading || settingsStore.slotPreviewLoading || settingsStore.blockedSlotsLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoading || isSaving)
            }
        }
        .safeAreaInset(edge: .bottom) {
            SettingsSaveBar(
                title: "Save Today Override",
                isSaving: isSaving || settingsStore.dayAvailabilitySaving,
                onCancel: { Task { await load() } },
                onSave: { Task { await save() } }
            )
        }
        .task {
            // Lazy screen load: day availability, public slots, and blocked slots
            // are date-scoped operations data owned by RestaurantSettingsStore.
            await load(force: false)
        }
    }

    private var todayDisplayText: String {
        Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
    }

    private func load(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            await settingsStore.refreshDateOperations(date: dateKey, force: force)
            guard let loadedAvailability = settingsStore.selectedDateAvailability,
                  loadedAvailability.date == dateKey else {
                throw SettingsValidationError(message: "Today availability did not load.")
            }
            availability = loadedAvailability
            apply(loadedAvailability)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        defer {
            isSaving = false
        }

        do {
            let request = try RestaurantDayAvailabilityUpdateRequest(
                isOpen: isOpen,
                openTime: isOpen ? normalizedTime(openTime, field: "Open time") : nil,
                closeTime: isOpen ? normalizedTime(closeTime, field: "Close time") : nil,
                reason: reason.trimmed.nilIfBlank
            )
            let saved = try await settingsStore.saveDayAvailability(date: dateKey, request: request)
            availability = saved
            apply(saved)
            ReservationHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
            ReservationHaptics.warning()
        }
    }

    private func apply(_ availability: RestaurantDayAvailabilityDTO) {
        isOpen = availability.isOpen
        openTime = shortTimeString(availability.openTime) ?? "16:30"
        closeTime = shortTimeString(availability.closeTime) ?? "21:30"
        reason = availability.reason ?? ""
    }
}

// MARK: - Weekly Hours

struct WeeklyHoursView: View {
    @ObservedObject var settingsStore: RestaurantSettingsStore

    @State private var drafts: [WeeklyHourDraft] = WeeklyHourDraft.defaultWeek()
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage {
                    SettingsNoticeCard(message: errorMessage, tint: .red)
                }

                ForEach($drafts) { $draft in
                    WeeklyDayCard(draft: $draft)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 112)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Weekly Hours")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    if isLoading || settingsStore.weeklyHoursLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoading || isSaving)
            }
        }
        .safeAreaInset(edge: .bottom) {
            SettingsSaveBar(
                title: "Save Weekly Hours",
                isSaving: isSaving || settingsStore.weeklyHoursSaving,
                onCancel: { Task { await load() } },
                onSave: { Task { await save() } }
            )
        }
        .task {
            await load()
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let hours = try await settingsStore.loadRestaurantHours()
            let byWeekday = Dictionary(uniqueKeysWithValues: hours.weeklyHours.map { ($0.weekday, $0) })
            drafts = WeeklyHourDraft.orderedWeekdays.map { weekday in
                if let hour = byWeekday[weekday] {
                    return WeeklyHourDraft(dto: hour)
                }
                return WeeklyHourDraft.businessDefault(weekday: weekday)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        defer {
            isSaving = false
        }

        do {
            let request = WeeklyHoursUpdateRequest(
                weeklyHours: try drafts.map { try $0.updateDTO() }
            )
            let saved = try await settingsStore.saveRestaurantHours(request: request)
            let byWeekday = Dictionary(uniqueKeysWithValues: saved.weeklyHours.map { ($0.weekday, $0) })
            drafts = WeeklyHourDraft.orderedWeekdays.map { weekday in
                byWeekday[weekday].map(WeeklyHourDraft.init(dto:))
                    ?? WeeklyHourDraft.businessDefault(weekday: weekday)
            }
            ReservationHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
            ReservationHaptics.warning()
        }
    }
}

// MARK: - Blocked Time Slots

struct BlockedTimeSlotsView: View {
    @ObservedObject var settingsStore: RestaurantSettingsStore

    @State private var selectedDate = Date()
    @State private var selectedAvailableSlotValues: Set<String> = []
    @State private var selectedBlockedSlotValues: Set<String> = []
    @State private var reason = ""
    @State private var actionMessage: String?
    @State private var errorMessage: String?

    private var dateKey: String {
        selectedDate.reservationDateString()
    }

    private var availability: RestaurantDayAvailabilityDTO? {
        guard settingsStore.selectedDateAvailability?.date == dateKey else { return nil }
        return settingsStore.selectedDateAvailability
    }

    private var slots: ReservationSlotsResponseDTO? {
        guard settingsStore.selectedDateSlots?.date == dateKey else { return nil }
        return settingsStore.selectedDateSlots
    }

    private var blockedSlots: [RestaurantBlockedSlotDTO] {
        settingsStore.selectedDateBlockedSlots
            .filter { $0.reservationDate.isEmpty || $0.reservationDate == dateKey }
            .sorted { BlockedSlotsPresenter.shortSlotValue($0.slotTime) < BlockedSlotsPresenter.shortSlotValue($1.slotTime) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let errorMessage {
                    SettingsNoticeCard(message: errorMessage, tint: .red)
                } else if let blockedSlotsError = settingsStore.blockedSlotsError {
                    SettingsNoticeCard(message: blockedSlotsError, tint: .red)
                } else if let slotPreviewError = settingsStore.slotPreviewError {
                    SettingsNoticeCard(message: slotPreviewError, tint: .red)
                } else if let actionMessage {
                    SettingsNoticeCard(message: actionMessage, tint: .green, systemImage: "checkmark.circle")
                }

                selectedDateCard

                SettingsCard(title: "Available Public Slots", systemImage: "clock") {
                    if slots?.isOpen == false || availability?.isOpen == false {
                        ContentUnavailableView(
                            "This Date Is Closed",
                            systemImage: "calendar.badge.exclamationmark",
                            description: Text("There are no public slots to block.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        SlotPreviewView(
                            slots: slots,
                            isLoading: settingsStore.slotPreviewLoading,
                            errorMessage: settingsStore.slotPreviewError,
                            blockedCount: blockedSlots.count,
                            selectedSlotValues: selectedAvailableSlotValues,
                            onRetry: { requestDateOperations(force: true) },
                            onSlotTap: { slot in
                                toggleAvailableSlot(BlockedSlotsPresenter.shortSlotValue(slot.value))
                                actionMessage = nil
                                ReservationHaptics.selection()
                            }
                        )
                    }
                }

                SettingsCard(title: "Blocked Slots", systemImage: "nosign") {
                    if settingsStore.blockedSlotsLoading && blockedSlots.isEmpty {
                        ProgressView("Loading blocked slots...")
                            .frame(maxWidth: .infinity, minHeight: 72)
                    } else if blockedSlots.isEmpty {
                        ContentUnavailableView(
                            "No Blocked Slots",
                            systemImage: "checkmark.circle",
                            description: Text("Public slots for this date are not individually blocked.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        LazyVGrid(
                            columns: ReservationSlotGridStyle.columns,
                            spacing: ReservationSlotGridStyle.rowSpacing
                        ) {
                            ForEach(blockedSlots) { slot in
                                let value = BlockedSlotsPresenter.shortSlotValue(slot.slotTime)
                                Button {
                                    toggleBlockedSlot(value)
                                    actionMessage = nil
                                    ReservationHaptics.selection()
                                } label: {
                                    ReservationChoiceChip(
                                        title: BlockedSlotsPresenter.displaySlotTime(slot.slotTime),
                                        subtitle: slot.reason?.nilIfBlank == nil ? "Blocked" : "Held",
                                        isSelected: selectedBlockedSlotValues.contains(value),
                                        minWidth: 86,
                                        minHeight: 40
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                SettingsCard(title: "Reason", systemImage: "text.bubble") {
                    SettingsTextField(title: "Reason", text: $reason, prompt: "Held for manual booking")
                    SettingsHelperText("Optional. Staff can remove specific public reservation times without changing the whole day's hours.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 148)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Blocked Time Slots")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    requestDateOperations(force: true)
                } label: {
                    if settingsStore.blockedSlotsLoading || settingsStore.slotPreviewLoading || settingsStore.dayAvailabilityLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            blockedSlotsActionBar
        }
        .onAppear {
            requestDateOperations()
        }
        .onChange(of: dateKey) { _, _ in
            requestDateOperations()
        }
    }

    private var selectedDateCard: some View {
        SettingsCard(title: "Selected Date", systemImage: "calendar") {
            DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)

            SettingsKeyValueGrid(items: [
                ("Day", selectedDate.formatted(.dateTime.weekday(.wide))),
                ("Source", DayAvailabilityPresenter.sourceTitle(availability?.source ?? slots?.source)),
                ("Status", effectiveStatusText),
                ("Effective hours", DayAvailabilityPresenter.effectiveHoursText(availability: availability))
            ])
        }
    }

    private var blockedSlotsActionBar: some View {
        VStack(spacing: 8) {
            Button {
                Task { await blockSelectedSlots() }
            } label: {
                actionButtonLabel(
                    title: selectedAvailableSlotValues.isEmpty
                        ? "Block Selected Slots"
                        : "Block \(selectedAvailableSlotValues.count) Selected"
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedAvailableSlotValues.isEmpty || settingsStore.blockedSlotsSaving)
            .opacity(selectedAvailableSlotValues.isEmpty ? 0.45 : 1)

            HStack(spacing: 8) {
                Button {
                    Task { await unblockSelectedSlots() }
                } label: {
                    actionButtonLabel(
                        title: selectedBlockedSlotValues.isEmpty
                            ? "Unblock Selected"
                            : "Unblock \(selectedBlockedSlotValues.count)"
                    )
                }
                .buttonStyle(.plain)
                .disabled(selectedBlockedSlotValues.isEmpty || settingsStore.blockedSlotsSaving)
                .opacity(selectedBlockedSlotValues.isEmpty ? 0.45 : 1)

                Button {
                    Task { await unblockAllSlots() }
                } label: {
                    actionButtonLabel(title: "Unblock All")
                }
                .buttonStyle(.plain)
                .disabled(blockedSlots.isEmpty || settingsStore.blockedSlotsSaving)
                .opacity(blockedSlots.isEmpty ? 0.45 : 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, ReservationLayout.floatingTabBarClearance)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }

    private func actionButtonLabel(title: String) -> some View {
        HStack {
            Spacer()
            if settingsStore.blockedSlotsSaving {
                ProgressView()
                    .tint(.white)
            } else {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .frame(minHeight: 42)
        .background(ReservationUIStyle.selectedControlColor, in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
    }

    private var effectiveStatusText: String {
        if let availability {
            return availability.isOpen ? "Open" : "Closed"
        }
        if let slots {
            return slots.isOpen ? "Open" : "Closed"
        }
        return "Loading"
    }

    // Asks the store (controller) to load this date. The store owns the request
    // lifecycle, so view re-computation does not cancel it.
    private func requestDateOperations(force: Bool = false) {
        errorMessage = nil
        actionMessage = nil
        selectedAvailableSlotValues.removeAll()
        selectedBlockedSlotValues.removeAll()
        settingsStore.ensureDateOperations(date: dateKey, force: force)
    }

    private func blockSelectedSlots() async {
        await performBlockedSlotMutation(successMessage: "Selected slots are blocked from the public form.") {
            try await settingsStore.blockSlots(
                date: dateKey,
                slots: selectedAvailableSlotValues.sorted(),
                reason: reason
            )
            selectedAvailableSlotValues.removeAll()
        }
    }

    private func unblockSelectedSlots() async {
        await performBlockedSlotMutation(successMessage: "Selected blocked slots are public again.") {
            try await settingsStore.unblockSlots(
                date: dateKey,
                slots: selectedBlockedSlotValues.sorted()
            )
            selectedBlockedSlotValues.removeAll()
        }
    }

    private func unblockAllSlots() async {
        await performBlockedSlotMutation(successMessage: "All blocked slots for this date were cleared.") {
            try await settingsStore.unblockAllSlots(date: dateKey)
            selectedAvailableSlotValues.removeAll()
            selectedBlockedSlotValues.removeAll()
        }
    }

    private func performBlockedSlotMutation(
        successMessage: String,
        operation: () async throws -> Void
    ) async {
        errorMessage = nil
        actionMessage = nil

        do {
            try await operation()
            actionMessage = successMessage
            ReservationHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
            ReservationHaptics.warning()
        }
    }

    private func toggleAvailableSlot(_ value: String) {
        if selectedAvailableSlotValues.contains(value) {
            selectedAvailableSlotValues.remove(value)
        } else {
            selectedAvailableSlotValues.insert(value)
        }
    }

    private func toggleBlockedSlot(_ value: String) {
        if selectedBlockedSlotValues.contains(value) {
            selectedBlockedSlotValues.remove(value)
        } else {
            selectedBlockedSlotValues.insert(value)
        }
    }
}

// MARK: - Analytics Preview

struct BusinessAnalyticsView: View {
    @ObservedObject var settingsStore: RestaurantSettingsStore

    @State private var summary: ReservationAnalyticsSummaryDTO?
    @State private var range: AnalyticsRangeOption = .all
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Range", selection: $range) {
                    ForEach(AnalyticsRangeOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if let errorMessage {
                    SettingsNoticeCard(message: errorMessage, tint: .red)
                        .padding(.horizontal, 16)
                }

                if isLoading && summary != nil {
                    SettingsNoticeCard(message: "Updating analytics...", tint: .secondary, systemImage: "arrow.clockwise")
                        .padding(.horizontal, 16)
                }

                if isLoading && summary == nil {
                    ProgressView("Loading analytics...")
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else if let summary {
                    analyticsContent(summary)
                } else {
                    ContentUnavailableView(
                        "No Analytics",
                        systemImage: "chart.bar",
                        description: Text("Refresh to load backend summary data.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 112)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Business Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    if isLoading || settingsStore.analyticsLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoading)
            }
        }
        .task(id: range) {
            // Lazy analytics load: backend summary is fetched only when this
            // screen is opened or the range changes.
            await load()
        }
    }

    private func analyticsContent(_ summary: ReservationAnalyticsSummaryDTO) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            KPIGrid(summary: summary)
                .padding(.horizontal, 16)

            AnalyticsStatusSection(rows: summary.byStatus)
                .padding(.horizontal, 16)

            AnalyticsMonthSection(rows: summary.byMonth)
                .padding(.horizontal, 16)

            AnalyticsHourSection(rows: summary.byHour)
                .padding(.horizontal, 16)

            AnalyticsPartySizeSection(rows: summary.byPartySize)
                .padding(.horizontal, 16)

            AnalyticsLeadTimeSection(rows: summary.leadTimeBuckets)
                .padding(.horizontal, 16)

            AnalyticsFieldCompletenessSection(values: summary.fieldCompleteness)
                .padding(.horizontal, 16)

            AnalyticsPipelineSection(pipeline: summary.pipelineHealth)
                .padding(.horizontal, 16)
        }
    }

    private func load() async {
        guard !isLoading else { return }
        if summary == nil, let cached = settingsStore.analyticsSummary {
            summary = cached
        }
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let dateRange = range.dateRange()
            summary = try await settingsStore.loadReservationAnalyticsSummary(
                from: dateRange.from,
                to: dateRange.to
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Settings Pieces

private struct SlotPreviewView: View {
    let slots: ReservationSlotsResponseDTO?
    let isLoading: Bool
    let errorMessage: String?
    let blockedCount: Int?
    var selectedSlotValues: Set<String> = []
    var onRetry: (() -> Void)?
    var onSlotTap: ((ReservationSlotDTO) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let blockedCount {
                SettingsStatusBadge(title: "Blocked slots: \(blockedCount)", tint: blockedCount > 0 ? .orange : .secondary)
            }

            if isLoading && slots == nil {
                ProgressView("Loading slots...")
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.red)
                    if let onRetry {
                        Button("Retry", action: onRetry)
                            .font(.caption.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let slots, !slots.isOpen {
                ContentUnavailableView(
                    "Closed",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text(slots.message ?? "Reservations are not available for this date.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if let slots, !slots.slots.isEmpty {
                LazyVGrid(
                    columns: ReservationSlotGridStyle.columns,
                    spacing: ReservationSlotGridStyle.rowSpacing
                ) {
                    ForEach(slots.slots) { slot in
                        if let onSlotTap {
                            Button {
                                onSlotTap(slot)
                            } label: {
                                ReservationChoiceChip(
                                    title: slot.label,
                                    isSelected: selectedSlotValues.contains(BlockedSlotsPresenter.shortSlotValue(slot.value)),
                                    minWidth: 68,
                                    minHeight: 34
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            ReservationChoiceChip(
                                title: slot.label,
                                isSelected: false,
                                minWidth: 68,
                                minHeight: 34
                            )
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Slots",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text(slots?.message ?? "Reservations are not available for this date.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
    }
}

private struct RestaurantSettingsHeader: View {
    let setup: RestaurantSetup

    var body: some View {
        SettingsCard(title: setup.businessName, systemImage: "fork.knife") {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(setup.timezone)
                        .font(.subheadline.weight(.medium))
                    Text("Backend source of truth")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if let updatedAt = setup.formattedUpdatedAt {
                    Text("Updated \(updatedAt)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        TryzubSectionCard(title: title, systemImage: systemImage, spacing: 12) {
            content
        }
    }
}

private struct SettingsTextField: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            TextField(prompt.isEmpty ? title : prompt, text: $text)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 11)
                .frame(minHeight: 38)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
    }
}

private struct SettingsNumberField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        SettingsTextField(title: title, text: $text)
            .keyboardType(.numberPad)
    }
}

private struct SettingsTextEditor: View {
    let title: String
    @Binding var text: String
    var minHeight: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(.subheadline.weight(.medium))
                .frame(minHeight: minHeight)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .scrollContentBackground(.hidden)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
    }
}

private struct SettingsHelperText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsNoticeCard: View {
    let message: String
    let tint: Color
    var systemImage = "exclamationmark.triangle"

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TryzubColors.cardBackground, in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
    }
}

private struct SettingsSaveBar: View {
    let title: String
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button("Cancel", action: onCancel)
                .buttonStyle(TryzubSecondaryButtonStyle())

            Button(action: onSave) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(title)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(TryzubPrimaryButtonStyle())
            .disabled(isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, ReservationLayout.floatingTabBarClearance)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }
}

private struct SettingsStatusBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        TryzubStatusBadge(title: title, tint: tint)
    }
}

private struct SettingsKeyValueGrid: View {
    let items: [(String, String)]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(items, id: \.0) { item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(item.0)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(TryzubColors.mutedText)
                        .frame(width: 96, alignment: .leading)
                    Text(item.1)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TryzubColors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(TryzubColors.secondaryCardBackground, in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
            }
        }
    }
}

private struct WeeklyDayCard: View {
    @Binding var draft: WeeklyHourDraft

    var body: some View {
        SettingsCard(title: draft.dayName, systemImage: "calendar") {
            HStack {
                Text(draft.isOpen ? "Open" : "Closed")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle(draft.isOpen ? "Open" : "Closed", isOn: $draft.isOpen)
                    .labelsHidden()
            }

            if draft.isOpen {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        SettingsTextField(title: "Open", text: $draft.openTime, prompt: "16:30")
                        SettingsTextField(title: "Close", text: $draft.closeTime, prompt: "21:30")
                    }

                    VStack(spacing: 10) {
                        SettingsTextField(title: "Open", text: $draft.openTime, prompt: "16:30")
                        SettingsTextField(title: "Close", text: $draft.closeTime, prompt: "21:30")
                    }
                }

                SettingsHelperText("Last bookable time is 30 minutes before close.")
                if let lastBookable = draft.lastBookableTime {
                    SettingsStatusBadge(title: "Last bookable: \(lastBookable)", tint: .secondary)
                }
            } else {
                Text("Closed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    .padding(.horizontal, 11)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
            }
        }
    }
}

private struct KPIGrid: View {
    let summary: ReservationAnalyticsSummaryDTO

    var body: some View {
        let metrics = summary.summary
        let pipeline = summary.pipelineHealth

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            AnalyticsKPI(title: "Direct reservations", value: "\(metrics?.reservationsCount ?? 0)", systemImage: "calendar")
            AnalyticsKPI(title: "Guests", value: "\(metrics?.guestsCount ?? 0)", systemImage: "person.2")
            AnalyticsKPI(title: "Avg party", value: metrics?.avgPartySize.map { String(format: "%.2f", $0) } ?? "-", systemImage: "number")
            AnalyticsKPI(
                title: "Pipeline health",
                value: "\(pipeline?.managedRowsWithSourceSubmissionId ?? 0) / \(pipeline?.flamingoInboundTotal ?? 0)",
                systemImage: "arrow.triangle.2.circlepath"
            )
        }
    }
}

private struct AnalyticsKPI: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
    }
}

private struct AnalyticsStatusSection: View {
    let rows: [ReservationAnalyticsStatusRowDTO]

    var body: some View {
        SettingsCard(title: "Status Breakdown", systemImage: "list.bullet.rectangle") {
            AnalyticsRowsEmptyAware(isEmpty: rows.isEmpty) {
                ForEach(rows) { row in
                    AnalyticsBreakdownRow(title: row.status.statusLabel, reservations: row.reservationsCount, guests: row.guestsCount)
                }
            }
        }
    }
}

private struct AnalyticsMonthSection: View {
    let rows: [ReservationAnalyticsMonthRowDTO]

    var body: some View {
        SettingsCard(title: "Demand by Month", systemImage: "calendar") {
            AnalyticsRowsEmptyAware(isEmpty: rows.isEmpty) {
                ForEach(rows) { row in
                    AnalyticsBreakdownRow(title: row.month, reservations: row.reservationsCount, guests: row.guestsCount)
                }
            }
        }
    }
}

private struct AnalyticsHourSection: View {
    let rows: [ReservationAnalyticsHourRowDTO]

    var body: some View {
        SettingsCard(title: "Peak Hours", systemImage: "clock") {
            AnalyticsRowsEmptyAware(isEmpty: rows.isEmpty) {
                ForEach(rows.sorted { $0.guestsCount == $1.guestsCount ? $0.hour < $1.hour : $0.guestsCount > $1.guestsCount }) { row in
                    AnalyticsBreakdownRow(title: AnalyticsPresenter.hourLabel(row.hour), reservations: row.reservationsCount, guests: row.guestsCount)
                }
            }
        }
    }
}

private struct AnalyticsPartySizeSection: View {
    let rows: [ReservationAnalyticsPartySizeRowDTO]

    var body: some View {
        SettingsCard(title: "Party Size", systemImage: "person.2") {
            AnalyticsRowsEmptyAware(isEmpty: rows.isEmpty) {
                ForEach(rows.sorted { $0.partySize < $1.partySize }) { row in
                    AnalyticsBreakdownRow(title: "\(row.partySize) \(row.partySize == 1 ? "guest" : "guests")", reservations: row.reservationsCount, guests: row.guestsCount)
                }
            }
        }
    }
}

private struct AnalyticsLeadTimeSection: View {
    let rows: [ReservationAnalyticsLeadTimeRowDTO]

    var body: some View {
        SettingsCard(title: "Lead Time", systemImage: "clock.arrow.circlepath") {
            AnalyticsRowsEmptyAware(isEmpty: rows.isEmpty) {
                ForEach(rows) { row in
                    AnalyticsBreakdownRow(title: AnalyticsPresenter.leadTimeLabel(row.bucket), reservations: row.reservationsCount, guests: row.guestsCount)
                }
            }
        }
    }
}

private struct AnalyticsFieldCompletenessSection: View {
    let values: [String: JSONValue]

    var body: some View {
        SettingsCard(title: "Field Completeness", systemImage: "checklist") {
            if tableAssignmentCompletenessIsLow {
                SettingsNoticeCard(message: "Few reservations have table assignment.", tint: .orange)
            }

            AnalyticsRowsEmptyAware(isEmpty: values.isEmpty) {
                ForEach(values.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(AnalyticsPresenter.fieldLabel(key))
                        Spacer()
                        Text(values[key]?.compactDisplayText ?? "-")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private var tableAssignmentCompletenessIsLow: Bool {
        let tableValue = values["table_name"] ?? values["table_assigned"]
        guard let percent = tableValue?.percentageValue else { return false }
        return percent < 0.25
    }
}

private struct AnalyticsPipelineSection: View {
    let pipeline: ReservationAnalyticsPipelineHealthDTO?

    var body: some View {
        SettingsCard(title: "Pipeline Health", systemImage: "arrow.triangle.2.circlepath") {
            if let pipeline {
                AnalyticsBreakdownLine(title: "Flamingo inbound total", value: "\(pipeline.flamingoInboundTotal)")
                AnalyticsBreakdownLine(title: "Managed linked rows", value: "\(pipeline.managedRowsWithSourceSubmissionId)")
                AnalyticsBreakdownLine(title: "Missing non-spam Flamingo", value: "\(pipeline.missingNonSpamFlamingo)")

                if pipeline.missingNonSpamFlamingo > 0 {
                    SettingsNoticeCard(message: "\(pipeline.missingNonSpamFlamingo) inbound submission needs import attention.", tint: .orange)
                }
            } else {
                Text("No pipeline data returned.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AnalyticsBreakdownRow: View {
    let title: String
    let reservations: Int
    let guests: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer()
            Text("\(reservations)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text("\(guests) guests")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }
}

private struct AnalyticsBreakdownLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}

private struct AnalyticsRowsEmptyAware<Content: View>: View {
    let isEmpty: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if isEmpty {
            Text("No rows returned.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                content
            }
        }
    }
}

// MARK: - Draft Models

private struct RestaurantSetupDraft: Equatable {
    var businessName: String
    var timezone: String
    var defaultPartySize: String
    var bookingWindowDays: String
    var slotIntervalMinutes: String
    var maxOnlinePartySize: String
    var largePartyReviewThreshold: String
    var sameDayBookingEnabled: Bool
    var minimumLeadTimeMinutes: String
    var callInPlaceholderEmail: String
    var fromEmail: String
    var replyToEmail: String

    init(setup: RestaurantSetup) {
        businessName = setup.businessName
        timezone = setup.timezone
        defaultPartySize = String(setup.defaultPartySize)
        bookingWindowDays = String(setup.bookingWindowDays)
        slotIntervalMinutes = String(setup.slotIntervalMinutes)
        maxOnlinePartySize = String(setup.maxOnlinePartySize)
        largePartyReviewThreshold = String(setup.largePartyReviewThreshold)
        sameDayBookingEnabled = setup.sameDayBookingEnabled
        minimumLeadTimeMinutes = String(setup.minimumLeadTimeMinutes)
        callInPlaceholderEmail = setup.callInPlaceholderEmail
        fromEmail = setup.fromEmail
        replyToEmail = setup.replyToEmail
    }

    func updateRequest() throws -> RestaurantSetupUpdateRequest {
        RestaurantSetupUpdateRequest(
            businessName: businessName.trimmed,
            timezone: timezone.trimmed,
            defaultPartySize: try requiredInt(defaultPartySize, field: "Default party size"),
            bookingWindowDays: try requiredInt(bookingWindowDays, field: "Booking window days"),
            slotIntervalMinutes: try requiredInt(slotIntervalMinutes, field: "Slot interval"),
            maxOnlinePartySize: try requiredInt(maxOnlinePartySize, field: "Max online party size"),
            largePartyReviewThreshold: try requiredInt(largePartyReviewThreshold, field: "Large party review threshold"),
            sameDayBookingEnabled: sameDayBookingEnabled,
            minimumLeadTimeMinutes: try requiredInt(minimumLeadTimeMinutes, field: "Minimum lead time"),
            callInPlaceholderEmail: callInPlaceholderEmail.trimmed,
            fromEmail: fromEmail.trimmed,
            replyToEmail: replyToEmail.trimmed
        )
    }

    private func requiredInt(_ value: String, field: String) throws -> Int {
        guard let intValue = Int(value.trimmed), intValue >= 0 else {
            throw SettingsValidationError(message: "\(field) must be a whole number.")
        }
        return intValue
    }
}

private struct WeeklyHourDraft: Identifiable, Equatable {
    // Backend convention: 0 = Monday through 6 = Sunday.
    static let orderedWeekdays = [0, 1, 2, 3, 4, 5, 6]

    var weekday: Int
    var isOpen: Bool
    var openTime: String
    var closeTime: String

    var id: Int { weekday }

    var dayName: String {
        switch weekday {
        case 0: return "Monday"
        case 1: return "Tuesday"
        case 2: return "Wednesday"
        case 3: return "Thursday"
        case 4: return "Friday"
        case 5: return "Saturday"
        case 6: return "Sunday"
        default: return "Day \(weekday)"
        }
    }

    init(weekday: Int, isOpen: Bool, openTime: String, closeTime: String) {
        self.weekday = weekday
        self.isOpen = isOpen
        self.openTime = openTime
        self.closeTime = closeTime
    }

    init(dto: WeeklyHourDTO) {
        weekday = dto.weekday
        isOpen = dto.isOpen
        openTime = shortTimeString(dto.openTime) ?? ""
        closeTime = shortTimeString(dto.closeTime) ?? ""
    }

    static func defaultWeek() -> [WeeklyHourDraft] {
        orderedWeekdays.map(businessDefault)
    }

    static func businessDefault(weekday: Int) -> WeeklyHourDraft {
        switch weekday {
        case 0:
            return WeeklyHourDraft(weekday: weekday, isOpen: false, openTime: "", closeTime: "")
        case 1, 2, 3:
            return WeeklyHourDraft(weekday: weekday, isOpen: true, openTime: "17:00", closeTime: "21:00")
        case 4:
            return WeeklyHourDraft(weekday: weekday, isOpen: true, openTime: "17:00", closeTime: "22:00")
        case 5:
            return WeeklyHourDraft(weekday: weekday, isOpen: true, openTime: "11:00", closeTime: "22:00")
        case 6:
            return WeeklyHourDraft(weekday: weekday, isOpen: true, openTime: "11:00", closeTime: "21:00")
        default:
            return WeeklyHourDraft(weekday: weekday, isOpen: false, openTime: "", closeTime: "")
        }
    }

    var lastBookableTime: String? {
        WeeklyHoursPresenter.lastBookableText(closeTime: closeTime)
    }

    func updateDTO() throws -> WeeklyHourUpdateDTO {
        WeeklyHourUpdateDTO(
            weekday: weekday,
            isOpen: isOpen,
            openTime: isOpen ? try normalizedTime(openTime, field: "\(dayName) open time") : nil,
            closeTime: isOpen ? try normalizedTime(closeTime, field: "\(dayName) close time") : nil
        )
    }
}

private enum AnalyticsRangeOption: String, CaseIterable, Identifiable {
    case all
    case thisMonth
    case last30Days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .thisMonth:
            return "This Month"
        case .last30Days:
            return "Last 30 Days"
        }
    }

    func dateRange(now: Date = Date(), calendar: Calendar = .current) -> (from: String?, to: String?) {
        switch self {
        case .all:
            return (nil, nil)
        case .thisMonth:
            let components = calendar.dateComponents([.year, .month], from: now)
            let start = calendar.date(from: components) ?? now
            return (start.reservationDateString(), now.reservationDateString())
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return (start.reservationDateString(), now.reservationDateString())
        }
    }
}

private struct SettingsValidationError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

// MARK: - Helpers

enum WeeklyHoursPresenter {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func lastBookableText(closeTime: String) -> String? {
        let normalized = BlockedSlotsPresenter.shortSlotValue(closeTime)

        guard let close = timeFormatter.date(from: normalized),
              let lastBookable = Calendar.current.date(byAdding: .minute, value: -30, to: close) else {
            return nil
        }

        return timeFormatter.string(from: lastBookable)
    }
}

enum DayAvailabilityPresenter {
    static func sourceTitle(_ source: String?) -> String {
        switch source?.lowercased() {
        case "special":
            return "Special Override"
        case "weekly":
            return "Weekly"
        case .some(let source):
            return source.capitalized
        case nil:
            return "Backend"
        }
    }

    static func effectiveHoursText(availability: RestaurantDayAvailabilityDTO?) -> String {
        guard let availability else { return "-" }
        guard availability.isOpen else { return "Closed" }
        return "\(shortTimeString(availability.openTime) ?? "-")-\(shortTimeString(availability.closeTime) ?? "-")"
    }
}

enum BlockedSlotsPresenter {
    private static let timeWithSeconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let timeWithoutSeconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func shortSlotValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5 else { return trimmed }
        return String(trimmed.prefix(5))
    }

    static func displaySlotTime(_ value: String) -> String {
        let shortValue = shortSlotValue(value)

        if let date = timeWithSeconds.date(from: value)
            ?? timeWithoutSeconds.date(from: value)
            ?? timeWithoutSeconds.date(from: shortValue) {
            return ReservationFormatters.shortTime.string(from: date)
        }

        return shortValue
    }
}

enum AnalyticsPresenter {
    static func hourLabel(_ value: String) -> String {
        let hourString = value.prefix(2)
        guard let hour = Int(hourString) else {
            return value
        }

        let adjustedHour = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return "\(adjustedHour) \(suffix)"
    }

    static func leadTimeLabel(_ value: String) -> String {
        switch value {
        case "same_day":
            return "Same day"
        case "one_day":
            return "1 day ahead"
        case "two_three_days":
            return "2-3 days ahead"
        case "four_seven_days":
            return "4-7 days ahead"
        case "eight_fourteen_days":
            return "8-14 days ahead"
        case "fifteen_thirty_days":
            return "15-30 days ahead"
        case "thirty_one_plus_days":
            return "31+ days ahead"
        default:
            return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func fieldLabel(_ value: String) -> String {
        switch value {
        case "guest_name", "name":
            return "Name"
        case "email":
            return "Email"
        case "phone":
            return "Phone"
        case "guest_notes":
            return "Guest notes"
        case "staff_notes":
            return "Staff notes"
        case "table_name", "table_assigned":
            return "Table assigned"
        default:
            return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private func normalizedTime(_ value: String, field: String) throws -> String {
    let trimmed = value.trimmed
    let formats = [
        #"^\d{2}:\d{2}$"#,
        #"^\d{2}:\d{2}:\d{2}$"#
    ]

    guard formats.contains(where: { trimmed.range(of: $0, options: .regularExpression) != nil }) else {
        throw SettingsValidationError(message: "\(field) must use HH:mm format.")
    }

    return trimmed.count == 5 ? "\(trimmed):00" : trimmed
}

private func shortTimeString(_ value: String?) -> String? {
    guard let value = value?.trimmed, !value.isEmpty else { return nil }
    return String(value.prefix(5))
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfBlank: String? {
        trimmed.isEmpty ? nil : trimmed
    }

    var statusLabel: String {
        ReservationStatus(rawValue: self)?.displayName
            ?? replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private extension JSONValue {
    var percentageValue: Double? {
        switch self {
        case .number(let value):
            return value > 1 ? value / 100 : value
        case .object(let object):
            if let percent = object["percent"]?.percentageValue {
                return percent
            }
            if let complete = object["complete"]?.numericValue,
               let total = object["total"]?.numericValue,
               total > 0 {
                return complete / total
            }
            return nil
        case .string(let value):
            let normalized = value.replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let number = Double(normalized) else { return nil }
            return value.contains("%") || number > 1 ? number / 100 : number
        case .bool, .array, .null:
            return nil
        }
    }

    var numericValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let value):
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case .bool(let value):
            return value ? 1 : 0
        case .object, .array, .null:
            return nil
        }
    }

    var compactDisplayText: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value <= 1, value >= 0 {
                return "\(Int(round(value * 100)))%"
            }
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(format: "%.2f", value)
        case .bool(let value):
            return value ? "Yes" : "No"
        case .object(let object):
            if let complete = object["complete"]?.compactDisplayText,
               let total = object["total"]?.compactDisplayText {
                return "\(complete) / \(total)"
            }
            if let percent = object["percent"]?.compactDisplayText {
                return percent
            }
            if let value = object["value"]?.compactDisplayText {
                return value
            }
            return "\(object.count) fields"
        case .array(let values):
            return "\(values.count)"
        case .null:
            return "-"
        }
    }
}
