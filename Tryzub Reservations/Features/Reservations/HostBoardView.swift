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
    let isAppActive: Bool
    let externalInteractionActive: Bool
    let onAddReservation: () -> Void
    let onManualRefresh: () -> Void
    let onShowFormProblems: () -> Void

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController

    @State private var compactScope: HostBoardScope = .upcoming
    @State private var servicePanel: HomeServicePanel = .reservations
    @State private var pendingAction: ReservationPendingAction?
    @State private var tableAssignmentReservation: ReservationRecord?

    private var hasOpenInteraction: Bool {
        externalInteractionActive
            || pendingAction != nil
            || tableAssignmentReservation != nil
    }

    var body: some View {
        GeometryReader { proxy in
            // Snapshot keeps time/status grouping out of the view layout code.
            let snapshot = HostBoardSnapshot(reservations: reservations, selectedDate: selectedDate)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
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
                        nextReservationText: snapshot.nextReservationText
                    )

                    if proxy.size.width >= 1100 {
                        wideBoard(snapshot: snapshot)
                    } else {
                        compactBoard(snapshot: snapshot)
                    }
                }
                .padding(.horizontal, proxy.size.width >= 1100 ? 16 : 12)
                .padding(.vertical, proxy.size.width >= 1100 ? 12 : 10)
                .padding(.bottom, 92)
            }
            .background(Color(.systemGroupedBackground))
        }
        .confirmationDialog(
            pendingActionTitle,
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingAction {
                if pendingAction.action == .confirmOnly {
                    Button("Confirm only") {
                        Task {
                            await perform(.confirmOnly, on: pendingAction.reservation)
                        }
                    }

                    if pendingAction.reservation.hasUsableConfirmationEmail {
                        Button("Confirm + Email") {
                            Task {
                                await perform(.confirmAndSendEmail, on: pendingAction.reservation)
                            }
                        }
                    } else {
                        Button(pendingAction.reservation.isManualOrCallIn ? "Call-in / no email" : "No usable email") {}
                            .disabled(true)
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
        } message: {
            if let pendingAction {
                Text(pendingAction.action.dialogMessage(for: pendingAction.reservation))
            }
        }
        .sheet(item: $tableAssignmentReservation) { reservation in
            TableAssignmentSheet(reservation: reservation) { tableName in
                // Table assignment is a server PATCH through the controller.
                _ = try await controller.updateReservation(
                    id: reservation.remoteID,
                    request: ReservationUpdateRequest(tableName: tableName),
                    context: modelContext
                )
            }
        }
        .task(id: isVisible && isAppActive) {
            // Starts/stops the auto-refresh loop when Today is visible and app is active.
            await runAutoRefreshLoop()
        }
    }

    private var pendingActionTitle: String {
        guard let pendingAction else {
            return "Update Reservation?"
        }

        return pendingAction.action.dialogTitle(for: pendingAction.reservation)
    }

    private func warningArea(snapshot: HostBoardSnapshot) -> some View {
        HStack(spacing: 8) {
            if failedImportCount > 0,
               controller.capabilities.canViewFailedImports,
               controller.capabilities.canViewDeveloperDiagnostics {
                FormProblemsBanner(count: failedImportCount, onTap: onShowFormProblems)
            }

            if !snapshot.needsReview.isEmpty {
                HostWarningBanner(
                    title: "\(snapshot.needsReview.count) need review",
                    message: "",
                    symbolName: "exclamationmark.triangle",
                    tint: .secondary
                )
            }

            if snapshot.noTableCount > 0 {
                HostWarningBanner(
                    title: "\(snapshot.noTableCount) without table",
                    message: "",
                    symbolName: "table.furniture",
                    tint: .secondary
                )
            }

            Spacer(minLength: 0)
        }
    }

    private func wideBoard(snapshot: HostBoardSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            HostBoardColumn(
                title: "Seated",
                subtitle: "\(snapshot.seated.count) seated",
                reservations: snapshot.seated,
                emptyTitle: "No one seated",
                emptySystemImage: "person.2.slash",
                nextReservationID: nil,
                environment: environment,
                onAction: handleAction
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)

            HomeReservationsPanel(
                selection: $servicePanel,
                snapshot: snapshot,
                environment: environment,
                onAction: handleAction
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func compactBoard(snapshot: HostBoardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HostBoardColumn(
                title: "Seated",
                subtitle: "\(snapshot.seated.count) seated",
                reservations: snapshot.seated,
                emptyTitle: "No one seated",
                emptySystemImage: "person.2.slash",
                nextReservationID: nil,
                environment: environment,
                onAction: handleAction
            )

            HomeReservationsPanel(
                selection: $servicePanel,
                snapshot: snapshot,
                environment: environment,
                onAction: handleAction
            )
        }
    }

    private func compactReservations(from snapshot: HostBoardSnapshot) -> [ReservationRecord] {
        switch compactScope {
        case .upcoming:
            return snapshot.upcoming
        case .seated:
            return snapshot.seated
        case .review:
            return snapshot.needsReview
        }
    }

    // MARK: - Staff Action Routing

    // View sends staff intent only; controller/service decide the network operation.
    private func handleAction(_ action: ReservationHostAction, reservation: ReservationRecord) {
        if action == .assignTable {
            tableAssignmentReservation = reservation
        } else if action == .seat, !reservation.hasTableAssignment {
            tableAssignmentReservation = reservation
        } else if action == .confirmOnly || action == .confirmAndSendEmail || action == .cancel || action == .noShow {
            pendingAction = ReservationPendingAction(reservation: reservation, action: action)
        } else {
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
            tableAssignmentReservation = reservation
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
}

// MARK: - Host Snapshot

private struct HostBoardSnapshot {
    let selectedDate: Date
    let upcoming: [ReservationRecord]
    let seated: [ReservationRecord]
    let needsReview: [ReservationRecord]
    let newReservations: [ReservationRecord]
    let noTableCount: Int
    let expectedGuestCount: Int
    let nextReservationID: Int?
    let peakTimeText: String
    let nextReservationText: String

    // Active same-day reservations remain visible until staff changes status.
    // Time only chooses the "next" highlight; it does not auto-complete or hide rows.
    init(reservations: [ReservationRecord], selectedDate: Date) {
        self.selectedDate = selectedDate
        upcoming = ReservationRecord.sortedForHostBoard(
            reservations.filter {
                $0.statusValue == .new || $0.statusValue == .needsReview || $0.statusValue == .confirmed
            }
        )
        seated = ReservationRecord.sortedChronologically(
            reservations.filter { $0.statusValue == .seated }
        )
        needsReview = upcoming.filter { $0.statusValue == .needsReview }
        newReservations = upcoming.filter { $0.statusValue == .new }
        noTableCount = upcoming.filter { !$0.hasTableAssignment }.count
        expectedGuestCount = upcoming.reduce(0) { $0 + $1.partySize } + seated.reduce(0) { $0 + $1.partySize }

        let currentTime = Date.currentReservationTimeString()
        let isToday = selectedDate.reservationDateString() == Date.reservationDateString()
        let nextReservation = isToday
            ? upcoming.first { $0.reservationTime >= currentTime } ?? upcoming.first
            : upcoming.first
        nextReservationID = nextReservation?.remoteID
        nextReservationText = nextReservation.map { "\($0.displayTime) · \($0.guestName)" } ?? "-"
        peakTimeText = Self.peakTimeText(from: upcoming + seated)
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

    var body: some View {
        
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)],spacing: 8) {
            ReservationInfoChip(title: "Count", value: "\(reservationCount)", systemImage: "calendar")
            ReservationInfoChip(title: "Guests", value: "\(guestCount)", systemImage: "person.2")
            ReservationInfoChip(title: "New", value: "\(newCount)", systemImage: "sparkle")
            ReservationInfoChip(title: "Review", value: "\(reviewCount)", systemImage: "exclamationmark.triangle")
            if failedImportCount > 0 {
                ReservationInfoChip(title: "Forms", value: "\(failedImportCount)", systemImage: "exclamationmark.octagon")
            }
            ReservationInfoChip(title: "No Table", value: "\(noTableCount)", systemImage: "table.furniture")
            ReservationInfoChip(title: "Peak", value: peakTimeText, systemImage: "chart.line.uptrend.xyaxis")
            ReservationInfoChip(title: "Next", value: nextReservationText, systemImage: "clock")
        }
       
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
    }
}

// MARK: - Home Service Header

private struct HomeServiceHeader: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
        (0..<10).compactMap {
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
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    titleBlock

                    Spacer(minLength: 12)

                    actionBar
                }

                VStack(alignment: .leading, spacing: 12) {
                    titleBlock
                    actionBar
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    dateStrip

                    Spacer(minLength: 12)

                    openCalendarButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    dateStrip
                    openCalendarButton
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Service")
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
            if canCreateReservation {
                Button {
                    ReservationHaptics.selection()
                    onAddReservation()
                } label: {
                    Label("Add Reservation", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 156, minHeight: 40)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(.systemBackground))
                .background(ReservationUIStyle.selectedControlColor, in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
            }

            Menu {
                Button {
                    ReservationHaptics.selection()
                    onManualRefresh()
                } label: {
                    Label("Refresh Reservations", systemImage: "arrow.clockwise")
                }
                .disabled(isSyncing)

                if canCreateReservation {
                    Button {
                        ReservationHaptics.selection()
                        onAddReservation()
                    } label: {
                        Label("Add Reservation", systemImage: "plus")
                    }
                }

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
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var dateStrip: some View {
        Group {
            if horizontalSizeClass == .regular {
                HStack(spacing: 10) {
                    ForEach(quickDates, id: \.timeIntervalSinceReferenceDate) { date in
                        dateButton(for: date, fillsWidth: true)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(quickDates, id: \.timeIntervalSinceReferenceDate) { date in
                            dateButton(for: date, fillsWidth: false)
                        }
                    }
                    .padding(.vertical, 1)
                }
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
                fillsWidth: fillsWidth
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
    let nextReservationID: Int?
    let environment: AppEnvironment
    let onAction: (ReservationHostAction, ReservationRecord) -> Void

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

            if reservations.isEmpty {
                CompactEmptyHostState(title: emptyTitle, systemImage: emptySystemImage)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(reservations) { reservation in
                        HostBoardReservationRow(
                            reservation: reservation,
                            environment: environment,
                            isNext: reservation.remoteID == nextReservationID,
                            onAction: onAction
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private enum HomeServicePanel: String, CaseIterable, Identifiable {
    case reservations = "Reservations"
    case waitlist = "Waitlist"

    var id: String { rawValue }
}

private struct HomeReservationsPanel: View {
    @Binding var selection: HomeServicePanel
    let snapshot: HostBoardSnapshot
    let environment: AppEnvironment
    let onAction: (ReservationHostAction, ReservationRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Service list", selection: $selection) {
                ForEach(HomeServicePanel.allCases) { panel in
                    Text(panel.rawValue).tag(panel)
                }
            }
            .pickerStyle(.segmented)

            switch selection {
            case .reservations:
                HostBoardColumn(
                    title: "Reservations",
                    subtitle: "\(snapshot.upcoming.count) active for selected date",
                    reservations: snapshot.upcoming,
                    emptyTitle: "No active reservations",
                    emptySystemImage: "calendar.badge.checkmark",
                    nextReservationID: snapshot.nextReservationID,
                    environment: environment,
                    onAction: onAction
                )
            case .waitlist:
                WaitlistPlaceholderCard()
            }
        }
    }
}

private struct WaitlistPlaceholderCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Waitlist", systemImage: "person.2.badge.clock")
                .font(.headline.weight(.medium))
            Text("No waitlist yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct HostBoardReservationRow: View {
    @EnvironmentObject private var controller: ReservationsController

    let reservation: ReservationRecord
    let environment: AppEnvironment
    let isNext: Bool
    let onAction: (ReservationHostAction, ReservationRecord) -> Void
    @State private var showDetail = false

    var body: some View {
        // Reuses the same compact reservation cell used by Schedule and Review.
        ReservationRowView(
            reservation: reservation,
            showsDate: false,
            context: rowContext
        ) {
            ReservationActionButtons(
                reservation: reservation,
                capabilities: controller.capabilities,
                compact: true,
                includeSecondary: false,
                isBusy: controller.isActionInProgress(for: reservation)
            ) { action in
                onAction(action, reservation)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            ReservationHaptics.selection()
            showDetail = true
        }
        .onLongPressGesture {
            ReservationHaptics.lightImpact()
        }
        .contextMenu {
            Button {
                showDetail = true
            } label: {
                Label("Details", systemImage: "info.circle")
            }

            ForEach(
                ReservationHostAction.availableActions(
                    for: reservation,
                    capabilities: controller.capabilities,
                    includeSecondary: true
                )
            ) { action in
                Button(role: action.role) {
                    onAction(action, reservation)
                } label: {
                    Label(action.fullTitle, systemImage: action.systemImage)
                }
            }
        }
        .navigationDestination(isPresented: $showDetail) {
            ReservationDetailView(reservation: reservation, environment: environment)
        }
    }

    private var rowContext: ReservationRowContext {
        if reservation.statusValue == .seated {
            return .todaySeated
        }
        return .todayUpcoming(isNext: isNext)
    }
}

// MARK: - Warning Banners

private struct FormProblemsBanner: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HostWarningBanner(
                title: "\(count) form \(count == 1 ? "problem" : "problems")",
                message: "A website submission could not be converted. Review before service.",
                symbolName: "exclamationmark.octagon",
                tint: .red
            )
        }
        .buttonStyle(.plain)
    }
}

private struct HostWarningBanner: View {
    let title: String
    let message: String
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: symbolName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 12, height: 12)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
        .fixedSize(horizontal: true, vertical: false)
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

// MARK: - Compact Board Scope

private enum HostBoardScope: String, CaseIterable, Identifiable {
    case upcoming
    case seated
    case review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upcoming:
            return "Upcoming"
        case .seated:
            return "Seated"
        case .review:
            return "Review"
        }
    }

    var emptyTitle: String {
        switch self {
        case .upcoming:
            return "No upcoming reservations"
        case .seated:
            return "No one seated"
        case .review:
            return "Nothing needs review"
        }
    }

    var emptySystemImage: String {
        switch self {
        case .upcoming:
            return "calendar.badge.checkmark"
        case .seated:
            return "person.2.slash"
        case .review:
            return "checkmark.seal"
        }
    }

    func subtitle(upcoming: Int, seated: Int, review: Int) -> String {
        switch self {
        case .upcoming:
            return "\(upcoming) upcoming"
        case .seated:
            return "\(seated) seated"
        case .review:
            return "\(review) need review"
        }
    }
}

// MARK: - Formatting Helpers

private extension Date {
    static func currentReservationTimeString() -> String {
        ReservationFormatters.apiTime.string(from: Date())
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
