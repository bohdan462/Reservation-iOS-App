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
                selectedTableBlock = nil
                assignmentContext = nil
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
                selectedTableBlock = block
                assignmentContext = .table(block)
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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.viewState.unassignedReservations.enumerated()), id: \.element.id) { index, reservation in
                        if index > 0 {
                            Divider().padding(.vertical, 8)
                        }
                        Button {
                            assignmentContext = .unassignedReservation(reservation)
                        } label: {
                            UnassignedReservationRow(reservation: reservation)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private struct UnassignedReservationRow: View {
        let reservation: ManagedReservationDTO

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reservation.guestName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(FloorPlanPresentation.displayTime(reservation.reservationTime)) · party of \(reservation.partySize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !noteChips.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(noteChips, id: \.self) { chip in
                                Text(chip)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.secondary.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Assign table")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(TryzubColors.primaryControl)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }

        private var noteChips: [String] {
            var chips: [String] = []
            let combined = [reservation.guestNotes, reservation.staffNotes]
                .compactMap { s -> String? in
                    guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    return s
                }
                .joined(separator: " ")
                .lowercased()
            if !combined.isEmpty {
                chips.append("Note")
            }
            if combined.contains("deposit") || combined.contains("payment") {
                chips.append("Deposit")
            }
            if combined.contains("preorder") || combined.contains("pre-order") {
                chips.append("Preorder")
            }
            if combined.contains("allerg") || combined.contains("gluten") || combined.contains("vegan") || combined.contains("vegetar") {
                chips.append("Dietary")
            }
            return chips
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
