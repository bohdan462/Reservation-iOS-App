//
//  FloorPlanTableAssignmentSheet.swift
//  Tryzub Reservations
//

import SwiftUI

enum FloorPlanAssignmentContext: Equatable {
    case unassignedReservation(ManagedReservationDTO)
    case assignedReservation(ManagedReservationDTO, TableAssignmentDTO)
    case table(FloorPlanTableBlock)
}

struct FloorPlanTableAssignmentSheet: View {
    let context: FloorPlanAssignmentContext
    let tableBlocks: [FloorPlanTableBlock]
    let unassignedReservations: [ManagedReservationDTO]
    let isWorking: Bool
    let onAssign: (Int, [String]) -> Void
    let onClear: (Int) -> Void
    let onDismiss: () -> Void

    @State private var selectedTableKeys: Set<String> = []
    @State private var showCapacityWarning = false
    @State private var pendingTableKeys: [String] = []
    @State private var pendingReservationID: Int?

    private var reservation: ManagedReservationDTO? {
        switch context {
        case let .unassignedReservation(reservation),
             let .assignedReservation(reservation, _):
            return reservation
        case .table:
            return nil
        }
    }

    private var selectedTables: [RestaurantTableDTO] {
        tableBlocks
            .map(\.table)
            .filter { selectedTableKeys.contains($0.tableKey) }
    }

    private var isTableDetailContext: Bool {
        if case .table = context {
            return true
        }
        return false
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                if case .table = context {
                    tableContextSection
                }
                if !isTableDetailContext {
                    tableSelectionSection
                }
                if let reservation {
                    actionSection(for: reservation)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
            .confirmationDialog(
                "Table may be too small for this party.",
                isPresented: $showCapacityWarning,
                titleVisibility: .visible
            ) {
                Button("Assign anyway") {
                    if let pendingReservationID {
                        onAssign(pendingReservationID, pendingTableKeys)
                    } else if let reservation {
                        onAssign(reservation.id, pendingTableKeys)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                let partySize = pendingReservationID.flatMap { id in
                    unassignedReservations.first(where: { $0.id == id })?.partySize
                } ?? reservation?.partySize ?? 0
                Text("Combined capacity is \(FloorPlanPresentation.combinedCapacity(for: selectedTables)). Party size is \(partySize).")
            }
        }
        .onAppear(perform: seedSelection)
    }

    @ViewBuilder
    private var headerSection: some View {
        Section {
            switch context {
            case let .unassignedReservation(reservation):
                reservationSummary(reservation)
            case let .assignedReservation(reservation, assignment):
                reservationSummary(reservation)
                if !assignment.tableKeys.isEmpty {
                    Text("Current tables: \(assignment.tableLabel ?? assignment.tableKeys.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case let .table(block):
                tableDetailSummary(block)
            }
        }
    }

    @ViewBuilder
    private var tableContextSection: some View {
        if case let .table(block) = context {
            if let reservation = block.reservation {
                Section("Current reservation") {
                    reservationSummary(reservation)
                    if block.assignment != nil {
                        Button("Clear table assignment", role: .destructive) {
                            onClear(reservation.id)
                        }
                        .disabled(isWorking)
                    }
                }
            }

            if !unassignedReservations.isEmpty {
                Section("Assign to this table") {
                    ForEach(unassignedReservations) { reservation in
                        Button {
                            confirmAssign(reservation: reservation)
                        } label: {
                            reservationSummary(reservation)
                        }
                        .disabled(isWorking)
                    }
                }
            } else {
                Section("Assign to this table") {
                    Text("No unassigned reservations for this service date.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func tableDetailSummary(_ block: FloorPlanTableBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(block.table.label)
                .font(.headline)
            Text("Key: \(block.table.tableKey)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Fits \(FloorPlanPresentation.capacityRange(min: block.table.minCapacity, max: block.table.maxCapacity)) guests")
                .font(.subheadline)
            if let section = block.table.section?.trimmingCharacters(in: .whitespacesAndNewlines),
               !section.isEmpty {
                Text("Section: \(section)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let reservation = block.reservation {
                Text("Assigned to \(reservation.guestName) · \(FloorPlanPresentation.displayTime(reservation.reservationTime))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No reservation assigned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var tableSelectionSection: some View {
        Section("Tables") {
            if !selectedTableKeys.isEmpty {
                Text("Selected tables: \(FloorPlanPresentation.selectedTablesLabel(selectedTables))")
                Text("Combined capacity: \(FloorPlanPresentation.combinedCapacity(for: selectedTables))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(tableBlocks) { block in
                let isSelected = selectedTableKeys.contains(block.table.tableKey)
                Button {
                    toggleSelection(for: block.table.tableKey)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(block.table.label)
                                .foregroundStyle(.primary)
                            Text(FloorPlanPresentation.tableStatusLabel(for: block))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(tableStatusColor(for: block))
                            Text("Fits \(FloorPlanPresentation.capacityRange(min: block.table.minCapacity, max: block.table.maxCapacity))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(TryzubColors.primaryControl)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionSection(for reservation: ManagedReservationDTO) -> some View {
        Section {
            switch context {
            case .unassignedReservation:
                Button("Assign table") {
                    confirmAssign(reservation: reservation)
                }
                .disabled(selectedTableKeys.isEmpty || isWorking)
            case .assignedReservation:
                Button("Change table") {
                    confirmAssign(reservation: reservation)
                }
                .disabled(selectedTableKeys.isEmpty || isWorking)
                Button("Clear table assignment", role: .destructive) {
                    onClear(reservation.id)
                }
                .disabled(isWorking)
            case .table:
                EmptyView()
            }
        }
    }

    private var navigationTitle: String {
        switch context {
        case .unassignedReservation:
            return "Assign table"
        case .assignedReservation:
            return "Change table"
        case .table:
            return "Table"
        }
    }

    private func reservationSummary(_ reservation: ManagedReservationDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reservation.guestName)
                .font(.headline)
            Text("\(FloorPlanPresentation.displayTime(reservation.reservationTime)) · party of \(reservation.partySize)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func seedSelection() {
        switch context {
        case let .assignedReservation(_, assignment):
            selectedTableKeys = Set(assignment.tableKeys)
        case let .table(block):
            selectedTableKeys = [block.table.tableKey]
        case .unassignedReservation:
            selectedTableKeys = []
        }
    }

    private func toggleSelection(for tableKey: String) {
        if selectedTableKeys.contains(tableKey) {
            selectedTableKeys.remove(tableKey)
        } else {
            selectedTableKeys.insert(tableKey)
        }
    }

    private func tableStatusColor(for block: FloorPlanTableBlock) -> Color {
        switch block.state {
        case .empty:
            return .secondary
        case .assignedUpcoming:
            return TryzubColors.info
        case .seated:
            return TryzubColors.warning
        case .completedHistorical:
            return .secondary
        case .conflict:
            return TryzubColors.danger
        case .inactive:
            return .secondary
        }
    }

    private func confirmAssign(reservation: ManagedReservationDTO) {
        let keys = selectedTableKeys.sorted()
        guard !keys.isEmpty else { return }

        let minCapacity = selectedTables.reduce(0) { $0 + $1.minCapacity }
        let maxCapacity = selectedTables.reduce(0) { $0 + max($1.minCapacity, $1.maxCapacity) }
        if reservation.partySize < minCapacity || reservation.partySize > maxCapacity {
            pendingTableKeys = keys
            pendingReservationID = reservation.id
            showCapacityWarning = true
            return
        }

        pendingReservationID = nil
        onAssign(reservation.id, keys)
    }
}
