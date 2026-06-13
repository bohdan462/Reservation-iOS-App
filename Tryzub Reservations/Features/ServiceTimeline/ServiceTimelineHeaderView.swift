//
//  ServiceTimelineHeaderView.swift
//  Tryzub Reservations
//
//  Horizontal time-tick strip at the top of the Service Timeline.
//  Major ticks show "5:00", "5:30" labels; minor ticks are subtle lines.
//

import SwiftUI

struct ServiceTimelineHeaderView: View {
    let ticks: [ServiceTimelineLayoutEngine.TimeTick]
    let totalWidth: CGFloat

    private let height: CGFloat = ServiceTimelineLayoutEngine.headerHeight

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Header background
            Color(.secondarySystemGroupedBackground)
                .frame(width: totalWidth, height: height)

            // Bottom separator
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(width: totalWidth, height: 0.5)
                .offset(y: height - 0.5)

            // Ticks
            ForEach(ticks) { tick in
                if tick.isMajor {
                    majorTickView(tick: tick)
                } else {
                    minorTickView(tick: tick)
                }
            }
        }
        .frame(width: totalWidth, height: height)
        .clipped()
    }

    // A major tick: label + full-height separator line
    private func majorTickView(tick: ServiceTimelineLayoutEngine.TimeTick) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(tick.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .frame(width: 54, alignment: .center)
            Spacer(minLength: 6)
            Rectangle()
                .fill(Color.primary.opacity(0.13))
                .frame(width: 1, height: 14)
        }
        .frame(width: 54, height: height)
        // Center the label on the tick position
        .offset(x: tick.xOffset - 27)
    }

    // A minor tick: short separator line only
    private func minorTickView(tick: ServiceTimelineLayoutEngine.TimeTick) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(width: 1, height: 8)
        }
        .frame(width: 1, height: height)
        .offset(x: tick.xOffset)
    }
}
