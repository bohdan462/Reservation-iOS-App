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
        VStack(alignment: .leading, spacing: 7) {
            header

            if state.showsSummary {
                summaryChipLane
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .hostIntelligenceCompactPanel(cornerRadius: 16)
        .background(styleTraceView)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: headerIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(headerTint)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            Text(state.headline)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.90)
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
        case .afterCloseNeedsCleanup: return .orange.opacity(0.86)
        case .duringService: return TryzubColors.primaryControl.opacity(0.80)
        case .afterCloseFinished, .pastRecap: return .green.opacity(0.82)
        case .beforeService, .futurePlanning: return .secondary
        }
    }

    // MARK: - Summary chips

    @ViewBuilder
    private var summaryChipLane: some View {
        let chips = summaryChips
        if !chips.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                        summaryChip(chip)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(.top, 1)
        }
    }

    private var summaryChips: [String] {
        state.summary
            .components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func summaryChip(_ label: String) -> some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .hostIntelligenceCompactCapsule(strokeOpacity: 0.06)
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
                        .font(.caption.weight(.medium))
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var styleTraceView: some View {
        Color.clear.onAppear {
            logStyleTrace()
        }
    }

    private func logStyleTrace() {
        #if DEBUG
        print(
            "[SERVICE_BRIEFING_STYLE_TRACE] source=HostServiceBriefingCard mode=\(state.mode) headlineFont=caption.medium summaryStyle=compact_chips panel=hostIntelligenceCompactPanel"
        )
        #endif
    }
}
