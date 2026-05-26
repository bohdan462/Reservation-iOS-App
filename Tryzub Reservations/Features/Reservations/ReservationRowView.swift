//
//  ReservationRowView.swift
//  Tryzub Reservations
//
//  Created by Bohdan Tkachenko on 5/13/26.
//

import SwiftUI

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

struct ReservationRowView<Accessory: View>: View {
    let reservation: ReservationRecord
    var showsDate = true
    var context: ReservationRowContext = .schedule
    var contextNote: String?

    @ViewBuilder let accessory: () -> Accessory

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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

    private var wideRow: some View {
        HStack(alignment: .center, spacing: 0) {
            timeBlock(width: 92)

            ReservationDashedLine(isVertical: true)
                .frame(width: 1, height: 52)
                .padding(.trailing, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(reservation.guestName)
                    .font(.headline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 9) {
                    ReservationInlineMeta(text: "\(reservation.partySize) guests", systemImage: "person.2")
                    ReservationInlineMeta(text: tableText, systemImage: "table.furniture")
                    if let notesIndicatorText {
                        ReservationInlineMeta(text: notesIndicatorText, systemImage: "note.text")
                    }
                    if !reservation.phone.isEmpty {
                        ReservationInlineMeta(text: reservation.formattedPhone, systemImage: "phone")
                    }
                }

                if let contextNote {
                    Text(contextNote)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(2)

            Spacer(minLength: 12)

            wideActionRail
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 70)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(rowStroke)
    }

    private var compactRow: some View {
        HStack(alignment: .center, spacing: 0) {
            timeBlock(width: 70)

            ReservationDashedLine(isVertical: true)
                .frame(width: 1, height: 50)
                .padding(.trailing, 10)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(reservation.guestName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .truncationMode(.tail)

                    Spacer(minLength: 2)

                    ReservationStatusBadge(status: reservation.statusValue)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 7) {
                        ReservationInlineMeta(text: "\(reservation.partySize)", systemImage: "person.2")
                        ReservationInlineMeta(text: tableText, systemImage: "table.furniture")
                        if let notesIndicatorText {
                            ReservationInlineMeta(text: notesIndicatorText, systemImage: "note.text")
                        }
                    }

                    HStack(spacing: 7) {
                        ReservationInlineMeta(text: "\(reservation.partySize)", systemImage: "person.2")
                        ReservationInlineMeta(text: tableText, systemImage: "table.furniture")
                    }
                }

                if let contextNote {
                    HStack(spacing: 5) {
                        Text(contextNote)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .layoutPriority(2)

            accessory()
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(minHeight: 68)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(rowStroke)
        .overlay(ticketNotches)
    }

    private var wideActionRail: some View {
        VStack(alignment: .trailing, spacing: 7) {
            ReservationStatusBadge(status: reservation.statusValue)

            accessory()
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: 132, alignment: .trailing)
    }

    private func timeBlock(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let compactEyebrow {
                Text(compactEyebrow)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(reservation.displayTime)
                .font(.title3.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: true, vertical: false)

            Text("\(reservation.partySize) \(reservation.partySize == 1 ? "guest" : "guests")")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(width: width, alignment: .leading)
    }

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
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(context.isNext ? Color.primary.opacity(0.22) : Color.primary.opacity(0.08), lineWidth: 1)
    }

    private var ticketNotches: some View {
        HStack {
            Circle()
                .fill(Color(.systemGroupedBackground))
                .frame(width: 12, height: 12)
                .offset(x: -6)

            Spacer()

            Circle()
                .fill(Color(.systemGroupedBackground))
                .frame(width: 12, height: 12)
                .offset(x: 6)
        }
        .allowsHitTesting(false)
    }
}

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
            .background(Color(.systemGray6), in: Capsule())
    }
}

private struct ReservationInlineMeta: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.medium))
                .frame(width: 11)

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

#if DEBUG
#Preview("Row") {
    List {
        ReservationRowView(reservation: ReservationPreviewData.sampleRecord)
    }
    .modelContainer(ReservationPreviewData.previewContainer)
}
#endif
