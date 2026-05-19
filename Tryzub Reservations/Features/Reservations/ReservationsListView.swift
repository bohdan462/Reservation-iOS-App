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
        TabView(selection: $selectedTab) {
            TodayDashboardView(environment: environment, isActive: selectedTab == .today)
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }
                .tag(ReservationsAppTab.today)

            ReservationScheduleView(environment: environment)
                .tabItem {
                    Label("Schedule", systemImage: "list.bullet.rectangle")
                }
                .tag(ReservationsAppTab.schedule)

            ReservationReviewQueueView(environment: environment)
                .tabItem {
                    Label("Review", systemImage: "exclamationmark.triangle")
                }
                .tag(ReservationsAppTab.review)

            ReservationMoreView(environment: environment)
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .tag(ReservationsAppTab.more)
        }
        .environmentObject(controller)
        .task {
            await controller.loadIfNeeded(context: modelContext)
        }
    }
}

private enum ReservationsAppTab: Hashable {
    case today
    case schedule
    case review
    case more
}

private struct TodayDashboardView: View {
    @Environment(\.modelContext) private var modelContext
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
                externalInteractionActive: showManualCreate || showImportFailures,
                onShowFormProblems: {
                    showImportFailures = true
                }
            )
            .navigationTitle("Today")
            .refreshable {
                await controller.refreshDashboard(context: modelContext)
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
                            await controller.refreshDashboard(context: modelContext)
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
                    onCreated: { createdReservation in
                        controller.save(createdReservation, context: modelContext)
                    }
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
                if let errorMessage = controller.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

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
                                ReservationNavigationRow(reservation: reservation, environment: environment)
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
            .searchable(text: $searchText, prompt: "Name, phone, email, table")
            .refreshable {
                await controller.refreshAll(context: modelContext)
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
                            await controller.refreshAll(context: modelContext)
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

    @State private var scope: ReservationQueueScope = .needsReview
    @State private var searchText = ""

    let environment: AppEnvironment

    private var queueReservations: [ReservationRecord] {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = reservations.filter { reservation in
            switch scope {
            case .needsReview:
                return reservation.statusValue == .needsReview
            case .new:
                return reservation.statusValue == .new
            }
        }

        let searchedRows = trimmedSearchText.isEmpty
            ? rows
            : rows.filter { $0.matchesSearch(trimmedSearchText) }

        return ReservationRecord.sortedChronologically(searchedRows)
    }

    private var sections: [ReservationDateSection] {
        ReservationRecord.dateSections(from: queueReservations, newestFirst: false)
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage = controller.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Picker("Queue", selection: $scope) {
                        ForEach(ReservationQueueScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if sections.isEmpty {
                    Section {
                        ContentUnavailableView(
                            scope == .needsReview ? "Nothing Needs Review" : "No New Reservations",
                            systemImage: scope == .needsReview ? "checkmark.seal" : "sparkle",
                            description: Text("Pull to refresh or adjust search.")
                        )
                    }
                } else {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.reservations) { reservation in
                                ReservationNavigationRow(reservation: reservation, environment: environment)
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
            .navigationTitle("Review")
            .searchable(text: $searchText, prompt: "Name, phone, email")
            .refreshable {
                await controller.refreshReviewQueues(context: modelContext)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await controller.refreshReviewQueues(context: modelContext)
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
        }
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
                if let errorMessage = controller.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

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
                                onCreated: { createdReservation in
                                    controller.save(createdReservation, context: modelContext)
                                }
                            )
                            .environmentObject(controller)
                        } label: {
                            Label("Failed Imports", systemImage: "exclamationmark.triangle")
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

    @State private var pendingAction: ReservationQuickAction?

    var body: some View {
        NavigationLink {
            ReservationDetailView(reservation: reservation, environment: environment)
        } label: {
            ReservationRowView(reservation: reservation)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            ForEach(availableActions) { action in
                Button(role: action.role) {
                    pendingAction = action
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
                Button(pendingAction.confirmButtonTitle, role: pendingAction.role) {
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
    }

    private var availableActions: [ReservationQuickAction] {
        let status = reservation.statusValue
        var actions: [ReservationQuickAction] = []

        if controller.capabilities.canConfirmReservations,
           status == .new || status == .needsReview {
            actions.append(.confirm)
        }

        if controller.capabilities.canSeatReservations,
           status == .confirmed {
            actions.append(.seat)
        }

        if controller.capabilities.canCancelReservations,
           status != .cancelled,
           status != .completed,
           status != .noShow {
            actions.append(.cancel)
        }

        return actions
    }

    private func perform(_ action: ReservationQuickAction) async {
        pendingAction = nil

        switch action {
        case .confirm:
            await controller.confirmReservation(reservation: reservation, context: modelContext)
        case .seat:
            await controller.updateStatus(reservation: reservation, status: .seated, context: modelContext)
        case .cancel:
            await controller.updateStatus(reservation: reservation, status: .cancelled, context: modelContext)
        }
    }
}

private enum ReservationQuickAction: String, Identifiable {
    case confirm
    case seat
    case cancel

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .confirm:
            return "Confirm"
        case .seat:
            return "Seat"
        case .cancel:
            return "Cancel"
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .confirm:
            return "Confirm and Send Email"
        case .seat:
            return "Seat Party"
        case .cancel:
            return "Cancel Reservation"
        }
    }

    var systemImage: String {
        switch self {
        case .confirm:
            return "checkmark.circle"
        case .seat:
            return "person.2"
        case .cancel:
            return "xmark.circle"
        }
    }

    var role: ButtonRole? {
        self == .cancel ? .destructive : nil
    }

    var tint: Color {
        switch self {
        case .confirm:
            return .green
        case .seat:
            return .blue
        case .cancel:
            return .red
        }
    }

    func dialogTitle(for reservation: ReservationRecord) -> String {
        switch self {
        case .confirm:
            return "Confirm reservation?"
        case .seat:
            return "Seat this party?"
        case .cancel:
            return "Cancel reservation?"
        }
    }

    func dialogMessage(for reservation: ReservationRecord) -> String {
        let summary = "\(reservation.guestName), \(reservation.displayDate) at \(reservation.displayTime), party of \(reservation.partySize)."

        switch self {
        case .confirm:
            return "\(summary)\n\nThis will mark the reservation confirmed and send a confirmation email to \(reservation.email)."
        case .seat:
            return "\(summary)\n\nThis only updates staff status. No email will be sent."
        case .cancel:
            return "\(summary)\n\nThis will cancel the managed reservation. No email will be sent yet."
        }
    }
}

#if DEBUG
#Preview("Reservations") {
    ReservationsListView(environment: AppEnvironment(apiClient: ReservationsAPIClient.preview, role: .developer))
        .modelContainer(ReservationPreviewData.previewContainer)
}
#endif
