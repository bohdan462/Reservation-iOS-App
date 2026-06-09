//
//  HostIntelligenceDiagnosticsView.swift
//  Tryzub Reservations
//
//  Read-only developer diagnostics for Host Intelligence output.
//

import SwiftUI

struct HostIntelligenceDiagnosticsView: View {
  let reservations: [ReservationRecord]
  let selectedDate: Date
  let availabilitySummary: ReservationAvailabilitySummary?
  let analyticsSummary: ReservationAnalyticsSummaryDTO?
  let restaurantSetup: RestaurantSetup?
  let localSeatedAtByReservationID: [Int: Date]
  let settings: HostIntelligenceSettings
  var tableConfigs: [RestaurantTableConfig] = []
  var allKnownReservations: [ReservationRecord] = []

  private var snapshot: HostDecisionSnapshot {
    let input = HostEngineInput(
      now: Date(),
      selectedDate: selectedDate,
      reservations: reservations,
      availabilitySummary: availabilitySummary,
      analyticsSummary: analyticsSummary,
      restaurantSetup: restaurantSetup,
      localSeatedAtByReservationID: localSeatedAtByReservationID,
      settings: settings,
      tableConfigs: tableConfigs,
      allKnownReservations: allKnownReservations
    )
    return HostIntelligenceEngine().evaluateHostDecisionSnapshot(input: input)
  }

  var body: some View {
    let decision = snapshot

    Group {
      hostIntelligenceSection(decision)
      topFactsSection(decision)
      suggestedActionsSection(decision)
      slotPressureSection(decision)
      tableInventorySection
      guestSignalsSection(decision)
      cancellationOverdueSection(decision)
      signalsSection(decision)
    }
  }

  // MARK: - Sections

  @ViewBuilder
  private func hostIntelligenceSection(_ decision: HostDecisionSnapshot) -> some View {
    Section("Host Intelligence") {
      Text(decision.templateBriefingText)
        .font(.subheadline)

      LabeledContent("State") {
        Text(decision.serviceState.rawValue.capitalized)
      }
      LabeledContent("Pressure score") {
        Text(String(format: "%.0f", decision.pressureScore))
      }
      LabeledContent("Generated at") {
        Text(decision.generatedAt.formatted(date: .omitted, time: .standard))
      }
    }
  }

  @ViewBuilder
  private func topFactsSection(_ decision: HostDecisionSnapshot) -> some View {
    Section("Top Facts") {
      if decision.briefingFacts.isEmpty {
        Text("No briefing facts.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(decision.briefingFacts.prefix(5)) { fact in
          VStack(alignment: .leading, spacing: 4) {
            Text("\(fact.severity.rawValue.capitalized) · \(fact.title)")
              .font(.subheadline.weight(.semibold))
            Text(fact.detail)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 2)
        }
      }
    }
  }

