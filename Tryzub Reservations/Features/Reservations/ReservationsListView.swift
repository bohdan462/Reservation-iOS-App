//
//  ReservationsListView.swift
//  Tryzub Reservations
//

import SwiftUI
import SwiftData

private func activeReservationWindowQueryBounds(daysAhead: Int = 120) -> (from: String, to: String) {
    let now = Date()
    let calendar = Calendar.current
    let from = calendar.date(byAdding: .day, value: -1, to: now) ?? now
    let to = calendar.date(byAdding: .day, value: daysAhead, to: now) ?? now
    return (from.reservationDateString(), to.reservationDateString())
}

// MARK: - Root Reservation Shell

struct ReservationsListView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var controller: ReservationsController
    @StateObject private var hiddenReservations = HiddenReservationsStore()
    @Query
    private var pendingReviewRows: [ReservationRecord]

    @State private var selectedTab: ReservationsAppTab = .host
    @State private var isLaunchLoadingPresented = true

    let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        _controller = StateObject(wrappedValue: ReservationsController(environment: environment))
        let bounds = activeReservationWindowQueryBounds()
        let fromDate = bounds.from
        let toDate = bounds.to
        _pendingReviewRows = Query(
            filter: #Predicate<ReservationRecord> { reservation in
                !reservation.isHidden
                    && reservation.reservationDate >= fromDate
                    && reservation.reservationDate <= toDate
                    && (reservation.status == "new" || reservation.status == "needs_review")
            }
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeDashboardView(
                environment: environment,
                isActive: selectedTab == .host,
                deferHomeNetworkLoads: isLaunchLoadingPresented
            )
            .tabItem {
                Label(hostTabTitle, systemImage: ReservationsAppTab.host.systemImage)
            }
            .tag(ReservationsAppTab.host)

            ReservationScheduleView(environment: environment, isActive: selectedTab == .bookings)
                .tabItem {
                    Label(ReservationsAppTab.bookings.title, systemImage: ReservationsAppTab.bookings.systemImage)
                }
                .badge(pendingReviewCount)
                .tag(ReservationsAppTab.bookings)

            GuestLookupView(environment: environment, isActive: selectedTab == .guests)
                .tabItem {
                    Label(ReservationsAppTab.guests.title, systemImage: ReservationsAppTab.guests.systemImage)
                }
                .tag(ReservationsAppTab.guests)

            ReservationMoreView(environment: environment)
                .tabItem {
                    Label(ReservationsAppTab.more.title, systemImage: ReservationsAppTab.more.systemImage)
                }
                .tag(ReservationsAppTab.more)
        }
        .fontDesign(.rounded)
        .environmentObject(controller)
        .environmentObject(hiddenReservations)
        .overlay(alignment: .topTrailing) {
            AppNoticeOverlay(
                notices: visibleNotices,
                onDismiss: controller.dismissNotice,
                onClearAll: controller.clearAllNotices
            )
            .padding(.top, noticeTopPadding)
            .padding(.trailing, 14)
        }
        .overlay {
            if isLaunchLoadingPresented {
                AppLaunchLoadingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(50)
            }
        }
        .task {
            await performInitialLaunchLoad()
        }
        .onAppear {
            controller.setPendingReviewAttentionCount(pendingReviewCount)
        }
        .onChange(of: pendingReviewCount) { _, count in
            controller.setPendingReviewAttentionCount(count)
        }
    }

    private func performInitialLaunchLoad() async {
        let minimumSplash = ContinuousClock.now

        // Never block the shell on network — show cached SwiftData and refresh in the background.
        Task {
            await controller.performStartupNetworkPass(context: modelContext)
        }

        let elapsed = minimumSplash.duration(to: .now)
        if elapsed < .seconds(1.1) {
            try? await Task.sleep(for: .seconds(1.1) - elapsed)
        }

        withAnimation(.easeInOut(duration: 0.42)) {
            isLaunchLoadingPresented = false
        }

        // Let the shell finish layout before staff actions can present iPad popovers/alerts.
        try? await Task.sleep(for: .milliseconds(200))
    }

    private var visibleNotices: [AppNotice] {
        controller.notices.filter { notice in
            switch notice.source {
            case .mutation, .email, .credentials:
                return true
            case .startup, .manualToday, .autoToday:
                return selectedTab == .host
            case .schedule:
                return selectedTab == .bookings
            case .review:
                return selectedTab == .bookings
            case .importFailures, .admin:
                return selectedTab == .host || selectedTab == .more
            }
        }
    }

    private var pendingReviewCount: Int {
        pendingReviewRows.count
    }

    private var hostTabTitle: String {
        environment.role == .developer ? "Dev" : ReservationsAppTab.host.title
    }

    private var noticeTopPadding: CGFloat {
        switch selectedTab {
        case .bookings:
            return 112
        case .host, .guests, .more:
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
    @Query
    private var reservations: [ReservationRecord]

    // MARK: - Local UI State

    @State private var showManualCreate = false
    @State private var showImportFailures = false
    @State private var selectedDate = Date()
    @State private var navigationPath: [Int] = []

    let environment: AppEnvironment
    let isActive: Bool
    let deferHomeNetworkLoads: Bool

    init(environment: AppEnvironment, isActive: Bool, deferHomeNetworkLoads: Bool = false) {
        self.environment = environment
        self.isActive = isActive
        self.deferHomeNetworkLoads = deferHomeNetworkLoads
        let bounds = activeReservationWindowQueryBounds()
        let fromDate = bounds.from
        let toDate = bounds.to
        _reservations = Query(
            filter: #Predicate<ReservationRecord> { reservation in
                !reservation.isHidden
                    && reservation.reservationDate >= fromDate
                    && reservation.reservationDate <= toDate
            },
            sort: [
                SortDescriptor(\ReservationRecord.reservationDate),
                SortDescriptor(\ReservationRecord.reservationTime)
            ]
        )
    }

    private var selectedDateReservations: [ReservationRecord] {
        guard isActive else { return [] }
        let selectedDateKey = selectedDate.reservationDateString()
        return ReservationRecord.sortedChronologically(
            reservations.filter {
                $0.reservationDate == selectedDateKey && !hiddenReservations.isHidden($0)
            }
        )
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            // Child view reads SwiftData cache and sends staff intent back to the controller.
            HostBoardView(
                reservations: selectedDateReservations,
                environment: environment,
                selectedDate: $selectedDate,
                failedImportCount: controller.importFailureCount,
                isVisible: isActive,
                deferNetworkLoads: deferHomeNetworkLoads,
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
                },
                onOpenReservation: { reservation in
                    navigationPath.append(reservation.remoteID)
                }
            )
            .refreshable {
                guard isActive else { return }
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
            .navigationDestination(for: Int.self) { remoteID in
                reservationDestination(remoteID: remoteID)
            }
        }
    }

    @ViewBuilder
    private func reservationDestination(remoteID: Int) -> some View {
        if let reservation = reservations.first(where: { $0.remoteID == remoteID }) {
            ReservationDetailView(reservation: reservation, environment: environment)
        } else {
            ContentUnavailableView(
                "Reservation Not Found",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("Refresh reservations and try again.")
            )
        }
    }

}

