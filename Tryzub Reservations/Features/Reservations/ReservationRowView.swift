//
//  ReservationRowView.swift
//  Tryzub Reservations
//
//  Created by Bohdan Tkachenko on 5/13/26.
//

import SwiftUI

// MARK: - Row Context

enum ReservationRowContext: Equatable {
    case schedule
    case todayUpcoming
    case todaySeated
    case review

    func eyebrow(for reservation: ReservationRecord, showsDate: Bool) -> String? {
        switch self {
        case .todayUpcoming:
            return nil
        case .todaySeated:
            return nil
        case .review:
            return showsDate ? reservation.displayDate.uppercased() : "REVIEW"
        case .schedule:
            return showsDate ? reservation.displayDate.uppercased() : nil
        }
    }

}

// MARK: - Row Presentation

enum ReservationRowStyle {
    case normal
    case dueSoon
    case attention

    var background: Color {
        switch self {
        case .normal:
            return TryzubColors.cardBackground
        case .dueSoon:
            return TryzubColors.dueSoonBackground
        case .attention:
            return TryzubColors.attentionBackground
        }
    }

    var strokeColor: Color {
        switch self {
        case .normal:
            return Color.primary.opacity(0.08)
        case .dueSoon:
            return Color.primary.opacity(0.22)
        case .attention:
            return TryzubColors.attentionBorder
        }
    }
}

struct ReservationRowPresentation: Identifiable {
    let id: Int
    let timeText: String
    let dateText: String?
    let guestName: String
    let partyText: String
    let compactPartyText: String
    let tableText: String?
    let phoneText: String?
    let guestNotesIndicator: String?
    let staffNotesIndicator: String?
    let statusText: String
    let status: ReservationStatus
    let sourceText: String?
    let submittedInsight: ReservationRowInsight?
    let insight: ReservationRowInsight?
    let isMuted: Bool
    let rowStyle: ReservationRowStyle
    let primaryAction: ReservationHostAction?
    let secondaryActions: [ReservationHostAction]
}

enum ReservationRowDisplayStyle {
    case standard
    case hostBoard
}

enum ReservationRowPresenter {
    static func make(
        reservation: ReservationRecord,
        context: ReservationRowContext,
        contextNote: String?,
        showsDate: Bool,
        showsSubmittedTime: Bool = false,
        now: Date = Date(),
        capabilities: AppCapabilities? = nil
    ) -> ReservationRowPresentation {
        let shouldShowSubmitted = showsSubmittedTime
            || (context == .review && reservation.isInReviewQueue)
        let submittedInsight = shouldShowSubmitted && reservation.isInReviewQueue
            ? submittedInsight(for: reservation)
            : nil
        let insight = primaryInsight(
            reservation: reservation,
            context: context,
            contextNote: contextNote,
            now: now,
            showsSubmittedTime: shouldShowSubmitted
        )
        let policy = capabilities.map {
            ReservationHostActionPolicy(reservation: reservation, capabilities: $0, surface: .row)
        }
        let primaryAction = policy?.primaryRowAction
        let secondaryActions = policy?.contextMenuActions.filter { $0 != primaryAction } ?? []

        return ReservationRowPresentation(
            id: reservation.remoteID,
            timeText: reservation.displayTime,
            dateText: dateText(for: reservation, context: context, showsDate: showsDate),
            guestName: reservation.guestName,
            partyText: "\(reservation.partySize) \(reservation.partySize == 1 ? "guest" : "guests")",
            compactPartyText: "\(reservation.partySize)",
            tableText: reservation.tableDisplay,
            phoneText: reservation.phone.isEmpty ? nil : reservation.formattedPhone,
            guestNotesIndicator: reservation.hasGuestNotes ? "Guest Notes" : nil,
            staffNotesIndicator: reservation.hasStaffNotes ? "Staff Notes" : nil,
            statusText: reservation.statusValue.shortDisplayName,
            status: reservation.statusValue,
            sourceText: reservation.sourceDisplayName,
            submittedInsight: submittedInsight,
            insight: insight,
            isMuted: isMuted(reservation),
            rowStyle: rowStyle(for: insight),
            primaryAction: primaryAction,
            secondaryActions: secondaryActions
        )
    }

