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
    let isVisible: Bool
    let isAppActive: Bool
    let externalInteractionActive: Bool
    let onShowFormProblems: () -> Void

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController

    @State private var compactScope: HostBoardScope = .upcoming
    @State private var pendingAction: ReservationPendingAction?
    @State private var tableAssignmentReservation: ReservationRecord?

    private var hasOpenInteraction: Bool {
        externalInteractionActive
            || pendingAction != nil
            || tableAssignmentReservation != nil
    }

    var body: some View {
        GeometryReader { proxy in
            let snapshot = HostBoardSnapshot(reservations: reservations)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HostBoardSummaryCard(
                        lastSyncedAt: lastSyncedAt,
                        isSyncing: isSyncing,
                        reservationCount: snapshot.upcoming.count + snapshot.seated.count,
                        guestCount: snapshot.expectedGuestCount,
                        newCount: snapshot.newReservations.count,
                        reviewCount: snapshot.needsReview.count,
                        failedImportCount: failedImportCount,
                        noTableCount: snapshot.noTableCount
                    )

                    warningArea(snapshot: snapshot)

                    if proxy.size.width >= 1100 {
                        wideBoard(snapshot: snapshot)
                    } else {
                        compactBoard(snapshot: snapshot)
                    }
                }
                .padding(.horizontal, proxy.size.width >= 1100 ? 16 : 12)
                .padding(.vertical, proxy.size.width >= 1100 ? 12 : 10)
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
        .sheet(item: $tableAssignmentReservation) { reservation in
            TableAssignmentSheet(reservation: reservation) { tableName in
                _ = try await controller.updateReservation(
                    id: reservation.remoteID,
                    request: ReservationUpdateRequest(tableName: tableName),
                    context: modelContext
                )
            }
        }
        .task(id: isVisible && isAppActive) {
            await runAutoRefreshLoop()
        }
    }

    private var pendingActionTitle: String {
        guard let pendingAction else {
            return "Update Reservation?"
        }

        return pendingAction.action.dialogTitle(for: pendingAction.reservation)
    }

    private func warningArea(snapshot: HostBoardSnapshot) -> some View {
        HStack(spacing: 8) {
            if failedImportCount > 0, controller.capabilities.canViewFailedImports {
                FormProblemsBanner(count: failedImportCount, onTap: onShowFormProblems)
            }

            if !snapshot.needsReview.isEmpty {
                HostWarningBanner(
                    title: "\(snapshot.needsReview.count) need review",
                    message: "",
                    symbolName: "exclamationmark.triangle",
                    tint: .secondary
                )
            }

            if snapshot.noTableCount > 0 {
                HostWarningBanner(
                    title: "\(snapshot.noTableCount) without table",
                    message: "",
                    symbolName: "table.furniture",
                    tint: .secondary
                )
            }

            Spacer(minLength: 0)
        }
    }

    private func wideBoard(snapshot: HostBoardSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            HostBoardColumn(
                title: "Seated / In House",
                subtitle: "\(snapshot.seated.count) seated",
                reservations: snapshot.seated,
                emptyTitle: "No one seated",
                emptySystemImage: "person.2.slash",
                nextReservationID: nil,
                environment: environment,
                onAction: handleAction
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)

            HostBoardColumn(
                title: "Upcoming Today",
                subtitle: "\(snapshot.upcoming.count) active reservations",
                reservations: snapshot.upcoming,
                emptyTitle: "No upcoming reservations",
                emptySystemImage: "calendar.badge.checkmark",
                nextReservationID: snapshot.nextReservationID,
                environment: environment,
                onAction: handleAction
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func compactBoard(snapshot: HostBoardSnapshot) -> some View {
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
                    upcoming: snapshot.upcoming.count,
                    seated: snapshot.seated.count,
                    review: snapshot.needsReview.count
                ),
                reservations: compactReservations(from: snapshot),
                emptyTitle: compactScope.emptyTitle,
                emptySystemImage: compactScope.emptySystemImage,
                nextReservationID: compactScope == .upcoming ? snapshot.nextReservationID : nil,
                environment: environment,
                onAction: handleAction
            )
        }
    }

    private func compactReservations(from snapshot: HostBoardSnapshot) -> [ReservationRecord] {
        switch compactScope {
        case .upcoming:
            return snapshot.upcoming
        case .seated:
            return snapshot.seated
        case .review:
            return snapshot.needsReview
        }
    }

    private func handleAction(_ action: ReservationHostAction, reservation: ReservationRecord) {
        if action == .assignTable {
            tableAssignmentReservation = reservation
        } else if action == .seat, !reservation.hasTableAssignment {
            tableAssignmentReservation = reservation
        } else if action == .sendConfirmationEmail || action == .cancel || action == .noShow {
            pendingAction = ReservationPendingAction(reservation: reservation, action: action)
        } else {
            Task {
                await perform(action, on: reservation)
            }
        }
    }

    private func perform(_ action: ReservationHostAction, on reservation: ReservationRecord) async {
        pendingAction = nil

        switch action {
        case .confirm:
            await controller.updateStatus(reservation: reservation, status: .confirmed, context: modelContext)
        case .sendConfirmationEmail:
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

    @MainActor
    private func runAutoRefreshLoop() async {
        guard isVisible, isAppActive else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }

            guard isVisible, isAppActive else { return }

            await controller.autoRefreshDashboardIfAllowed(
                context: modelContext,
                isInteractionActive: hasOpenInteraction,
                isAppActive: isAppActive
            )
        }
    }
}

