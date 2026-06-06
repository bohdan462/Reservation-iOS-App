//
//  HostBoardView.swift
//  Tryzub Reservations
//

import SwiftUI
import SwiftData

// MARK: - Host Board

struct HostBoardView: View {
    // Cached reservations for the selected service date.
    let reservations: [ReservationRecord]
    let environment: AppEnvironment
    @Binding var selectedDate: Date
    let lastSyncedAt: Date?
    let isSyncing: Bool
    let failedImportCount: Int
    let isVisible: Bool
    var deferNetworkLoads: Bool = false
    let isAppActive: Bool
    let externalInteractionActive: Bool
    let onAddReservation: () -> Void
    let onManualRefresh: () -> Void
    let onShowFormProblems: () -> Void
    let onOpenReservation: (ReservationRecord) -> Void

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController

    @State private var pendingAction: ReservationPendingAction?
    @State private var clockTick = Date()

    private var hasOpenInteraction: Bool {
        externalInteractionActive
            || pendingAction != nil
    }

    // Open→close service window for the busy-by-time chart x-axis. Prefers the
    // day availability hours, then public slot bounds; nil falls back to data range.
    private var serviceWindow: ClosedRange<Int>? {
        func hour(_ value: String?) -> Int? {
            guard let value, let h = Int(value.prefix(2)) else { return nil }
            return h
        }

        if let open = hour(todayAvailability?.openTime),
           let close = hour(todayAvailability?.closeTime),
           open <= close {
            return open...close
        }

        let slotHours = (todaySlots?.slots ?? []).compactMap { hour($0.value) }
        if let lo = slotHours.min(), let hi = slotHours.max(), lo <= hi {
            return lo...hi
        }

        return nil
    }

    private var isRunningForPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private var selectedDateKey: String {
        selectedDate.reservationDateString()
    }

    private var availabilitySummary: ReservationAvailabilitySummary? {
        controller.availabilitySummary(for: selectedDateKey)
    }

    private var todayAvailability: RestaurantDayAvailabilityDTO? {
        availabilitySummary?.availability
    }

    private var todaySlots: ReservationSlotsResponseDTO? {
        availabilitySummary?.slots
    }

    private var todayBlockedSlots: [RestaurantBlockedSlotDTO] {
        availabilitySummary?.blockedSlots ?? []
    }

    private var availabilitySummaryError: String? {
        controller.availabilitySummaryError(for: selectedDateKey)
    }

    private var isLoadingAvailabilitySummary: Bool {
        controller.isAvailabilitySummaryLoading(date: selectedDateKey)
    }

