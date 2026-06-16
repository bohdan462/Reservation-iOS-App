//
//  FloorPlanView.swift
//  Tryzub Reservations
//

import SwiftUI
import SwiftData

struct FloorPlanView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @ObservedObject var store: FloorPlanStore

    let isActive: Bool

    @State private var selectedDate = Date()
    @State private var assignmentContext: FloorPlanAssignmentContext?
    @State private var tableAssignmentReservation: ReservationRecord?
    @State private var showLayoutSetup = false

    private var selectedDateKey: String {
        selectedDate.reservationDateString()
    }

    private var isShowingStaleContent: Bool {
        store.viewState.selectedDate != selectedDateKey
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    if isShowingStaleContent {
                        dateLoadingState
                    } else if store.viewState.hasTables {
                        gridSection
                        assignedReservationsSection
                        unassignedSection
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(TryzubColors.screenBackground)
            .navigationTitle("Floor Plan")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refresh(date: selectedDateKey, force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(store.isLoading)
                }
                if !isShowingStaleContent && store.viewState.hasTables {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Edit Layout") {
                            showLayoutSetup = true
                        }
                    }
                }
            }
            .sheet(item: $assignmentContext) { context in
                FloorPlanTableAssignmentSheet(
                    context: context,
                    tableBlocks: store.viewState.tableBlocks,
                    unassignedReservations: store.viewState.unassignedReservations,
                    isWorking: store.isAssigning,
                    onAssign: { reservationID, tableKeys in
                        Task {
                            await store.assign(
                                reservationID: reservationID,
                                tableKeys: tableKeys,
                                controller: controller,
                                context: modelContext
                            )
                            if store.conflict == nil {
                                assignmentContext = nil
                            }
                        }
                    },
                    onClear: { reservationID in
                        Task {
                            await store.clearAssignment(
                                reservationID: reservationID,
                                controller: controller,
                                context: modelContext
                            )
                            assignmentContext = nil
                        }
                    },
                    onDismiss: {
                        assignmentContext = nil
                    }
                )
            }
            .sheet(item: $tableAssignmentReservation) { reservation in
                TableAssignmentSheet(reservation: reservation) { tableName in
                    await TableAssignmentCoordinator.assign(
                        reservationID: reservation.remoteID,
                        tableName: tableName,
                        floorPlanStore: store,
                        controller: controller,
                        context: modelContext
                    )
                    await store.refresh(date: selectedDateKey, force: true)
                }
            }
            .sheet(isPresented: $showLayoutSetup) {
                FloorPlanLayoutSetupView(store: store) {
                    showLayoutSetup = false
                }
            }
            .alert(
                "Table assignment conflict",
                isPresented: conflictBinding,
                presenting: store.conflict
            ) { _ in
                Button("Refresh Floor Plan") {
                    store.dismissConflict()
                    Task { await store.refresh(date: selectedDateKey, force: true) }
                }
                Button("OK", role: .cancel) {
                    store.dismissConflict()
                }
            } message: { conflict in
                Text(conflict.message)
            }
            .onAppear {
                loadForSelectedDate()
                floorDateTrace(fetchDate: selectedDateKey)
                store.setAutoRefreshActive(isActive && store.viewState.isToday)
            }
            .onDisappear {
                store.setAutoRefreshActive(false)
            }
            .onChange(of: isActive) { _, active in
                store.setAutoRefreshActive(active && store.viewState.isToday)
            }
            .onChange(of: selectedDate) { _, date in
                loadForSelectedDate(date)
                assignmentContext = nil
                tableAssignmentReservation = nil
                floorDateTrace(fetchDate: date.reservationDateString())
            }
            .onChange(of: store.viewState.isToday) { _, isToday in
                store.setAutoRefreshActive(isActive && isToday)
            }
            .onChange(of: store.viewState.selectedDate) { _, _ in
                floorDateTrace(fetchDate: selectedDateKey)
            }
        }
    }

    private var usesWideServiceHeader: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var headerCard: some View {
        Group {
            if usesWideServiceHeader {
                wideServiceHeaderCard
            } else {
                compactServiceHeaderCard
            }
        }
    }

    private var compactServiceHeaderCard: some View {
        TryzubChartCard(title: "Service", systemImage: "calendar") {
            VStack(alignment: .leading, spacing: 12) {
                DatePicker(
                    "Service date",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)

                HStack {
                    serviceModeBadge

                    Spacer()

                    Text(isShowingStaleContent ? "Loading selected date…" : store.viewState.lastCheckedLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    serviceStatusTrailing
                }

                serviceHeaderFooter
            }
        }
    }

    private var wideServiceHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(TryzubTypography.sectionTitle)
                        .foregroundStyle(TryzubColors.primaryText)

                    Text("Service")
                        .font(TryzubTypography.sectionTitle)
                        .foregroundStyle(TryzubColors.primaryText)

                    serviceModeBadge
                }

                Spacer(minLength: 8)

                DatePicker(
                    "Service date",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            }

            HStack(spacing: 12) {
                Text(isShowingStaleContent ? "Loading selected date…" : store.viewState.lastCheckedLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                serviceStatusTrailing
            }

            serviceHeaderFooter
        }
        .padding(TryzubSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(TryzubColors.cardBackground, in: RoundedRectangle(cornerRadius: TryzubSpacing.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TryzubSpacing.cornerRadius, style: .continuous)
                .stroke(TryzubColors.border, lineWidth: 1)
        }
    }

    private var serviceModeBadge: some View {
        Label(headerMode.badgeTitle, systemImage: "circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(headerMode == .liveService ? TryzubColors.success : TryzubColors.info)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (headerMode == .liveService ? TryzubColors.success : TryzubColors.info)
                    .opacity(0.12)
            )
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var serviceStatusTrailing: some View {
        if !isShowingStaleContent && store.viewState.unassignedCount > 0 {
            Text("\(store.viewState.unassignedCount) unassigned")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TryzubColors.warning)
        }
    }

    @ViewBuilder
    private var serviceHeaderFooter: some View {
        if store.isLoading {
            HStack(spacing: 8) {
                TryzubSubtleLoadingDot(diameter: 6)
                Text("Loading floor plan…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let errorMessage = store.errorMessage {
            StaffFormErrorCaption(message: errorMessage)
        }
    }

    private var headerMode: FloorPlanMode {
        isShowingStaleContent ? .planning : store.viewState.mode
    }

    private var dateLoadingState: some View {
        TryzubChartCard(title: "Floor plan", systemImage: "square.grid.3x3") {
            HStack(spacing: 10) {
                TryzubSubtleLoadingDot(diameter: 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Loading \(FloorPlanPresentation.displayDate(selectedDateKey))")
                        .font(.subheadline.weight(.semibold))
                    Text("Reservations and table assignments are hidden until this date loads.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var gridSection: some View {
        FloorPlanGridView(
            viewState: store.viewState,
            unitSize: 44,
            onTableTap: { block in
                assignmentContext = .table(block)
            }
        )
        .frame(minHeight: 320)
    }

    private var reservationGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: usesWideServiceHeader ? 168 : 148), spacing: 10)]
    }

    @ViewBuilder
    private var assignedReservationsSection: some View {
        if !store.viewState.assignedReservations.isEmpty {
            FloorPlanReservationGridSection(
                title: "Assigned",
                systemImage: "table.furniture"
            ) {
                LazyVGrid(columns: reservationGridColumns, alignment: .leading, spacing: 10) {
                    ForEach(store.viewState.assignedReservations) { item in
                        FloorPlanAssignedReservationCard(item: item) {
                            openTableAssignment(for: item.reservation.id)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var unassignedSection: some View {
        if !store.viewState.unassignedReservations.isEmpty {
            FloorPlanReservationGridSection(
                title: "Unassigned",
                systemImage: "person.crop.circle.badge.questionmark"
            ) {
                LazyVGrid(columns: reservationGridColumns, alignment: .leading, spacing: 10) {
                    ForEach(store.viewState.unassignedReservations) { reservation in
                        FloorPlanUnassignedReservationCard(reservation: reservation) {
                            openTableAssignment(for: reservation.id)
                        }
                    }
                }
            }
        }
    }

    private func openTableAssignment(for reservationID: Int) {
        let predicate = #Predicate<ReservationRecord> { record in
            record.remoteID == reservationID
        }
        var descriptor = FetchDescriptor<ReservationRecord>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let record = try? modelContext.fetch(descriptor).first else { return }
        tableAssignmentReservation = record
    }

    private var emptyState: some View {
        TryzubChartCard(title: "Layout", systemImage: "square.grid.3x3") {
            VStack(alignment: .leading, spacing: 12) {
                Text("No tables set up yet. Set up floor layout to start assigning reservations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Set Up Tables") {
                    showLayoutSetup = true
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var conflictBinding: Binding<Bool> {
        Binding(
            get: { store.conflict != nil },
            set: { isPresented in
                if !isPresented {
                    store.dismissConflict()
                }
            }
        )
    }

    private func loadForSelectedDate(_ date: Date? = nil) {
        let target = date ?? selectedDate
        store.load(date: target.reservationDateString())
    }

    private func floorDateTrace(fetchDate: String) {
        #if DEBUG
        print(
            "[FLOOR_DATE_TRACE] selectedDate=\(selectedDateKey) viewStateDate=\(store.viewState.selectedDate) staleContentHidden=\(isShowingStaleContent) fetchDate=\(fetchDate)"
        )
        #endif
    }
}

extension FloorPlanAssignmentContext: Identifiable {
    var id: String {
        switch self {
        case let .unassignedReservation(reservation):
            return "unassigned-\(reservation.id)"
        case let .assignedReservation(reservation, _):
            return "assigned-\(reservation.id)"
        case let .table(block):
            return "table-\(block.table.tableKey)"
        }
    }
}

#if DEBUG
#Preview {
    FloorPlanView(
        store: FloorPlanStore(apiClient: ReservationsAPIClient.preview),
        isActive: true
    )
    .environmentObject(
        ReservationsController(
            environment: AppEnvironment(apiClient: ReservationsAPIClient.preview, role: .developer)
        )
    )
}
#endif
