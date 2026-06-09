//
//  SlotPressureStripView.swift
//  Tryzub Reservations
//
//  Read-only horizontal slot pressure strip for the Host board.
//

import SwiftUI

struct SlotPressureStripView: View {
  let pressures: [HostSlotPressure]

  var body: some View {
    if displayedPressures.isEmpty {
      EmptyView()
    } else {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(displayedPressures) { pressure in
            slotChip(pressure)
          }
        }
        .padding(.vertical, 2)
      }
    }
  }

  // MARK: - Chips

  private func slotChip(_ pressure: HostSlotPressure) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(displaySlotTime(pressure.slotTime))
        .font(.caption.weight(.semibold))
        .monospacedDigit()

      Text(severityLabel(pressure.severity))
        .font(.caption2)
        .foregroundStyle(severityColor(pressure.severity))

      if pressure.guestCount > 0 {
        Text("\(pressure.guestCount) guests")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      if pressure.largePartyCount > 0 {
        Text("\(pressure.largePartyCount) large")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      if pressure.noTableCount > 0 {
        Text("\(pressure.noTableCount) no table")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  // MARK: - Helpers

  private var displayedPressures: [HostSlotPressure] {
    Array(
      pressures
        .filter { $0.reservationCount > 0 || $0.severity != .calm }
        .sorted { lhs, rhs in
          if severityRank(lhs.severity) != severityRank(rhs.severity) {
            return severityRank(lhs.severity) < severityRank(rhs.severity)
          }
          return lhs.slotTime < rhs.slotTime
        }
        .prefix(8)
    )
  }

  private func displaySlotTime(_ value: String) -> String {
    if let date = ReservationFormatters.apiTime.date(from: value) {
      return ReservationFormatters.shortTime.string(from: date)
    }
    return String(value.prefix(5))
  }

  private func severityLabel(_ severity: HostPressureSeverity) -> String {
    severity.rawValue.capitalized
  }

  private func severityColor(_ severity: HostPressureSeverity) -> Color {
    switch severity {
    case .critical: return .red
    case .busy: return .orange
    case .watch: return .yellow
    case .calm: return .secondary
    }
  }

  private func severityRank(_ severity: HostPressureSeverity) -> Int {
    switch severity {
    case .critical: return 0
    case .busy: return 1
    case .watch: return 2
    case .calm: return 3
    }
  }
}