    var body: some View {
        GeometryReader { proxy in
            let safeWidth = proxy.size.width.tryzubFiniteNonNegativeLayoutValue
            let safeHeight = proxy.size.height.tryzubFiniteNonNegativeLayoutValue
            // Snapshot keeps time/status grouping out of the view layout code.
            let snapshot = HostBoardSnapshot(
                reservations: reservations,
                selectedDate: selectedDate,
                now: clockTick,
                serviceWindow: serviceWindow
            )

            Group {
                if safeWidth >= 1100 {
                    VStack(alignment: .leading, spacing: 8) {
                        homeHeaderAndStats(snapshot: snapshot)

                        wideBoard(snapshot: snapshot)
                            .layoutPriority(1)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            homeHeaderAndStats(snapshot: snapshot)
                            phoneLists(snapshot: snapshot)
                        }
                        .padding(.bottom, 12)
                    }
                }
            }
            .padding(.horizontal, safeWidth >= 1100 ? 16 : 12)
            .padding(.top, safeWidth >= 1100 ? 8 : 6)
            .padding(.bottom, 92)
            .frame(maxWidth: 1100)
            .frame(width: safeWidth, height: safeHeight, alignment: .top)
            .background(TryzubColors.screenBackground)
        }
        .alert(
            pendingActionTitle,
            isPresented: Binding(
                get: { pendingAction != nil && isVisible },
                set: { if !$0 { pendingAction = nil } }
            ),
            actions: {
                if let pendingAction {
                    if pendingAction.action == .confirmOnly {
                        Button("Confirm only") {
                            Task {
                                await perform(.confirmOnly, on: pendingAction.reservation)
                            }
                        }

                        ReservationConfirmDialog.backendEmailButton(
                            hasUsableEmail: pendingAction.reservation.hasUsableConfirmationEmail
                        ) {
                            Task {
                                await perform(.confirmAndSendEmail, on: pendingAction.reservation)
                            }
                        }
                    } else {
                        Button(pendingAction.action.fullTitle, role: pendingAction.action.role) {
                            Task {
                                await perform(pendingAction.action, on: pendingAction.reservation)
                            }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingAction = nil
                }
            },
            message: {
                if let pendingAction {
                    Text(pendingAction.action.dialogMessage(for: pendingAction.reservation))
                }
            }
        )
        .task(id: isVisible && isAppActive) {
            // Starts/stops the auto-refresh loop when Today is visible and app is active.
            guard !isRunningForPreviews else { return }
            await runAutoRefreshLoop()
        }
        .task(id: isVisible) {
            guard !isRunningForPreviews else { return }
            await runClockLoop()
        }
        .task(id: "\(isVisible)-\(deferNetworkLoads)-\(controller.isStartupNetworkPassInFlight)-\(selectedDate.reservationDateString())") {
            // Lazy Home indicator load: availability/slots/blocked are screen-specific
            // and cached by the controller so tab switching does not refetch them.
            guard !isRunningForPreviews else { return }
            guard !deferNetworkLoads, !controller.isStartupNetworkPassInFlight else { return }
            guard isVisible else {
                controller.cancelAvailabilitySummary(date: selectedDateKey)
                return
            }
            guard isVisible,
                  selectedDate.reservationDateString() == Date.reservationDateString() else {
                return
            }
            // Brief pause after launch sync so the next batch does not race QUIC setup.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled,
                  !deferNetworkLoads,
                  !controller.isStartupNetworkPassInFlight,
                  isVisible else { return }
            controller.ensureAvailabilitySummary(date: selectedDateKey)
        }
    }

    private var pendingActionTitle: String {
        guard let pendingAction else {
            return "Update Reservation?"
        }

        return pendingAction.action.dialogTitle(for: pendingAction.reservation)
    }

    private func wideBoard(snapshot: HostBoardSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            HostBoardColumn(
                title: "Seated",
                subtitle: "\(snapshot.seated.count) seated",
                reservations: snapshot.seated,
                emptyTitle: "No one seated",
                emptySystemImage: "person.2.slash",
                environment: environment,
                onAction: handleAction,
                onOpenReservation: onOpenReservation
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)

            HomeReservationsPanel(
                snapshot: snapshot,
                environment: environment,
                onAction: handleAction,
                onOpenReservation: onOpenReservation
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var availabilitySummaryLine: String? {
        guard selectedDate.reservationDateString() == Date.reservationDateString() else { return nil }

        if let availabilitySummaryError {
            return availabilitySummaryError
        }

        if isLoadingAvailabilitySummary && todayAvailability == nil && todaySlots == nil {
            return "Loading"
        }

        if let availability = todayAvailability, !availability.isOpen {
            return "Closed today"
        }
        if let slots = todaySlots, !slots.isOpen {
            return "Closed today"
        }

        var parts: [String] = []
        if let availability = todayAvailability,
           let open = shortAvailabilityTime(availability.openTime),
           let close = shortAvailabilityTime(availability.closeTime) {
            parts.append("\(open)–\(close)")
        }
        if let slots = todaySlots {
            parts.append("\(slots.slots.count) slots")
        }
        if todayBlockedSlots.count > 0 {
            parts.append("\(todayBlockedSlots.count) blocked")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func shortAvailabilityTime(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return String(value.prefix(5))
    }

    @ViewBuilder
    private func homeHeaderAndStats(snapshot: HostBoardSnapshot) -> some View {
        HomeServiceHeader(
            selectedDate: $selectedDate,
            lastSyncedAt: lastSyncedAt,
            isSyncing: isSyncing,
            canCreateReservation: controller.capabilities.canCreateManualReservations,
            canViewFormProblems: controller.capabilities.canViewFailedImports
                && controller.capabilities.canViewDeveloperDiagnostics,
            failedImportCount: failedImportCount,
            onAddReservation: onAddReservation,
            onManualRefresh: onManualRefresh,
            onShowFormProblems: onShowFormProblems
        )

        HostBoardSummaryCard(
            reservationCount: snapshot.upcoming.count + snapshot.seated.count,
            guestCount: snapshot.expectedGuestCount,
            newCount: snapshot.newReservations.count,
            reviewCount: snapshot.needsReview.count,
            failedImportCount: controller.capabilities.canViewDeveloperDiagnostics ? failedImportCount : 0,
            noTableCount: snapshot.noTableCount,
            peakTimeText: snapshot.peakTimeText,
            nextReservationText: snapshot.nextReservationText,
            timelineSlots: snapshot.timelineSlots,
            highlightHour: snapshot.nextReservationHour,
            availabilitySummary: availabilitySummaryLine,
            isAvailabilityLoading: isLoadingAvailabilitySummary,
            onRefreshAvailability: selectedDate.reservationDateString() == Date.reservationDateString()
                ? { controller.ensureAvailabilitySummary(date: selectedDateKey, force: true) }
                : nil
        )
    }

    private func phoneLists(snapshot: HostBoardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HostBoardColumn(
                title: "Seated",
                subtitle: "\(snapshot.seated.count) seated",
                reservations: snapshot.seated,
                emptyTitle: "No one seated",
                emptySystemImage: "person.2.slash",
                scrollsInternally: false,
                environment: environment,
                onAction: handleAction,
                onOpenReservation: onOpenReservation
            )

            HomeReservationsPanel(
                snapshot: snapshot,
                scrollsInternally: false,
                environment: environment,
                onAction: handleAction,
                onOpenReservation: onOpenReservation
            )
        }
    }

    // MARK: - Staff Action Routing

    // View sends staff intent only; controller/service decide the network operation.
    private func handleAction(_ action: ReservationHostAction, reservation: ReservationRecord) {
        if action == .confirmOnly || action == .confirmAndSendEmail || action == .cancel || action == .noShow {
            pendingAction = ReservationPendingAction(reservation: reservation, action: action)
        } else if action != .assignTable {
            Task {
                await perform(action, on: reservation)
            }
        }
    }

    // Intent: Converts host-board actions into controller calls.
    // Confirm = PATCH status confirmed; Confirm + Email = POST /confirm.
    private func perform(_ action: ReservationHostAction, on reservation: ReservationRecord) async {
        pendingAction = nil

        switch action {
        case .confirmOnly:
            await controller.updateStatus(reservation: reservation, status: .confirmed, context: modelContext)
            ReservationHaptics.success()
        case .confirmAndSendEmail:
            guard ReservationEmailWorkflow.isBackendConfirmEmailEnabled else { return }
            await controller.confirmReservation(reservation: reservation, context: modelContext)
            ReservationHaptics.success()
        case .seat:
            await controller.updateStatus(reservation: reservation, status: .seated, context: modelContext)
            ReservationHaptics.success()
        case .complete:
            await controller.updateStatus(reservation: reservation, status: .completed, context: modelContext)
            ReservationHaptics.success()
        case .cancel:
            await controller.updateStatus(reservation: reservation, status: .cancelled, context: modelContext)
            ReservationHaptics.warning()
        case .noShow:
            await controller.updateStatus(reservation: reservation, status: .noShow, context: modelContext)
            ReservationHaptics.warning()
        case .assignTable:
            break
        }
    }

    // MARK: - Auto Refresh Loop

    // Intent: Keeps Today fresh without interrupting staff while sheets/dialogs are open.
    // Network: Controller may call GET /managed-reservations?date=today.
    @MainActor
    private func runAutoRefreshLoop() async {
        guard isVisible, isAppActive else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }

            guard isVisible, isAppActive else { return }

            await controller.autoRefreshDashboardIfAllowed(
                context: modelContext,
                isInteractionActive: hasOpenInteraction,
                isAppActive: isAppActive
            )
        }
    }

    @MainActor
    private func runClockLoop() async {
        guard isVisible else { return }
        clockTick = Date()

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }

            guard isVisible else { return }
            clockTick = Date()
        }
    }

}