  @ViewBuilder
  private func suggestedActionsSection(_ decision: HostDecisionSnapshot) -> some View {
    Section("Suggested Actions") {
      if decision.suggestedActions.isEmpty {
        Text("No suggested actions.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(decision.suggestedActions.prefix(5)) { action in
          VStack(alignment: .leading, spacing: 4) {
            Text("\(action.severity.rawValue.capitalized) · \(action.title)")
              .font(.subheadline.weight(.semibold))
            Text(action.reason)
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(
              HostSuggestedActionRouter.routeDescription(
                for: action,
                dayReservations: reservations,
                knownReservations: allKnownReservations
              )
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
          }
          .padding(.vertical, 2)
        }
      }
    }
  }

  @ViewBuilder
  private func slotPressureSection(_ decision: HostDecisionSnapshot) -> some View {
    Section("Slot Pressure") {
      if decision.slotPressures.isEmpty {
        Text("No slot pressure data.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(topSlotPressures(decision.slotPressures)) { pressure in
          VStack(alignment: .leading, spacing: 4) {
            Text("\(pressure.slotTime) · \(pressure.severity.rawValue.capitalized)")
              .font(.subheadline.weight(.semibold))
            Text(slotPressureSummary(pressure))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 2)
        }
      }
    }
  }

  @ViewBuilder
  private var tableInventorySection: some View {
    Section("Table Inventory") {
      let summary = HostTableIntelligenceSupport.buildTableCapacitySummary(
        tableConfigs: tableConfigs
      )

      LabeledContent("Tables configured", value: tableConfigs.isEmpty ? "No" : "Yes")
      LabeledContent("Active tables", value: "\(summary.activeTableCount)")
      LabeledContent("Inactive tables", value: "\(summary.inactiveTableCount)")
      LabeledContent("Total active capacity", value: "\(summary.totalActiveCapacity)")
      LabeledContent("Largest single table", value: "\(summary.largestSingleTableCapacity)")
      LabeledContent("Largest combination", value: "\(summary.largestCombinationCapacity)")
      LabeledContent("Capacity source") {
        Text(summary.totalActiveCapacity > 0 ? "Table inventory" : "Settings fallback")
      }

      let fitRecommendations = HostTableIntelligenceSupport.recommendedTableFits(
        reservations: reservations,
        tableConfigs: tableConfigs,
        limit: 3
      )
      if !fitRecommendations.isEmpty {
        ForEach(fitRecommendations) { option in
          VStack(alignment: .leading, spacing: 4) {
            Text("\(option.guestName) · party \(option.partySize)")
              .font(.subheadline.weight(.semibold))
            Text(
              HostTableIntelligenceSupport.displayTableNames(option.tableNames)
                + " · seats \(option.totalCapacity)"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          .padding(.vertical, 2)
        }
      }
    }
  }

  @ViewBuilder
  private func guestSignalsSection(_ decision: HostDecisionSnapshot) -> some View {
    Section("Top Guest Signals") {
      if decision.guestSignals.isEmpty {
        Text("No guest signals.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(Array(decision.guestSignals.prefix(5))) { signal in
          VStack(alignment: .leading, spacing: 4) {
            Text("\(signal.severity.rawValue.capitalized) · \(signal.kind.rawValue)")
              .font(.subheadline.weight(.semibold))
            Text(signal.guestName)
              .font(.caption)
            Text(signal.message)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 2)
        }
      }
    }
  }

  @ViewBuilder
  private func cancellationOverdueSection(_ decision: HostDecisionSnapshot) -> some View {
    let cancellationFacts = decision.briefingFacts.filter {
      $0.category == .cancellation || $0.category == .opportunity || $0.category == .overdue
    }
    let cancellationActions = decision.suggestedActions.filter {
      $0.kind == .reviewCancellationOpportunity
        || $0.kind == .markNoShow
        || $0.kind == .completeReservation
        || ($0.kind == .reviewReservation && $0.id.hasPrefix("overdue-"))
        || ($0.kind == .assignTable && $0.id.hasPrefix("overdue-no-table-"))
    }

    Section("Cancellation / Overdue") {
      LabeledContent("Cancellation facts") {
        Text("\(decision.briefingFacts.filter { $0.category == .cancellation }.count)")
      }
      LabeledContent("Opportunity facts") {
        Text("\(decision.briefingFacts.filter { $0.category == .opportunity }.count)")
      }
      LabeledContent("Overdue facts") {
        Text("\(decision.briefingFacts.filter { $0.category == .overdue }.count)")
      }
      LabeledContent("Mark no-show actions") {
        Text("\(decision.suggestedActions.filter { $0.kind == .markNoShow }.count)")
      }
      LabeledContent("Cancellation opportunity actions") {
        Text("\(decision.suggestedActions.filter { $0.kind == .reviewCancellationOpportunity }.count)")
      }

      if cancellationFacts.isEmpty {
        Text("No cancellation or overdue facts.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(Array(cancellationFacts.prefix(5))) { fact in
          VStack(alignment: .leading, spacing: 4) {
            Text("\(fact.severity.rawValue.capitalized) · \(fact.category.rawValue) · \(fact.title)")
              .font(.subheadline.weight(.semibold))
            Text(fact.detail)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 2)
        }
      }

      if !cancellationActions.isEmpty {
        ForEach(Array(cancellationActions.prefix(5))) { action in
          VStack(alignment: .leading, spacing: 4) {
            Text("\(action.severity.rawValue.capitalized) · \(action.kind.rawValue) · \(action.title)")
              .font(.subheadline.weight(.semibold))
            Text(action.reason)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 2)
        }
      }
    }
  }

  @ViewBuilder
  private func signalsSection(_ decision: HostDecisionSnapshot) -> some View {
    Section("Signals") {
      LabeledContent("Guest signals") {
        Text("\(decision.guestSignals.count)")
      }
      LabeledContent("Regular guests") {
        Text("\(decision.guestSignals.filter { $0.kind == .regularGuest }.count)")
      }
      LabeledContent("Seating preferences") {
        Text("\(decision.guestSignals.filter { $0.kind == .seatingPreference }.count)")
      }
      LabeledContent("Accessibility") {
        Text("\(decision.guestSignals.filter { $0.kind == .accessibility }.count)")
      }
      LabeledContent("Special occasions") {
        Text("\(decision.guestSignals.filter { $0.kind == .specialOccasion }.count)")
      }
      LabeledContent("Cancellation risk") {
        Text("\(decision.guestSignals.filter { $0.kind == .cancellationRisk }.count)")
      }
      LabeledContent("No-show risk") {
        Text("\(decision.guestSignals.filter { $0.kind == .noShowRisk }.count)")
      }
      LabeledContent("Prior service issues") {
        Text("\(decision.guestSignals.filter { $0.kind == .previousServiceIssue }.count)")
      }
      LabeledContent("Possible duplicates") {
        Text("\(decision.guestSignals.filter { $0.kind == .possibleDuplicate }.count)")
      }
      LabeledContent("Allergy signals") {
        Text("\(decision.guestSignals.filter { $0.kind == .allergy }.count)")
      }
      LabeledContent("Table signals") {
        Text("\(decision.tableSignals.count)")
      }
      LabeledContent("No-table signals") {
        Text("\(decision.tableSignals.filter { $0.kind == .noTableAssigned }.count)")
      }
      LabeledContent("Table capacity mismatch") {
        Text("\(decision.tableSignals.filter { $0.kind == .tableCapacityMismatch }.count)")
      }
      LabeledContent("Table turn risk") {
        Text("\(decision.tableSignals.filter { $0.kind == .tableTurnRisk }.count)")
      }
      LabeledContent("Cancellation freed table") {
        Text("\(decision.tableSignals.filter { $0.kind == .cancellationFreedTable }.count)")
      }
      LabeledContent("Seated timing signals") {
        Text("\(decision.seatedTimingSignals.count)")
      }
    }
  }

  // MARK: - Helpers

  private func topSlotPressures(_ pressures: [HostSlotPressure]) -> [HostSlotPressure] {
    Array(
      pressures
        .sorted { lhs, rhs in
          if lhs.severity != rhs.severity {
            return severityRank(lhs.severity) < severityRank(rhs.severity)
          }
          return (lhs.capacityRatio ?? 0) > (rhs.capacityRatio ?? 0)
        }
        .prefix(5)
    )
  }

  private func severityRank(_ severity: HostPressureSeverity) -> Int {
    switch severity {
    case .critical: return 0
    case .busy: return 1
    case .watch: return 2
    case .calm: return 3
    }
  }

  private func slotPressureSummary(_ pressure: HostSlotPressure) -> String {
    var parts = [
      "reservations=\(pressure.reservationCount)",
      "guests=\(pressure.guestCount)",
      "largeParties=\(pressure.largePartyCount)",
      "noTable=\(pressure.noTableCount)"
    ]
    if let ratio = pressure.capacityRatio {
      parts.append(String(format: "capacityRatio=%.0f%%", ratio * 100))
    }
    if pressure.isBlocked {
      parts.append("blocked")
    }
    return parts.joined(separator: " · ")
  }
}

#Preview {
  List {
    HostIntelligenceDiagnosticsView(
      reservations: [],
      selectedDate: Date(),
      availabilitySummary: nil,
      analyticsSummary: nil,
      restaurantSetup: nil,
      localSeatedAtByReservationID: [:],
      settings: HostIntelligenceSettings()
    )
  }
}
