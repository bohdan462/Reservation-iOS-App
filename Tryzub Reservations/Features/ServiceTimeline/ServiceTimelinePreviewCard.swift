//
//  ServiceTimelinePreviewCard.swift
//  Tryzub Reservations
//
//  Compact timeline strip shown inside the Host view on iPad.
//  Shows a 3-hour window around the current time with compressed blocks
//  and a "Now" indicator. Tapping "Open Timeline" opens the full view.
//

import SwiftUI

struct ServiceTimelinePreviewCard: View {
    let reservations: [ReservationRecord]
    let selectedDate: Date
    let serviceOpen: Date?
    let serviceClose: Date?
    let onOpenTimeline: () -> Void

    // Preview shows a 3-hour window: 30 min before now to 2.5 hrs after.
    private let previewWindowMinutes: Double = 180
    private let previewPPM: CGFloat = 2.2   // points-per-minute for compact view
    private let cardHeight: CGFloat = 108

    @State private var clockNow = Date()

    private var window: ServiceTimelineWindow {
        if let open = serviceOpen, let close = serviceClose, close > open {
            return ServiceTimelineWindow(open: open, close: close)
        }
        return ServiceTimelineLayoutEngine.defaultServiceWindow(for: selectedDate)
    }

    /// Preview window: 30 min before now → 150 min after
    private var previewStart: Date {
        clockNow.addingTimeInterval(-30 * 60)
    }

    private var previewEnd: Date {
        clockNow.addingTimeInterval(150 * 60)
    }

    /// Blocks that fall within the preview window
    private var visibleBlocks: [ServiceTimelineBlock] {
        let previewWindow = ServiceTimelineWindow(open: previewStart, close: previewEnd)
        guard previewWindow.isValid else { return [] }

        let in_window = reservations.filter { r in
            guard let sd = r.serviceDateTime else { return false }
            // Include if reservation starts within or overlaps the preview window
            let endApprox = sd.addingTimeInterval(TimeInterval(
                ServiceTimelineLayoutEngine.estimatedDurationMinutes(partySize: r.partySize) * 60
            ))
            return endApprox > previewStart && sd < previewEnd
        }

        return ServiceTimelineLayoutEngine.computeBlocks(
            from: in_window,
            window: ServiceTimelineWindow(open: previewStart, close: previewEnd),
            pointsPerMinute: previewPPM
        )
    }

    private var previewTotalWidth: CGFloat {
        CGFloat(previewWindowMinutes) * previewPPM + ServiceTimelineLayoutEngine.timelineHorizontalPadding * 2
    }

    // "Now" sits at 30 min * previewPPM from the left edge
    private var nowX: CGFloat {
        30 * previewPPM + ServiceTimelineLayoutEngine.timelineHorizontalPadding
    }

    private var previewTicks: [ServiceTimelineLayoutEngine.TimeTick] {
        ServiceTimelineLayoutEngine.timeTicks(
            window: ServiceTimelineWindow(open: previewStart, close: previewEnd),
            majorIntervalMinutes: 60,
            minorIntervalMinutes: 30,
            pointsPerMinute: previewPPM
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header
            HStack {
                Label("Service Timeline", systemImage: "chart.bar.xaxis")
                    .font(TryzubTypography.sectionTitle)
                    .foregroundStyle(TryzubColors.primaryText)

                Spacer(minLength: 8)

                Button(action: onOpenTimeline) {
                    HStack(spacing: 4) {
                        Text("Open")
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TryzubColors.primaryControl)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Service Timeline")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Preview strip
            previewStrip

            Divider()
                .padding(.horizontal, 14)

            // Footer: summary
            previewFooter
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .background(TryzubColors.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TryzubColors.border, lineWidth: 1)
        }
        // Refresh clock every 60 sec
        .onReceive(
            Timer.publish(every: 60, on: .main, in: .common).autoconnect()
        ) { now in
            clockNow = now
        }
    }

    // MARK: - Preview strip

    private var previewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                // Canvas
                Color.clear
                    .frame(width: previewTotalWidth, height: cardHeight)

                // Time ticks (major only)
                ForEach(previewTicks.filter(\.isMajor)) { tick in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Text(tick.label)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                        Spacer(minLength: 4)
                        Rectangle()
                            .fill(Color.primary.opacity(0.10))
                            .frame(width: 1, height: cardHeight * 0.35)
                    }
                    .frame(width: 46, height: cardHeight)
                    .offset(x: tick.xOffset - 23)
                }

                // Compact blocks
                ForEach(visibleBlocks) { block in
                    compactBlock(block: block)
                }

                // Now line
                Rectangle()
                    .fill(Color.accentColor.opacity(0.60))
                    .frame(width: 1.5, height: cardHeight)
                    .offset(x: nowX - 0.75)
                    .allowsHitTesting(false)

                // "Now" pill
                Text("Now")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
                    .offset(x: nowX - 14, y: 4)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: cardHeight)
    }

    private func compactBlock(block: ServiceTimelineBlock) -> some View {
        let compactHeight: CGFloat = 26
        let laneY = 14 + CGFloat(block.laneIndex % 3) * (compactHeight + 4)

        return ServiceTimelineCompactBlock(block: block, height: compactHeight)
            .offset(x: block.xOffset, y: laneY)
    }

    // MARK: - Footer

    private var previewFooter: some View {
        let active = reservations.filter { $0.isExpectedGuest }
        let seated = reservations.filter { $0.statusValue == .seated }
        let noTable = reservations.filter { $0.isExpectedGuest && !$0.hasTableAssignment }

        return HStack(spacing: 12) {
            footerStat(value: "\(active.count)", label: "Total", color: .secondary)
            footerStat(value: "\(seated.count)", label: "Seated", color: Color.accentColor)
            if noTable.count > 0 {
                footerStat(value: "\(noTable.count)", label: "No Table", color: TryzubColors.warning)
            }
            Spacer(minLength: 0)
        }
    }

    private func footerStat(value: String, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