    private static func dateText(
        for reservation: ReservationRecord,
        context: ReservationRowContext,
        showsDate: Bool
    ) -> String? {
        switch context {
        case .schedule, .review:
            if showsDate {
                return shortDateLabel(from: reservation.reservationDate)
            }
            return context.eyebrow(for: reservation, showsDate: showsDate)
        case .todayUpcoming, .todaySeated:
            return context.eyebrow(for: reservation, showsDate: showsDate)
        }
    }

    private static func primaryInsight(
        reservation: ReservationRecord,
        context: ReservationRowContext,
        contextNote: String?,
        now: Date,
        showsSubmittedTime: Bool
    ) -> ReservationRowInsight? {
        switch context {
        case .review:
            if showsSubmittedTime {
                return contextNoteInsight(contextNote)
            }
            return reviewInsight(reservation: reservation, contextNote: contextNote)
        case .todayUpcoming, .todaySeated, .schedule:
            if showsSubmittedTime, reservation.isInReviewQueue {
                return contextNoteInsight(contextNote)
            }
            return operationalInsight(
                reservation: reservation,
                context: context,
                contextNote: contextNote,
                now: now
            )
        }
    }

    private static func shouldShowOperationalTimingInsight(
        reservation: ReservationRecord,
        context: ReservationRowContext
    ) -> Bool {
        guard reservation.reservationDate == Date.reservationDateString() else {
            return false
        }

        switch context {
        case .todayUpcoming, .todaySeated:
            return true
        case .schedule, .review:
            return false
        }
    }

    private static func submittedInsight(for reservation: ReservationRecord) -> ReservationRowInsight? {
        guard let timeText = reservation.submittedStaffTimeText else { return nil }
        return ReservationRowInsight(
            text: "Submitted \(timeText)",
            systemImage: "arrow.up.circle",
            tint: .secondary,
            prominence: .normal
        )
    }

    private static func contextNoteInsight(_ contextNote: String?) -> ReservationRowInsight? {
        guard let contextNote = contextNote?.nilIfBlank else { return nil }
        return ReservationRowInsight(
            text: contextNote,
            systemImage: "info.circle",
            tint: .secondary,
            prominence: .normal
        )
    }

    private static func reviewInsight(
        reservation: ReservationRecord,
        contextNote: String?
    ) -> ReservationRowInsight? {
        if reservation.statusValue == .needsReview {
            return contextNoteInsight(contextNote)
        }

        if let submittedAgoText = reservation.submittedStaffTimeText {
            return ReservationRowInsight(
                text: "Submitted \(submittedAgoText)",
                systemImage: "arrow.up.circle",
                tint: .secondary,
                prominence: .normal
            )
        }

        return contextNoteInsight(contextNote)
    }

    private static func operationalTimingInsight(
        reservation: ReservationRecord,
        context: ReservationRowContext,
        now: Date
    ) -> ReservationRowInsight? {
        guard shouldShowOperationalTimingInsight(reservation: reservation, context: context) else {
            return nil
        }

        let timingState = reservation.operationalTimingState(now: now)
        guard let timingText = timingState.insightText else { return nil }
        return ReservationRowInsight(
            text: timingText,
            systemImage: timingState.isAttention ? "exclamationmark.triangle" : "clock",
            tint: timingState.isAttention ? .red : .orange,
            prominence: timingState.isAttention ? .attention : .dueSoon
        )
    }

    private static func operationalInsight(
        reservation: ReservationRecord,
        context: ReservationRowContext,
        contextNote: String?,
        now: Date
    ) -> ReservationRowInsight? {
        if reservation.statusValue == .needsReview {
            return contextNoteInsight(contextNote)
        }

        if let timingInsight = operationalTimingInsight(
            reservation: reservation,
            context: context,
            now: now
        ) {
            return timingInsight
        }

        if let contextNoteInsight = contextNoteInsight(contextNote) {
            return contextNoteInsight
        }

        return nil
    }

    private static func shortDateLabel(from value: String) -> String {
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month) else {
            return value
        }

