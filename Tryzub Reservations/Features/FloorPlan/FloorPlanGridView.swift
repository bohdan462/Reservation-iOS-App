//
//  FloorPlanGridView.swift
//  Tryzub Reservations
//

import SwiftUI

struct FloorPlanGridView: View {
    let viewState: FloorPlanViewState
    let unitSize: CGFloat
    var topContentInset: CGFloat = 0
    var trailingContentInset: CGFloat = 0
    let onTableTap: (FloorPlanTableBlock) -> Void

    private var gridLineColor: Color {
        Color.primary.opacity(0.06)
    }

    var body: some View {
        let width = CGFloat(viewState.gridWidth) * unitSize
        let height = CGFloat(viewState.gridHeight) * unitSize

        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            ZStack(alignment: .topLeading) {
                gridBackground(width: width, height: height)

                ForEach(viewState.tableBlocks) { block in
                    tableBlockView(block)
                        .frame(
                            width: CGFloat(block.table.widthUnits) * unitSize - 4,
                            height: CGFloat(block.table.heightUnits) * unitSize - 4
                        )
                        .offset(
                            x: CGFloat(block.table.x) * unitSize + 2,
                            y: CGFloat(block.table.y) * unitSize + 2
                        )
                }
            }
            .frame(width: width, height: height)
            .padding(.top, 12 + topContentInset)
            .padding(.leading, 12)
            .padding(.trailing, 12 + trailingContentInset)
            .padding(.bottom, 12)
        }
        .background(TryzubColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TryzubColors.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func gridBackground(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            let columns = viewState.gridWidth
            let rows = viewState.gridHeight
            var path = Path()

            for column in 0...columns {
                let x = CGFloat(column) * unitSize
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }

            for row in 0...rows {
                let y = CGFloat(row) * unitSize
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }

            context.stroke(path, with: .color(gridLineColor), lineWidth: 1)
        }
        .frame(width: width, height: height)
    }

    private func tableBlockView(_ block: FloorPlanTableBlock) -> some View {
        let isCompact = block.table.widthUnits == 1 && block.table.heightUnits == 1

        return Button {
            onTableTap(block)
        } label: {
            Group {
                if isCompact {
                    compactTableContent(block)
                } else {
                    standardTableContent(block)
                }
            }
            .padding(isCompact ? 6 : 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(backgroundColor(for: block.state))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor(for: block.state), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: block))
    }

    @ViewBuilder
    private func compactTableContent(_ block: FloorPlanTableBlock) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(block.table.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                Text(FloorPlanPresentation.compactTableStatusLabel(for: block))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            if let hint = FloorPlanPresentation.assignmentCountHint(for: block.assignedCount),
               block.table.widthUnits > 1 || block.table.heightUnits > 1 {
                Text(hint)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(TryzubColors.info)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func standardTableContent(_ block: FloorPlanTableBlock) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(block.table.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let reservation = block.reservation,
               block.state != .completedHistorical {
                Text(reservation.guestName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(FloorPlanPresentation.displayTime(reservation.reservationTime))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let hint = FloorPlanPresentation.assignmentCountHint(for: block.assignedCount) {
                    Text(hint)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(TryzubColors.info)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            } else {
                Text(FloorPlanPresentation.tableStatusLabel(for: block))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    private func backgroundColor(for state: FloorPlanTableState) -> Color {
        switch state {
        case .empty:
            return TryzubColors.secondaryCardBackground
        case .assignedUpcoming:
            return TryzubColors.info.opacity(0.12)
        case .seated:
            return TryzubColors.warning.opacity(0.16)
        case .completedHistorical:
            return Color.secondary.opacity(0.08)
        case .conflict:
            return TryzubColors.attentionBackground
        case .inactive:
            return Color.secondary.opacity(0.06)
        }
    }

    private func borderColor(for state: FloorPlanTableState) -> Color {
        switch state {
        case .empty:
            return TryzubColors.border
        case .assignedUpcoming:
            return TryzubColors.info.opacity(0.45)
        case .seated:
            return TryzubColors.warning.opacity(0.55)
        case .completedHistorical:
            return Color.secondary.opacity(0.25)
        case .conflict:
            return TryzubColors.attentionBorder
        case .inactive:
            return Color.secondary.opacity(0.2)
        }
    }

    private func accessibilityLabel(for block: FloorPlanTableBlock) -> String {
        var label = FloorPlanPresentation.tableDetailLine(table: block.table, reservation: block.reservation)
        if let hint = FloorPlanPresentation.assignmentCountAccessibilityHint(for: block.assignedCount) {
            label += "\n\(hint)"
        }
        return label
    }
}
