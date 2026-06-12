//
//  HostServiceBriefingCard.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 2.
//
//  Deterministic Host Board card for after-close cleanup, after-close finished,
//  past recap, and future planning. Staff language only, structured actions first,
//  no live "due in X" / "table opened" facts. Read-only; tapping is optional and
//  handled by the host via `onActionTapped`.
//

import SwiftUI

struct HostServiceBriefingCard: View {
    let state: HostServiceBriefingViewState
    var onActionTapped: ((StaffActionIntent) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if state.showsSummary {
                Text(state.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let title = state.primaryGroupTitle {
                actionGroup(title: title, actions: state.primaryActions, emphasized: true)
            }

            if let title = state.secondaryGroupTitle {
                actionGroup(title: title, actions: state.secondaryActions, emphasized: false)
            }

            if !state.todaySummary.isEmpty {
                summaryLines
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: headerIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(headerTint)
            Text(state.headline)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var headerIcon: String {
        switch state.mode {
        case .afterCloseFinished, .pastRecap: return "checkmark.seal"
        case .afterCloseNeedsCleanup: return "exclamationmark.circle"
        case .duringService: return "bell"
        case .beforeService, .futurePlanning: return "calendar"
        }
    }

    private var headerTint: Color {
        switch state.mode {
        case .afterCloseNeedsCleanup: return .orange
        case .duringService: return .blue
        case .afterCloseFinished, .pastRecap: return .green
        case .beforeService, .futurePlanning: return .secondary
        }
    }

    // MARK: - Action group

    private func actionGroup(title: String, actions: [StaffActionIntent], emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(emphasized ? .primary : .secondary)
                .textCase(.uppercase)

            ForEach(actions) { action in
                actionRow(action)
            }
        }
    }

    @ViewBuilder
    private func actionRow(_ action: StaffActionIntent) -> some View {
        let content = VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(priorityColor(action.priority))
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = action.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        if let onActionTapped {
            Button { onActionTapped(action) } label: { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func priorityColor(_ priority: ActionPriority) -> Color {
        switch priority {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        case .none: return .secondary
        }
    }

    // MARK: - Summary lines

    private var summaryLines: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(state.todaySummary.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
