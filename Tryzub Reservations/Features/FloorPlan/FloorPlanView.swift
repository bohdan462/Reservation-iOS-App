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
    @State private var selectedTableBlock: FloorPlanTableBlock?
    @State private var showLayoutSetup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    if store.viewState.hasTables {
                        gridSection
                        selectedTableSection
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
                        Task { await store.refresh(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(store.isLoading)
                }
                if store.viewState.hasTables {
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
                    Task { await store.refresh(force: true) }
                }
                Button("OK", role: .cancel) {
                    store.dismissConflict()
                }
            } message: { conflict in
                Text(conflict.message)
            }
            .onAppear {
                loadForSelectedDate()
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
            }
            .onChange(of: store.viewState.isToday) { _, isToday in
                store.setAutoRefreshActive(isActive && isToday)
            }
        }
    }

    private var headerCard: some View {
        TryzubChartCard(title: "Service", systemImage: "calendar") {
            VStack(alignment: .leading, spacing: 12) {
                DatePicker(
                    "Service date",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)

                HStack {
                    Label(store.viewState.mode.badgeTitle, systemImage: "circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(store.viewState.mode == .liveService ? TryzubColors.success : TryzubColors.info)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            (store.viewState.mode == .liveService ? TryzubColors.success : TryzubColors.info)
                                .opacity(0.12)
                        )
                        .clipShape(Capsule())

                    Spacer()

                    Text(store.viewState.lastCheckedLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(FloorPlanPresentation.displayDate(store.viewState.selectedDate))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if store.viewState.unassignedCount > 0 {
                        Text("\(store.viewState.unassignedCount) unassigned")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TryzubColors.warning)
                    }
                }

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
        }
    }

    @ViewBuilder
    private var gridSection: some View {
        FloorPlanGridView(
            viewState: store.viewState,
            unitSize: 44,
            onTableTap: { block in
                selectedTableBlock = block
                if let reservation = block.reservation,
                   let assignment = block.assignment {
                    assignmentContext = .assignedReservation(reservation, assignment)
                } else {
                    assignmentContext = .table(block)
                }
            }
        )
        .frame(minHeight: 320)
    }

    @ViewBuilder
    private var selectedTableSection: some View {
        if let block = selectedTableBlock ?? store.viewState.tableBlocks.first {
            TryzubChartCard(title: "Selected table", systemImage: "table.furniture") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Table details")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(
                        FloorPlanPresentation.tableDetailLine(
                            table: block.table,
                            reservation: block.reservation
                        )
                    )
                    .font(.subheadline)
                }
            }
        }
    }

    @ViewBuilder
    private var unassignedSection: some View {
        if !store.viewState.unassignedReservations.isEmpty {
            TryzubChartCard(title: "Unassigned", systemImage: "person.crop.circle.badge.questionmark") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.viewState.unassignedReservations) { reservation in
                        Button {
                            assignmentContext = .unassignedReservation(reservation)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reservation.guestName)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text("\(FloorPlanPresentation.displayTime(reservation.reservationTime)) · party of \(reservation.partySize)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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
