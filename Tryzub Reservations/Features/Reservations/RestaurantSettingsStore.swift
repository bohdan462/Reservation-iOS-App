//
//  RestaurantSettingsStore.swift
//  Tryzub Reservations
//

import SwiftUI

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

    @State private var draft = RestaurantSetupDraft(setup: .default)
    @State private var savedDraft = RestaurantSetupDraft(setup: .default)
    @State private var setup = RestaurantSetup.default
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didLoadInitialDraft = false

    private var hasChanges: Bool {
        draft != savedDraft
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let errorMessage {
                    SettingsNoticeCard(message: errorMessage, tint: .red)
                }

                RestaurantSettingsHeader(setup: setup)

                SettingsCard(title: "Management", systemImage: "slider.horizontal.3") {
                    VStack(spacing: 8) {
                        AdminNavigationRow(title: "Today Availability", subtitle: "Override today and preview slots", systemImage: "calendar.badge.clock") {
                            TodayAvailabilityView()
                        }
                        AdminNavigationRow(title: "Weekly Hours", subtitle: "Edit the regular open days", systemImage: "clock") {
                            WeeklyHoursView()
                        }
                    }
                }

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
                    if controller.isLoadingRestaurantSetup {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(controller.isLoadingRestaurantSetup || isSaving)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if hasChanges {
                SettingsSaveBar(
                    title: "Save",
                    isSaving: isSaving || controller.isSavingRestaurantSetup,
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
        do {
            let loadedSetup = try await controller.loadRestaurantSetup()
            setup = loadedSetup
            if forceDraftUpdate || !didLoadInitialDraft {
                draft = RestaurantSetupDraft(setup: loadedSetup)
                savedDraft = draft
                didLoadInitialDraft = true
            }
        } catch {
            errorMessage = error.localizedDescription
            setup = controller.restaurantSetup
            if !didLoadInitialDraft {
                draft = RestaurantSetupDraft(setup: controller.restaurantSetup)
                savedDraft = draft
                didLoadInitialDraft = true
            }
        }
    }

    private func resetDraft() {
        draft = savedDraft
        errorMessage = nil
        ReservationHaptics.selection()
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        defer {
            isSaving = false
        }

        do {
            let request = try draft.updateRequest()
            let saved = try await controller.updateRestaurantSetup(request: request)
            setup = saved
            draft = RestaurantSetupDraft(setup: saved)
            savedDraft = draft
            ReservationHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
            ReservationHaptics.warning()
        }
    }
}

// MARK: - Today Availability

struct TodayAvailabilityView: View {
    @EnvironmentObject private var controller: ReservationsController

    @State private var availability: RestaurantDayAvailabilityDTO?
    @State private var slots: ReservationSlotsResponseDTO?
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

                        SettingsStatusBadge(title: sourceTitle, tint: .secondary)
                        SettingsStatusBadge(title: isOpen ? "Open" : "Closed", tint: isOpen ? .green : .red)
                    }
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
                    slotPreview
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
                    Task { await load() }
                } label: {
                    if isLoading {
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
                isSaving: isSaving || controller.isSavingRestaurantDayAvailability,
                onCancel: { Task { await load() } },
                onSave: { Task { await save() } }
            )
        }
        .task {
            await load()
        }
    }

    @ViewBuilder
    private var slotPreview: some View {
        if isLoading && slots == nil {
            ProgressView("Loading slots...")
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
        } else if let slots, slots.isOpen, !slots.slots.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(slots.slots) { slot in
                    Text(slot.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
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

    private var todayDisplayText: String {
        Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
    }

    private var sourceTitle: String {
        switch availability?.source.lowercased() {
        case "special":
            return "Special Override"
        case "weekly":
            return "Weekly"
        default:
            return availability?.source.capitalized ?? "Backend"
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
            let loadedAvailability = try await controller.loadRestaurantDayAvailability(date: dateKey)
            availability = loadedAvailability
            apply(loadedAvailability)
            slots = try await controller.loadReservationSlots(date: dateKey)
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
            let saved = try await controller.updateRestaurantDayAvailability(date: dateKey, request: request)
            availability = saved
            apply(saved)
            slots = try await controller.loadReservationSlots(date: dateKey)
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
    @EnvironmentObject private var controller: ReservationsController

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
                    if isLoading {
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
                isSaving: isSaving || controller.isSavingRestaurantHours,
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
            let hours = try await controller.loadRestaurantHours()
            let byWeekday = Dictionary(uniqueKeysWithValues: hours.weeklyHours.map { ($0.weekday, $0) })
            drafts = WeeklyHourDraft.orderedWeekdays.map { weekday in
                if let hour = byWeekday[weekday] {
                    return WeeklyHourDraft(dto: hour)
                }
                return WeeklyHourDraft(weekday: weekday, isOpen: false, openTime: "", closeTime: "")
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
            let saved = try await controller.updateRestaurantHours(request: request)
            let byWeekday = Dictionary(uniqueKeysWithValues: saved.weeklyHours.map { ($0.weekday, $0) })
            drafts = WeeklyHourDraft.orderedWeekdays.map { weekday in
                byWeekday[weekday].map(WeeklyHourDraft.init(dto:))
                    ?? WeeklyHourDraft(weekday: weekday, isOpen: false, openTime: "", closeTime: "")
            }
            ReservationHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
            ReservationHaptics.warning()
        }
    }
}

// MARK: - Analytics Preview

struct BusinessAnalyticsView: View {
    @EnvironmentObject private var controller: ReservationsController

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
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoading)
            }
        }
        .task(id: range) {
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
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let dateRange = range.dateRange()
            summary = try await controller.loadReservationAnalyticsSummary(
                from: dateRange.from,
                to: dateRange.to
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Settings Pieces

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
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.82))

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
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

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.72))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))

            Button(action: onSave) {
                if isSaving {
                    ProgressView()
                        .tint(Color(.systemBackground))
                        .frame(maxWidth: .infinity)
                } else {
                    Text(title)
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(.systemBackground))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(ReservationUIStyle.selectedControlColor, in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
            .disabled(isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

private struct AdminNavigationRow<Destination: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder let destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(10)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsStatusBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .frame(minHeight: 26)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
    }
}

private struct SettingsKeyValueGrid: View {
    let items: [(String, String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.0) { item in
                HStack {
                    Text(item.0)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(item.1)
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 34)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
            }
        }
    }
}

