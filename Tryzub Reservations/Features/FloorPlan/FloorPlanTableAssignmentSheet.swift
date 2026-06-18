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
            Group {
                if isTableDetailContext {
                    tableDetailScrollBody
                } else {
                    reservationAssignmentListBody
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

    // MARK: - Table tap layout

    @ViewBuilder
    private var tableDetailScrollBody: some View {
        if case let .table(block) = context {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    tableDetailCard(block)

                    if !block.assignments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Assigned reservations")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TryzubColors.mutedText)

                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(block.assignments) { item in
                                    assignedReservationCard(item)
                                }
                            }
                            .overlay(alignment: .leading) {
                                Rectangle()
                                    .fill(TryzubColors.border)
                                    .frame(width: 1)
                                    .padding(.leading, 5)
                                    .padding(.vertical, 12)
                            }
                        }
                    }

                    if !unassignedReservations.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggested guests")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TryzubColors.mutedText)

                            ForEach(reservationProposals(for: block)) { proposal in
                                suggestedGuestRow(proposal)
                            }
                        }
                        .disabled(isWorking)
                    } else if block.assignments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggested guests")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TryzubColors.mutedText)

                            HostAssignmentCardSurface {
                                Text("No unassigned reservations for this service date.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(TryzubColors.screenBackground)
        }
    }

    @ViewBuilder
    private func tableDetailCard(_ block: FloorPlanTableBlock) -> some View {
        HostAssignmentCardSurface {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(block.table.label)
                        .font(.subheadline.weight(.semibold))

                    Spacer(minLength: 8)

                    Label {
                        Text(FloorPlanPresentation.capacityRange(min: block.table.minCapacity, max: block.table.maxCapacity))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "person.2.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .labelStyle(.titleAndIcon)
                }

                HStack(alignment: .center, spacing: 10) {
                    Label {
                        Text(block.table.tableKey)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "key")
                            .font(.caption.weight(.semibold))
                    }
                    .labelStyle(.titleAndIcon)

                    Spacer(minLength: 8)

                    if block.assignments.isEmpty {
                        Image(systemName: "circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("No reservations assigned")
                    } else if block.assignedCount > 1 {
                        Label {
                            Text("\(block.assignedCount)")
                                .font(.caption.weight(.semibold))
                        } icon: {
                            Image(systemName: "list.bullet")
                                .font(.caption.weight(.semibold))
                        }
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(TryzubColors.info)
                        .accessibilityLabel("\(block.assignedCount) assigned reservations")
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TryzubColors.success)
                            .accessibilityLabel("One assigned reservation")
                    }
                }

                if let section = block.table.section?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !section.isEmpty {
                    Text("Section: \(section)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func assignedReservationCard(
        _ item: FloorPlanTableReservationAssignment
    ) -> some View {
        let reservation = item.reservation
        HostAssignmentCardSurface {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(TryzubColors.info)
                    .frame(width: 10, height: 10)
                    .padding(.leading, -2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(reservation.guestName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TryzubColors.primaryText)
                            .lineLimit(1)

                        Text(reservation.status.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 8) {
                        Text(FloorPlanPresentation.displayTime(reservation.reservationTime))
                        Label("\(reservation.partySize)", systemImage: "person.2.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button(role: .destructive) {
                    onClear(reservation.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
                .accessibilityLabel("Clear table assignment for \(reservation.guestName)")
            }
        }
    }

    // MARK: - Reservation-first layout

    @ViewBuilder
    private var reservationAssignmentListBody: some View {
        List {
            headerSection
            tableSelectionSection
            if let reservation {
                actionSection(for: reservation)
            }
        }
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
            case .table:
                EmptyView()
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
            HStack(spacing: 8) {
                Text(FloorPlanPresentation.displayTime(reservation.reservationTime))
                Label("\(reservation.partySize)", systemImage: "person.2.fill")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private func suggestedGuestRow(_ proposal: HostTableAssignmentProposal) -> some View {
        Button {
            assignFromProposal(proposal)
            ReservationHaptics.selection()
        } label: {
            HostAssignmentCardSurface(isMuted: !proposal.isAvailable) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(proposal.tableLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(proposal.isAvailable ? TryzubColors.primaryText : TryzubColors.mutedText)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            if let reservationID = Int(proposal.id),
                               let reservation = unassignedReservations.first(where: { $0.id == reservationID }) {
                                Text(FloorPlanPresentation.displayTime(reservation.reservationTime))
                                Label("\(reservation.partySize)", systemImage: "person.2.fill")
                            } else {
                                Text(proposal.summary)
                            }

                            if let fit = proposal.fitDescription {
                                Text(fit)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                        if let detail = proposal.detail {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(TryzubColors.warning)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)

                    Image(systemName: proposal.isAvailable ? "plus.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(proposal.isAvailable ? TryzubColors.success : TryzubColors.warning)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!proposal.isAvailable || isWorking)
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

        let maxCapacity = selectedTables.reduce(0) { $0 + max($1.minCapacity, $1.maxCapacity) }
        if reservation.partySize > maxCapacity {
            pendingTableKeys = keys
            pendingReservationID = reservation.id
            showCapacityWarning = true
            return
        }

        pendingReservationID = nil
        onAssign(reservation.id, keys)
    }

    private func reservationProposals(for block: FloorPlanTableBlock) -> [HostTableAssignmentProposal] {
        FloorPlanReservationFitSupport.proposals(
            for: block.table,
            reservations: unassignedReservations
        )
    }

    private func assignFromProposal(_ proposal: HostTableAssignmentProposal) {
        guard let reservationID = Int(proposal.id),
              let reservation = unassignedReservations.first(where: { $0.id == reservationID }) else {
            return
        }
        confirmAssign(reservation: reservation)
    }
}