        let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        return "\(months[month - 1]) \(day)"
    }

    private static func isMuted(_ reservation: ReservationRecord) -> Bool {
        switch reservation.statusValue {
        case .completed, .cancelled, .noShow:
            return true
        case .new, .needsReview, .confirmed, .seated:
            return false
        }
    }

    private static func rowStyle(for insight: ReservationRowInsight?) -> ReservationRowStyle {
        switch insight?.prominence {
        case .attention:
            return .attention
        case .dueSoon:
            return .dueSoon
        case .normal, nil:
            return .normal
        }
    }
}

// MARK: - Shared Reservation Row

struct ReservationRowView<Accessory: View>: View {
    let reservation: ReservationRecord
    var showsDate = true
    var context: ReservationRowContext = .schedule
    var contextNote: String?
    var showsSubmittedTime = false
    var newBookingInsight: NewBookingRowInsight?
    var seatedDurationDotStyle: TryzubStaffStatusDotStyle?
    var capabilities: AppCapabilities?
    var onTableTap: (() -> Void)?
    var displayStyle: ReservationRowDisplayStyle = .standard

    @ViewBuilder let accessory: () -> Accessory

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Accessory lets Today, Schedule, and Review reuse the same compact cell with different actions.
    init(
        reservation: ReservationRecord,
        showsDate: Bool = true,
        context: ReservationRowContext = .schedule,
        contextNote: String? = nil,
        showsSubmittedTime: Bool = false,
        newBookingInsight: NewBookingRowInsight? = nil,
        seatedDurationDotStyle: TryzubStaffStatusDotStyle? = nil,
        capabilities: AppCapabilities? = nil,
        onTableTap: (() -> Void)? = nil,
        displayStyle: ReservationRowDisplayStyle = .standard,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.reservation = reservation
        self.showsDate = showsDate
        self.context = context
        self.contextNote = contextNote
        self.showsSubmittedTime = showsSubmittedTime
        self.newBookingInsight = newBookingInsight
        self.seatedDurationDotStyle = seatedDurationDotStyle
        self.capabilities = capabilities
        self.onTableTap = onTableTap
        self.displayStyle = displayStyle
        self.accessory = accessory
    }

    var body: some View {
        let presentation = ReservationRowPresenter.make(
            reservation: reservation,
            context: context,
            contextNote: contextNote,
            showsDate: showsDate,
            showsSubmittedTime: showsSubmittedTime,
            capabilities: capabilities
        )

        Group {
            if horizontalSizeClass == .regular {
                wideRow(presentation)
            } else {
                compactRow(presentation)
            }
        }
        .opacity(presentation.isMuted ? 0.58 : 1)
    }

    // MARK: - Wide / Compact Layouts

    private func wideRow(_ presentation: ReservationRowPresentation) -> some View {
        HStack(alignment: .center, spacing: ReservationRowLayout.wideSectionSpacing) {
            ReservationRowTimeSection(
                eyebrow: timeEyebrow(for: presentation),
                time: presentation.timeText,
                guestCountText: timeGuestCountText(for: presentation),
                showsGuestIcon: displayStyle == .hostBoard,
                eyebrowIsStatus: displayStyle == .hostBoard,
                width: timeColumnWidth
            )

            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 1, height: displayStyle == .hostBoard ? 48 : 52)
                .padding(.leading, displayStyle == .hostBoard ? ReservationRowLayout.hostTrailingContentLeadingInset : 0)

            ReservationRowGuestSection(
                guestName: presentation.guestName,
                status: nil,
                metaItems: metaItems(for: presentation),
                submittedInsight: displayStyle == .hostBoard ? nil : presentation.submittedInsight,
                insight: displayStyle == .hostBoard ? nil : presentation.insight,
                newBookingInsight: displayStyle == .hostBoard ? nil : newBookingInsight,
                seatedDurationDotStyle: seatedDurationDotStyle,
                onTableTap: onTableTap,
                usesCompactName: false
            )
            .layoutPriority(2)

            Spacer(minLength: ReservationRowLayout.minimumSpacer)

            ReservationRowAccessorySection(
                status: displayStyle == .hostBoard ? nil : presentation.status,
                width: actionColumnWidth,
                accessory: accessory
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, displayStyle == .hostBoard ? 8 : 9)
        .frame(minHeight: displayStyle == .hostBoard ? 68 : 70)
        .background(rowBackground(for: presentation.rowStyle))
        .overlay(rowStroke(for: presentation.rowStyle))
    }

