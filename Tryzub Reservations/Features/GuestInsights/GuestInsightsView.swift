//
//  GuestInsightsView.swift
//  Tryzub Reservations
//

import SwiftUI
import Charts

// MARK: - Guest Insights View

struct GuestInsightsView: View {
    let selectedReservation: ReservationRecord
    let allReservations: [ReservationRecord]

    // Read-only analysis from cached ReservationRecord rows; no network or mutation.
    private var report: GuestInsightReport {
        GuestInsightsController().analyze(
            selected: selectedReservation,
            allReservations: allReservations
        )
    }

    var body: some View {
        let report = report

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                GuestInsightHeader(report: report)
                GuestInsightSnapshotGrid(report: report)
                GuestInsightNotesSection(report: report)
                GuestInsightBookingHistorySection(report: report)
                GuestInsightPreferencesSection(report: report)
                GuestInsightPossibleMatchesSection(report: report)
                GuestInsightWarningsSection(warnings: report.warnings)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Guest Insights")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
    }
}

// MARK: - Header

private struct GuestInsightHeader: View {
    let report: GuestInsightReport

    var body: some View {
        GuestInsightCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "person.text.rectangle")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, height: 38)
                        .background(Color(.systemGray6), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.displayName)
                            .font(.title3.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        VStack(alignment: .leading, spacing: 2) {
                            if let phone = report.primaryPhone {
                                Text(phone)
                                    .lineLimit(1)
                            }
                            if let email = report.primaryEmail {
                                Text(email)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            if !report.hasReliableContactIdentity {
                                Text("No reliable contact on file")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                FlowLayout(spacing: 7) {
                    GuestRegularityBadge(level: report.regularityLevel)
                    if report.isLikelyManualGuest {
                        GuestInsightBadge("Manual / Call-in", systemImage: "phone")
                    }
                    if !report.possibleMatches.isEmpty {
                        GuestInsightBadge("Possible matches", systemImage: "person.2")
                    }
                    if report.primaryEmail == nil {
                        GuestInsightBadge("No real email", systemImage: "envelope.badge")
                    }
                    if !report.staffMentionHistory.isEmpty {
                        GuestInsightBadge("Staff notes found", systemImage: "note.text")
                    }
                }
            }
        }
    }
}

// MARK: - Snapshot Cards

private struct GuestInsightSnapshotGrid: View {
    let report: GuestInsightReport

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 142), spacing: 10)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            GuestInsightMetricCard(
                title: "Clean visits",
                value: "\(report.summary.totalMatchedReservations)",
                caption: report.regularityLevel.displayName
            )

            GuestInsightMetricCard(
                title: "Last booked",
                value: report.summary.lastBookedDate ?? "-",
                caption: recencyCaption
            )

            GuestInsightMetricCard(
                title: "Usual time",
                value: report.summary.mostCommonReservationTime ?? "-",
                caption: report.summary.mostCommonWeekday ?? "Based on cached records"
            )

            GuestInsightMetricCard(
                title: "Party size",
                value: report.summary.mostCommonPartySize.map { "\($0)" } ?? "-",
                caption: partySizeCaption
            )

            GuestInsightMetricCard(
                title: "Source",
                value: sourceValue,
                caption: sourceCaption
            )

            GuestInsightMetricCard(
                title: "Notes",
                value: "\(report.hospitalitySnapshot.noteCount)",
                caption: notesCaption
            )
        }
    }

    private var recencyCaption: String {
        if let upcoming = report.hospitalitySnapshot.lastUpcomingReservationDate {
            return "Next: \(upcoming)"
        }

        if report.hospitalitySnapshot.isNotRecent {
            return "Not recent"
        }

        if report.hospitalitySnapshot.isRecent {
            return "Recent"
        }

        return "\(report.summary.pastReservationsCount) past"
    }

    private var partySizeCaption: String {
        if let average = report.hospitalitySnapshot.averagePartySize,
           let largest = report.hospitalitySnapshot.largestPartySize {
            return "Avg \(String(format: "%.1f", average)) · Max \(largest)"
        }

        return "No pattern yet"
    }

    private var sourceValue: String {
        if report.bookingBehavior.manualCount > 0,
           report.bookingBehavior.onlineCount > 0 {
            return "Mixed"
        }

        if report.bookingBehavior.manualCount > 0 {
            return "Call-in"
        }

        return "Online"
    }

    private var sourceCaption: String {
        "\(report.bookingBehavior.onlineCount) online · \(report.bookingBehavior.manualCount) call-in"
    }

    private var notesCaption: String {
        if report.hospitalitySnapshot.hasStaffNotes {
            return "Staff notes found"
        }

        if report.hospitalitySnapshot.hasGuestNotes {
            return "Guest notes found"
        }

        return "No prior notes found"
    }
}

