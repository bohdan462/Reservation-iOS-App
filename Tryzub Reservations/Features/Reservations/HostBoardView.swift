//
//  HostBoardView.swift
//  Tryzub Reservations
//

import SwiftUI
import SwiftData

struct HostBoardView: View {
    let reservations: [ReservationRecord]
    let environment: AppEnvironment
    let lastSyncedAt: Date?
    let isSyncing: Bool
    let failedImportCount: Int
    let onShowFormProblems: () -> Void

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController

    @State private var compactScope: HostBoardScope = .upcoming
    @State private var pendingAction: ReservationPendingAction?
    @State private var tableAssignmentReservation: ReservationRecord?
    @State private var seatWithoutTableReservation: ReservationRecord?

    private var upcoming: [ReservationRecord] {
        ReservationRecord.sortedForHostBoard(
            reservations.filter {
                $0.statusValue == .new || $0.statusValue == .needsReview || $0.statusValue == .confirmed
            }
        )
    }

    private var seated: [ReservationRecord] {
        ReservationRecord.sortedChronologically(
            reservations.filter { $0.statusValue == .seated }
        )
    }

    private var done: [ReservationRecord] {
        ReservationRecord.sortedChronologically(
            reservations.filter {
                $0.statusValue == .completed || $0.statusValue == .cancelled || $0.statusValue == .noShow
            }
        )
    }

    private var needsReview: [ReservationRecord] {
        upcoming.filter { $0.statusValue == .needsReview }
    }

    private var newReservations: [ReservationRecord] {
        upcoming.filter { $0.statusValue == .new }
    }

    private var noTableCount: Int {
        upcoming.filter { !$0.hasTableAssignment }.count
    }

    private var expectedGuestCount: Int {
        upcoming.reduce(0) { $0 + $1.partySize } + seated.reduce(0) { $0 + $1.partySize }
    }