// MARK: - Host Snapshot

private struct HostBoardSnapshot {
    let selectedDate: Date
    let now: Date
    let upcoming: [ReservationRecord]
    let seated: [ReservationRecord]
    let needsReview: [ReservationRecord]
    let newReservations: [ReservationRecord]
    let noTableCount: Int
    let expectedGuestCount: Int
    let peakTimeText: String
    let nextReservationText: String
    let timelineSlots: [ServiceTimelineSlot]
    let nextReservationHour: Int?

    // Active same-day reservations remain visible until staff changes status.
    // Time only chooses the "next" highlight; it does not auto-complete or hide rows.
    init(reservations: [ReservationRecord], selectedDate: Date, now: Date, serviceWindow: ClosedRange<Int>? = nil) {
        self.selectedDate = selectedDate
        self.now = now
        upcoming = ReservationRecord.sortedForHostBoard(
            reservations.filter {
                $0.statusValue == .new || $0.statusValue == .needsReview || $0.statusValue == .confirmed
            },
            now: now
        )
        seated = ReservationRecord.sortedChronologically(
            reservations.filter { $0.statusValue == .seated }
        )
        needsReview = upcoming.filter { $0.statusValue == .needsReview }
        newReservations = upcoming.filter { $0.statusValue == .new }
        noTableCount = upcoming.filter { !$0.hasTableAssignment }.count
        expectedGuestCount = upcoming.reduce(0) { $0 + $1.partySize } + seated.reduce(0) { $0 + $1.partySize }

        let isToday = selectedDate.reservationDateString() == Date.reservationDateString()
        let nextReservation = isToday
            ? upcoming.first { reservation in
                guard let serviceDate = reservation.serviceDateTime else { return false }
                return serviceDate >= now
            } ?? upcoming.first
            : upcoming.first
        nextReservationText = nextReservation.map { reservation in
            if isToday, let serviceDate = reservation.serviceDateTime {
                let minutes = Int(ceil(abs(serviceDate.timeIntervalSince(now)) / 60))
                if serviceDate < now {
                    return "\(Self.durationText(minutes: minutes)) late"
                }
                if minutes <= 15 {
                    return "now"
                }
                return "in \(Self.durationText(minutes: minutes))"
            }
            return reservation.displayTime
        } ?? "-"
        peakTimeText = Self.peakTimeText(from: upcoming + seated)
        timelineSlots = ServiceTimeline.slots(from: upcoming + seated, window: serviceWindow)
        nextReservationHour = nextReservation.flatMap { Int($0.reservationTime.prefix(2)) }
    }

