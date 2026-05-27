//
//  ReservationsListView.swift
//  Tryzub Reservations
//

import SwiftUI
import SwiftData

// MARK: - Root Reservation Shell

struct ReservationsListView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var controller: ReservationsController
    @StateObject private var hiddenReservations = HiddenReservationsStore()
    @StateObject private var restaurantSettings = RestaurantSettingsStore()
    @Query private var rootReservations: [ReservationRecord]

    // Source of truth for custom floating navigation; there is no default TabView state.
    @State private var selectedTab: ReservationsAppTab = .home

    let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        _controller = StateObject(wrappedValue: ReservationsController(environment: environment))
    }

    var body: some View {
        ZStack {
            switch selectedTab {
            case .home:
                HomeDashboardView(environment: environment, isActive: true)
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
            // Custom staff navigation stays visible while each screen owns its own NavigationStack.
            ReservationFloatingTabBar(
                selection: $selectedTab,
                reviewAttentionCount: pendingReviewCount
            )
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 5)
        }
        
        .fontDesign(.rounded)
        .environmentObject(controller)
        .environmentObject(hiddenReservations)
        .environmentObject(restaurantSettings)
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
            // Initial app load: show SwiftData cache immediately, then refresh today if needed.
            await controller.loadIfNeeded(context: modelContext)
        }
    }

    private var visibleNotices: [AppNotice] {
        controller.notices.filter { notice in
            switch notice.source {
            case .mutation, .email, .credentials:
                return true
            case .startup, .manualToday, .autoToday:
                return selectedTab == .home
            case .schedule:
                return selectedTab == .schedule
            case .review:
                return selectedTab == .review
            case .importFailures, .admin:
                return selectedTab == .home || selectedTab == .more
            }
        }
    }

    private var pendingReviewCount: Int {
        rootReservations.filter {
            !hiddenReservations.isHidden($0)
                && ($0.statusValue == .new || $0.statusValue == .needsReview)
        }.count
    }

    private var noticeTopPadding: CGFloat {
        switch selectedTab {
        case .schedule, .review:
            return 112
        case .home, .more:
            return 62
        }
    }
}

// MARK: - Home Dashboard

private struct HomeDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var hiddenReservations: HiddenReservationsStore
    @Query(sort: [
        SortDescriptor(\ReservationRecord.reservationDate),
        SortDescriptor(\ReservationRecord.reservationTime)
    ])
    private var reservations: [ReservationRecord]

    // MARK: - Local UI State

    @State private var showManualCreate = false
    @State private var showImportFailures = false
    @State private var selectedDate = Date()

    let environment: AppEnvironment
    let isActive: Bool

    private var selectedDateReservations: [ReservationRecord] {
        let selectedDateKey = selectedDate.reservationDateString()
        return ReservationRecord.sortedChronologically(
            reservations.filter {
                $0.reservationDate == selectedDateKey && !hiddenReservations.isHidden($0)
            }
        )
    }

    var body: some View {
        NavigationStack {
            // Child view reads SwiftData cache and sends staff intent back to the controller.
            HostBoardView(
                reservations: selectedDateReservations,
                environment: environment,
                selectedDate: $selectedDate,
                lastSyncedAt: controller.lastSyncedAt,
                isSyncing: controller.isSyncing,
                failedImportCount: controller.importFailureCount,
                isVisible: isActive,
                isAppActive: scenePhase == .active && selectedDate.reservationDateString() == Date.reservationDateString(),
                externalInteractionActive: showManualCreate || showImportFailures,
                onAddReservation: {
                    showManualCreate = true
                },
                onManualRefresh: {
                    Task {
                        await controller.requestManualTodayRefresh(context: modelContext)
                    }
                },
                onShowFormProblems: {
                    showImportFailures = true
                }
            )
            .refreshable {
                // Staff manual refresh: controller decides whether this becomes a network GET.
                await controller.requestManualTodayRefresh(context: modelContext)
            }
            .fullScreenCover(isPresented: $showManualCreate) {
                ManualReservationFormView { request in
                    // Manual call-in create is accepted immediately; no email is sent.
                    try await controller.createAcceptedManualReservation(request, context: modelContext)
                }
                .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showImportFailures) {
                ImportFailuresView(
                    environment: environment,
                    onCreateReservation: { request in
                        // Failed import repair creates a managed reservation through the controller.
                        try await controller.createAcceptedManualReservation(request, context: modelContext)
                    },
                    onCreated: { _ in }
                )
                .environmentObject(controller)
            }
        }
    }
}

