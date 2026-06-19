//
//  HostBoardAuxiliaryCards.swift
//  Tryzub Reservations
//

import SwiftUI

enum ReservationPresentationTime {
    static func hourLabel(from hourString: String) -> String {
        guard let hour = Int(hourString) else { return hourString }
        let adjustedHour = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return "\(adjustedHour) \(suffix)"
    }
}

struct HostBookingLoadCompactStrip: View {
    let item: BookingSuggestionViewItem
    let knownOnlyNote: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.severity == .veryBusy ? .red : .orange)
                .frame(width: 22, height: 22)
                .hostBoardGlassCapsule(strokeOpacity: 0.10)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.headline). \(item.loadLine).")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TryzubColors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(knownOnlyNote)
                    .font(.caption2)
                    .foregroundStyle(TryzubColors.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hostBoardGlassPanel(cornerRadius: 12, strokeOpacity: 0.10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.headline). \(item.loadLine). \(knownOnlyNote)")
    }
}

struct HostFloorSetupPromptCard: View {
    var onOpenFloorSetup: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Floor plan not set up yet", systemImage: "square.grid.3x3.topleft.filled")
                .font(.subheadline.weight(.semibold))
            Text("Set up tables in the Floor tab.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let onOpenFloorSetup {
                Button("Open Floor Setup", action: onOpenFloorSetup)
                    .font(.footnote.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .hostBoardGlassPanel(cornerRadius: 12)
    }
}
