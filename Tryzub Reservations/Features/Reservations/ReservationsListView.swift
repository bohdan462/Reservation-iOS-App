//
//  ReservationsListView.swift
//  Tryzub Reservations
//

import SwiftUI
import SwiftData

struct ReservationsListView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var controller: ReservationsController
    @State private var selectedTab: ReservationsAppTab = .today

    let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        _controller = StateObject(wrappedValue: ReservationsController(environment: environment))
    }

    var body: some View {
        ZStack {
            switch selectedTab {
            case .today:
                TodayDashboardView(environment: environment, isActive: true)
            case .schedule:
                ReservationScheduleView(environment: environment, isActive: true)
            case .review:
                ReservationReviewQueueView(environment: environment, isActive: true)
            case .more:
                ReservationMoreView(environment: environment)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            ReservationFloatingTabBar(selection: $selectedTab)
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 8)
        }
        .fontDesign(.rounded)
        .environmentObject(controller)
        .overlay(alignment: .topTrailing) {
            AppNoticeOverlay(
                notices: visibleNotices,
                onDismiss: controller.dismissNotice,
                onClearAll: controller.clearAllNotices
            )
            .padding(.top, noticeTopPadding)
            .padding(.trailing, 14)
        }
        .task {
            await controller.loadIfNeeded(context: modelContext)
        }
    }

    private var visibleNotices: [AppNotice] {
        controller.notices.filter { notice in
            switch notice.source {
            case .mutation, .email, .credentials:
                return true
            case .startup, .manualToday, .autoToday:
                return selectedTab == .today
            case .schedule:
                return selectedTab == .schedule
            case .review:
                return selectedTab == .review
            case .importFailures, .admin:
                return selectedTab == .today || selectedTab == .more
            }
        }
    }

    private var noticeTopPadding: CGFloat {
        switch selectedTab {
        case .schedule, .review:
            return 112
        case .today, .more:
            return 62
        }
    }
}

private struct TodayDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var controller: ReservationsController
    @Query(sort: [
        SortDescriptor(\ReservationRecord.reservationDate),
        SortDescriptor(\ReservationRecord.reservationTime)
    ])
    private var reservations: [ReservationRecord]

    @State private var showManualCreate = false
    @State private var showImportFailures = false

    let environment: AppEnvironment
    let isActive: Bool

    private var todayReservations: [ReservationRecord] {
        ReservationRecord.sortedChronologically(reservations.filter(\.isToday))
    }

    var body: some View {
        NavigationStack {
            HostBoardView(
                reservations: todayReservations,
                environment: environment,
                lastSyncedAt: controller.lastSyncedAt,
                isSyncing: controller.isSyncing,
                failedImportCount: controller.importFailureCount,
                isVisible: isActive,
                isAppActive: scenePhase == .active,
                externalInteractionActive: showManualCreate || showImportFailures,
                onShowFormProblems: {
                    showImportFailures = true
                }
            )
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await controller.requestManualTodayRefresh(context: modelContext)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if controller.capabilities.canViewFailedImports {
                        Button {
                            showImportFailures = true
                        } label: {
                            Label("Failed imports", systemImage: "exclamationmark.triangle")
                        }
                        .badge(controller.importFailureCount)
                        .accessibilityLabel("Failed imports")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if controller.capabilities.canCreateManualReservations {
                        Button {
                            showManualCreate = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Create reservation")
                    }

                    Button {
                        Task {
                            await controller.requestManualTodayRefresh(context: modelContext)
                        }
                    } label: {
                        if controller.isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(controller.isSyncing)
                    .accessibilityLabel("Refresh")
                }
            }
            .sheet(isPresented: $showManualCreate) {
                ManualReservationFormView { request in
                    try await controller.createReservation(request, context: modelContext)
                }
            }
            .sheet(isPresented: $showImportFailures) {
                ImportFailuresView(
                    environment: environment,
                    onCreateReservation: { request in
                        try await controller.createReservation(request, context: modelContext)
                    },
                    onCreated: { _ in }
                )
                .environmentObject(controller)
            }
        }
    }
}

