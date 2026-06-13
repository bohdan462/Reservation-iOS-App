//
//  ServiceTimelineReservationBlock.swift
//  Tryzub Reservations
//
//  Horizontal reservation card for the Service Timeline.
//  Safe for staff use: shows time, name, party, status, table. No phone/email/notes.
//

import SwiftUI

struct ServiceTimelineReservationBlock: View {
    let block: ServiceTimelineBlock
    let blockHeight: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            content
        }
        .buttonStyle(.plain)
        .accessibilityLabel(block.voiceOverLabel)
        .accessibilityAddTraits(.isButton)
        .frame(width: block.width, height: blockHeight)
    }

    private var content: some View {
        ZStack(alignment: .leading) {
            // Fill
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(block.status.timelineBlockFill)

            // Border
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(block.status.timelineBlockBorder, lineWidth: 1)

            // Label content
            blockLabel
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
        }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private var blockLabel: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                // Row 1: Guest name + party size
                HStack(spacing: 3) {
                    Text(block.guestName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(block.status.timelineLabelColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text("·\(block.partySize)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                // Row 2: Time + table label
                HStack(spacing: 4) {
                    Text(block.displayTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)

                    if let table = block.assignedTableName {
                        Text(table)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 2)

            // Status badge dots
            badgePips
        }
    }

    @ViewBuilder
    private var badgePips: some View {
        VStack(spacing: 3) {
            if !block.hasTableAssignment {
                pip(color: TryzubColors.warning, label: "No table")
            }
            if block.hasGuestNotes {
                pip(color: TryzubColors.info, label: "Guest note")
            }
            if block.status == .seated {
                pip(color: Color.accentColor, label: "Seated")
            }
        }
    }

    private func pip(color: Color, label: String) -> some View {
        Circle()
            .fill(color.opacity(0.78))
            .frame(width: 5, height: 5)
            .accessibilityLabel(label)
    }
}

// MARK: - Compact block used in preview card

struct ServiceTimelineCompactBlock: View {
    let block: ServiceTimelineBlock
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(block.status.timelineBlockFill)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(block.status.timelineBlockBorder, lineWidth: 0.5)
            }
            .frame(width: block.width, height: height)
            .accessibilityLabel(block.voiceOverLabel)
    }
}
