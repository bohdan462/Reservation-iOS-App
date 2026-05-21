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
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                if let compactEyebrow {
                    Text(compactEyebrow)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(reservation.displayTime)
                    .font(.title3.weight(.black))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: 86, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Text("\(reservation.partySize)")
                        .font(.subheadline.weight(.black))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                HStack(spacing: 5) {
                    Image(systemName: "table.furniture")
                        .font(.caption2.weight(.bold))
                    Text(tableText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            }
            .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(reservation.guestName.uppercased())
                    .font(.headline.weight(.black))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 10) {
                    if !reservation.phone.isEmpty {
                        ReservationInlineMeta(text: reservation.formattedPhone, systemImage: "phone.fill")
                    }

                    if reservation.hasGuestNotes || reservation.hasStaffNotes {
                        ReservationInlineMeta(text: "NOTES", systemImage: "note.text")
                    }

                    if reservation.partySize >= 7 {
                        ReservationInlineMeta(text: "LARGE", systemImage: "person.3.fill")
                    }
                }

                if let contextNote {
                    Text(contextNote)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(2)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                ReservationStatusBadge(status: reservation.statusValue)

                if reservation.statusValue == .needsReview,
                   let staffNotes = reservation.staffNotes,
                   !staffNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(staffNotes)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 140, alignment: .trailing)
                }
            }

            accessory()
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 54)
      
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(rowStroke)
    }

    private var compactRow: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                if let compactEyebrow {
                    Text(compactEyebrow)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(reservation.displayTime)
                    .font(.title3.weight(.black))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: 66, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(reservation.guestName.uppercased())
                        .font(.subheadline.weight(.black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .truncationMode(.tail)

                    Spacer(minLength: 2)

                    ReservationStatusBadge(status: reservation.statusValue)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 7) {
                        ReservationInlineMeta(text: "\(reservation.partySize)", systemImage: "person.fill")
                        ReservationInlineMeta(text: tableText, systemImage: "table.furniture")
                        if !reservation.phone.isEmpty {
                            ReservationInlineMeta(text: reservation.formattedPhone, systemImage: "phone.fill")
                        }
                    }

                    HStack(spacing: 7) {
                        ReservationInlineMeta(text: "\(reservation.partySize)", systemImage: "person.fill")
                        ReservationInlineMeta(text: tableText, systemImage: "table.furniture")
                    }
                }

                HStack(spacing: 5) {
                    if let contextNote {
                        Text(contextNote)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    if reservation.hasGuestNotes || reservation.hasStaffNotes {
                        ReservationInlineMeta(text: "NOTES", systemImage: "note.text")
                    }
                }
            }
            .layoutPriority(2)

            accessory()
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(minHeight: 58)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(rowStroke)
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
            return "x"
        }
        return tableName.uppercased()
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
            : Color(.systemBackground)
    }

    private var rowStroke: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(context.isNext ? Color.primary.opacity(0.32) : Color.primary.opacity(0.08), lineWidth: 1)
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
        Text(status.shortDisplayName.uppercased())
            .font(.caption2.weight(.black))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ReservationInlineMeta: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .frame(width: 11)

            Text(text)
                .font(.caption2.weight(.bold))
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