// MARK: - Operational Notes

private struct GuestInsightNotesSection: View {
    let report: GuestInsightReport

    var body: some View {
        GuestInsightCard(title: "Operational Notes", systemImage: "note.text") {
            VStack(alignment: .leading, spacing: 12) {
                if let staffNote = report.summary.lastStaffNote {
                    GuestInsightNoteBlock(
                        title: "Most recent staff note",
                        note: staffNote,
                        emphasized: true
                    )
                }

                if let guestNote = report.summary.lastGuestNote {
                    GuestInsightNoteBlock(
                        title: "Recent guest note",
                        note: guestNote,
                        emphasized: false
                    )
                }

                if report.noteHistory.isEmpty {
                    Text("No previous guest or staff notes found in the local cache.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(report.noteHistory) { note in
                                GuestInsightNoteBlock(
                                    title: "\(note.noteType.displayName) note",
                                    note: note,
                                    emphasized: false
                                )
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("View all notes")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary.opacity(0.82))
                    }
                }
            }
        }
    }
}

// MARK: - Booking History

private struct GuestInsightBookingHistorySection: View {
    let report: GuestInsightReport

    var body: some View {
        GuestInsightCard(title: "Booking History", systemImage: "calendar") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(report.bookingHistory) { item in
                    GuestInsightBookingRow(item: item)
                }
            }
        }
    }
}

// MARK: - Preferences

private struct GuestInsightPreferencesSection: View {
    let report: GuestInsightReport

    var body: some View {
        GuestInsightCard(title: "Preferences", systemImage: "chart.bar.doc.horizontal") {
            VStack(alignment: .leading, spacing: 14) {
                if report.preferredTimes.isEmpty,
                   report.preferredWeekdays.isEmpty,
                   report.partySizeStats.mostCommon == nil {
                    Text("Not enough matching history for useful patterns yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    if !report.preferredTimes.isEmpty {
                        GuestInsightBarChart(
                            title: "Common times",
                            bars: report.preferredTimes.prefix(5).map {
                                GuestInsightBar(label: $0.bucket, count: $0.count)
                            }
                        )
                    }

                    if !report.preferredWeekdays.isEmpty {
                        GuestInsightBarChart(
                            title: "Common weekdays",
                            bars: report.preferredWeekdays.prefix(7).map {
                                GuestInsightBar(label: String($0.weekday.prefix(3)), count: $0.count)
                            }
                        )
                    }

                    preferenceGroup(
                        title: "Party sizes",
                        values: partySizeValues
                    )

                    preferenceGroup(
                        title: "Booking source",
                        values: bookingSourceValues
                    )
                }
            }
        }
    }

    private var partySizeValues: [String] {
        var values: [String] = []
        if let mostCommon = report.partySizeStats.mostCommon {
            values.append("Often party of \(mostCommon)")
        }
        if let min = report.partySizeStats.min, let max = report.partySizeStats.max, min != max {
            values.append("Range \(min)-\(max)")
        }
        if report.partySizeStats.largePartyCount > 0 {
            values.append("\(report.partySizeStats.largePartyCount) large party")
        }
        return values
    }

    private var bookingSourceValues: [String] {
        var values = [
            "\(report.bookingBehavior.onlineCount) online",
            "\(report.bookingBehavior.manualCount) call-in"
        ]

        if let table = report.bookingBehavior.commonTable {
            values.append("Common table \(table)")
        }

        if report.bookingBehavior.upcomingActiveCount > 0 {
            values.append("\(report.bookingBehavior.upcomingActiveCount) upcoming")
        }

        if report.bookingBehavior.cancelledNoShowCount > 0 {
            values.append("\(report.bookingBehavior.cancelledNoShowCount) cancelled/no-show")
        }

        return values
    }

    private func preferenceGroup(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            if values.isEmpty {
                Text("-")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 7) {
                    ForEach(values, id: \.self) { value in
                        GuestInsightBadge(value, systemImage: nil)
                    }
                }
            }
        }
    }
}

// MARK: - Possible Matches

private struct GuestInsightPossibleMatchesSection: View {
    let report: GuestInsightReport

    var body: some View {
        if !report.possibleMatches.isEmpty {
            GuestInsightCard(title: "Possible Same Guest", systemImage: "person.2") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("These records look similar, but are not strong identity matches. Review only; nothing is merged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(report.possibleMatches) { match in
                        GuestInsightMatchRow(match: match)
                    }
                }
            }
        }
    }
}

// MARK: - Watchouts

