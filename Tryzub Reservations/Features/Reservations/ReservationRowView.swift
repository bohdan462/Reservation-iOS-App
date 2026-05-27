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
    case todayUpcoming(isNext: Bool)
    case todaySeated
    case review

    func eyebrow(for reservation: ReservationRecord, showsDate: Bool) -> String? {
        switch self {
        case .todayUpcoming(let isNext):
            return isNext ? "NEXT" : nil
        case .todaySeated:
            return nil
        case .review:
            return showsDate ? reservation.displayDate.uppercased() : "REVIEW"
        case .schedule:
            return showsDate ? reservation.displayDate.uppercased() : nil
        }
    }

    var isNext: Bool {
        if case .todayUpcoming(let isNext) = self {
            return isNext
        }
        return false
    }
}

// MARK: - Shared Reservation Row

struct ReservationRowView<Accessory: View>: View {
    let reservation: ReservationRecord
    var showsDate = true
    var context: ReservationRowContext = .schedule
    var contextNote: String?

    @ViewBuilder let accessory: () -> Accessory

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Accessory lets Today, Schedule, and Review reuse the same compact cell with different actions.
    init(
        reservation: ReservationRecord,
        showsDate: Bool = true,
        context: ReservationRowContext = .schedule,
        contextNote: String? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.reservation = reservation
        self.showsDate = showsDate
        self.context = context
        self.contextNote = contextNote
        self.accessory = accessory
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                wideRow
            } else {
                compactRow
            }
        }
        .opacity(isMuted ? 0.58 : 1)
    }

    // MARK: - Wide / Compact Layouts

    private var wideRow: some View {
        HStack(alignment: .center, spacing: ReservationRowLayout.wideSectionSpacing) {
            ReservationRowTimeSection(
                eyebrow: compactEyebrow,
                time: reservation.displayTime,
                guestCountText: guestCountText,
                width: ReservationRowLayout.wideTimeWidth
            )

            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 1, height: 52)

            ReservationRowGuestSection(
                guestName: reservation.guestName,
                status: nil,
                metaItems: wideMetaItems,
                submittedAgoText: reservation.submittedAgoText,
                contextNote: contextNote,
                usesCompactName: false
            )
            .layoutPriority(2)

            Spacer(minLength: ReservationRowLayout.minimumSpacer)

            ReservationRowAccessorySection(
                status: reservation.statusValue,
                width: ReservationRowLayout.wideActionWidth,
                accessory: accessory
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 70)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay(rowStroke)
    }

    private var compactRow: some View {
        HStack(alignment: .center, spacing: ReservationRowLayout.compactSectionSpacing) {
            ReservationRowTimeSection(
                eyebrow: compactEyebrow,
                time: reservation.displayTime,
                guestCountText: guestCountText,
                width: ReservationRowLayout.compactTimeWidth
            )

            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 1, height: 50)

            ReservationRowGuestSection(
                guestName: reservation.guestName,
                status: reservation.statusValue,
                metaItems: compactMetaItems,
                submittedAgoText: reservation.submittedAgoText,
                contextNote: contextNote,
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
        .padding(.vertical, 9)
        .frame(minHeight: 68)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay(rowStroke)
    }

    // MARK: - Action Area

    // MARK: - Display Helpers

    private var eyebrow: String? {
        context.eyebrow(for: reservation, showsDate: showsDate)
    }

    private var compactEyebrow: String? {
        switch context {
        case .schedule, .review:
            return showsDate ? Self.shortDateLabel(from: reservation.reservationDate) : eyebrow
        case .todayUpcoming, .todaySeated:
            return eyebrow
        }
    }

    private var guestCountText: String {
        "\(reservation.partySize) \(reservation.partySize == 1 ? "guest" : "guests")"
    }

    private var wideMetaItems: [ReservationRowMetaItem] {
        var items: [ReservationRowMetaItem] = [
            ReservationRowMetaItem(text: guestCountText, systemImage: "person.2"),
            ReservationRowMetaItem(text: tableText, systemImage: "table.furniture")
        ]

        if let notesIndicatorText {
            items.append(ReservationRowMetaItem(text: notesIndicatorText, systemImage: "note.text"))
        }

        if let sourceLabel = reservation.rowSourceLabel {
            items.append(ReservationRowMetaItem(text: sourceLabel, systemImage: reservation.rowSourceSystemImage))
        }

        if !reservation.phone.isEmpty {
            items.append(ReservationRowMetaItem(text: reservation.formattedPhone, systemImage: "phone"))
        }

        return items
    }

    private var compactMetaItems: [ReservationRowMetaItem] {
        var items: [ReservationRowMetaItem] = [
            ReservationRowMetaItem(text: "\(reservation.partySize)", systemImage: "person.2"),
            ReservationRowMetaItem(text: tableText, systemImage: "table.furniture")
        ]

        if let notesIndicatorText {
            items.append(ReservationRowMetaItem(text: notesIndicatorText, systemImage: "note.text"))
        }

        if let sourceLabel = reservation.rowSourceLabel {
            items.append(ReservationRowMetaItem(text: sourceLabel, systemImage: reservation.rowSourceSystemImage))
        }

        return items
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

    private var tableText: String {
        guard let tableName = reservation.tableName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tableName.isEmpty else {
            return "No table"
        }
        return "Table \(tableName)"
    }

    private var notesIndicatorText: String? {
        if reservation.hasStaffNotes {
            return "STAFF"
        }

        if reservation.hasGuestNotes {
            return "Notes"
        }

        return nil
    }

    private var isMuted: Bool {
        switch reservation.statusValue {
        case .completed, .cancelled, .noShow:
            return true
        case .new, .needsReview, .confirmed, .seated:
            return false
        }
    }

    private var rowBackground: Color {
        context.isNext
            ? Color(.systemGray5)
            : Color(.secondarySystemGroupedBackground)
    }

    private var rowStroke: some View {
        RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
            .stroke(context.isNext ? Color.primary.opacity(0.22) : Color.primary.opacity(0.08), lineWidth: 1)
    }

}

// MARK: - Row Sections

private enum ReservationRowLayout {
    static let wideTimeWidth: CGFloat = 92
    static let compactTimeWidth: CGFloat = 70
    static let wideActionWidth: CGFloat = 132
    static let wideSectionSpacing: CGFloat = 12
    static let compactSectionSpacing: CGFloat = 10
    static let minimumSpacer: CGFloat = 12
}

private struct ReservationRowMetaItem: Identifiable {
    let id = UUID()
    let text: String
    let systemImage: String
}

private struct ReservationRowTimeSection: View {
    let eyebrow: String?
    let time: String
    let guestCountText: String
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow ?? "")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(height: 14, alignment: .leading)

            Text(time)
                .font(.title3.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: 25, alignment: .leading)

            Text(guestCountText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(height: 14, alignment: .leading)
        }
        .frame(width: width, alignment: .leading)
    }
}

