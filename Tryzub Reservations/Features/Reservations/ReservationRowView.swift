//
//  ReservationRowView.swift
//  Tryzub Reservations
//
//  Created by Bohdan Tkachenko on 5/13/26.
//

import SwiftUI

struct ReservationRowView: View {
    let reservation: ReservationRecord
    var showsDate = true

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularRow
            } else {
                compactRow
            }
        }
        .padding(.vertical, 3)
    }

    private var compactRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(reservation.guestName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(2)

                Spacer(minLength: 8)

                ReservationStatusBadge(status: reservation.statusValue)
            }

            // Primary info: time, party size, table
            HStack(spacing: 6) {
                ReservationMetaPill(text: reservation.displayTime, systemImage: "clock", emphasized: true)
                    .layoutPriority(3)
                
                ReservationMetaPill(text: "\(reservation.partySize)", systemImage: "person.2")
                    .layoutPriority(2)
                
                ReservationMetaPill(
                    text: reservation.tableDisplay,
                    systemImage: "table.furniture",
                    tint: reservation.hasTableAssignment ? .secondary : .orange
                )
                .layoutPriority(1)
                
                Spacer(minLength: 0)
                
                ReservationMetaPill(text: reservation.formattedPhone, systemImage: "phone")
                    .layoutPriority(0)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            if showsDate || reservation.needsOperationalWarning {
                HStack(spacing: 4) {
                    if showsDate {
                        ReservationMetaPill(text: reservation.displayDate, systemImage: "calendar")
                            .layoutPriority(1)
                    }
                    if reservation.statusValue == .needsReview {
                        ReservationMetaPill(text: "Review", systemImage: "exclamationmark.triangle", tint: .orange)
                            .layoutPriority(2)
                    }
                    if reservation.hasGuestNotes || reservation.hasStaffNotes {
                        ReservationMetaPill(text: "Notes", systemImage: "note.text", tint: .secondary)
                            .layoutPriority(0)
                    }
                    if reservation.partySize >= 7 {
                        ReservationMetaPill(text: "Large party", systemImage: "person.3", tint: .orange)
                            .layoutPriority(0)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var regularRow: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(reservation.displayTime)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: 82, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(reservation.guestName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 8) {
                    Text(reservation.formattedPhone)
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if showsDate {
                        Text(reservation.displayDate)
                            .lineLimit(1)
                    }

                    if reservation.hasGuestNotes || reservation.hasStaffNotes {
                        Label("Notes", systemImage: "note.text")
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .layoutPriority(2)

            Text("\(reservation.partySize)")
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .frame(width: 42, alignment: .center)

            Text(reservation.tableDisplay)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(reservation.hasTableAssignment ? Color.secondary : Color.orange)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 92, maxWidth: 140, alignment: .leading)

            ReservationStatusBadge(status: reservation.statusValue)
                .frame(width: 116, alignment: .trailing)
        }
    }
}

struct ReservationStatusBadge: View {
    let status: ReservationStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
            Text(status.displayName)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(status.tintColor)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(status.tintColor.opacity(0.13), in: Capsule())
    }
}

private struct ReservationMetaPill: View {
    let text: String
    let systemImage: String
    var emphasized = false
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .flexibleFrame(horizontal: 14, vertical: 14)
            
            Text(text)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(emphasized ? .subheadline.weight(.semibold) : .caption.weight(.medium))
        .foregroundStyle(tint)
        .layoutPriority(emphasized ? 2 : 1)
    }
}

extension View {
    func flexibleFrame(horizontal: CGFloat, vertical: CGFloat) -> some View {
        self.frame(width: horizontal, height: vertical)
    }
}

extension ReservationStatus {
    var tintColor: Color {
        switch self {
        case .new:
            return .blue.opacity(0.8)
        case .needsReview:
            return .orange.opacity(0.8)
        case .confirmed:
            return .green.opacity(0.8)
        case .seated:
            return .purple.opacity(0.8)
        case .completed:
            return .gray.opacity(0.8)
        case .cancelled, .noShow:
            return .red.opacity(0.8)
        }
    }

    var systemImage: String {
        switch self {
        case .new:
            return "sparkle"
        case .needsReview:
            return "exclamationmark.triangle"
        case .confirmed:
            return "checkmark.circle"
        case .seated:
            return "person.2"
        case .completed:
            return "checkmark.seal"
        case .cancelled:
            return "xmark.circle"
        case .noShow:
            return "person.crop.circle.badge.xmark"
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