private struct ReservationScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @Query(sort: [
        SortDescriptor(\ReservationRecord.reservationDate),
        SortDescriptor(\ReservationRecord.reservationTime)
    ])
    private var reservations: [ReservationRecord]

    @State private var scope: ReservationScheduleScope = .upcoming
    @State private var searchText = ""
    @State private var showManualCreate = false

    let environment: AppEnvironment
    let isActive: Bool

    private var displayedReservations: [ReservationRecord] {
        let today = Date.reservationDateString()
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        var rows = reservations

        if scope == .upcoming {
            rows = rows.filter {
                $0.reservationDate >= today && $0.statusValue != .cancelled && $0.statusValue != .noShow
            }
        }

        if !trimmedSearchText.isEmpty {
            rows = rows.filter { $0.matchesSearch(trimmedSearchText) }
        }

        return scope == .all
            ? ReservationRecord.sortedNewestFirst(rows)
            : ReservationRecord.sortedChronologically(rows)
    }

    private var sections: [ReservationDateSection] {
        ReservationRecord.dateSections(
            from: displayedReservations,
            newestFirst: scope == .all
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Schedule", selection: $scope) {
                        ForEach(ReservationScheduleScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if controller.isSyncing && reservations.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Loading reservations...")
                            Spacer()
                        }
                        .padding(.vertical, 24)
                    }
                } else if sections.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Reservations",
                            systemImage: "calendar",
                            description: Text("Try a different search or pull to refresh.")
                        )
                    }
                } else {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.reservations) { reservation in
                                ReservationNavigationRow(
                                    reservation: reservation,
                                    environment: environment,
                                    context: .schedule
                                )
                            }
                        } header: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title)
                                Text(section.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Name, phone, email, table")
            .listStyle(.plain)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .refreshable {
                await controller.requestScheduleRefresh(context: modelContext)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if controller.capabilities.canCreateManualReservations {
                        Button {
                            showManualCreate = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Create reservation")
                    }

                    Button {
                        Task {
                            await controller.requestScheduleRefresh(context: modelContext)
                        }
                    } label: {
                        if controller.isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(controller.isSyncing)
                    .accessibilityLabel("Refresh")
                }
            }
            .sheet(isPresented: $showManualCreate) {
                ManualReservationFormView { request in
                    try await controller.createReservation(request, context: modelContext)
                }
            }
            .task(id: isActive) {
                guard isActive else { return }
                await controller.scheduleBecameActive(context: modelContext)
            }
        }
    }
}

private struct ReservationReviewQueueView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @Query(sort: [
        SortDescriptor(\ReservationRecord.reservationDate),
        SortDescriptor(\ReservationRecord.reservationTime)
    ])
    private var reservations: [ReservationRecord]

    @State private var scope: ReservationQueueScope = .pending
    @State private var searchText = ""

    let environment: AppEnvironment
    let isActive: Bool

    private var queueReservations: [ReservationRecord] {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = reservations.filter { reservation in
            switch scope {
            case .pending:
                return reservation.statusValue == .new || reservation.statusValue == .needsReview
            case .needsReview:
                return reservation.statusValue == .needsReview
            }
        }

        let searchedRows = trimmedSearchText.isEmpty
            ? rows
            : rows.filter { $0.matchesSearch(trimmedSearchText) }

        return ReservationRecord.sortedByCreatedAtAscending(searchedRows)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Queue", selection: $scope) {
                        ForEach(ReservationQueueScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if queueReservations.isEmpty {
                    Section {
                        ContentUnavailableView(
                            scope == .needsReview ? "Nothing Needs Review" : "No Pending Reservations",
                            systemImage: scope == .needsReview ? "checkmark.seal" : "tray",
                            description: Text("Pull to refresh or adjust search.")
                        )
                    }
                } else {
                    Section {
                        ForEach(queueReservations) { reservation in
                            ReservationNavigationRow(
                                reservation: reservation,
                                environment: environment,
                                context: .review,
                                contextNote: reviewContext(for: reservation)
                            )
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scope == .pending ? "Pending reservations" : "Needs review")
                            Text("Oldest submitted first")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Name, phone, email")
            .listStyle(.plain)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .refreshable {
                await controller.requestReviewRefresh(context: modelContext)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await controller.requestReviewRefresh(context: modelContext)
                        }
                    } label: {
                        if controller.isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(controller.isSyncing)
                    .accessibilityLabel("Refresh")
                }
            }
            .task(id: isActive) {
                guard isActive else { return }
                await controller.reviewBecameActive(context: modelContext)
            }
        }
    }

    private func reviewContext(for reservation: ReservationRecord) -> String {
        let activeSameDay = reservations.filter {
            $0.reservationDate == reservation.reservationDate
                && $0.statusValue != .cancelled
                && $0.statusValue != .noShow
        }
        let dayGuests = activeSameDay.reduce(0) { $0 + $1.partySize }
        let sameTime = activeSameDay.filter {
            String($0.reservationTime.prefix(5)) == String(reservation.reservationTime.prefix(5))
        }
        let sameTimeGuests = sameTime.reduce(0) { $0 + $1.partySize }

        return "Booked: \(activeSameDay.count)/\(dayGuests) ppl · Same time: \(sameTime.count)/\(sameTimeGuests) ppl"
    }
}