    private func compactRow(_ presentation: ReservationRowPresentation) -> some View {
        HStack(alignment: .center, spacing: ReservationRowLayout.compactSectionSpacing) {
            ReservationRowTimeSection(
                eyebrow: timeEyebrow(for: presentation),
                time: presentation.timeText,
                guestCountText: timeGuestCountText(for: presentation),
                showsGuestIcon: displayStyle == .hostBoard,
                eyebrowIsStatus: displayStyle == .hostBoard,
                width: timeColumnWidth
            )

            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 1, height: displayStyle == .hostBoard ? 46 : 50)
                .padding(.leading, displayStyle == .hostBoard ? ReservationRowLayout.hostTrailingContentLeadingInset : 0)

            ReservationRowGuestSection(
                guestName: presentation.guestName,
                status: nil,
                metaItems: metaItems(for: presentation),
                submittedInsight: displayStyle == .hostBoard ? nil : presentation.submittedInsight,
                insight: displayStyle == .hostBoard ? nil : presentation.insight,
                newBookingInsight: displayStyle == .hostBoard ? nil : newBookingInsight,
                seatedDurationDotStyle: seatedDurationDotStyle,
                onTableTap: onTableTap,
                usesCompactName: true
            )
            .layoutPriority(2)

            ReservationRowAccessorySection(
                status: nil,
                width: nil,
                accessory: accessory
            )
        }
        .padding(.horizontal, 11)
        .padding(.vertical, displayStyle == .hostBoard ? 8 : 9)
        .frame(minHeight: displayStyle == .hostBoard ? 66 : 68)
        .background(rowBackground(for: presentation.rowStyle))
        .overlay(rowStroke(for: presentation.rowStyle))
    }

    // MARK: - Display Helpers

    private var timeColumnWidth: CGFloat {
        switch displayStyle {
        case .standard:
            return horizontalSizeClass == .regular
                ? ReservationRowLayout.wideTimeWidth
                : ReservationRowLayout.compactTimeWidth
        case .hostBoard:
            return horizontalSizeClass == .regular
                ? ReservationRowLayout.hostWideTimeWidth
                : ReservationRowLayout.hostCompactTimeWidth
        }
    }

    private var actionColumnWidth: CGFloat? {
        switch displayStyle {
        case .standard:
            return ReservationRowLayout.wideActionWidth
        case .hostBoard:
            return ReservationRowLayout.hostWideActionWidth
        }
    }

    private func timeGuestCountText(for presentation: ReservationRowPresentation) -> String {
        displayStyle == .hostBoard ? presentation.compactPartyText : presentation.partyText
    }

    private func timeEyebrow(for presentation: ReservationRowPresentation) -> String? {
        displayStyle == .hostBoard ? presentation.statusText.uppercased() : presentation.dateText
    }

    private func metaItems(for presentation: ReservationRowPresentation) -> [ReservationRowDetailLabelData] {
        switch displayStyle {
        case .standard:
            return horizontalSizeClass == .regular
                ? wideMetaItems(for: presentation)
                : compactMetaItems(for: presentation)
        case .hostBoard:
            return hostBoardMetaItems(for: presentation)
        }
    }

    private func wideMetaItems(for presentation: ReservationRowPresentation) -> [ReservationRowDetailLabelData] {
        var items: [ReservationRowDetailLabelData] = [
            ReservationRowDetailLabelData(text: presentation.partyText, systemImage: "person.2"),
            ReservationRowDetailLabelData(text: presentation.tableText ?? "No table", systemImage: "table.furniture", isTable: true)
        ]

        if let guestNotesIndicator = presentation.guestNotesIndicator {
            items.append(ReservationRowDetailLabelData(text: guestNotesIndicator, systemImage: "note.text"))
        }

        if let staffNotesIndicator = presentation.staffNotesIndicator {
            items.append(ReservationRowDetailLabelData(text: staffNotesIndicator, systemImage: "note.text.badge.plus"))
        }

//        if let phoneText = presentation.phoneText {
//            items.append(ReservationRowDetailLabelData(text: phoneText, systemImage: "phone"))
//        }

        return items
    }

    private func hostBoardMetaItems(for presentation: ReservationRowPresentation) -> [ReservationRowDetailLabelData] {
        let tableText = presentation.tableText ?? "No table"
        var items = [
            ReservationRowDetailLabelData(
                text: tableText.removingTablePrefix,
                systemImage: "table.furniture",
                isTable: true,
                accessibilityLabel: tableText
            )
        ]

        if presentation.guestNotesIndicator != nil {
            items.append(
                ReservationRowDetailLabelData(
                    text: "",
                    systemImage: "note.text",
                    accessibilityLabel: "Guest notes"
                )
            )
        }

        if presentation.staffNotesIndicator != nil {
            items.append(
                ReservationRowDetailLabelData(
                    text: "",
                    systemImage: "note.text.badge.plus",
                    accessibilityLabel: "Staff notes"
                )
            )
        }

        if presentation.status == .needsReview {
            items.append(
                ReservationRowDetailLabelData(
                    text: "",
                    systemImage: "exclamationmark.triangle",
                    accessibilityLabel: "Needs review"
                )
            )
        }

        if let insight = presentation.insight, insight.prominence != .normal {
            items.append(
                ReservationRowDetailLabelData(
                    text: "",
                    systemImage: insight.systemImage,
                    accessibilityLabel: insight.text
                )
            )
        }

        return items
    }

    private func compactMetaItems(for presentation: ReservationRowPresentation) -> [ReservationRowDetailLabelData] {
        var parts = [
            "\(presentation.compactPartyText) \(presentation.compactPartyText == "1" ? "guest" : "guests")",
            presentation.tableText ?? "No table",
            presentation.statusText
        ]
        if let guestNotesIndicator = presentation.guestNotesIndicator {
            parts.append(guestNotesIndicator)
        }
        if let staffNotesIndicator = presentation.staffNotesIndicator {
            parts.append(staffNotesIndicator)
        }

        return [
            ReservationRowDetailLabelData(
                text: parts.joined(separator: " • "),
                systemImage: presentation.status == .needsReview ? "exclamationmark.triangle" : "info.circle",
                allowsWrapping: true
            )
        ]
    }

    private func rowStroke(for style: ReservationRowStyle) -> some View {
        RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
            .stroke(displayStyle == .hostBoard ? hostRowStrokeColor(for: style) : style.strokeColor, lineWidth: 1)
    }

    @ViewBuilder
    private func rowBackground(for style: ReservationRowStyle) -> some View {
        let corner = ReservationUIStyle.cardCorner
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)

        if displayStyle == .hostBoard {
            shape
                .fill(hostRowTint(for: style))
                .background {
                    Group {
                        if #available(iOS 26.0, *) {
                            shape
                                .fill(.clear)
                                .glassEffect(.clear, in: .rect(cornerRadius: corner))
                        } else {
                            shape
                                .fill(.ultraThinMaterial.opacity(0.42))
                        }
                    }
                }
        } else {
            shape.fill(style.background)
        }
    }

    private func hostRowTint(for style: ReservationRowStyle) -> Color {
        switch style {
        case .normal:
            return Color.primary.opacity(0.015)
        case .dueSoon:
            return Color.orange.opacity(0.08)
        case .attention:
            return Color.red.opacity(0.08)
        }
    }

    private func hostRowStrokeColor(for style: ReservationRowStyle) -> Color {
        switch style {
        case .normal:
            return Color.primary.opacity(0.10)
        case .dueSoon:
            return Color.orange.opacity(0.22)
        case .attention:
            return TryzubColors.attentionBorder.opacity(0.55)
        }
    }

}

