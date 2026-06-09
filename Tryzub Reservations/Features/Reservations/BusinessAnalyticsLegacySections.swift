//
//  BusinessAnalyticsLegacySections.swift
//  Tryzub Reservations
//

import SwiftUI

struct BusinessAnalyticsLegacyContent: View {
    let summary: ReservationAnalyticsSummaryDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            KPIGrid(summary: summary)
                .padding(.horizontal, 16)

            BusinessAnalyticsInsightsSection(
                lines: BusinessAnalyticsInsightBuilder.build(from: summary)
            )
            .padding(.horizontal, 16)

            AnalyticsStatusSection(rows: summary.byStatus)
                .padding(.horizontal, 16)

            AnalyticsMonthSection(rows: summary.byMonth)
                .padding(.horizontal, 16)

            AnalyticsHourSection(rows: summary.byHour)
                .padding(.horizontal, 16)

            AnalyticsPartySizeSection(rows: summary.byPartySize)
                .padding(.horizontal, 16)

            AnalyticsLeadTimeSection(rows: summary.leadTimeBuckets)
                .padding(.horizontal, 16)

            AnalyticsFieldCompletenessSection(values: summary.fieldCompleteness)
                .padding(.horizontal, 16)

            AnalyticsPipelineSection(pipeline: summary.pipelineHealth)
                .padding(.horizontal, 16)
        }
    }
}

// MARK: - Insights

private struct BusinessAnalyticsInsightsSection: View {
    let lines: [String]