// MARK: - Schedule View

private struct ReservationScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var hiddenReservations: HiddenReservationsStore
    @Query(sort: [
        SortDescriptor(\ReservationRecord.reservationDate),
        SortDescriptor(\ReservationRecord.reservationTime)
    ])
    private var reservations: [ReservationRecord]

    // MARK: - Local UI State

    @State private var scope: ReservationScheduleScope = .upcoming
    @State private var searchText = ""
    @State private var showManualCreate = false

    let environment: AppEnvironment
    let isActive: Bool

    // Schedule reads cached rows; sync freshness is handled by ReservationsController.
    private var displayedReservations: [ReservationRecord] {
        let today = Date.reservationDateString()
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        var rows = reservations.filter { !hiddenReservations.isHidden($0) }

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
            .contentMargins(.bottom, 92, for: .scrollContent)
            .refreshable {
                // Staff manual schedule refresh: GET schedule window through controller/service.
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
                            // Same schedule-window refresh path as pull-to-refresh.
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
            .fullScreenCover(isPresented: $showManualCreate) {
                ManualReservationFormView { request in
                    // Manual call-in create is accepted immediately; no email is sent.
                    try await controller.createAcceptedManualReservation(request, context: modelContext)
                }
            }
            .task(id: isActive) {
                guard isActive else { return }
                // Schedule tab activation: controller fetches only when cached window is stale.
                await controller.scheduleBecameActive(context: modelContext)
            }
        }
    }
}

// MARK: - Pending Review View

