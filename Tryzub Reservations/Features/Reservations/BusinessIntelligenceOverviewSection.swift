//
//  BusinessIntelligenceOverviewSection.swift
//  Tryzub Reservations
//

import SwiftUI

struct BusinessIntelligenceOverviewSection: View {
    let summary: BusinessIntelligenceSummaryDTO?
    let systemStatus: IntelligenceSystemStatusDTO?
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading, summary == nil, systemStatus == nil {
                loadingCard
            } else if let errorMessage, summary == nil, systemStatus == nil {
                errorCard(errorMessage)
            } else {
                if let summary {
                    headlineStrip(summary)
                    insightSection(summary)
                }

                if let dataQualityNote {
                    Text(dataQualityNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                if let summary {
                    demandSection(summary)
                    guestRelationshipsSection(summary)
                    operationalRiskSection(summary)
                }

                if let systemStatus {
                    systemHealthSection(systemStatus)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var dataQualityNote: String? {
        guard let summary else { return nil }
        return BusinessIntelligenceInsightBuilder.dataQualityNote(for: summary)
    }

    private var loadingCard: some View {
        TryzubSectionCard(title: "Overview", systemImage: "chart.line.uptrend.xyaxis", spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading overview...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        TryzubSectionCard(title: "Overview", systemImage: "chart.line.uptrend.xyaxis", spacing: 10) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func headlineStrip(_ summary: BusinessIntelligenceSummaryDTO) -> some View {
        let metrics = summary.summary
        let risk = summary.risk
        let peak = BusinessIntelligenceFormatting.peakWindowLabel(summary: summary)
            ?? BusinessIntelligenceFormatting.missingValue

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            BusinessIntelligenceHeadlineMetric(
                title: "Total guests",
                value: BusinessIntelligenceFormatting.integer(metrics.totalGuests)
            )
            BusinessIntelligenceHeadlineMetric(
                title: "Repeat guests",
                value: BusinessIntelligenceFormatting.percent(summary.guestRelationships.repeatGuestRate)
            )
            BusinessIntelligenceHeadlineMetric(title: "Peak window", value: peak)
            BusinessIntelligenceHeadlineMetric(
                title: "Needs review",
                value: BusinessIntelligenceFormatting.integer(risk.needsReviewCount)
            )
        }
    }

    @ViewBuilder
    private func insightSection(_ summary: BusinessIntelligenceSummaryDTO) -> some View {
        let lines = BusinessIntelligenceInsightBuilder.build(
            summary: summary,
            systemStatus: systemStatus
        )
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
            )
        }
    }

    @ViewBuilder
    private func demandSection(_ summary: BusinessIntelligenceSummaryDTO) -> some View {
        let metrics = summary.summary
        let arrivalBars = BusinessIntelligenceChartData.arrivalBars(
            from: summary.breakdowns.by15MinWindow
        )

        TryzubSectionCard(title: "Demand", systemImage: "calendar.badge.clock", spacing: 10) {
            BusinessIntelligenceMetricGrid {
                BusinessIntelligenceMetricCard(
                    title: "Total guests",
                    value: BusinessIntelligenceFormatting.integer(metrics.totalGuests),
                    systemImage: "person.2"
                )
                BusinessIntelligenceMetricCard(
                    title: "Active guests",
                    value: BusinessIntelligenceFormatting.integer(metrics.activeGuests),
                    systemImage: "person.2.wave.2"
                )
                BusinessIntelligenceMetricCard(
                    title: "Peak window",
                    value: BusinessIntelligenceFormatting.peakWindowLabel(summary: summary)
                        ?? BusinessIntelligenceFormatting.missingValue,
                    systemImage: "clock"
                )
                BusinessIntelligenceMetricCard(
                    title: "Avg party",
                    value: BusinessIntelligenceFormatting.decimal(metrics.averagePartySize),
                    systemImage: "number"
                )
            }

            if let arrivalBars {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Arrival pressure by 15-minute window")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    BusinessIntelligenceVerticalBarChart(bars: arrivalBars)
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func guestRelationshipsSection(_ summary: BusinessIntelligenceSummaryDTO) -> some View {
        let guests = summary.guestRelationships
        let weekdayBars = BusinessIntelligenceChartData.weekdayBars(
            from: summary.breakdowns.byWeekday
        )
        let mixBars = BusinessIntelligenceChartData.guestMixBars(from: guests)
        let notesOrPrefs = combinedNotesOrPreferences(guests)

        TryzubSectionCard(title: "Guest relationships", systemImage: "person.3", spacing: 10) {
            BusinessIntelligenceMetricGrid {
                BusinessIntelligenceMetricCard(
                    title: "Unique guests",
                    value: BusinessIntelligenceFormatting.integer(guests.estimatedUniqueGuests),
                    systemImage: "person.crop.circle"
                )
                BusinessIntelligenceMetricCard(
                    title: "Repeat guests",
                    value: BusinessIntelligenceFormatting.integer(guests.returningGuestCount),
                    systemImage: "arrow.uturn.backward"
                )
                BusinessIntelligenceMetricCard(
                    title: "Repeat rate",
                    value: BusinessIntelligenceFormatting.percent(guests.repeatGuestRate),
                    systemImage: "percent"
                )
                BusinessIntelligenceMetricCard(
                    title: "Notes or prefs",
                    value: notesOrPrefs,
                    systemImage: "note.text"
                )
            }

            if let mixBars {
                VStack(alignment: .leading, spacing: 6) {
                    Text("New vs repeat guests")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    BusinessIntelligenceHorizontalBarChart(bars: mixBars)
                }
                .padding(.top, 4)
            }

            if let weekdayBars {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Guests by weekday")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    BusinessIntelligenceHorizontalBarChart(bars: weekdayBars)
                }
                .padding(.top, mixBars == nil ? 4 : 8)
            }
        }
    }

    @ViewBuilder
    private func operationalRiskSection(_ summary: BusinessIntelligenceSummaryDTO) -> some View {
        let risk = summary.risk

        TryzubSectionCard(title: "Operational risk", systemImage: "exclamationmark.triangle", spacing: 10) {
            BusinessIntelligenceMetricGrid {
                BusinessIntelligenceMetricCard(
                    title: "Needs review",
                    value: BusinessIntelligenceFormatting.integer(risk.needsReviewCount),
                    systemImage: "tray"
                )
                BusinessIntelligenceMetricCard(
                    title: "No table",
                    value: BusinessIntelligenceFormatting.integer(risk.noTableCount),
                    systemImage: "table.furniture"
                )
                BusinessIntelligenceMetricCard(
                    title: "Unconfirmed",
                    value: BusinessIntelligenceFormatting.integer(risk.unconfirmedCount),
                    systemImage: "questionmark.circle"
                )
                BusinessIntelligenceMetricCard(
                    title: "Cancel rate",
                    value: BusinessIntelligenceFormatting.percent(risk.cancelRate),
                    systemImage: "xmark.circle"
                )
                BusinessIntelligenceMetricCard(
                    title: "No-show rate",
                    value: BusinessIntelligenceFormatting.percent(risk.noShowRate),
                    systemImage: "person.slash"
                )
            }
        }
    }

    @ViewBuilder
    private func systemHealthSection(_ systemStatus: IntelligenceSystemStatusDTO) -> some View {
        let manager = systemStatus.managerSummary
        let developer = systemStatus.developerSummary
        let warningLines = BusinessIntelligenceInsightBuilder.managerSafeSystemWarnings(
            systemStatus.warnings
        )

        TryzubSectionCard(title: "System health", systemImage: "heart.text.square", spacing: 8) {
            HStack {
                Text("Status")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(BusinessIntelligenceFormatting.overallStatusTitle(systemStatus.status))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusTint(systemStatus.status))
            }
            .padding(.vertical, 2)

            BusinessIntelligenceCompactRow(
                title: "Needs review",
                value: BusinessIntelligenceFormatting.integer(manager.itemsNeedingReview)
            )
            BusinessIntelligenceCompactRow(
                title: "Possible duplicates",
                value: BusinessIntelligenceFormatting.integer(manager.possibleDuplicatesCount)
            )

            if let importFailures = developer.importFailureCount, importFailures > 0 {
                BusinessIntelligenceCompactRow(
                    title: "Import failures",
                    value: BusinessIntelligenceFormatting.integer(importFailures)
                )
            }

            if let rejected = developer.spamOrRejectedSubmissionCount, rejected > 0 {
                BusinessIntelligenceCompactRow(
                    title: "Rejected submissions",
                    value: BusinessIntelligenceFormatting.integer(rejected)
                )
            }

            if !warningLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(warningLines, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func combinedNotesOrPreferences(_ guests: GuestRelationshipMetricsDTO) -> String {
        let preferences = guests.guestsWithPreferences ?? 0
        let notes = guests.guestsWithPriorNotes ?? 0
        if preferences == 0, notes == 0 {
            return BusinessIntelligenceFormatting.integer(0)
        }
        if preferences == notes || preferences == 0 || notes == 0 {
            return BusinessIntelligenceFormatting.integer(max(preferences, notes))
        }
        return "\(preferences) / \(notes)"
    }

    private func statusTint(_ status: IntelligenceSystemOverallStatusDTO) -> Color {
        switch status {
        case .ok:
            return .green
        case .warning:
            return .orange
        case .needsAttention:
            return .red
        }
    }
}

// MARK: - Layout

private struct BusinessIntelligenceHeadlineMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
        )
    }
}

private struct BusinessIntelligenceMetricGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
            content
        }
    }
}

private struct BusinessIntelligenceMetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.tertiarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
        )
    }
}

private struct BusinessIntelligenceCompactRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