private struct ReservationRowGuestSection: View {
    let guestName: String
    let status: ReservationStatus?
    let metaItems: [ReservationRowMetaItem]
    let submittedAgoText: String?
    let contextNote: String?
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

            ReservationRowMetaLine(items: metaItems)

            if let submittedAgoText {
                ReservationSubmittedBadge(text: submittedAgoText)
            } else if let contextNote {
                Text(contextNote)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct ReservationRowMetaLine: View {
    let items: [ReservationRowMetaItem]

    var body: some View {
        HStack(spacing: 12) {
            if let item = items[safe: 0] {
                ReservationInlineMeta(text: item.text, systemImage: item.systemImage)
            }
            if let item = items[safe: 1] {
                ReservationInlineMeta(text: item.text, systemImage: item.systemImage)
            }
            if let item = items[safe: 2] {
                ReservationInlineMeta(text: item.text, systemImage: item.systemImage)
            }
            if let item = items[safe: 3] {
                ReservationInlineMeta(text: item.text, systemImage: item.systemImage)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
        .clipped()
    }
}

private struct ReservationSubmittedBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark")
                .font(.caption2.weight(.semibold))
                .frame(width: 8)

            Text("Submitted \(text)")
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
    }
}

// MARK: - Empty Accessory Convenience

extension ReservationRowView where Accessory == EmptyView {
    init(
        reservation: ReservationRecord,
        showsDate: Bool = true,
        context: ReservationRowContext = .schedule,
        contextNote: String? = nil
    ) {
        self.init(
            reservation: reservation,
            showsDate: showsDate,
            context: context,
            contextNote: contextNote
        ) {
            EmptyView()
        }
    }
}

// MARK: - Status Badge

struct ReservationStatusBadge: View {
    let status: ReservationStatus

    var body: some View {
        Text(status.shortDisplayName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
    }
}

// MARK: - Inline Metadata

private struct ReservationInlineMeta: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.medium))
                .frame(width: 13)

            Text(text)
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: false)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
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
