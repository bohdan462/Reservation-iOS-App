//
//  HostIntelligenceCard.swift
//  Tryzub Reservations
//
//  Read-only Host Intelligence briefing card for the Host board.
//

import SwiftUI

struct HostIntelligenceCard: View {
  let snapshot: HostDecisionSnapshot

  var body: some View {
    if isCalmPresentation {
      calmCard
    } else {
      activeCard
    }
  }

  // MARK: - Layout

  private var calmCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Host Intelligence")
        .font(.headline)

      Text("Service looks stable right now.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .cardStyle()
  }

  private var activeCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("Host Intelligence")
          .font(.headline)

        Spacer(minLength: 8)

        Text(stateTitle)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        Text("\(Int(snapshot.pressureScore.rounded()))")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      Text(stateLine)
        .font(.caption)
        .foregroundStyle(.secondary)

      Text(snapshot.templateBriefingText)
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)

      if !topActions.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(topActions) { action in
            actionRow(action)
          }
        }
      }

      if signalCount > 0 {
        Text("Based on \(signalCount) live signal\(signalCount == 1 ? "" : "s")")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .cardStyle()
  }

  private func actionRow(_ action: HostSuggestedAction) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Text(action.severity.rawValue.capitalized)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 54, alignment: .leading)

      VStack(alignment: .leading, spacing: 2) {
        Text(action.title)
          .font(.caption.weight(.semibold))
          .lineLimit(2)
        Text(action.reason)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  // MARK: - Helpers

  private var isCalmPresentation: Bool {
    snapshot.briefingFacts.isEmpty
      && snapshot.suggestedActions.isEmpty
      && snapshot.slotPressures.allSatisfy { $0.severity == .calm && $0.reservationCount == 0 }
  }

  private var stateTitle: String {
    switch snapshot.serviceState {
    case .calm: return "Calm"
    case .building: return "Building"
    case .busy: return "Busy"
    case .critical: return "Critical"
    }
  }

  private var stateLine: String {
    "Service state · pressure \(Int(snapshot.pressureScore.rounded()))/100"
  }

  private var topActions: [HostSuggestedAction] {
    Array(snapshot.suggestedActions.prefix(3))
  }

  private var signalCount: Int {
    snapshot.briefingFacts.count
      + snapshot.guestSignals.count
      + snapshot.tableSignals.count
      + snapshot.seatedTimingSignals.count
  }
}

// MARK: - Card Style

private extension View {
  func cardStyle() -> some View {
    padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}