    private static func peakTimeText(from reservations: [ReservationRecord]) -> String {
        let counts = reservations.reduce(into: [String: Int]()) { result, record in
            let hour = String(record.reservationTime.prefix(2))
            result[hour, default: 0] += record.partySize
        }

        guard let peak = counts.sorted(by: {
            if $0.value == $1.value {
                return $0.key < $1.key
            }
            return $0.value > $1.value
        }).first else {
            return "No peak yet"
        }

        let display = ReservationPresentationTime.hourLabel(from: peak.key)
        return "\(display) · \(peak.value) guests"
    }

    private static func durationText(minutes: Int) -> String {
        let minutes = max(minutes, 1)
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
    }
}

// MARK: - Pending Host Action

private struct ReservationPendingAction: Identifiable {
    let reservation: ReservationRecord
    let action: ReservationHostAction

    var id: String {
        "\(reservation.remoteID)-\(action.rawValue)"
    }
}

// MARK: - Summary Card

private struct HostBoardSummaryCard: View {
    let reservationCount: Int
    let guestCount: Int
    let newCount: Int
    let reviewCount: Int
    let failedImportCount: Int
    let noTableCount: Int
    let peakTimeText: String
    let nextReservationText: String
    let timelineSlots: [ServiceTimelineSlot]
    let highlightHour: Int?
    var availabilitySummary: String?
    var isAvailabilityLoading = false
    var onRefreshAvailability: (() -> Void)?