    private var nextReservationID: Int? {
        let currentTime = Date.currentReservationTimeString()
        return upcoming.first { $0.reservationTime >= currentTime }?.remoteID ?? upcoming.first?.remoteID
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
               
                VStack(alignment: .leading, spacing: 16) {
                    
                    warningArea
                        .frame(maxWidth: 400)
                    
                    HostBoardSummaryCard(
                        lastSyncedAt: lastSyncedAt,
                        isSyncing: isSyncing,
                        reservationCount: upcoming.count + seated.count,
                        guestCount: expectedGuestCount,
                        newCount: newReservations.count,
                        reviewCount: needsReview.count,
                        failedImportCount: failedImportCount,
                        noTableCount: noTableCount
                    )

//                    warningArea

                    if proxy.size.width >= 820 {
                        wideBoard
                    } else {
                        compactBoard
                    }
                }
                .padding(.horizontal, proxy.size.width >= 820 ? 20 : 16)
                .padding(.vertical, 16)
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
                Button(pendingAction.action.fullTitle, role: pendingAction.action.role) {
                    Task {
                        await perform(pendingAction.action, on: pendingAction.reservation)
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
        .confirmationDialog(
            "Seat without table assignment?",
            isPresented: Binding(
                get: { seatWithoutTableReservation != nil },
                set: { if !$0 { seatWithoutTableReservation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let reservation = seatWithoutTableReservation {
                Button("Assign Table") {
                    tableAssignmentReservation = reservation
                    seatWithoutTableReservation = nil
                }
                Button("Seat Anyway") {
                    Task {
                        seatWithoutTableReservation = nil
                        await controller.updateStatus(reservation: reservation, status: .seated, context: modelContext)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                seatWithoutTableReservation = nil
            }
        } message: {
            if let reservation = seatWithoutTableReservation {
                Text("\(reservation.guestName) has no table assigned. Assign a table first or seat anyway.")
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

    private var pendingActionTitle: String {
        guard let pendingAction else {
            return "Update Reservation?"
        }

        return pendingAction.action.dialogTitle(for: pendingAction.reservation)
    }

    private var warningArea: some View {
        HStack(spacing: 10) {
            if failedImportCount > 0, controller.capabilities.canViewFailedImports {
                FormProblemsBanner(count: failedImportCount, onTap: onShowFormProblems)
            }

            if !needsReview.isEmpty {
                HostWarningBanner(
                    title: "\(needsReview.count) need review",
                    message: "",
                    symbolName: "exclamationmark.triangle",
                    tint: .orange
                )
            }

            if noTableCount > 0 {
                HostWarningBanner(
                    title: "\(noTableCount) without table",
                    message: "",
                    symbolName: "table.furniture",
                    tint: .indigo
                )
            }
        }
        
    }

    private var wideBoard: some View {
        HStack(alignment: .top, spacing: 16) {
            HostBoardColumn(
                title: "Seated",
                subtitle: "\(seated.count) seated",
                reservations: seated,
                emptyTitle: "No one seated",
                emptySystemImage: "person.2.slash",
                nextReservationID: nil,
                environment: environment,
                onAction: handleAction
            )

            HostBoardColumn(
                title: "Upcoming Today",
                subtitle: "\(upcoming.count) active reservations",
                reservations: upcoming,
                emptyTitle: "No upcoming reservations",
                emptySystemImage: "calendar.badge.checkmark",
                nextReservationID: nextReservationID,
                environment: environment,
                onAction: handleAction
            )
        }
    }

    private var compactBoard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Board", selection: $compactScope) {
                ForEach(HostBoardScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            HostBoardColumn(
                title: compactScope.title,
                subtitle: compactScope.subtitle(
                    upcoming: upcoming.count,
                    seated: seated.count,
                    review: needsReview.count
                ),
                reservations: compactReservations,
                emptyTitle: compactScope.emptyTitle,
                emptySystemImage: compactScope.emptySystemImage,
                nextReservationID: compactScope == .upcoming ? nextReservationID : nil,
                environment: environment,
                onAction: handleAction
            )
        }
    }

    private var compactReservations: [ReservationRecord] {
        switch compactScope {
        case .upcoming:
            return upcoming
        case .seated:
            return seated
        case .review:
            return needsReview
        }
    }

    private func handleAction(_ action: ReservationHostAction, reservation: ReservationRecord) {
        if action == .assignTable {
            tableAssignmentReservation = reservation
        } else if action == .seat, !reservation.hasTableAssignment {
            seatWithoutTableReservation = reservation
        } else {
            pendingAction = ReservationPendingAction(reservation: reservation, action: action)
        }
    }

    private func perform(_ action: ReservationHostAction, on reservation: ReservationRecord) async {
        pendingAction = nil

        switch action {
        case .confirm:
            await controller.confirmReservation(reservation: reservation, context: modelContext)
        case .seat:
            await controller.updateStatus(reservation: reservation, status: .seated, context: modelContext)
        case .complete:
            await controller.updateStatus(reservation: reservation, status: .completed, context: modelContext)
        case .cancel:
            await controller.updateStatus(reservation: reservation, status: .cancelled, context: modelContext)
        case .noShow:
            await controller.updateStatus(reservation: reservation, status: .noShow, context: modelContext)
        case .assignTable:
            tableAssignmentReservation = reservation
        }
    }
}

private struct ReservationPendingAction: Identifiable {
    let reservation: ReservationRecord
    let action: ReservationHostAction

    var id: String {
        "\(reservation.remoteID)-\(action.rawValue)"
    }
}

private struct HostBoardSummaryCard: View {
    let lastSyncedAt: Date?
    let isSyncing: Bool
    let reservationCount: Int
    let guestCount: Int
    let newCount: Int
    let reviewCount: Int
    let failedImportCount: Int
    let noTableCount: Int

    private var lastSyncedText: String {
        guard let lastSyncedAt else {
            return "Not synced yet"
        }

        return "Synced \(lastSyncedAt.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date().formatted(date: .complete, time: .omitted))
                        .font(.title3.weight(.bold))
                    HStack(spacing: 6) {
                        if isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isSyncing ? "Refreshing..." : lastSyncedText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    DashboardMetricCard(title: "Count", value: reservationCount, symbolName: "calendar", tint: .blue)
                    DashboardMetricCard(title: "Guests", value: guestCount, symbolName: "person.2", tint: .green)
                    DashboardMetricCard(title: "New", value: newCount, symbolName: "sparkle", tint: .cyan)
                    DashboardMetricCard(title: "Review", value: reviewCount, symbolName: "exclamationmark.triangle", tint: .orange)
                    DashboardMetricCard(title: "Failed", value: failedImportCount, symbolName: "exclamationmark.octagon", tint: .red)
                    DashboardMetricCard(title: "No Table", value: noTableCount, symbolName: "table.furniture", tint: .indigo)
                }
            }

//            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
//                DashboardMetricCard(title: "Count", value: reservationCount, symbolName: "calendar", tint: .blue)
//                DashboardMetricCard(title: "Guests", value: guestCount, symbolName: "person.2", tint: .green)
//                DashboardMetricCard(title: "New", value: newCount, symbolName: "sparkle", tint: .cyan)
//                DashboardMetricCard(title: "Review", value: reviewCount, symbolName: "exclamationmark.triangle", tint: .orange)
//                DashboardMetricCard(title: "Failed", value: failedImportCount, symbolName: "exclamationmark.octagon", tint: .red)
//                DashboardMetricCard(title: "No Table", value: noTableCount, symbolName: "table.furniture", tint: .indigo)
//            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct DashboardMetricCard: View {
    let title: String
    let value: Int
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.footnote)
                .foregroundStyle(tint)
                .frame(width: 15, height: 15)
                .background(tint.opacity(0.1), in: Circle())

            HStack(alignment: .center, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(value, format: .number)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground).opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
    }
}

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
                        .font(.headline.weight(.bold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if reservations.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptySystemImage)
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
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

private struct HostBoardReservationRow: View {
    @EnvironmentObject private var controller: ReservationsController

    let reservation: ReservationRecord
    let environment: AppEnvironment
    let isNext: Bool
    let onAction: (ReservationHostAction, ReservationRecord) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wideLayout
            compactLayout
        }
        .padding(12)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isNext ? Color.blue.opacity(0.45) : Color.clear, lineWidth: 2)
        )
    }

    private var wideLayout: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reservation.displayTime)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                if isNext {
                    Text("Next")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.blue)
                }
            }
            .frame(width: 74, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(reservation.guestName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(reservation.formattedPhone)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(2)

            Text("\(reservation.partySize)")
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .frame(width: 36)

            Text(reservation.tableDisplay)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(reservation.hasTableAssignment ? Color.secondary : Color.orange)
                .lineLimit(1)
                .frame(width: 98, alignment: .leading)

            ReservationStatusBadge(status: reservation.statusValue)
                .frame(width: 108, alignment: .trailing)

            ReservationActionButtons(
                reservation: reservation,
                capabilities: controller.capabilities,
                compact: true,
                includeSecondary: true,
                isBusy: controller.isActionInProgress(for: reservation)
            ) { action in
                onAction(action, reservation)
            }

            NavigationLink {
                ReservationDetailView(reservation: reservation, environment: environment)
            } label: {
                Image(systemName: "chevron.right.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(reservation.displayTime)
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                Text(reservation.guestName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(2)
                Spacer(minLength: 8)
                ReservationStatusBadge(status: reservation.statusValue)
            }

            HStack(spacing: 10) {
                Label("\(reservation.partySize)", systemImage: "person.2")
                Label(reservation.tableDisplay, systemImage: "table.furniture")
                    .foregroundStyle(reservation.hasTableAssignment ? Color.secondary : Color.orange)
                Label(reservation.formattedPhone, systemImage: "phone")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            HStack {
                ReservationActionButtons(
                    reservation: reservation,
                    capabilities: controller.capabilities,
                    compact: true,
                    includeSecondary: false,
                    isBusy: controller.isActionInProgress(for: reservation)
                ) { action in
                    onAction(action, reservation)
                }

                Spacer()

                NavigationLink {
                    ReservationDetailView(reservation: reservation, environment: environment)
                } label: {
                    Label("Details", systemImage: "chevron.right.circle")
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
            }
        }
    }

    private var rowBackground: Color {
        if isNext {
            return Color.blue.opacity(0.08)
        }

        if reservation.statusValue == .needsReview {
            return Color.orange.opacity(0.09)
        }

        return Color(.secondarySystemGroupedBackground)
    }
}

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
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbolName)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 15, height: 15)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

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

private extension Date {
    static func currentReservationTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