private struct ReservationMoreView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController

    @State private var showManualCreate = false

    let environment: AppEnvironment

    var body: some View {
        NavigationStack {
            List {
                Section("Operations") {
                    if controller.capabilities.canCreateManualReservations {
                        Button {
                            showManualCreate = true
                        } label: {
                            Label("Create Manual Reservation", systemImage: "plus.circle")
                        }
                    }

                    if controller.capabilities.canViewFailedImports {
                        NavigationLink {
                            ImportFailuresView(
                                environment: environment,
                                onCreateReservation: { request in
                                    try await controller.createReservation(request, context: modelContext)
                                },
                                onCreated: { _ in }
                            )
                            .environmentObject(controller)
                        } label: {
                            Label("Failed Imports", systemImage: "exclamationmark.triangle")
                        }
                    }
                }

                if controller.capabilities.canViewDeveloperDiagnostics {
                    Section("Admin") {
                        NavigationLink {
                            DeveloperDiagnosticsView(environment: environment)
                                .environmentObject(controller)
                        } label: {
                            Label("API & App Diagnostics", systemImage: "stethoscope")
                        }
                    }
                }

                Section("Duplicate Resolution") {
                    Text("Keep the correct reservation active. Open the duplicate, tap Edit, set Superseded By to the keeper ID, change status to Cancelled, and add a staff note.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("More")
            .sheet(isPresented: $showManualCreate) {
                ManualReservationFormView { request in
                    try await controller.createReservation(request, context: modelContext)
                }
            }
        }
    }
}

private struct ReservationNavigationRow: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController

    let reservation: ReservationRecord
    let environment: AppEnvironment
    var context: ReservationRowContext = .schedule
    var contextNote: String?

    @State private var pendingAction: ReservationHostAction?
    @State private var tableAssignmentReservation: ReservationRecord?
    @State private var showDetail = false

    var body: some View {
        ReservationRowView(
            reservation: reservation,
            context: context,
            contextNote: contextNote
        ) {
            HStack(spacing: 8) {
                ReservationActionButtons(
                    reservation: reservation,
                    capabilities: controller.capabilities,
                    compact: true,
                    includeSecondary: false,
                    isBusy: controller.isActionInProgress(for: reservation)
                ) { action in
                    handleAction(action)
                }

                Button {
                    showDetail = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Details for \(reservation.guestName)")
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                showDetail = true
            } label: {
                Label("Details", systemImage: "info.circle")
            }

            ForEach(contextMenuActions) { action in
                Button(role: action.role) {
                    handleAction(action)
                } label: {
                    Label(action.fullTitle, systemImage: action.systemImage)
                }
            }
        }
        .navigationDestination(isPresented: $showDetail) {
            ReservationDetailView(reservation: reservation, environment: environment)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            ForEach(swipeActions) { action in
                Button(role: action.role) {
                    handleAction(action)
                } label: {
                    Label(action.shortTitle, systemImage: action.systemImage)
                }
                .tint(action.tint)
                .disabled(controller.isActionInProgress(for: reservation))
            }
        }
        .confirmationDialog(
            pendingAction?.dialogTitle(for: reservation) ?? "Update Reservation?",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingAction {
                Button(pendingAction.fullTitle, role: pendingAction.role) {
                    Task {
                        await perform(pendingAction)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            if let pendingAction {
                Text(pendingAction.dialogMessage(for: reservation))
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

    private var contextMenuActions: [ReservationHostAction] {
        availableActions(includeEmailAction: true)
    }

    private var swipeActions: [ReservationHostAction] {
        availableActions(includeEmailAction: false)
    }

    private func availableActions(includeEmailAction: Bool) -> [ReservationHostAction] {
        let status = reservation.statusValue
        var actions: [ReservationHostAction] = []

        if controller.capabilities.canConfirmReservations,
           status == .new || status == .needsReview {
            actions.append(.confirm)
            if includeEmailAction {
                actions.append(.sendConfirmationEmail)
            }
        }

        if controller.capabilities.canSeatReservations,
           status == .confirmed {
            actions.append(.seat)
        }

        if includeEmailAction,
           controller.capabilities.canConfirmReservations,
           status == .confirmed,
           !reservation.hasConfirmationEmailRecord {
            actions.append(.sendConfirmationEmail)
        }

        if controller.capabilities.canEditReservationDetails,
           status != .cancelled,
           status != .completed,
           status != .noShow {
            actions.append(.assignTable)
        }

        if controller.capabilities.canCancelReservations,
           status != .cancelled,
           status != .completed,
           status != .noShow {
            actions.append(.cancel)
        }

        return actions
    }

    private func handleAction(_ action: ReservationHostAction) {
        switch action {
        case .assignTable:
            tableAssignmentReservation = reservation
        case .sendConfirmationEmail, .cancel, .noShow:
            pendingAction = action
        case .confirm, .seat, .complete:
            Task {
                await perform(action)
            }
        }
    }

    private func perform(_ action: ReservationHostAction) async {
        pendingAction = nil

        switch action {
        case .confirm:
            await controller.updateStatus(reservation: reservation, status: .confirmed, context: modelContext)
        case .sendConfirmationEmail:
            await controller.confirmReservation(reservation: reservation, context: modelContext)
        case .seat:
            await controller.updateStatus(reservation: reservation, status: .seated, context: modelContext)
        case .cancel:
            await controller.updateStatus(reservation: reservation, status: .cancelled, context: modelContext)
        case .assignTable:
            tableAssignmentReservation = reservation
        case .complete:
            await controller.updateStatus(reservation: reservation, status: .completed, context: modelContext)
        case .noShow:
            await controller.updateStatus(reservation: reservation, status: .noShow, context: modelContext)
        }
    }
}

#if DEBUG
#Preview("Reservations") {
    ReservationsListView(environment: AppEnvironment(apiClient: ReservationsAPIClient.preview, role: .developer))
        .modelContainer(ReservationPreviewData.previewContainer)
}
#endif
