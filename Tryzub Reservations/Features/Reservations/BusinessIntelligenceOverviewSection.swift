//
//  BusinessIntelligenceOverviewSection.swift
//  Tryzub Reservations
//

import SwiftUI

struct BusinessIntelligenceOverviewSection: View {
    let summary: BusinessIntelligenceSummaryDTO?
    let systemStatus: IntelligenceSystemStatusDTO?
    let isEnrichmentLoading: Bool
    let reservationAnalyticsAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEnrichmentLoading, summary == nil, systemStatus == nil {
                loadingCard
            } else {
                if isEnrichmentLoading, summary != nil || systemStatus != nil {
                    HStack(spacing: 8) {
                        TryzubSubtleLoadingDot(diameter: 6)
                        Text("Loading advanced insight…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }

                if let summary {
                    headlineInsightCard(summary)
                    headlineStrip(summary)
                    if BusinessIntelligenceInsightBuilder.headline(
                        summary: summary,
                        systemStatus: systemStatus
                    ) == nil {
                        insightSection(summary)
                    }
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
                    bookingHealthBanner(systemStatus)
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
        VStack(alignment: .leading, spacing: 8) {
            TryzubSectionLoadingCard(
                title: "Loading advanced insight…",
                systemImage: "chart.line.uptrend.xyaxis"
            )
            if reservationAnalyticsAvailable {
                Text("Core reservation analytics are available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private func headlineInsightCard(_ summary: BusinessIntelligenceSummaryDTO) -> some View {
        if let headline = BusinessIntelligenceInsightBuilder.headline(
            summary: summary,
            systemStatus: systemStatus
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What to check")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(headline)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(
                    Array(
                        BusinessIntelligenceInsightBuilder
                            .supportingLines(summary: summary, systemStatus: systemStatus)
                            .prefix(2)
                            .enumerated()
                    ),
                    id: \.offset
                ) { _, line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
            )
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
                title: "Guests",
                value: BusinessIntelligenceFormatting.integer(metrics.totalGuests)
            )
            BusinessIntelligenceHeadlineMetric(
                title: "Repeat rate",
                value: BusinessIntelligenceFormatting.percent(summary.guestRelationships.repeatGuestRate)
            )
            BusinessIntelligenceHeadlineMetric(title: "Peak window", value: peak)
            BusinessIntelligenceHeadlineMetric(
                title: "Need attention",
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
                BusinessIntelligenceMetricCard(
                    title: "Reservations",
                    value: BusinessIntelligenceFormatting.integer(metrics.totalReservations),
                    systemImage: "calendar"
                )
            }

            if let arrivalBars {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Arrival pressure by 15-minute window")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    if let caption = BusinessIntelligenceInsightBuilder.chartCaption(summary: summary) {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

        TryzubSectionCard(title: "Service watch", systemImage: "exclamationmark.triangle", spacing: 10) {
            BusinessIntelligenceMetricGrid {
                BusinessIntelligenceMetricCard(
                    title: "Need attention",
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
    private func bookingHealthBanner(_ systemStatus: IntelligenceSystemStatusDTO) -> some View {
        let manager = systemStatus.managerSummary
        let developer = systemStatus.developerSummary
        let needAttention = manager.itemsNeedingReview ?? 0
        let mayNeedReview = manager.possibleDuplicatesCount ?? 0
        let rejectedForms = developer.spamOrRejectedSubmissionCount ?? 0
        let importFailures = developer.importFailureCount ?? 0

        if needAttention == 0,
           mayNeedReview == 0,
           rejectedForms == 0,
           importFailures == 0,
           systemStatus.status == .ok {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Booking pipeline warning", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusTint(systemStatus.status))

                Text(bookingWarningMessage(
                    needAttention: needAttention,
                    mayNeedReview: mayNeedReview,
                    rejectedForms: rejectedForms,
                    importFailures: importFailures
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Text("Hidden bookings are excluded.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
            )
        }
    }

    private func bookingWarningMessage(
        needAttention: Int,
        mayNeedReview: Int,
        rejectedForms: Int,
        importFailures: Int
    ) -> String {
        var parts: [String] = []
        if needAttention > 0 {
            parts.append("\(needAttention) need attention")
        }
        if mayNeedReview > 0 {
            parts.append("\(mayNeedReview) may need review")
        }
        if rejectedForms > 0 {
            parts.append("\(rejectedForms) rejected forms")
        }
        if importFailures > 0 {
            parts.append("\(importFailures) form problems")
        }
        if parts.isEmpty {
            return "Booking pipeline needs a quick check."
        }
        return parts.joined(separator: " · ")
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