private struct ReservationReviewQueueView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var hiddenReservations: HiddenReservationsStore
    @Query(sort: [
        SortDescriptor(\ReservationRecord.reservationDate),
        SortDescriptor(\ReservationRecord.reservationTime)
    ])
    private var reservations: [ReservationRecord]

    // MARK: - Local UI State

    @State private var scope: ReservationQueueScope = .pending
    @State private var searchText = ""

    let environment: AppEnvironment
    let isActive: Bool

    // Pending is the staff default: new and needs_review, oldest submitted first.
    private var queueReservations: [ReservationRecord] {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = reservations.filter { reservation in
            guard !hiddenReservations.isHidden(reservation) else { return false }
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
            .contentMargins(.bottom, 92, for: .scrollContent)
            .refreshable {
                // Staff manual queue refresh: controller fetches new + needs_review.
                await controller.requestReviewRefresh(context: modelContext)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            // Same pending queue refresh path as pull-to-refresh.
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
                // Review tab activation: controller refreshes only when queue cache is stale.
                await controller.reviewBecameActive(context: modelContext)
            }
        }
    }

    // Intent: Small operational context for pending queue triage.
    private func reviewContext(for reservation: ReservationRecord) -> String {
        let activeSameDay = reservations.filter {
            $0.reservationDate == reservation.reservationDate
                && !hiddenReservations.isHidden($0)
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

// MARK: - More View

private struct ReservationMoreView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var hiddenReservations: HiddenReservationsStore

    @State private var showManualCreate = false

    let environment: AppEnvironment

    var body: some View {
        NavigationStack {
            List {
                Section("Operations") {
                    NavigationLink {
                        RegularGuestsView()
                    } label: {
                        Label("Regulars / Guest Memory", systemImage: "person.2.crop.square.stack")
                    }

                    NavigationLink {
                        HiddenReservationsView(environment: environment)
                    } label: {
                        Label("Hidden Reservations", systemImage: "archivebox")
                    }

                    NavigationLink {
                        RestaurantSettingsView()
                    } label: {
                        Label("Restaurant Settings", systemImage: "gearshape")
                    }

                    if controller.capabilities.canCreateManualReservations {
                        Button {
                            showManualCreate = true
                        } label: {
                            Label("Create Manual Reservation", systemImage: "plus.circle")
                        }
                    }

                    if controller.capabilities.canViewFailedImports,
                       controller.capabilities.canViewDeveloperDiagnostics {
                        NavigationLink {
                            ImportFailuresView(
                                environment: environment,
                                onCreateReservation: { request in
                                    try await controller.createAcceptedManualReservation(request, context: modelContext)
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
            .contentMargins(.bottom, 92, for: .scrollContent)
            .fullScreenCover(isPresented: $showManualCreate) {
                ManualReservationFormView { request in
                    // Manual call-in create is accepted immediately; no email is sent.
                    try await controller.createAcceptedManualReservation(request, context: modelContext)
                }
            }
        }
    }
}

// MARK: - Hidden Reservations View

private struct HiddenReservationsView: View {
    @EnvironmentObject private var hiddenReservations: HiddenReservationsStore
    @Query(sort: [
        SortDescriptor(\ReservationRecord.reservationDate, order: .reverse),
        SortDescriptor(\ReservationRecord.reservationTime, order: .reverse)
    ])
    private var reservations: [ReservationRecord]

    let environment: AppEnvironment

    private var hiddenRows: [ReservationRecord] {
        ReservationRecord.sortedNewestFirst(
            reservations.filter { hiddenReservations.isHidden($0) }
        )
    }

    var body: some View {
        List {
            if hiddenRows.isEmpty {
                ContentUnavailableView(
                    "No Hidden Reservations",
                    systemImage: "archivebox",
                    description: Text("Wrong manual entries hidden from service lists will appear here.")
                )
            } else {
                Section("Hidden from service lists") {
                    ForEach(hiddenRows) { reservation in
                        VStack(alignment: .leading, spacing: 10) {
                            ReservationNavigationRow(
                                reservation: reservation,
                                environment: environment,
                                context: .schedule
                            )

                            Button {
                                hiddenReservations.restore(remoteID: reservation.remoteID)
                                ReservationHaptics.success()
                            } label: {
                                Label("Restore to lists", systemImage: "arrow.uturn.backward")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 38)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary.opacity(0.82))
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.plain)
        .contentMargins(.bottom, 92, for: .scrollContent)
        .navigationTitle("Hidden Reservations")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Reservation Navigation Row

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
            ReservationActionButtons(
                reservation: reservation,
                capabilities: controller.capabilities,
                compact: true,
                includeSecondary: false,
                isBusy: controller.isActionInProgress(for: reservation)
            ) { action in
                handleAction(action)
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
        .confirmationDialog(
            pendingAction?.dialogTitle(for: reservation) ?? "Update Reservation?",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingAction {
                if pendingAction == .confirmOnly {
                    Button("Confirm only") {
                        Task {
                            await perform(.confirmOnly)
                        }
                    }

                    if reservation.hasUsableConfirmationEmail {
                        Button("Confirm + Email") {
                            Task {
                                await perform(.confirmAndSendEmail)
                            }
                        }
                    } else {
                        Button(reservation.isManualOrCallIn ? "Call-in / no email" : "No usable email") {}
                            .disabled(true)
                    }
                } else {
                    Button(pendingAction.fullTitle, role: pendingAction.role) {
                        Task {
                            await perform(pendingAction)
                        }
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

    // MARK: - Available Staff Actions

    // Intent: Rows expose compact staff actions; no API clients/services are created here.
    private var contextMenuActions: [ReservationHostAction] {
        ReservationHostAction.contextMenuActions(for: reservation, capabilities: controller.capabilities)
    }

    // MARK: - Staff Action Routing

    private func handleAction(_ action: ReservationHostAction) {
        switch action {
        case .assignTable:
            tableAssignmentReservation = reservation
        case .confirmOnly, .confirmAndSendEmail, .cancel, .noShow:
            pendingAction = action
        case .seat, .complete:
            Task {
                await perform(action)
            }
        }
    }

    // Intent: Converts row actions into controller calls.
    // Confirm = PATCH status confirmed; Confirm + Email = POST /confirm.
    private func perform(_ action: ReservationHostAction) async {
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
        case .cancel:
            await controller.updateStatus(reservation: reservation, status: .cancelled, context: modelContext)
            ReservationHaptics.warning()
        case .assignTable:
            tableAssignmentReservation = reservation
        case .complete:
            await controller.updateStatus(reservation: reservation, status: .completed, context: modelContext)
            ReservationHaptics.success()
        case .noShow:
            await controller.updateStatus(reservation: reservation, status: .noShow, context: modelContext)
            ReservationHaptics.warning()
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Reservations") {
    ReservationsListView(environment: AppEnvironment(apiClient: ReservationsAPIClient.preview, role: .developer))
        .modelContainer(ReservationPreviewData.previewContainer)
}
#endif