// MARK: - Row Sections

private enum ReservationRowLayout {
    static let wideTimeWidth: CGFloat = 92
    static let compactTimeWidth: CGFloat = 70
    static let hostWideTimeWidth: CGFloat = 86
    static let hostCompactTimeWidth: CGFloat = 72
    static let hostTrailingContentLeadingInset: CGFloat = 10
    static let wideActionWidth: CGFloat = 108
    static let hostWideActionWidth: CGFloat = 124
    static let wideSectionSpacing: CGFloat = 12
    static let compactSectionSpacing: CGFloat = 10
    static let minimumSpacer: CGFloat = 12
}

private struct ReservationRowDetailLabelData: Identifiable {
    let text: String
    let systemImage: String
    var isTable = false
    var allowsWrapping = false
    var accessibilityLabel: String?

    var id: String {
        "\(systemImage)-\(text)-\(isTable)-\(allowsWrapping)-\(accessibilityLabel ?? "")"
    }
}

struct ReservationRowInsight {
    enum Prominence: Equatable {
        case normal
        case dueSoon
        case attention
    }

    let text: String
    let systemImage: String
    let tint: Color
    let prominence: Prominence
}

private struct ReservationRowTimeSection: View {
    let eyebrow: String?
    let time: String
    let guestCountText: String
    var showsGuestIcon = false
    var eyebrowIsStatus = false
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow ?? "")
                .font(.caption2.weight(eyebrowIsStatus ? .bold : .medium))
                .foregroundStyle(eyebrowIsStatus ? Color.primary.opacity(0.62) : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(height: 14, alignment: .leading)

            Text(time)
                .font(.title3.weight(eyebrowIsStatus ? .semibold : .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: 25, alignment: .leading)

            HStack(spacing: 4) {
                if showsGuestIcon {
                    Image(systemName: "person.fill")
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }

                Text(guestCountText)
                    .font(.caption.weight(showsGuestIcon ? .bold : .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(height: 14, alignment: .leading)
            .accessibilityLabel(showsGuestIcon ? "\(guestCountText) guests" : guestCountText)
        }
        .frame(width: width, alignment: .leading)
    }
}

private struct ReservationRowGuestSection: View {
    let guestName: String
    let status: ReservationStatus?
    let metaItems: [ReservationRowDetailLabelData]
    let submittedInsight: ReservationRowInsight?
    let insight: ReservationRowInsight?
    let newBookingInsight: NewBookingRowInsight?
    var seatedDurationDotStyle: TryzubStaffStatusDotStyle?
    let onTableTap: (() -> Void)?
    let usesCompactName: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(guestName)
                    .font(usesCompactName ? .subheadline.weight(.medium) : .headline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let status {
                    ReservationStatusBadge(status: status)
                }
            }
            .frame(minHeight: 22, alignment: .center)

            ReservationRowDetailsLine(items: metaItems, onTableTap: onTableTap)

            if let submittedInsight {
                ReservationRowInsightLine(insight: submittedInsight)
            }

            if let insight {
                ReservationRowInsightLine(
                    insight: insight,
                    seatedDurationDotStyle: seatedDurationDotStyle
                )
            }

            if let newBookingInsight {
                ReservationRowNewBookingInsightLines(insight: newBookingInsight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReservationRowNewBookingInsightLines: View {
    let insight: NewBookingRowInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(insight.displayLines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(index == 0 ? Color.secondary : Color.secondary.opacity(0.82))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, minHeight: insight.displayLines.isEmpty ? 0 : 16, alignment: .leading)
    }
}

private struct ReservationRowAccessorySection<Accessory: View>: View {
    let status: ReservationStatus?
    let width: CGFloat?
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            if let status {
                ReservationStatusBadge(status: status)
            }

            accessory()
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: width, alignment: .trailing)
    }
}

private struct ReservationRowDetailsLine: View {
    let items: [ReservationRowDetailLabelData]
    let onTableTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 9) {
            if let item = items[safe: 0] {
                metaView(item)
            }
            if let item = items[safe: 1] {
                metaView(item)
            }
            if let item = items[safe: 2] {
                metaView(item)
            }
            if let item = items[safe: 3] {
                metaView(item)
            }
            if let item = items[safe: 4] {
                metaView(item)
            }
        }
        .frame(maxWidth: .infinity, minHeight: items.contains(where: \.allowsWrapping) ? 34 : 18, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func metaView(_ item: ReservationRowDetailLabelData) -> some View {
        if item.isTable, let onTableTap {
            Button {
                ReservationHaptics.selection()
                onTableTap()
            } label: {
                ReservationRowDetailLabel(item: item)
            }
            .buttonStyle(.plain)
        } else {
            ReservationRowDetailLabel(item: item)
        }
    }
}

private struct ReservationRowInsightLine: View {
    let insight: ReservationRowInsight
    var seatedDurationDotStyle: TryzubStaffStatusDotStyle?

    var body: some View {
        HStack(spacing: 6) {
            if let seatedDurationDotStyle {
                TryzubStaffStatusDot(style: seatedDurationDotStyle, diameter: 5)
            }

            Image(systemName: insight.systemImage)
                .font(.caption2.weight(.semibold))
                .frame(width: 12)

            Text(insight.text)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(insight.tint)
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
    }
}

// MARK: - Empty Accessory Convenience

extension ReservationRowView where Accessory == EmptyView {
    init(
        reservation: ReservationRecord,
        showsDate: Bool = true,
        context: ReservationRowContext = .schedule,
        contextNote: String? = nil,
        seatedDurationDotStyle: TryzubStaffStatusDotStyle? = nil,
        capabilities: AppCapabilities? = nil,
        onTableTap: (() -> Void)? = nil
    ) {
        self.init(
            reservation: reservation,
            showsDate: showsDate,
            context: context,
            contextNote: contextNote,
            seatedDurationDotStyle: seatedDurationDotStyle,
            capabilities: capabilities,
            onTableTap: onTableTap
        ) {
            EmptyView()
        }
    }
}

// MARK: - Status Badge

struct ReservationStatusBadge: View {
    let status: ReservationStatus
    var style: BadgeStyle = .standard

    enum BadgeStyle {
        case standard
        case homeRow
    }

    var body: some View {
        TryzubStatusBadge(
            title: status.shortDisplayName,
            tint: .secondary,
            minHeight: style == .homeRow ? 22 : 26,
            horizontalPadding: style == .homeRow ? 6 : 8
        )
        .font(style == .homeRow ? .caption2.weight(.semibold) : .caption2.weight(.medium))
    }
}

struct AutoConfirmedBadge: View {
    var body: some View {
        TryzubStatusBadge(
            title: "Auto-confirmed",
            tint: .secondary,
            minHeight: 22,
            horizontalPadding: 8
        )
        .font(.caption2.weight(.medium))
    }
}

//OLD
//struct ReservationStatusBadge: View {
//    let status: ReservationStatus
//
//    var body: some View {
//        TryzubStatusBadge(title: status.shortDisplayName, tint: .secondary)
//            .font(.caption2.weight(.medium))
//    }
//}

// MARK: - Inline Metadata

private struct ReservationRowDetailLabel: View {
    let item: ReservationRowDetailLabelData

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: item.systemImage)
                .font(.caption2.weight(.medium))
                .frame(width: 13)

            if !item.text.isEmpty {
                Text(item.text)
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .lineLimit(item.allowsWrapping ? 2 : 1)
                    .truncationMode(.tail)
            }
        }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: item.allowsWrapping)
        .accessibilityLabel(item.accessibilityLabel ?? item.text)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var removingTablePrefix: String {
        if hasPrefix("Table ") {
            return String(dropFirst("Table ".count))
        }
        return self
    }
}

// MARK: - Compact Status Copy

extension ReservationStatus {
    var shortDisplayName: String {
        switch self {
        case .needsReview:
            return "Review"
        case .noShow:
            return "No Show"
        case .new, .confirmed, .seated, .completed, .cancelled:
            return displayName
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Row") {
    List {
        ReservationRowView(reservation: ReservationPreviewData.sampleRecord)
    }
    .modelContainer(ReservationPreviewData.previewContainer)
}
#endif
