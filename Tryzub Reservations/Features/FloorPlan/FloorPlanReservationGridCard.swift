//
//  FloorPlanReservationGridCard.swift
//  Tryzub Reservations
//

import SwiftUI

enum FloorPlanReservationGridCard {
    static func columns(for width: CGFloat) -> [GridItem] {
        let minimum: CGFloat
        if width >= 900 {
            minimum = 176
        } else if width >= 640 {
            minimum = 160
        } else {
            minimum = 148
        }
        return [GridItem(.adaptive(minimum: minimum), spacing: 10)]
    }
}

struct FloorPlanAssignedReservationCard: View {
    let item: FloorPlanAssignedReservation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HostAssignmentCardSurface {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.reservation.guestName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TryzubColors.primaryText)
                            .lineLimit(1)

                        Text(
                            "\(FloorPlanPresentation.displayTime(item.reservation.reservationTime)) · party of \(item.reservation.partySize)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }

                    Label {
                        Text(item.tableLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TryzubColors.primaryControl)
                    } icon: {
                        Image(systemName: "table.furniture")
                            .font(.caption.weight(.semibold))
                    }
                    .labelStyle(.titleAndIcon)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct FloorPlanUnassignedReservationCard: View {
    let reservation: ManagedReservationDTO
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HostAssignmentCardSurface {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reservation.guestName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TryzubColors.primaryText)
                            .lineLimit(1)

                        Text(
                            "\(FloorPlanPresentation.displayTime(reservation.reservationTime)) · party of \(reservation.partySize)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }

                    if !noteChips.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(noteChips, id: \.self) { chip in
                                Text(chip)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.secondary.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    Label {
                        Text("Assign")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TryzubColors.primaryControl)
                    } icon: {
                        Image(systemName: "table.furniture")
                            .font(.caption.weight(.semibold))
                    }
                    .labelStyle(.titleAndIcon)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var noteChips: [String] {
        var chips: [String] = []
        let combined = [reservation.guestNotes, reservation.staffNotes]
            .compactMap { value -> String? in
                guard let value,
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return value
            }
            .joined(separator: " ")
            .lowercased()
        if !combined.isEmpty {
            chips.append("Note")
        }
        if combined.contains("deposit") || combined.contains("payment") {
            chips.append("Deposit")
        }
        if combined.contains("preorder") || combined.contains("pre-order") {
            chips.append("Preorder")
        }
        if combined.contains("allerg")
            || combined.contains("gluten")
            || combined.contains("vegan")
            || combined.contains("vegetar") {
            chips.append("Dietary")
        }
        return chips
    }
}

struct FloorPlanReservationGridSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(TryzubTypography.sectionTitle)
                .foregroundStyle(TryzubColors.primaryText)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