// MARK: - Schedule View

private struct ReservationScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var hiddenReservations: HiddenReservationsStore
    @Query
    private var reservations: [ReservationRecord]

    // MARK: - Local UI State

    @State private var scope: ReservationScheduleScope = .upcoming
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var scheduleDateFilter: Date?
    @State private var scheduleCalendarAnchor = Date()
    @State private var isLoadingAllPage = false
    @State private var allModeRecords: [ReservationRecord] = []
    @State private var allModeRemoteIDs: [Int] = []
    @State private var allModeLoadGeneration = 0
    @State private var allModeLoadedPage = 0
    @State private var allModeTotal: Int?
    @State private var allModeTotalPages = 0
    @State private var allModeErrorMessage: String?
    @State private var showManualCreate = false
    @State private var navigationPath: [Int] = []

    let environment: AppEnvironment
    let isActive: Bool

    init(environment: AppEnvironment, isActive: Bool) {
        self.environment = environment
        self.isActive = isActive
        let bounds = activeReservationWindowQueryBounds()
        let fromDate = bounds.from
        let toDate = bounds.to
        _reservations = Query(
            filter: #Predicate<ReservationRecord> { reservation in
                !reservation.isHidden
                    && reservation.reservationDate >= fromDate
                    && reservation.reservationDate <= toDate
            },
            sort: [
                SortDescriptor(\ReservationRecord.reservationDate),
                SortDescriptor(\ReservationRecord.reservationTime)
            ]
        )
    }

    // Schedule reads cached rows; sync freshness is handled by ReservationsController.
    private var displayedReservations: [ReservationRecord] {
        guard isActive else { return [] }
        let today = Date.reservationDateString()
        let trimmedSearchText = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)

        var rows = (scope == .all ? allModeRecords : reservations)
            .filter { !hiddenReservations.isHidden($0) }

        switch scope {
        case .upcoming:
            rows = rows.filter {
                $0.reservationDate >= today
                    && $0.statusValue != .completed
                    && $0.statusValue != .cancelled
                    && $0.statusValue != .noShow
            }
        case .needsReview:
            rows = rows.filter {
                $0.reservationDate >= today
                    && ($0.statusValue == .new || $0.statusValue == .needsReview)
            }
        case .cancelled:
            rows = rows.filter {
                $0.statusValue == .cancelled
            }
        case .all:
            break
        }

        if scope == .all, let scheduleDateFilter {
            let filterKey = scheduleDateFilter.reservationDateString()
            let cachedForDate = reservations.filter { $0.reservationDate == filterKey }
            let existingIDs = Set(rows.map(\.remoteID))
            rows.append(contentsOf: cachedForDate.filter { !existingIDs.contains($0.remoteID) })
            rows = rows.filter { $0.reservationDate == filterKey }
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
        NavigationStack(path: $navigationPath) {
            List {
                Section {
                    scheduleControls
                }

                if let allModeErrorMessage {
                    Section {
                        Label(allModeErrorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
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
                                    context: .schedule,
                                    onOpenDetails: { navigationPath.append($0.remoteID) }
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

                if scope == .all {
                    Section {
                        HStack(spacing: 12) {
                            Text(allModeSummaryText)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 8)

                            if allModeHasMore, scheduleDateFilter == nil {
                                Button {
                                    Task {
                                        await loadAllPage(reset: false, caller: "load_more_button")
                                    }
                                } label: {
                                    if isLoadingAllPage {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Text("Load More")
                                            .font(.caption.weight(.semibold))
                                    }
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.primary.opacity(0.82))
                                .padding(.horizontal, 10)
                                .frame(minHeight: 30)
                                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                                }
                                .disabled(isLoadingAllPage)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bookings")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Name, phone, email, table")
            .listStyle(.plain)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .contentMargins(.bottom, ReservationLayout.scrollBottomInset, for: .scrollContent)
            .refreshable {
                guard isActive else { return }
                if scope == .all {
                    await loadAllPage(reset: true, caller: "refreshable_all")
                } else {
                    // Bookings manual refresh stays on the shared active-window path unless All is explicit.
                    await controller.requestScheduleRefresh(context: modelContext)
                }
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
                            guard isActive else { return }
                            if scope == .all {
                                await loadAllPage(reset: true, caller: "toolbar_all")
                            } else {
                                // Bookings manual refresh stays on the shared active-window path unless All is explicit.
                                await controller.requestScheduleRefresh(context: modelContext)
                            }
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
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                // Bookings tab activation: controller fetches only when cached active window is stale.
                await controller.scheduleBecameActive(context: modelContext)
            }
            .task(id: searchText) {
                guard isActive else { return }
                let value = searchText
                try? await Task.sleep(for: .milliseconds(250))
                if !Task.isCancelled {
                    debouncedSearchText = value
                }
            }
            .onChange(of: scope) { _, newScope in
                allModeLoadGeneration += 1
                if newScope != .all {
                    isLoadingAllPage = false
                    return
                }

                if newScope == .all, isActive, allModeLoadedPage == 0 {
                    Task {
                        await loadAllPage(reset: true, caller: "scope_change_all")
                    }
                }
            }
            .onChange(of: debouncedSearchText) { _, _ in
                guard isActive, scope == .all else { return }
                allModeLoadGeneration += 1
                Task {
                    await loadAllPage(reset: true, caller: "search_change_all")
                }
            }
            .onChange(of: scheduleDateFilter) { _, newFilter in
                guard isActive, scope == .all, let newFilter else { return }
                Task {
                    let search = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                    try? await controller.refreshScheduleDate(
                        context: modelContext,
                        date: newFilter.reservationDateString(),
                        search: search
                    )
                }
            }
            .navigationDestination(for: Int.self) { remoteID in
                reservationDestination(remoteID: remoteID)
            }
        }
    }

    private var reviewAttentionCount: Int {
        let today = Date.reservationDateString()
        return reservations.filter { reservation in
            !hiddenReservations.isHidden(reservation)
                && reservation.reservationDate >= today
                && (reservation.statusValue == .new || reservation.statusValue == .needsReview)
        }.count
    }

    private var scheduleControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            TryzubSegmentedControl(
                segments: ReservationScheduleScope.allCases.map { scope in
                    TryzubSegmentedControl<ReservationScheduleScope>.Segment(
                        value: scope,
                        title: scope.rawValue,
                        attentionDotStyle: scope == .needsReview && reviewAttentionCount > 0
                            ? .greenFlashing
                            : nil
                    )
                },
                selection: $scope
            )

            if scope == .all {
                ReservationOptionalDateFilter(
                    filterDate: $scheduleDateFilter,
                    calendarAnchor: $scheduleCalendarAnchor
                )
            }
        }
    }

    private var allModeSummaryText: String {
        if let scheduleDateFilter {
            let dateLabel = scheduleDateFilter.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            return "Showing \(displayedReservations.count) on \(dateLabel)"
        }

        guard let allModeTotal else {
            return isLoadingAllPage ? "Loading history..." : "History not loaded"
        }

        return "Showing \(min(displayedReservations.count, allModeTotal)) of \(allModeTotal)"
    }

    private var allModeHasMore: Bool {
        scope == .all && scheduleDateFilter == nil && allModeLoadedPage > 0 && allModeLoadedPage < allModeTotalPages
    }

    private func loadAllPage(reset: Bool, caller: String) async {
        guard isActive, scope == .all else {
            ReservationAPILogger.skip(
                reason: .scheduleAllBlocked,
                message: "schedule_all_page blocked caller=\(caller) scope=\(scope.rawValue) isActive=\(isActive)"
            )
            return
        }

        guard !isLoadingAllPage else { return }
        isLoadingAllPage = true
        allModeErrorMessage = nil
        let generation = allModeLoadGeneration
        defer { isLoadingAllPage = false }

        let page = reset ? 1 : allModeLoadedPage + 1
        let search = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank

        do {
            let response = try await controller.loadScheduleAllPage(
                context: modelContext,
                page: page,
                search: search,
                isAllScope: scope == .all,
                isScheduleTabActive: isActive,
                callerContext: "\(caller) tab=Schedule scope=\(scope.rawValue) generation=\(generation)",
                isStillAllowed: {
                    isActive && scope == .all && generation == allModeLoadGeneration
                }
            )
            guard generation == allModeLoadGeneration, isActive, scope == .all else {
                ReservationAPILogger.skip(
                    reason: .scheduleAllBlocked,
                    message: "schedule_all_page result ignored caller=\(caller) generation=\(generation) currentGeneration=\(allModeLoadGeneration) scope=\(scope.rawValue) isActive=\(isActive)"
                )
                return
            }
            if reset {
                allModeRemoteIDs = []
                allModeRecords = []
            }
            let existingIDs = Set(allModeRemoteIDs)
            allModeRemoteIDs.append(contentsOf: response.data.map(\.id).filter { !existingIDs.contains($0) })
            refreshAllModeRecords()
            allModeLoadedPage = page
            allModeTotal = response.total
            allModeTotalPages = response.totalPages
        } catch {
            allModeErrorMessage = error.localizedDescription
        }
    }

    private func refreshAllModeRecords() {
        guard !allModeRemoteIDs.isEmpty else {
            allModeRecords = []
            return
        }

        do {
            let repository = ReservationRepository(context: modelContext)
            allModeRecords = ReservationRecord.sortedNewestFirst(
                try repository.records(remoteIDs: allModeRemoteIDs)
            )
        } catch {
            allModeErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func reservationDestination(remoteID: Int) -> some View {
        let lookupRows = scope == .all ? allModeRecords : reservations
        if let reservation = lookupRows.first(where: { $0.remoteID == remoteID }) {
            ReservationDetailView(reservation: reservation, environment: environment)
        } else {
            ContentUnavailableView(
                "Reservation Not Found",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("Refresh the schedule and try again.")
            )
        }
    }
}

// MARK: - Pending Review View

private struct ReservationReviewQueueView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var hiddenReservations: HiddenReservationsStore

    // MARK: - Local UI State

    @State private var scope: ReservationQueueScope = .pending
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var navigationPath: [Int] = []

    let reservations: [ReservationRecord]
    let environment: AppEnvironment
    let isActive: Bool

    private var visibleReservations: [ReservationRecord] {
        reservations.filter { !hiddenReservations.isHidden($0) }
    }

    private var pendingAttentionCount: Int {
        visibleReservations.filter {
            $0.statusValue == .new || $0.statusValue == .needsReview
        }.count
    }

    private var needsReviewCount: Int {
        visibleReservations.filter { $0.statusValue == .needsReview }.count
    }

    // Pending is the staff default: new and needs_review, oldest submitted first.
    private var queueReservations: [ReservationRecord] {
        guard isActive else { return [] }
        let trimmedSearchText = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        NavigationStack(path: $navigationPath) {
            List {
                Section {
                    Picker("Queue", selection: $scope) {
                        Text(queuePickerLabel(for: .pending)).tag(ReservationQueueScope.pending)
                        Text(queuePickerLabel(for: .needsReview)).tag(ReservationQueueScope.needsReview)
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
                                contextNote: reviewContext(for: reservation),
                                onOpenDetails: { navigationPath.append($0.remoteID) }
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
            .contentMargins(.bottom, ReservationLayout.scrollBottomInset, for: .scrollContent)
            .refreshable {
                guard isActive else { return }
                // Staff manual queue refresh: controller fetches new + needs_review.
                await controller.requestReviewRefresh(context: modelContext)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            guard isActive else { return }
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
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                // Legacy Review screen activation; visible Needs Review now lives in Bookings.
                await controller.reviewBecameActive(context: modelContext)
            }
            .task(id: searchText) {
                guard isActive else { return }
                let value = searchText
                try? await Task.sleep(for: .milliseconds(250))
                if !Task.isCancelled {
                    debouncedSearchText = value
                }
            }
            .navigationDestination(for: Int.self) { remoteID in
                reservationDestination(remoteID: remoteID)
            }
        }
    }

    @ViewBuilder
    private func reservationDestination(remoteID: Int) -> some View {
        if let reservation = reservations.first(where: { $0.remoteID == remoteID }) {
            ReservationDetailView(reservation: reservation, environment: environment)
        } else {
            ContentUnavailableView(
                "Reservation Not Found",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("Refresh review and try again.")
            )
        }
    }

    private func queuePickerLabel(for scope: ReservationQueueScope) -> String {
        switch scope {
        case .pending:
            let count = pendingAttentionCount
            return count > 0 ? "Pending (\(count))" : "Pending"
        case .needsReview:
            let count = needsReviewCount
            return count > 0 ? "Needs Review (\(count))" : "Needs Review"
        }
    }

    // Intent: Small operational context for pending queue triage.
    private func reviewContext(for reservation: ReservationRecord) -> String? {
        if reservation.statusValue == .needsReview {
            return "Needs review"
        }

        if reservation.partySize >= 7 {
            return "Large party"
        }

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

        if sameTime.count > 1 {
            return "Same time conflict"
        }

        if dayGuests >= 20 {
            return "Busy service day"
        }

        return nil
    }
}

// MARK: - More View

private struct ReservationMoreView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var roleStore: AppRoleStore

    @StateObject private var settingsStore: RestaurantSettingsStore
    @State private var showManualCreate = false
    @State private var showFailedImports = false
    @State private var path: [ReservationMoreDestination] = []

    let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        _settingsStore = StateObject(
            wrappedValue: RestaurantSettingsStore(apiClient: environment.apiClient)
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: ReservationMoreDestination.notices) {
                        HStack {
                            Label("Notices", systemImage: "bell")
                            Spacer()
                            if !controller.notices.isEmpty {
                                Text("\(controller.notices.count)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("App Mode") {
                    Picker(
                        "Role",
                        selection: Binding(
                            get: { roleStore.selectedRole ?? controller.environment.role },
                            set: { roleStore.select($0) }
                        )
                    ) {
                        ForEach(AppRoleStore.selectableRoles, id: \.self) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section("Restaurant Operations") {
                    NavigationLink(value: ReservationMoreDestination.cancelled) {
                        Label("Cancelled Reservations", systemImage: "xmark.circle")
                    }

                    if controller.capabilities.canViewHiddenReservations {
                        NavigationLink(value: ReservationMoreDestination.hidden) {
                            Label("Hidden Reservations", systemImage: "archivebox")
                        }
                    }

                    if controller.capabilities.canManageRestaurantSettings {
                        NavigationLink(value: ReservationMoreDestination.restaurantSettings) {
                            Label("Restaurant Settings", systemImage: "gearshape")
                        }

                        NavigationLink(value: ReservationMoreDestination.todayAvailability) {
                            Label("Today Availability", systemImage: "calendar.badge.clock")
                        }

                        NavigationLink(value: ReservationMoreDestination.weeklyHours) {
                            Label("Weekly Hours", systemImage: "clock")
                        }

                        NavigationLink(value: ReservationMoreDestination.blockedTimeSlots) {
                            Label("Blocked Time Slots", systemImage: "nosign")
                        }
                    }

                    if controller.capabilities.canCreateManualReservations {
                        Button {
                            showManualCreate = true
                        } label: {
                            Label("Create Manual Reservation", systemImage: "plus.circle")
                        }
                    }
                }

                Section("Business") {
                    if controller.capabilities.canViewAnalytics {
                        NavigationLink(value: ReservationMoreDestination.businessAnalytics) {
                            Label("Business Analytics", systemImage: "chart.bar")
                        }
                    }

                    NavigationLink(value: ReservationMoreDestination.regularGuests) {
                        Label("Regulars / Guest Memory", systemImage: "person.2.crop.square.stack")
                    }
                }

                if controller.capabilities.canViewFailedImports
                    || controller.capabilities.canViewDeveloperDiagnostics {
                    Section("Developer / Support") {
                        if controller.capabilities.canViewFailedImports {
                            Button {
                                showFailedImports = true
                            } label: {
                                Label("Failed Imports", systemImage: "exclamationmark.triangle")
                            }
                        }

                        if controller.capabilities.canViewDeveloperDiagnostics {
                            NavigationLink(value: ReservationMoreDestination.diagnostics) {
                                Label("API & App Diagnostics", systemImage: "stethoscope")
                            }
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
            .contentMargins(.bottom, ReservationLayout.scrollBottomInset, for: .scrollContent)
            .navigationDestination(for: ReservationMoreDestination.self) { destination in
                moreDestination(destination)
            }
            .fullScreenCover(isPresented: $showManualCreate) {
                ManualReservationFormView { request in
                    // Manual call-in create is accepted immediately; no email is sent.
                    try await controller.createAcceptedManualReservation(request, context: modelContext)
                }
            }
            .sheet(isPresented: $showFailedImports) {
                ImportFailuresView(
                    environment: environment,
                    onCreateReservation: { request in
                        try await controller.createAcceptedManualReservation(request, context: modelContext)
                    },
                    onCreated: { _ in }
                )
                .environmentObject(controller)
            }
        }
    }

    @ViewBuilder
    private func moreDestination(_ destination: ReservationMoreDestination) -> some View {
        switch destination {
        case .cancelled:
            CancelledReservationsView(
                environment: environment,
                onOpenDetails: { reservation in
                    path.append(.cancelledDetail(remoteID: reservation.remoteID))
                }
            )
        case .cancelledDetail(let remoteID):
            ReservationDetailDestinationView(remoteID: remoteID, environment: environment)
        case .hidden:
            HiddenReservationsView(environment: environment)
        case .restaurantSettings:
            RestaurantSettingsView(settingsStore: settingsStore)
        case .todayAvailability:
            TodayAvailabilityView(settingsStore: settingsStore)
        case .weeklyHours:
            WeeklyHoursView(settingsStore: settingsStore)
        case .blockedTimeSlots:
            BlockedTimeSlotsView(settingsStore: settingsStore)
        case .businessAnalytics:
            BusinessAnalyticsView(settingsStore: settingsStore)
        case .regularGuests:
            RegularGuestsView()
        case .diagnostics:
            DeveloperDiagnosticsView(environment: environment)
                .environmentObject(controller)
        case .notices:
            AppNoticesScreen(
                notices: controller.notices,
                onDismiss: controller.dismissNotice,
                onClearAll: controller.clearAllNotices
            )
        }
    }
}

private enum ReservationMoreDestination: Hashable {
    case notices
    case cancelled
    case cancelledDetail(remoteID: Int)
    case hidden
    case restaurantSettings
    case todayAvailability
    case weeklyHours
    case blockedTimeSlots
    case businessAnalytics
    case regularGuests
    case diagnostics
}

private struct ReservationDetailDestinationView: View {
    @Query private var reservations: [ReservationRecord]

    let remoteID: Int
    let environment: AppEnvironment

    init(remoteID: Int, environment: AppEnvironment) {
        self.remoteID = remoteID
        self.environment = environment
        _reservations = Query(
            filter: #Predicate<ReservationRecord> { $0.remoteID == remoteID },
            sort: [
                SortDescriptor(\ReservationRecord.reservationDate, order: .reverse),
                SortDescriptor(\ReservationRecord.reservationTime, order: .reverse)
            ]
        )
    }

    var body: some View {
        if let reservation = reservations.first {
            ReservationDetailView(reservation: reservation, environment: environment)
        } else {
            ContentUnavailableView(
                "Reservation Not Found",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("Refresh reservations and try again.")
            )
        }
    }
}

// MARK: - Cancelled Reservations View

private struct CancelledReservationsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var hiddenReservations: HiddenReservationsStore
    @Query
    private var reservations: [ReservationRecord]

    let environment: AppEnvironment
    let onOpenDetails: (ReservationRecord) -> Void

    @State private var isLoading = false
    @State private var errorMessage: String?

    private let window: (from: String, to: String)

    init(
        environment: AppEnvironment,
        onOpenDetails: @escaping (ReservationRecord) -> Void
    ) {
        self.environment = environment
        self.onOpenDetails = onOpenDetails
        let window = CancelledReservationsPresenter.defaultWindow()
        self.window = window
        let statusCancelled = ReservationStatus.cancelled.rawValue
        let from = window.from
        let to = window.to
        _reservations = Query(
            filter: #Predicate<ReservationRecord> { record in
                record.status == statusCancelled
                    && record.reservationDate >= from
                    && record.reservationDate <= to
            },
            sort: [
                SortDescriptor(\ReservationRecord.reservationDate, order: .reverse),
                SortDescriptor(\ReservationRecord.reservationTime, order: .reverse)
            ]
        )
    }

    private var cancelledRows: [ReservationRecord] {
        ReservationRecord.sortedNewestFirst(
            reservations.filter {
                $0.statusValue == .cancelled
                    && !hiddenReservations.isHidden($0)
                    && $0.reservationDate >= window.from
                    && $0.reservationDate <= window.to
            }
        )
    }

    var body: some View {
        List {
            Section {
                Text("Real cancelled reservations from \(window.from) through \(window.to). Hidden/test rows live in admin cleanup instead.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            if isLoading && cancelledRows.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading cancelled reservations...")
                        Spacer()
                    }
                    .padding(.vertical, 24)
                }
            } else if cancelledRows.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Cancelled Reservations",
                        systemImage: "xmark.circle",
                        description: Text("Cancelled guest self-service and staff cancellations will appear here.")
                    )
                }
            } else {
                Section("Cancelled reservations") {
                    ForEach(cancelledRows) { reservation in
                        ReservationNavigationRow(
                            reservation: reservation,
                            environment: environment,
                            context: .schedule,
                            contextNote: "Cancelled",
                            onOpenDetails: onOpenDetails
                        )
                    }
                }
            }
        }
        .navigationTitle("Cancelled Reservations")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.plain)
        .contentMargins(.bottom, ReservationLayout.scrollBottomInset, for: .scrollContent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load(force: true) }
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
        .task {
            // Lazy screen load: status=cancelled window fetch, upsert-only.
            await load(force: false)
        }
        .refreshable {
            // Staff manual refresh: forces the cancelled status window fetch.
            await load(force: true)
        }
    }

    private func load(force: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            _ = try await controller.loadCancelledReservations(context: modelContext, force: force)
        } catch {
            if !error.isCancellationLike {
                errorMessage = error.isOfflineLike
                    ? "You're offline. Showing saved data."
                    : error.localizedDescription
            }
        }
    }
}

private enum CancelledReservationsPresenter {
    static func defaultWindow() -> (from: String, to: String) {
        let now = Date()
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let to = calendar.date(byAdding: .day, value: 60, to: now) ?? now
        return (from.reservationDateString(), to.reservationDateString())
    }
}

// MARK: - Hidden Reservations View

private struct HiddenReservationsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @Query
    private var reservations: [ReservationRecord]

    let environment: AppEnvironment

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hardDeleteCandidate: ReservationRecord?
    @State private var hardDeletingIDs: Set<Int> = []
    @State private var loadedPage = 0
    @State private var totalPages = 1

    private var hiddenRows: [ReservationRecord] {
        ReservationRecord.sortedNewestFirst(
            reservations.filter(\.isHidden)
        )
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        _reservations = Query(
            filter: #Predicate<ReservationRecord> { record in
                record.isHidden
            },
            sort: [
                SortDescriptor(\ReservationRecord.reservationDate, order: .reverse),
                SortDescriptor(\ReservationRecord.reservationTime, order: .reverse)
            ]
        )
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            if isLoading && hiddenRows.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading hidden reservations...")
                        Spacer()
                    }
                    .padding(.vertical, 24)
                }
            } else if hiddenRows.isEmpty {
                ContentUnavailableView(
                    "No Hidden Reservations",
                    systemImage: "archivebox",
                    description: Text("Wrong manual entries hidden from service lists will appear here.")
                )
            } else {
                Section("Hidden from service lists") {
                    ForEach(hiddenRows) { reservation in
                        VStack(alignment: .leading, spacing: 10) {
                            NavigationLink {
                                ReservationDetailView(reservation: reservation, environment: environment)
                            } label: {
                                HiddenReservationRow(reservation: reservation)
                            }
                            .buttonStyle(.plain)

                            Button {
                                Task {
                                    await restore(reservation)
                                }
                            } label: {
                                Label("Restore to lists", systemImage: "arrow.uturn.backward")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 38)
                            }
                            .buttonStyle(.plain)
                            .disabled(controller.isNetworkDegraded)
                            .foregroundStyle(.primary.opacity(0.82))
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                            }

                            if controller.capabilities.canHardDeleteReservations {
                                Button(role: .destructive) {
                                    hardDeleteCandidate = reservation
                                } label: {
                                    if hardDeletingIDs.contains(reservation.remoteID) {
                                        ProgressView()
                                            .frame(maxWidth: .infinity, minHeight: 38)
                                    } else {
                                        Label("Permanently delete test reservation", systemImage: "trash")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity, minHeight: 38)
                                    }
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                                        .stroke(Color.red.opacity(0.28), lineWidth: 1)
                                }
                                .disabled(hardDeletingIDs.contains(reservation.remoteID) || controller.isNetworkDegraded)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    if loadedPage > 0 && loadedPage < totalPages {
                        Button {
                            Task {
                                await loadHiddenReservations(force: false, page: loadedPage + 1)
                            }
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            } else {
                                Text("Load More")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                        }
                        .disabled(isLoading)
                    }
                }
            }
        }
        .listStyle(.plain)
        .contentMargins(.bottom, ReservationLayout.scrollBottomInset, for: .scrollContent)
        .navigationTitle("Hidden Reservations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await loadHiddenReservations(force: true, page: 1)
                    }
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
        .confirmationDialog(
            "Permanently delete this test reservation?",
            isPresented: Binding(
                get: { hardDeleteCandidate != nil },
                set: { if !$0 { hardDeleteCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Permanently delete test reservation", role: .destructive) {
                if let candidate = hardDeleteCandidate {
                    Task {
                        await hardDelete(candidate)
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                hardDeleteCandidate = nil
            }
        } message: {
            Text("Use permanent delete only for admin/developer cleanup of test or noise reservations. Staff should normally hide wrong entries.")
        }
        .task {
            // Lazy admin/dev load: hidden rows are fetched only when this screen opens.
            await loadHiddenReservations(force: hiddenRows.isEmpty, page: 1)
        }
        .refreshable {
            await loadHiddenReservations(force: true, page: 1)
        }
    }

    private func loadHiddenReservations(force: Bool, page: Int) async {
        guard !isLoading else { return }
        guard controller.capabilities.canViewHiddenReservations else {
            errorMessage = "This account cannot view hidden reservations."
            return
        }
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let response = try await controller.loadHiddenReservationsPage(
                context: modelContext,
                page: page,
                force: force
            )
            loadedPage = page == 1 ? response.page : max(loadedPage, response.page)
            totalPages = max(response.totalPages, 1)
        } catch {
            errorMessage = error.isOfflineLike
                ? "No internet connection. Showing saved reservations."
                : "Could not load hidden reservations. Please try again."
        }
    }

    private func restore(_ reservation: ReservationRecord) async {
        errorMessage = nil
        do {
            _ = try await controller.restoreHiddenReservation(
                reservation: reservation,
                context: modelContext
            )
            ReservationHaptics.success()
        } catch {
            errorMessage = "Could not restore this reservation. Please try again."
            ReservationHaptics.warning()
        }
    }

    private func hardDelete(_ reservation: ReservationRecord) async {
        let remoteID = reservation.remoteID
        guard !hardDeletingIDs.contains(remoteID) else { return }

        hardDeleteCandidate = nil
        hardDeletingIDs.insert(remoteID)
        errorMessage = nil

        defer {
            hardDeletingIDs.remove(remoteID)
        }

        do {
            try await controller.hardDeleteReservation(
                reservation: reservation,
                context: modelContext,
                cleanupReason: "iOS admin test cleanup"
            )
            ReservationHaptics.warning()
        } catch {
            errorMessage = "Could not permanently delete this test reservation. Please try again."
            ReservationHaptics.warning()
        }
    }
}

private struct HiddenReservationRow: View {
    let reservation: ReservationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(reservation.guestName)
                    .font(.headline.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(reservation.sourceDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 12) {
                Label(reservation.displayDate, systemImage: "calendar")
                Label(reservation.displayTime, systemImage: "clock")
                if !reservation.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(reservation.formattedPhone, systemImage: "phone")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            HiddenReservationInfoLine(title: "Reason", value: reservation.hiddenReason?.nilIfBlank ?? "Hidden wrong entry")
            HiddenReservationInfoLine(title: "Hidden", value: HiddenReservationDateFormatting.server(reservation.hiddenAt))
        }
        .padding(.vertical, 4)
    }
}

private struct HiddenReservationInfoLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}

