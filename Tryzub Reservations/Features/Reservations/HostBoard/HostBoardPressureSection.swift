//
//  HostBoardPressureSection.swift
//  Tryzub Reservations
//

import SwiftUI

struct HostBoardPressureSection: View {
    let snapshot: HostBoardSnapshot
    let reservations: [ReservationRecord]
    @Binding var isExpanded: Bool
    let onOpenReservation: (ReservationRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 10 : 0) {
            Button {
                withAnimation(.snappy(duration: 0.32)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(TryzubColors.mutedText)
                        .frame(width: 24, height: 24)
                        .hostBoardGlassCapsule(strokeOpacity: 0.08)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Service pressure")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(TryzubColors.primaryText)
                            .lineLimit(1)

                        Text(pressureSummaryLine(for: snapshot.arrivalPressure))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(TryzubColors.mutedText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(TryzubColors.mutedText)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.snappy(duration: 0.32), value: isExpanded)
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pressureAccessibilityLabel(for: snapshot.arrivalPressure))
            .accessibilityHint(isExpanded ? "Collapse service pressure chart" : "Expand service pressure chart")

            if isExpanded {
                ArrivalPressureWaveChart(
                    summary: snapshot.arrivalPressure,
                    height: 112,
                    isToday: snapshot.selectedDate.reservationDateString() == Date.reservationDateString(),
                    now: snapshot.now,
                    onOpenReservation: { remoteID in
                        if let reservation = reservations.first(where: { $0.remoteID == remoteID }) {
                            onOpenReservation(reservation)
                        }
                    }
                )
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    )
                )
            }
        }
        .clipped()
        .padding(12)
        .hostBoardGlassPanel(cornerRadius: ReservationUIStyle.cardCorner, strokeOpacity: 0.12)
    }

    private func pressureSummaryLine(for arrivalPressure: ArrivalPressureSummary) -> String {
        guard arrivalPressure.hasArrivals else {
            return "No arrivals today"
        }

        var parts = [
            "Peak \(arrivalPressure.peakLegendText)",
            arrivalPressure.chartSubtitle
        ]
        if let next = arrivalPressure.nextLegendText {
            parts.append("Next \(next)")
        }
        return parts.joined(separator: " · ")
    }

    private func pressureAccessibilityLabel(for arrivalPressure: ArrivalPressureSummary) -> String {
        "Service pressure. \(pressureSummaryLine(for: arrivalPressure))"
    }
}