    private var stats: [HostBoardStat] {
        var items = [
            HostBoardStat(value: reservationCount, label: "Booked"),
            HostBoardStat(value: guestCount, label: "Guests"),
            HostBoardStat(value: newCount, label: "New"),
            HostBoardStat(value: reviewCount, label: "Review"),
            HostBoardStat(value: noTableCount, label: "No table")
        ]
        if failedImportCount > 0 {
            items.append(HostBoardStat(value: failedImportCount, label: "Forms"))
        }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 0) {
                    ForEach(Array(stats.enumerated()), id: \.element.label) { index, stat in
                        if index > 0 {
                            Divider().frame(height: 26).opacity(0.4)
                                .padding(.horizontal, 10)
                        }
                        statItem(stat)
                    }
                    Spacer(minLength: 0)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(stats) { statItem($0) }
                }
            }

            if let availabilitySummary {
                HStack(spacing: 8) {
                    Text(availabilitySummary)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(TryzubColors.mutedText)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let onRefreshAvailability {
                        Button(action: onRefreshAvailability) {
                            if isAvailabilityLoading {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(TryzubColors.mutedText)
                        .disabled(isAvailabilityLoading)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Guests by time")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(TryzubColors.mutedText)

                    Spacer(minLength: 8)

                    HStack(spacing: 10) {
                        timelineLegend(label: "Peak", value: peakTimeText)
                        timelineLegend(label: "Next", value: nextReservationText)
                    }
                }

                ServiceLoadChart(slots: timelineSlots, highlightHour: highlightHour, height: 58)
            }
        }
        .padding(12)
        .background(TryzubColors.cardBackground, in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(TryzubColors.border, lineWidth: 1)
        }
    }

    private func statItem(_ stat: HostBoardStat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(stat.value)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(stat.value == 0 ? TryzubColors.mutedText : TryzubColors.primaryText)
                .lineLimit(1)
            Text(stat.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(TryzubColors.mutedText)
                .lineLimit(1)
        }
        .fixedSize()
    }

    private func timelineLegend(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(TryzubColors.mutedText)
            Text(value)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TryzubColors.primaryText)
                .lineLimit(1)
        }
    }
}

private struct HostBoardStat: Identifiable {
    let value: Int
    let label: String
    var id: String { label }
}

// MARK: - Availability Indicator

private struct HomeAvailabilityIndicator: View {
    let availability: RestaurantDayAvailabilityDTO?
    let slots: ReservationSlotsResponseDTO?
    let blockedCount: Int
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isClosed ? "calendar.badge.exclamationmark" : "calendar.badge.clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isClosed ? .red : .secondary)
                .frame(width: 28, height: 28)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(isClosed ? "Reservations closed today" : "Today availability")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isClosed ? .red : .primary)

                Text(summaryText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: onRefresh) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isLoading)
        }
        .padding(10)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isClosed ? Color.red.opacity(0.18) : Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var isClosed: Bool {
        if let availability {
            return !availability.isOpen
        }
        if let slots {
            return !slots.isOpen
        }
        return false
    }

    private var backgroundColor: Color {
        isClosed ? Color(.systemRed).opacity(0.08) : Color(.secondarySystemGroupedBackground)
    }

    private var summaryText: String {
        if let errorMessage {
            return errorMessage
        }

        if isLoading && availability == nil && slots == nil {
            return "Loading..."
        }

        if isClosed {
            return sourceText
        }

        var parts: [String] = []
        if let availability,
           let openTime = shortTime(availability.openTime),
           let closeTime = shortTime(availability.closeTime) {
            parts.append("\(openTime)-\(closeTime)")
        }
        parts.append("\(slots?.slots.count ?? 0) public slots")
        if sourceText == "Special override" {
            parts.append(sourceText)
        }
        if blockedCount > 0 {
            parts.append("Blocked slots: \(blockedCount)")
        }
        return parts.joined(separator: " | ")
    }

    private var sourceText: String {
        switch availability?.source.lowercased() ?? slots?.source?.lowercased() {
        case "special":
            return "Special override"
        case "weekly":
            return "Weekly"
        case .some(let source):
            return source.capitalized
        case nil:
            return "Server availability"
        }
    }

    private func shortTime(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return String(value.prefix(5))
    }
}

// MARK: - Home Service Header

private struct HomeServiceHeader: View {
    @Binding var selectedDate: Date
    let lastSyncedAt: Date?
    let isSyncing: Bool
    let canCreateReservation: Bool
    let canViewFormProblems: Bool
    let failedImportCount: Int
    let onAddReservation: () -> Void
    let onManualRefresh: () -> Void
    let onShowFormProblems: () -> Void

