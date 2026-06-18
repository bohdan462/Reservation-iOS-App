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
            FloorPlanReservationChipSurface {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.reservation.guestName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TryzubColors.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 7) {
                        Text(FloorPlanPresentation.displayTime(item.reservation.reservationTime))
                        Label("\(item.reservation.partySize)", systemImage: "person.2.fill")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    Label {
                        Text(item.tableLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(TryzubColors.primaryControl)
                    } icon: {
                        Image(systemName: "table.furniture")
                            .font(.caption2.weight(.semibold))
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
            FloorPlanReservationChipSurface {
                VStack(alignment: .leading, spacing: 6) {
                    Text(reservation.guestName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TryzubColors.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 7) {
                        Text(FloorPlanPresentation.displayTime(reservation.reservationTime))
                        Label("\(reservation.partySize)", systemImage: "person.2.fill")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    Label {
                        Text("Assign")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(TryzubColors.primaryControl)
                    } icon: {
                        Image(systemName: "table.furniture")
                            .font(.caption2.weight(.semibold))
                    }
                    .labelStyle(.titleAndIcon)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct FloorPlanReservationChipSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .floorPlanGlassSurface(cornerRadius: 10)
    }
}

private extension View {
    func floorPlanGlassSurface(cornerRadius: CGFloat = 10) -> some View {
        background {
            Group {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

struct FloorPlanReservationGridSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(TryzubColors.primaryText)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