private enum HiddenReservationDateFormatting {
    private static let parser: DateFormatter = {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return parser
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func server(_ dateString: String?) -> String {
        guard let dateString = dateString?.nilIfBlank else {
            return "-"
        }

        guard let date = parser.date(from: dateString) else {
            return dateString
        }

        return displayFormatter.string(from: date)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
    let onOpenDetails: (ReservationRecord) -> Void

    @State private var pendingAction: ReservationHostAction?
    @State private var tableAssignmentReservation: ReservationRecord?
    @State private var seatPromptReservation: ReservationRecord?
    @State private var seatAfterTableAssignment = false
    @State private var hideCandidate: ReservationRecord?
    @State private var hardDeleteCandidate: ReservationRecord?

    var body: some View {
        ReservationRowView(
            reservation: reservation,
            context: context,
            contextNote: contextNote,
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
                isBusy: controller.isActionInProgress(for: reservation) || controller.isNetworkDegraded,
                onAction: { action in
                    handleAction(action)
                },
                onSeatRequiresTableChoice: {
                    seatPromptReservation = reservation
                }
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            ReservationHaptics.selection()
            onOpenDetails(reservation)
        }
        .onLongPressGesture {
            ReservationHaptics.lightImpact()
        }
        .contextMenu {
            Button {
                onOpenDetails(reservation)
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

            if showsReservationCleanupActions {
                Divider()

                if canHideFromLongPress {
                    Button(role: .destructive) {
                        hideCandidate = reservation
                    } label: {
                        Label("Hide from normal lists", systemImage: "eye.slash")
                    }
                    .disabled(controller.isNetworkDegraded || controller.isActionInProgress(for: reservation))
                }

                if controller.capabilities.canHardDeleteReservations {
                    Button(role: .destructive) {
                        hardDeleteCandidate = reservation
                    } label: {
                        Label("Permanently delete", systemImage: "trash")
                    }
                    .disabled(controller.isNetworkDegraded || controller.isActionInProgress(for: reservation))
                }
            }
        }
        .reservationSeatTableChoice(
            seatPromptReservation: $seatPromptReservation,
            onAssignTable: { reservation in
                seatAfterTableAssignment = true
                tableAssignmentReservation = reservation
            },
            onSeatWithoutTable: { _ in
                Task { await perform(.seat) }
            }
        )
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

                    ReservationConfirmDialog.backendEmailButton(
                        hasUsableEmail: reservation.hasUsableConfirmationEmail
                    ) {
                        Task {
                            await perform(.confirmAndSendEmail)
                        }
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
        .confirmationDialog(
            "Hide this reservation?",
            isPresented: Binding(
                get: { hideCandidate != nil },
                set: { if !$0 { hideCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Hide from normal lists", role: .destructive) {
                if let candidate = hideCandidate {
                    Task {
                        await hideReservation(candidate)
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                hideCandidate = nil
            }
        } message: {
            Text(hideConfirmationMessage)
        }
        .confirmationDialog(
            "Permanently delete this reservation?",
            isPresented: Binding(
                get: { hardDeleteCandidate != nil },
                set: { if !$0 { hardDeleteCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Permanently delete reservation", role: .destructive) {
                if let candidate = hardDeleteCandidate {
                    Task {
                        await hardDeleteReservation(candidate)
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                hardDeleteCandidate = nil
            }
        } message: {
            Text("Developer mode only. This permanently removes the server reservation and deletes the local cache row after the server confirms.")
        }
        .sheet(item: $tableAssignmentReservation) { reservation in
            TableAssignmentSheet(reservation: reservation) { tableName in
                _ = try await controller.updateReservation(
                    id: reservation.remoteID,
                    request: ReservationUpdateRequest(tableName: tableName),
                    context: modelContext
                )
                if seatAfterTableAssignment {
                    seatAfterTableAssignment = false
                    await controller.updateStatus(
                        reservation: reservation,
                        status: .seated,
                        context: modelContext
                    )
                    ReservationHaptics.success()
                }
            }
        }
    }

    // MARK: - Available Staff Actions

    // Intent: Rows expose compact staff actions; no API clients/services are created here.
    private var contextMenuActions: [ReservationHostAction] {
        ReservationHostActionPolicy(
            reservation: reservation,
            capabilities: controller.capabilities
        )
        .contextMenuActions
    }

    private var canHideFromLongPress: Bool {
        guard !reservation.isHidden else { return false }

        if controller.capabilities.canHardDeleteReservations {
            return true
        }

        return reservation.canSoftHideAsWrongEntry
    }

    private var showsReservationCleanupActions: Bool {
        canHideFromLongPress || controller.capabilities.canHardDeleteReservations
    }

    private var hideConfirmationMessage: String {
        if controller.capabilities.canHardDeleteReservations {
            return "Developer mode can hide any reservation from normal staff lists without deleting backend history."
        }

        return "Staff and manager modes can only hide manual reservations. The reservation remains in backend history."
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
            guard ReservationEmailWorkflow.isBackendConfirmEmailEnabled else { return }
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

    // Intent: Long-press cleanup action. Non-developer modes only reach this for manual rows.
    // Network: PATCH /managed-reservations/{id} with is_hidden=true.
    private func hideReservation(_ reservation: ReservationRecord) async {
        hideCandidate = nil

        do {
            let reason = controller.capabilities.canHardDeleteReservations
                ? "iOS developer cleanup"
                : "Wrong manual entry"
            _ = try await controller.hideWrongEntry(
                reservation: reservation,
                reason: reason,
                context: modelContext
            )
            ReservationHaptics.warning()
        } catch {
            ReservationHaptics.warning()
        }
    }

    // Intent: Developer-only cleanup of test/noise reservations.
    // Network: DELETE /managed-reservations/{id}?force=1.
    private func hardDeleteReservation(_ reservation: ReservationRecord) async {
        hardDeleteCandidate = nil

        do {
            try await controller.hardDeleteReservation(
                reservation: reservation,
                context: modelContext,
                cleanupReason: "iOS developer long-press cleanup"
            )
            ReservationHaptics.warning()
        } catch {
            ReservationHaptics.warning()
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Reservations") {
    let roleStore = AppRoleStore()
    roleStore.select(.developer)

    return ReservationsListView(environment: AppEnvironment(apiClient: ReservationsAPIClient.preview, role: .developer))
        .environmentObject(roleStore)
        .modelContainer(ReservationPreviewData.previewContainer)
}
#endif