    private var quickDates: [Date] {
        (0..<7).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: Date())
        }
    }

    private var serviceDateText: String {
        selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    private var syncText: String {
        if isSyncing {
            return "Syncing"
        }

        guard let lastSyncedAt else {
            return "Cache only"
        }

        return "Synced \(lastSyncedAt.formatted(date: .omitted, time: .shortened))"
        
        
    }
    
    var body: some View {
        ViewThatFits(in: .horizontal) {
            // Wide (iPad): everything on one row
            HStack(alignment: .top, spacing: 10) {
                titleBlock
                dateStrip
                    .frame(maxWidth: .infinity)
                openCalendarButton
            
                actionBar
                    .fixedSize()
            }

            // Narrow (iPhone): title + actions, then dates below
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    titleBlock
                    Spacer(minLength: 8)
                    actionBar
                        .fixedSize()
                }

                HStack(alignment: .center, spacing: 10) {
                    dateStrip
                        .frame(maxWidth: .infinity)
                    openCalendarButton
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }
    
//OLD VERSION
//    var body: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            ViewThatFits(in: .horizontal) {
//                HStack(alignment: .top, spacing: 14) {
//                    titleBlock
////                        .frame(minWidth: 120)
//                  
//                    dateStrip
//                        .frame(maxWidth: .infinity)
//                        .layoutPriority(0)
//                    openCalendarButton
//                    
//                    
//                    actionBar
//                        .fixedSize()
//                }
//
//                VStack(alignment: .leading, spacing: 12) {
//                    titleBlock
//                    actionBar
//                }
//            }
//
//            ViewThatFits(in: .horizontal) {
////                HStack(alignment: .center, spacing: 12) {
////                    dateStrip
////
////                    Spacer(minLength: 12)
////
////                    openCalendarButton
////                }
//
//                VStack(alignment: .leading, spacing: 10) {
//                    dateStrip
//                    openCalendarButton
//                }
//            }
//        }
//        .padding(.horizontal, 16)
//        .padding(.vertical, 14)
////        .frame(maxWidth: .infinity, alignment: .leading)
//        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
//        .overlay {
//            RoundedRectangle(cornerRadius: 14, style: .continuous)
//                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
//        }
//    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Host")
                .font(.title2.weight(.semibold))
                .foregroundStyle(ReservationUIStyle.serviceTitleColor)
                .lineLimit(1)

            HStack(spacing: 7) {
                Text(serviceDateText)
                    .lineLimit(1)

                Text(syncText)
                    .lineLimit(1)

                if isSyncing {
                    ProgressView()
                        .controlSize(.mini)
                } else if lastSyncedAt != nil {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .frame(minWidth: 220, alignment: .leading)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button {
                    ReservationHaptics.selection()
                    onManualRefresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isSyncing)

                if canViewFormProblems, failedImportCount > 0 {
                    Button {
                        ReservationHaptics.warning()
                        onShowFormProblems()
                    } label: {
                        Label("\(failedImportCount) Form Problems", systemImage: "exclamationmark.triangle")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 42, height: 40)
            }
            .buttonStyle(ReservationHeaderIconButtonStyle())
            
            if canCreateReservation {
                Button {
                    ReservationHaptics.selection()
                    onAddReservation()
                } label: {
                   Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 42, height: 40)
                }
                .buttonStyle(ReservationHeaderIconButtonStyle())
            }

            
        }
//        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var dateStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ForEach(quickDates, id: \.timeIntervalSinceReferenceDate) { date in
                    dateButton(for: date, fillsWidth: false)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(quickDates, id: \.timeIntervalSinceReferenceDate) { date in
                        dateButton(for: date, fillsWidth: false)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func dateButton(for date: Date, fillsWidth: Bool) -> some View {
        Button {
            selectedDate = date
            ReservationHaptics.selection()
        } label: {
            ReservationChoiceChip(
                title: chipTitle(for: date),
                subtitle: chipSubtitle(for: date),
                isSelected: isSameDay(selectedDate, date),
                minWidth: 56,
                minHeight: 40,
                fillsWidth: false
                
            )
        }
        .buttonStyle(.plain)
    }

    private var openCalendarButton: some View {
        ReservationOpenCalendarButton(selectedDate: $selectedDate)
    }

    private func chipTitle(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }

        return date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    private func chipSubtitle(for date: Date) -> String? {
        guard Calendar.current.isDateInToday(date) else {
            return nil
        }

        return date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    private func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        Calendar.current.isDate(lhs, inSameDayAs: rhs)
    }
}

// MARK: - Host Columns / Rows

private struct HostBoardColumn: View {
    let title: String
    let subtitle: String
    let reservations: [ReservationRecord]
    let emptyTitle: String
    let emptySystemImage: String
    var scrollsInternally = true
    let environment: AppEnvironment
    let onAction: (ReservationHostAction, ReservationRecord) -> Void
    let onOpenReservation: (ReservationRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if scrollsInternally {
                ScrollView {
                    columnContent
                        .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                columnContent
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: scrollsInternally ? CGFloat.infinity : nil,
            alignment: .topLeading
        )
    }

    @ViewBuilder
    private var columnContent: some View {
        if reservations.isEmpty {
            CompactEmptyHostState(title: emptyTitle, systemImage: emptySystemImage)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(reservations) { reservation in
                    HostBoardReservationRow(
                        reservation: reservation,
                        environment: environment,
                        onAction: onAction,
                        onOpenReservation: onOpenReservation
                    )
                }
            }
        }
    }
}

private struct HomeReservationsPanel: View {
    let snapshot: HostBoardSnapshot
    var scrollsInternally = true
    let environment: AppEnvironment
    let onAction: (ReservationHostAction, ReservationRecord) -> Void
    let onOpenReservation: (ReservationRecord) -> Void

    var body: some View {
        HostBoardColumn(
            title: "Reservations",
            subtitle: "\(snapshot.upcoming.count) active for selected date",
            reservations: snapshot.upcoming,
            emptyTitle: "No active reservations",
            emptySystemImage: "calendar.badge.checkmark",
            scrollsInternally: scrollsInternally,
            environment: environment,
            onAction: onAction,
            onOpenReservation: onOpenReservation
        )
    }
}

private struct HostBoardReservationRow: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController

    let reservation: ReservationRecord
    let environment: AppEnvironment
    let onAction: (ReservationHostAction, ReservationRecord) -> Void
    let onOpenReservation: (ReservationRecord) -> Void

    @State private var tableAssignmentReservation: ReservationRecord?

    var body: some View {
        // Reuses the same compact reservation cell used by Schedule and Review.
        ReservationRowView(
            reservation: reservation,
            showsDate: false,
            context: rowContext,
            contextNote: seatedDurationText,
            capabilities: controller.capabilities,
            onTableTap: controller.capabilities.canEditReservationDetails && !controller.isNetworkDegraded
                ? { tableAssignmentReservation = reservation }
                : nil
        ) {
            ReservationActionButtons(
                reservation: reservation,
                capabilities: controller.capabilities,
                compact: true,
                includeSecondary: false,
                isBusy: controller.isActionInProgress(for: reservation) || controller.isNetworkDegraded
            ) { action in
                handle(action)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            ReservationHaptics.selection()
            onOpenReservation(reservation)
        }
        .onLongPressGesture {
            ReservationHaptics.lightImpact()
        }
        .contextMenu {
            Button {
                onOpenReservation(reservation)
            } label: {
                Label("Details", systemImage: "info.circle")
            }

            ForEach(actionPolicy.contextMenuActions) { action in
                Button(role: action.role) {
                    handle(action)
                } label: {
                    Label(action.fullTitle, systemImage: action.systemImage)
                }
            }
        }
        .sheet(item: $tableAssignmentReservation) { reservation in
            TableAssignmentSheet(reservation: reservation) { tableName in
                _ = try await controller.updateReservation(
                    id: reservation.remoteID,
                    request: ReservationUpdateRequest(tableName: tableName),
                    context: modelContext
                )
            }
        }
    }

    private var actionPolicy: ReservationHostActionPolicy {
        ReservationHostActionPolicy(reservation: reservation, capabilities: controller.capabilities)
    }

    private var rowContext: ReservationRowContext {
        if reservation.statusValue == .seated {
            return .todaySeated
        }
        return .todayUpcoming
    }

    private var seatedDurationText: String? {
        controller.seatedDurationText(for: reservation)
    }

    private func handle(_ action: ReservationHostAction) {
        if action == .assignTable {
            tableAssignmentReservation = reservation
        } else {
            onAction(action, reservation)
        }
    }
}

private struct CompactEmptyHostState: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

private enum ReservationPresentationTime {
    static func hourLabel(from hourString: String) -> String {
        guard let hour = Int(hourString) else { return hourString }
        let adjustedHour = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return "\(adjustedHour) \(suffix)"
    }
}