private struct GuestInsightWarningsSection: View {
    let warnings: [GuestInsightWarning]

    var body: some View {
        if !warnings.isEmpty {
            GuestInsightCard(title: "Watchouts", systemImage: "exclamationmark.circle") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(warnings) { warning in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: warning.systemImage)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(warning.title)
                                    .font(.subheadline.weight(.medium))
                                Text(warning.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - History Rows

private struct GuestInsightBookingRow: View {
    let item: GuestBookingHistoryItem

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayDate)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(item.displayTime)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
            .frame(width: 78, alignment: .leading)

            ReservationDashedLine(isVertical: true)
                .frame(width: 1, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(item.partySize) \(item.partySize == 1 ? "guest" : "guests")")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 7) {
                    Text(item.status.displayName)
                    Text(item.table.map { "Table \($0)" } ?? "No table")
                    if item.hasNotes {
                        Text("Notes")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(item.source.displayName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
        .padding(.vertical, 4)
    }
}

private struct GuestInsightMatchRow: View {
    let match: GuestMatchedReservation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(match.guestName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(match.confidence.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
            }

            Text("\(match.displayDate) at \(match.displayTime) · \(match.partySize) \(match.partySize == 1 ? "guest" : "guests")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            FlowLayout(spacing: 6) {
                ForEach(match.matchReasons, id: \.self) { reason in
                    GuestInsightBadge(reason, systemImage: nil)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct GuestInsightNoteBlock: View {
    let title: String
    let note: GuestNoteHistoryItem
    let emphasized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(note.displayDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(note.text)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(emphasized ? 12 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            emphasized ? Color(.systemGray6) : Color.clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

// MARK: - Shared Guest Insight Components

struct GuestInsightBar: Identifiable {
    let label: String
    let count: Int
    var id: String { label }
}

private struct GuestInsightBarChart: View {
    let title: String
    let bars: [GuestInsightBar]

    private var maxCount: Int { max(bars.map(\.count).max() ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Chart(bars) { bar in
                BarMark(
                    x: .value("Count", bar.count),
                    y: .value("Label", bar.label),
                    height: .ratio(0.62)
                )
                .foregroundStyle(TryzubColors.primaryControl.opacity(bar.count == maxCount ? 0.85 : 0.32))
                .cornerRadius(5)
                .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                    Text("\(bar.count)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .chartYScale(domain: Array(bars.map(\.label).reversed()))
            .chartXScale(domain: 0...(Double(maxCount) * 1.18))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(preset: .aligned, position: .leading) { _ in
                    AxisValueLabel()
                        .font(.caption.weight(.medium))
                }
            }
            .frame(height: CGFloat(bars.count) * 30 + 4)
        }
    }
}

private struct GuestInsightMetricCard: View {
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct GuestInsightCard<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder let content: Content

    init(
        title: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label(title, systemImage: systemImage ?? "circle")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

struct GuestRegularityBadge: View {
    let level: GuestRegularityLevel

    var body: some View {
        Label(level.displayName, systemImage: systemImage)
            .font(.caption.weight(level.rank >= GuestRegularityLevel.regular.rank ? .semibold : .medium))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(background, in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                    .stroke(Color.primary.opacity(level.rank >= GuestRegularityLevel.regular.rank ? 0.16 : 0.08), lineWidth: 1)
            }
    }

    private var systemImage: String {
        switch level {
        case .firstTime:
            return "person"
        case .seenBefore:
            return "checkmark.circle"
        case .becomingRegular:
            return "leaf"
        case .regular:
            return "star"
        case .frequentRegular:
            return "star.fill"
        }
    }

    private var foreground: Color {
        switch level {
        case .regular, .frequentRegular:
            return Color(.label)
        case .becomingRegular:
            return Color(.secondaryLabel)
        case .firstTime, .seenBefore:
            return Color(.secondaryLabel)
        }
    }

    private var background: Color {
        switch level {
        case .regular, .frequentRegular:
            return Color(.label).opacity(0.08)
        case .becomingRegular:
            return Color(.systemGray5).opacity(0.72)
        case .firstTime, .seenBefore:
            return Color(.systemGray6)
        }
    }
}

struct GuestInsightBadge: View {
    let text: String
    let systemImage: String?

    init(_ text: String, systemImage: String?) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - Shared Flow Layout

struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) {
                content
            }
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Guest Insights") {
    NavigationStack {
        GuestInsightsView(
            selectedReservation: ReservationPreviewData.guestInsightsRecord,
            allReservations: ReservationPreviewData.allRecords
        )
    }
    .modelContainer(ReservationPreviewData.previewContainer)
}
#endif