private struct WeeklyDayCard: View {
    @Binding var draft: WeeklyHourDraft

    var body: some View {
        SettingsCard(title: draft.dayName, systemImage: "calendar") {
            Toggle(draft.isOpen ? "Open" : "Closed", isOn: $draft.isOpen)
                .font(.subheadline.weight(.medium))

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
                title: "Pipeline",
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
                    AnalyticsBreakdownRow(title: hourLabel(row.hour), reservations: row.reservationsCount, guests: row.guestsCount)
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
                    AnalyticsBreakdownRow(title: row.bucket.leadTimeLabel, reservations: row.reservationsCount, guests: row.guestsCount)
                }
            }
        }
    }
}

private struct AnalyticsFieldCompletenessSection: View {
    let values: [String: JSONValue]

    var body: some View {
        SettingsCard(title: "Field Completeness", systemImage: "checklist") {
            AnalyticsRowsEmptyAware(isEmpty: values.isEmpty) {
                ForEach(values.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key.analyticsFieldLabel)
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
    static let orderedWeekdays = [1, 2, 3, 4, 5, 6, 0]

    var weekday: Int
    var isOpen: Bool
    var openTime: String
    var closeTime: String

    var id: Int { weekday }

    var dayName: String {
        switch weekday {
        case 0: return "Sunday"
        case 1: return "Monday"
        case 2: return "Tuesday"
        case 3: return "Wednesday"
        case 4: return "Thursday"
        case 5: return "Friday"
        case 6: return "Saturday"
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
        orderedWeekdays.map {
            WeeklyHourDraft(weekday: $0, isOpen: false, openTime: "", closeTime: "")
        }
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

private func hourLabel(_ value: String) -> String {
    let hourString = value.prefix(2)
    guard let hour = Int(hourString) else {
        return value
    }

    let adjustedHour = hour % 12 == 0 ? 12 : hour % 12
    let suffix = hour < 12 ? "AM" : "PM"
    return "\(adjustedHour) \(suffix)"
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

    var leadTimeLabel: String {
        switch self {
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
            return replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var analyticsFieldLabel: String {
        switch self {
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
            return replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private extension JSONValue {
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