private struct HostBoardSnapshot {
    let upcoming: [ReservationRecord]
    let seated: [ReservationRecord]
    let needsReview: [ReservationRecord]
    let newReservations: [ReservationRecord]
    let noTableCount: Int
    let expectedGuestCount: Int
    let nextReservationID: Int?

    init(reservations: [ReservationRecord]) {
        upcoming = ReservationRecord.sortedForHostBoard(
            reservations.filter {
                $0.statusValue == .new || $0.statusValue == .needsReview || $0.statusValue == .confirmed
            }
        )
        seated = ReservationRecord.sortedChronologically(
            reservations.filter { $0.statusValue == .seated }
        )
        needsReview = upcoming.filter { $0.statusValue == .needsReview }
        newReservations = upcoming.filter { $0.statusValue == .new }
        noTableCount = upcoming.filter { !$0.hasTableAssignment }.count
        expectedGuestCount = upcoming.reduce(0) { $0 + $1.partySize } + seated.reduce(0) { $0 + $1.partySize }

        let currentTime = Date.currentReservationTimeString()
        nextReservationID = upcoming.first { $0.reservationTime >= currentTime }?.remoteID ?? upcoming.first?.remoteID
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
        ViewThatFits(in: .horizontal) {
            wideSummary
            compactSummary
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 9))
    }

    private var wideSummary: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                        if isSyncing {
                            ProgressView()
                            .controlSize(.small)
                    }
                    Text(isSyncing ? "Refreshing..." : lastSyncedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 210, alignment: .leading)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                SummaryMetricChip(title: "Count", value: reservationCount, symbolName: "calendar", tint: .secondary)
                SummaryMetricChip(title: "Guests", value: guestCount, symbolName: "person.2", tint: .secondary)
                SummaryMetricChip(title: "New", value: newCount, symbolName: "sparkle", tint: .secondary)
                SummaryMetricChip(title: "Review", value: reviewCount, symbolName: "exclamationmark.triangle", tint: .secondary)
                SummaryMetricChip(title: "Forms", value: failedImportCount, symbolName: "exclamationmark.octagon", tint: .secondary)
                SummaryMetricChip(title: "No Table", value: noTableCount, symbolName: "table.furniture", tint: .secondary)
            }
        }
    }

    private var compactSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date().formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 6) {
                        if isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isSyncing ? "Refreshing..." : lastSyncedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                SummaryMetricChip(title: "Count", value: reservationCount, symbolName: "calendar", tint: .secondary)
                SummaryMetricChip(title: "Guests", value: guestCount, symbolName: "person.2", tint: .secondary)
                SummaryMetricChip(title: "New", value: newCount, symbolName: "sparkle", tint: .secondary)
                SummaryMetricChip(title: "Review", value: reviewCount, symbolName: "exclamationmark.triangle", tint: .secondary)
                SummaryMetricChip(title: "Forms", value: failedImportCount, symbolName: "exclamationmark.octagon", tint: .secondary)
                SummaryMetricChip(title: "No Table", value: noTableCount, symbolName: "table.furniture", tint: .secondary)
            }
        }
    }
}

private struct SummaryMetricChip: View {
    let title: String
    let value: Int
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value, format: .number)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(.systemGray6), in: Capsule())
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
                        .font(.headline.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if reservations.isEmpty {
                CompactEmptyHostState(title: emptyTitle, systemImage: emptySystemImage)
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
        ReservationRowView(
            reservation: reservation,
            showsDate: false,
            context: rowContext
        ) {
            HStack(spacing: 8) {
                ReservationActionButtons(
                    reservation: reservation,
                    capabilities: controller.capabilities,
                    compact: true,
                    includeSecondary: false,
                    isBusy: controller.isActionInProgress(for: reservation)
                ) { action in
                    onAction(action, reservation)
                }

                NavigationLink {
                    ReservationDetailView(reservation: reservation, environment: environment)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary.opacity(0.64))
                }
                .buttonStyle(.plain)
            }
        }
        .contextMenu {
            NavigationLink {
                ReservationDetailView(reservation: reservation, environment: environment)
            } label: {
                Label("Details", systemImage: "info.circle")
            }

            ForEach(
                ReservationHostAction.availableActions(
                    for: reservation,
                    capabilities: controller.capabilities,
                    includeSecondary: true
                )
            ) { action in
                Button(role: action.role) {
                    onAction(action, reservation)
                } label: {
                    Label(action.fullTitle, systemImage: action.systemImage)
                }
            }
        }
    }

    private var rowContext: ReservationRowContext {
        if reservation.statusValue == .seated {
            return .todaySeated
        }
        return .todayUpcoming(isNext: isNext)
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
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: symbolName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 12, height: 12)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct CompactEmptyHostState: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
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
        ReservationFormatters.apiTime.string(from: Date())
    }
}