    var body: some View {
        AnalyticsSectionCard(title: "Reservation trends", systemImage: "lightbulb") {
            if lines.isEmpty {
                Text("No interpretation is available for this range yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - KPI + Sections

private struct KPIGrid: View {
    let summary: ReservationAnalyticsSummaryDTO

    var body: some View {
        let metrics = summary.summary
        let pipeline = summary.pipelineHealth

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            AnalyticsKPI(title: "Direct reservations", value: "\(metrics?.reservationsCount ?? 0)", systemImage: "calendar")
            AnalyticsKPI(title: "Guests", value: "\(metrics?.guestsCount ?? 0)", systemImage: "person.2")
            AnalyticsKPI(title: "Avg party", value: metrics?.avgPartySize.map { String(format: "%.2f", $0) } ?? "-", systemImage: "number")
            AnalyticsKPI(
                title: "Pipeline health",
                value: "\(pipeline?.managedRowsWithSourceSubmissionId ?? 0) / \(pipeline?.flamingoInboundTotal ?? 0)",
                systemImage: "arrow.triangle.2.circlepath"
            )
        }
    }
}

private struct AnalyticsKPI: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
    }
}

private struct AnalyticsStatusSection: View {
    let rows: [ReservationAnalyticsStatusRowDTO]

    var body: some View {
        AnalyticsSectionCard(title: "Status Breakdown", systemImage: "list.bullet.rectangle") {
            AnalyticsRowsEmptyAware(isEmpty: rows.isEmpty) {
                ForEach(rows) { row in
                    AnalyticsBreakdownRow(title: row.status.analyticsStatusLabel, reservations: row.reservationsCount, guests: row.guestsCount)
                }
            }
        }
    }
}

private struct AnalyticsMonthSection: View {
    let rows: [ReservationAnalyticsMonthRowDTO]

    var body: some View {
        AnalyticsSectionCard(title: "Demand by Month", systemImage: "calendar") {
            AnalyticsRowsEmptyAware(isEmpty: rows.isEmpty) {
                ForEach(rows) { row in
                    AnalyticsBreakdownRow(title: row.month, reservations: row.reservationsCount, guests: row.guestsCount)
                }
            }
        }
    }
}

private struct AnalyticsHourSection: View {
    let rows: [ReservationAnalyticsHourRowDTO]

    var body: some View {
        AnalyticsSectionCard(title: "Peak Hours", systemImage: "clock") {
            AnalyticsRowsEmptyAware(isEmpty: rows.isEmpty) {
                ForEach(rows.sorted { $0.guestsCount == $1.guestsCount ? $0.hour < $1.hour : $0.guestsCount > $1.guestsCount }) { row in
                    AnalyticsBreakdownRow(title: AnalyticsPresenter.hourLabel(row.hour), reservations: row.reservationsCount, guests: row.guestsCount)
                }
            }
        }
    }
}

private struct AnalyticsPartySizeSection: View {
    let rows: [ReservationAnalyticsPartySizeRowDTO]

    var body: some View {
        AnalyticsSectionCard(title: "Party Size", systemImage: "person.2") {
            AnalyticsRowsEmptyAware(isEmpty: rows.isEmpty) {
                ForEach(rows.sorted { $0.partySize < $1.partySize }) { row in
                    AnalyticsBreakdownRow(title: "\(row.partySize) \(row.partySize == 1 ? "guest" : "guests")", reservations: row.reservationsCount, guests: row.guestsCount)
                }
            }
        }
    }
}

private struct AnalyticsLeadTimeSection: View {
    let rows: [ReservationAnalyticsLeadTimeRowDTO]

    var body: some View {
        AnalyticsSectionCard(title: "Lead Time", systemImage: "clock.arrow.circlepath") {
            AnalyticsRowsEmptyAware(isEmpty: rows.isEmpty) {
                ForEach(rows) { row in
                    AnalyticsBreakdownRow(title: AnalyticsPresenter.leadTimeLabel(row.bucket), reservations: row.reservationsCount, guests: row.guestsCount)
                }
            }
        }
    }
}

private struct AnalyticsFieldCompletenessSection: View {
    let values: [String: JSONValue]

    var body: some View {
        AnalyticsSectionCard(title: "Field Completeness", systemImage: "checklist") {
            if tableAssignmentCompletenessIsLow {
                AnalyticsNoticeCard(message: "Few reservations have table assignment.", tint: .orange)
            }

            AnalyticsRowsEmptyAware(isEmpty: values.isEmpty) {
                ForEach(values.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(AnalyticsPresenter.fieldLabel(key))
                        Spacer()
                        Text(values[key]?.analyticsCompactDisplayText ?? "-")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private var tableAssignmentCompletenessIsLow: Bool {
        let tableValue = values["table_name"] ?? values["table_assigned"]
        guard let percent = tableValue?.analyticsPercentageValue else { return false }
        return percent < 0.25
    }
}

private struct AnalyticsPipelineSection: View {
    let pipeline: ReservationAnalyticsPipelineHealthDTO?

    var body: some View {
        AnalyticsSectionCard(title: "Pipeline Health", systemImage: "arrow.triangle.2.circlepath") {
            if let pipeline {
                AnalyticsBreakdownLine(title: "Flamingo inbound total", value: "\(pipeline.flamingoInboundTotal)")
                AnalyticsBreakdownLine(title: "Managed linked rows", value: "\(pipeline.managedRowsWithSourceSubmissionId)")
                AnalyticsBreakdownLine(title: "Missing non spam- Flamingo", value: "\(pipeline.missingNonSpamFlamingo)")

                if pipeline.missingNonSpamFlamingo > 0 {
                    AnalyticsNoticeCard(message: "\(pipeline.missingNonSpamFlamingo) inbound submission needs import attention.", tint: .orange)
                }
            } else {
                Text("No pipeline data returned.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Shared Pieces

private struct AnalyticsSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        TryzubSectionCard(title: title, systemImage: systemImage, spacing: 12) {
            content
        }
        .padding(.horizontal, 16)
    }
}

struct AnalyticsNoticeCard: View {
    let message: String
    let tint: Color
    var systemImage = "exclamationmark.triangle"

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TryzubColors.cardBackground, in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
    }
}

private struct AnalyticsBreakdownRow: View {
    let title: String
    let reservations: Int
    let guests: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer()
            Text("\(reservations)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text("\(guests) guests")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }
}

private struct AnalyticsBreakdownLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}

private struct AnalyticsRowsEmptyAware<Content: View>: View {
    let isEmpty: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if isEmpty {
            Text("No rows returned.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                content
            }
        }
    }
}

private extension String {
    var analyticsStatusLabel: String {
        ReservationStatus(rawValue: self)?.displayName
            ?? replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private extension JSONValue {
    var analyticsPercentageValue: Double? {
        switch self {
        case .number(let value):
            return value > 1 ? value / 100 : value
        case .object(let object):
            if let percent = object["percent"]?.analyticsPercentageValue {
                return percent
            }
            if let complete = object["complete"]?.analyticsNumericValue,
               let total = object["total"]?.analyticsNumericValue,
               total > 0 {
                return complete / total
            }
            return nil
        case .string(let value):
            let normalized = value.replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let number = Double(normalized) else { return nil }
            return value.contains("%") || number > 1 ? number / 100 : number
        case .bool, .array, .null:
            return nil
        }
    }

    var analyticsNumericValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let value):
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case .bool(let value):
            return value ? 1 : 0
        case .object, .array, .null:
            return nil
        }
    }

    var analyticsCompactDisplayText: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value <= 1, value >= 0 {
                return "\(Int(round(value * 100)))%"
            }
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(format: "%.2f", value)
        case .bool(let value):
            return value ? "Yes" : "No"
        case .object(let object):
            if let complete = object["complete"]?.analyticsCompactDisplayText,
               let total = object["total"]?.analyticsCompactDisplayText {
                return "\(complete) / \(total)"
            }
            if let percent = object["percent"]?.analyticsCompactDisplayText {
                return percent
            }
            if let value = object["value"]?.analyticsCompactDisplayText {
                return value
            }
            return "\(object.count) fields"
        case .array(let values):
            return "\(values.count)"
        case .null:
            return "-"
        }
    }
}

enum AnalyticsPresenter {
    static func hourLabel(_ value: String) -> String {
        let hourString = value.prefix(2)
        guard let hour = Int(hourString) else {
            return value
        }

        let adjustedHour = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return "\(adjustedHour) \(suffix)"
    }

    static func leadTimeLabel(_ value: String) -> String {
        switch value {
        case "same_day":
            return "Same day"
        case "one_day":
            return "1 day ahead"
        case "two_three_days":
            return "2-3 days ahead"
        case "four_seven_days":
            return "4-7 days ahead"
        case "eight_fourteen_days":
            return "8-14 days ahead"
        case "fifteen_thirty_days":
            return "15-30 days ahead"
        case "thirty_one_plus_days":
            return "31+ days ahead"
        default:
            return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func fieldLabel(_ value: String) -> String {
        switch value {
        case "guest_name", "name":
            return "Name"
        case "email":
            return "Email"
        case "phone":
            return "Phone"
        case "guest_notes":
            return "Guest notes"
        case "staff_notes":
            return "Staff notes"
        case "table_name", "table_assigned":
            return "Table assigned"
        default:
            return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
