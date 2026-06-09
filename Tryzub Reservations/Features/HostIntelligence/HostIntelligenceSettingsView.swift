//
//  HostIntelligenceSettingsView.swift
//  Tryzub Reservations
//
//  Local Host Intelligence thresholds and table inventory entry point.
//

import SwiftUI

struct HostIntelligenceSettingsView: View {
  @ObservedObject var settingsStore: HostIntelligenceSettingsStore
  @ObservedObject var tableStore: HostTableConfigStore

  @State private var showResetSettingsConfirmation = false
  @State private var showResetTablesConfirmation = false

  var body: some View {
    Form {
      featureSection
      briefingWriterSection
      bookingDecisionsSection
      capacitySection
      timingSection
      partyThresholdsSection
      tableInventorySection
      resetSection
    }
    .navigationTitle("Host Intelligence")
    .navigationBarTitleDisplayMode(.inline)
  }

  // MARK: - Sections

  private var featureSection: some View {
    Section("Feature") {
      Toggle("Enable Host Intelligence", isOn: binding(\.isEnabled))
      Toggle("Include guest signals", isOn: binding(\.includeGuestSignals))
      Toggle("Prepare LLM packet", isOn: binding(\.includeLLMPacket))
      Toggle("Include analytics signals", isOn: binding(\.includeAnalyticsSignals))
      Text("Historical signals use backend aggregate analytics, not full local reservation history.")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("The host board uses cached analytics when loaded from Restaurant Settings. It does not fetch analytics during service.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var briefingWriterSection: some View {
    Section("Briefing Writer") {
      Toggle("Use enhanced briefing", isOn: binding(\.useEnhancedBriefing))

      Picker("Provider", selection: providerBinding) {
        ForEach(HostBriefingProviderKind.allCases, id: \.self) { provider in
          Text(provider.displayName).tag(provider)
        }
      }
      .disabled(!settingsStore.settings.useEnhancedBriefing)

      if settingsStore.settings.useEnhancedBriefing,
         settingsStore.settings.enhancedBriefingProvider == .localModel {
        localModelReadinessNotice
      }

      Text("The engine still makes all decisions. The writer only rewrites approved facts.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var localModelReadinessNotice: some View {
    let readiness = HostLocalModelReadinessProvider.currentReadiness()

    VStack(alignment: .leading, spacing: 6) {
      Text(readiness.title)
        .font(.subheadline.weight(.semibold))
      Text(readiness.detail)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("Local model is not installed in this build. The app will use template fallback.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
  }

  private var providerBinding: Binding<HostBriefingProviderKind> {
    Binding(
      get: { settingsStore.settings.enhancedBriefingProvider },
      set: { newValue in
        settingsStore.update { $0.enhancedBriefingProvider = newValue }
      }
    )
  }

  private var bookingDecisionsSection: some View {
    Section("Booking Decisions") {
      Toggle("Enable booking decisioning", isOn: binding(\.enableBookingDecisioning))
      Toggle("Suggest alternate times", isOn: binding(\.suggestAlternateTimesEnabled))
      Toggle("Show auto-confirm candidates", isOn: binding(\.autoConfirmRecommendationsEnabled))
      Toggle("Auto-confirm weekdays only", isOn: binding(\.autoConfirmWeekdaysOnly))
        .disabled(!settingsStore.settings.autoConfirmRecommendationsEnabled)

      Stepper(
        value: intBinding(\.maxPartySizeForAutoConfirm, minimum: 1, maximum: 20),
        in: 1...20
      ) {
        LabeledContent(
          "Max party size for auto-confirm",
          value: "\(settingsStore.settings.maxPartySizeForAutoConfirm)"
        )
      }
      .disabled(!settingsStore.settings.autoConfirmRecommendationsEnabled)

      Stepper(
        value: Binding(
          get: { Int((settingsStore.settings.minimumConfidenceForAutoConfirm * 100).rounded()) },
          set: { newValue in
            settingsStore.update {
              $0.minimumConfidenceForAutoConfirm = Double(min(max(newValue, 50), 100)) / 100.0
            }
          }
        ),
        in: 50...100
      ) {
        LabeledContent(
          "Minimum confidence",
          value: "\(Int((settingsStore.settings.minimumConfidenceForAutoConfirm * 100).rounded()))%"
        )
      }
      .disabled(!settingsStore.settings.autoConfirmRecommendationsEnabled)

      Text("Recommendations only. Staff must still confirm in reservation detail.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var capacitySection: some View {
    Section("Capacity") {
      Stepper(
        value: intBinding(\.restaurantCapacity, minimum: 1, maximum: 500),
        in: 1...500
      ) {
        LabeledContent("Restaurant capacity", value: "\(settingsStore.settings.restaurantCapacity)")
      }

      percentRow(
        title: "Comfortable capacity",
        value: settingsStore.settings.comfortableCapacityRatio
      ) { newValue in
        settingsStore.update { $0.comfortableCapacityRatio = newValue }
      }

      percentRow(
        title: "Critical capacity",
        value: settingsStore.settings.criticalCapacityRatio
      ) { newValue in
        settingsStore.update { $0.criticalCapacityRatio = newValue }
      }
    }
  }

  private var timingSection: some View {
    Section("Timing") {
      stepperRow("Slot interval (minutes)", keyPath: \.slotIntervalMinutes, range: 5...60)
      stepperRow("Lookahead (minutes)", keyPath: \.lookaheadMinutes, range: 30...480)
      stepperRow("Due soon (minutes)", keyPath: \.dueSoonMinutes, range: 5...120)
      stepperRow("No-table due soon (minutes)", keyPath: \.noTableDueSoonMinutes, range: 5...120)
      stepperRow("Long-seated warning (minutes)", keyPath: \.longSeatedWarningMinutes, range: 30...240)
    }
  }

  private var partyThresholdsSection: some View {
    Section("Party Thresholds") {
      stepperRow("Large party threshold", keyPath: \.largePartyThreshold, range: 2...20)
      stepperRow("Critical party threshold", keyPath: \.criticalPartyThreshold, range: 2...30)
      stepperRow("Max reservations per slot", keyPath: \.maxReservationsPerSlot, range: 1...20)
      stepperRow("Max large parties per slot", keyPath: \.maxLargePartiesPerSlot, range: 1...10)
    }
  }

  private var tableInventorySection: some View {
    Section("Table Inventory") {
      LabeledContent("Active tables", value: "\(tableStore.activeTables.count)")
      LabeledContent("Total active capacity", value: "\(tableStore.totalActiveCapacity)")
      LabeledContent("Inactive tables", value: "\(tableStore.tables.count - tableStore.activeTables.count)")

      NavigationLink {
        HostTableConfigView(tableStore: tableStore)
      } label: {
        Text("Manage Table Inventory")
      }
    }
  }

  private var resetSection: some View {
    Section("Reset") {
      Button("Reset Host Intelligence Settings", role: .destructive) {
        showResetSettingsConfirmation = true
      }
      .confirmationDialog(
        "Reset Host Intelligence settings?",
        isPresented: $showResetSettingsConfirmation,
        titleVisibility: .visible
      ) {
        Button("Reset Settings", role: .destructive) {
          settingsStore.resetToDefaults()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This restores all Host Intelligence thresholds to their defaults.")
      }

      Button("Reset Table Inventory", role: .destructive) {
        showResetTablesConfirmation = true
      }
      .confirmationDialog(
        "Reset table inventory?",
        isPresented: $showResetTablesConfirmation,
        titleVisibility: .visible
      ) {
        Button("Reset Tables", role: .destructive) {
          tableStore.reset()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This removes all configured tables from local inventory.")
      }
    }
  }

  // MARK: - Bindings

  private func binding(_ keyPath: WritableKeyPath<HostIntelligenceSettings, Bool>) -> Binding<Bool> {
    Binding(
      get: { settingsStore.settings[keyPath: keyPath] },
      set: { newValue in
        settingsStore.update { $0[keyPath: keyPath] = newValue }
      }
    )
  }

  private func intBinding(
    _ keyPath: WritableKeyPath<HostIntelligenceSettings, Int>,
    minimum: Int,
    maximum: Int
  ) -> Binding<Int> {
    Binding(
      get: { settingsStore.settings[keyPath: keyPath] },
      set: { newValue in
        settingsStore.update {
          $0[keyPath: keyPath] = min(max(newValue, minimum), maximum)
        }
      }
    )
  }

  private func stepperRow(
    _ title: String,
    keyPath: WritableKeyPath<HostIntelligenceSettings, Int>,
    range: ClosedRange<Int>
  ) -> some View {
    Stepper(value: intBinding(keyPath, minimum: range.lowerBound, maximum: range.upperBound), in: range) {
      LabeledContent(title, value: "\(settingsStore.settings[keyPath: keyPath])")
    }
  }

  private func percentRow(
    title: String,
    value: Double,
    onChange: @escaping (Double) -> Void
  ) -> some View {
    Stepper(
      value: Binding(
        get: { Int((value * 100).rounded()) },
        set: { onChange(Double(min(max($0, 50), 150)) / 100.0) }
      ),
      in: 50...150
    ) {
      LabeledContent(title, value: "\(Int((value * 100).rounded()))%")
    }
  }
}
