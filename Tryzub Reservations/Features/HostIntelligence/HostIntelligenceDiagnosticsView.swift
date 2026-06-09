//
//  HostIntelligenceDiagnosticsView.swift
//  Tryzub Reservations
//
//  Read-only developer diagnostics for Host Intelligence output.
//

import SwiftUI
import UniformTypeIdentifiers

struct HostIntelligenceDiagnosticsView: View {
  let reservations: [ReservationRecord]
  let selectedDate: Date
  let availabilitySummary: ReservationAvailabilitySummary?
  let analyticsSummary: ReservationAnalyticsSummaryDTO?
  var analyticsLoadedAt: Date? = nil
  let restaurantSetup: RestaurantSetup?
  let localSeatedAtByReservationID: [Int: Date]
  let settings: HostIntelligenceSettings
  var briefingSource: HostBriefingWriterSource? = nil
  var briefingFailureReason: String? = nil
  var tableConfigs: [RestaurantTableConfig] = []
  var allKnownReservations: [ReservationRecord] = []

  @State private var isShowingModelImporter = false
  @State private var modelImportMessage: String?
  @State private var modelImportError: String?
  @State private var readinessRefreshToken = UUID()
  @ObservedObject private var modelCoordinator = HostLocalModelDiagnosticsCoordinator.shared

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
      bookingDecisionsSection(decision)
      analyticsIntelligenceSection(decision)
      briefingWriterSection(decision)
      signalsSection(decision)
    }
  }

  private var analyticsIntelligence: HostAnalyticsIntelligenceResult {
    HostAnalyticsIntelligenceSupport.analyze(
      slotPressures: snapshot.slotPressures,
      analyticsSummary: analyticsSummary,
      selectedDate: selectedDate,
      now: Date(),
      settings: settings
    )
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
  private func bookingDecisionsSection(_ decision: HostDecisionSnapshot) -> some View {
    Section("Booking Decisions") {
      LabeledContent("Total decisions") {
        Text("\(decision.bookingDecisions.count)")
      }
      LabeledContent("Auto-confirm candidates") {
        Text("\(decision.bookingDecisions.filter { $0.decision == .autoConfirm }.count)")
      }
      LabeledContent("Suggest alternate") {
        Text("\(decision.bookingDecisions.filter { $0.decision == .suggestAlternateTime }.count)")
      }
      LabeledContent("Manual review") {
        Text("\(decision.bookingDecisions.filter { $0.decision == .manualReview }.count)")
      }
      LabeledContent("Reject / no safe option") {
        Text("\(decision.bookingDecisions.filter { $0.decision == .reject }.count)")
      }

      if decision.bookingDecisions.isEmpty {
        Text("No booking decisions.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(Array(decision.bookingDecisions.prefix(5))) { result in
          VStack(alignment: .leading, spacing: 4) {
            Text("\(result.decision.rawValue) · \(result.reason)")
              .font(.subheadline.weight(.semibold))
            if let requested = result.requestedTime {
              Text("Requested \(requested)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let suggested = result.suggestedTime {
              Text("Suggested \(suggested)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if !result.evidence.isEmpty {
              Text(result.evidence.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
          }
          .padding(.vertical, 2)
        }
      }
    }
  }

  @ViewBuilder
  private func analyticsIntelligenceSection(_ decision: HostDecisionSnapshot) -> some View {
    let metrics = analyticsIntelligence.metrics
    let analyticsFacts = decision.briefingFacts.filter { $0.category == .analytics }

    Section("Analytics Intelligence") {
      LabeledContent("Enabled in settings") {
        Text(settings.includeAnalyticsSignals ? "Yes" : "No")
      }
      LabeledContent("Cached summary present") {
        Text(analyticsSummary == nil ? "No" : "Yes")
      }
      LabeledContent("Used by engine") {
        Text(settings.includeAnalyticsSignals && metrics.hasAnalytics ? "Yes" : "No")
      }
      LabeledContent("Source") {
        Text("Backend aggregate analytics")
      }
      if let analyticsLoadedAt {
        LabeledContent("Loaded at") {
          Text(analyticsLoadedAt.formatted(date: .omitted, time: .standard))
        }
      }
      Text("Not full local reservation history.")
        .font(.caption)
        .foregroundStyle(.secondary)
      LabeledContent("Has analytics") {
        Text(metrics.hasAnalytics ? "Yes" : "No")
      }
      LabeledContent("Confidence") {
        Text(String(format: "%.0f%%", metrics.confidence * 100))
      }
      LabeledContent("Unusually busy slots") {
        Text("\(metrics.unusuallyBusySlotCount)")
      }
      LabeledContent("Unusually light slots") {
        Text("\(metrics.unusuallyLightSlotCount)")
      }
      LabeledContent("Weekday pressure signals") {
        Text("\(metrics.weekdayPressureSignalCount)")
      }

      if !metrics.hasAnalytics {
        Text("Analytics unavailable.")
          .foregroundStyle(.secondary)
        Text("Historical analytics unavailable; using live reservations only.")
          .font(.caption)
          .foregroundStyle(.tertiary)
      } else if analyticsFacts.isEmpty {
        Text("No analytics facts for the current live pattern.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(Array(analyticsFacts.prefix(5))) { fact in
          VStack(alignment: .leading, spacing: 4) {
            Text("\(fact.severity.rawValue.capitalized) · \(fact.title)")
              .font(.subheadline.weight(.semibold))
            Text(fact.detail)
              .font(.caption)
              .foregroundStyle(.secondary)
            if !fact.evidence.isEmpty {
              Text(fact.evidence.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
          }
          .padding(.vertical, 2)
        }
      }
    }
  }

  @ViewBuilder
  private func briefingWriterSection(_ decision: HostDecisionSnapshot) -> some View {
    let packet = decision.llmPacket
    let fallback = decision.templateBriefingText
    let placeholderPreview = LocalPlaceholderHostBriefingWriter.buildPlaceholderText(
      packet: packet,
      fallbackText: fallback
    )
    let templateValidation = HostBriefingWriterValidator.validationResult(
      fallback,
      packet: packet,
      fallbackText: fallback
    )
    let placeholderValidation = HostBriefingWriterValidator.validationResult(
      placeholderPreview,
      packet: packet,
      fallbackText: fallback
    )
    let _ = readinessRefreshToken
    let localModelReadiness = HostLocalModelReadinessProvider.currentReadiness()
    let promptPreview = HostLLMPacketPromptBuilder.buildDebugPromptPreview(from: packet)
    let modelPresence = HostLocalModelFileLocator.modelPresenceDescription()
    let modelSource = HostLocalModelFileLocator.modelSourceLabel()
    let localModelMissingPreview = LocalModelHostBriefingWriter.previewFallbackResult(
      fallbackText: fallback,
      packet: packet
    )
    let modelLookup = HostLocalModelFileLocator.modelLookupPathDescription()
    let localModelExpectedBehavior: String = {
      switch localModelReadiness.status {
      case .ready:
        return "Will attempt local inference"
      case .modelMissing, .runtimeMissing, .unavailable:
        return "Will use template fallback"
      }
    }()

    Section("Briefing Writer") {
      LabeledContent("Enhanced briefing") {
        Text(settings.useEnhancedBriefing ? "Yes" : "No")
      }
      LabeledContent("Provider") {
        Text(settings.enhancedBriefingProvider.displayName)
      }
      if settings.enhancedBriefingProvider == .localModel {
        LabeledContent("Host board local model gate") {
          Text(settings.useLocalModelOnHostBoard ? "Enabled" : "Disabled")
        }
      }
      if let briefingSource {
        LabeledContent("Current source") {
          Text(briefingSource.displayName)
        }
      }
      if let briefingFailureReason, !briefingFailureReason.isEmpty {
        LabeledContent("Failure reason") {
          Text(briefingFailureReason)
        }
      }

      LocalModelDiagnosticsControls(
        coordinator: modelCoordinator,
        readiness: localModelReadiness,
        settings: settings,
        packet: packet,
        fallbackText: fallback,
        onModelPrepared: {
          readinessRefreshToken = UUID()
        }
      )

      Text("Local model readiness")
        .font(.subheadline.weight(.semibold))
      LabeledContent("Current readiness") {
        Text(localModelReadiness.status.rawValue)
      }
      LabeledContent("Adapter shell present") {
        Text(HostLocalModelRuntimeFactory.isAdapterShellPresent ? "Yes" : "No")
      }
      LabeledContent("Inference runtime linked") {
        Text(HostLocalModelRuntimeFactory.isRuntimeIntegrated ? "Yes" : "No")
      }
      LabeledContent("Title") {
        Text(localModelReadiness.title)
      }
      Text(localModelReadiness.detail)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("Model lookup path: \(modelLookup)")
        .font(.caption)
        .foregroundStyle(.secondary)
      if let runtimeName = localModelReadiness.runtimeName {
        LabeledContent("Runtime") {
          Text(runtimeName)
        }
      } else {
        LabeledContent("Runtime") {
          Text("Not linked")
        }
      }
      if let modelName = localModelReadiness.modelName {
        LabeledContent("Model") {
          Text(modelName)
        }
      } else {
        LabeledContent("Model") {
          Text("Not installed")
        }
      }
      LabeledContent("Model presence") {
        Text(modelSource)
      }
      Text(modelPresence)
        .font(.caption)
        .foregroundStyle(.secondary)
      if settings.enhancedBriefingProvider == .localModel {
        Text(localModelExpectedBehavior)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

      LocalModelGGUFImportControls(
        isShowingModelImporter: $isShowingModelImporter,
        modelImportMessage: $modelImportMessage,
        modelImportError: $modelImportError,
        onImportSuccess: {
          readinessRefreshToken = UUID()
        }
      )

      Text("Local model prompt preview")
        .font(.subheadline.weight(.semibold))
      Text(promptPreview)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)

      Text("Template briefing")
        .font(.subheadline.weight(.semibold))
      Text(fallback)
        .font(.caption)
        .foregroundStyle(.secondary)

      Text("LLM packet")
        .font(.subheadline.weight(.semibold))
      LabeledContent("Generated at") {
        Text(packet.generatedAtDescription.isEmpty ? "—" : packet.generatedAtDescription)
      }
      LabeledContent("Service state") {
        Text(packet.serviceState.rawValue.capitalized)
      }
      LabeledContent("Pressure score") {
        Text(String(format: "%.0f", packet.pressureScore))
      }
      LabeledContent("Top facts") {
        Text("\(packet.topFacts.count)")
      }
      LabeledContent("Forbidden behaviors") {
        Text("\(packet.forbiddenBehaviors.count)")
      }
      LabeledContent("Writing rules") {
        Text("\(packet.writingRules.count)")
      }

      if packet.topFacts.isEmpty {
        Text("No packet facts.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ForEach(Array(packet.topFacts.prefix(5).enumerated()), id: \.offset) { _, fact in
          VStack(alignment: .leading, spacing: 4) {
            Text("\(fact.severity.rawValue.capitalized) · \(fact.category.rawValue) · \(fact.title)")
              .font(.caption.weight(.semibold))
            Text(fact.detail)
              .font(.caption2)
              .foregroundStyle(.secondary)
            if let action = fact.suggestedAction?.trimmingCharacters(in: .whitespacesAndNewlines),
               !action.isEmpty {
              Text("Action: \(action)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
          }
          .padding(.vertical, 2)
        }
      }

      Text("Packet debug summary")
        .font(.subheadline.weight(.semibold))
      Text(HostLLMPacketDebugFormatter.debugSummary(from: packet))
        .font(.caption2)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)

      Text("Validator")
        .font(.subheadline.weight(.semibold))
      LabeledContent("Template briefing") {
        Text(templateValidation.isValid ? "Valid" : "Invalid")
      }
      if let reason = templateValidation.reason {
        Text(reason)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

      Text("Local placeholder preview")
        .font(.subheadline.weight(.semibold))
      Text(placeholderPreview)
        .font(.caption)
        .foregroundStyle(.secondary)
      LabeledContent("Placeholder validation") {
        Text(placeholderValidation.isValid ? "Valid" : "Invalid")
      }
      if let reason = placeholderValidation.reason {
        Text(reason)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

      Text("Local model fallback preview")
        .font(.subheadline.weight(.semibold))
      Text(localModelMissingPreview.text)
        .font(.caption)
        .foregroundStyle(.secondary)
      LabeledContent("Preview source") {
        Text(localModelMissingPreview.source.displayName)
      }
      if let reason = localModelMissingPreview.failedReason {
        Text(reason)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

      LocalModelSamplePacketTests(
        settings: settings,
        readiness: localModelReadiness,
        currentPacket: packet,
        currentFallback: fallback
      )

      OperationalPromptPreviewSection(decision: decision)

      Text("Writer output is presentation only. The deterministic engine remains authoritative.")
        .font(.caption2)
        .foregroundStyle(.tertiary)
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

// MARK: - Local Model Diagnostics Controls (developer diagnostics only)

private struct LocalModelDiagnosticsControls: View {
  @ObservedObject var coordinator: HostLocalModelDiagnosticsCoordinator
  let readiness: HostLocalModelReadiness
  let settings: HostIntelligenceSettings
  let packet: HostLLMPacket
  let fallbackText: String
  let onModelPrepared: () -> Void

  @State private var isPreparing = false
  @State private var isRunningTest = false
  @State private var testResult: LocalModelBriefingDiagnosticResult?

  private var canRunTest: Bool {
    settings.enhancedBriefingProvider == .localModel
      && readiness.status == .ready
      && coordinator.isInferenceModelInstalled
      && !isRunningTest
      && !coordinator.loadingState.isBusy
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Local model")
        .font(.subheadline.weight(.semibold))

      Text("Local model is included with this build but is optional. Prepare it here only for developer testing.")
        .font(.caption2)
        .foregroundStyle(.tertiary)

      Text("Host board uses deterministic assistance by default. Normal staff do not need to prepare the model.")
        .font(.caption2)
        .foregroundStyle(.tertiary)

      LabeledContent("Model status") {
        Text(coordinator.modelStatusTitle)
      }
      LabeledContent("Model path source") {
        Text(coordinator.modelPathSourceLabel)
      }
      Text(coordinator.modelStatusDetail)
        .font(.caption)
        .foregroundStyle(.secondary)

      if coordinator.canPrepareBundledModel {
        Button("Prepare local model") {
          prepareModel()
        }
        .disabled(isPreparing || coordinator.loadingState.isBusy)
      } else if coordinator.isInferenceModelInstalled {
        Text("Prepared model is installed in Application Support.")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

      Button("Test local model briefing") {
        runTest()
      }
      .disabled(!canRunTest)

      if settings.enhancedBriefingProvider != .localModel {
        Text("Select Local model provider to enable manual tests.")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      } else if !coordinator.isInferenceModelInstalled {
        Text("Prepare or import the GGUF into Application Support before testing.")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

      localModelProgressView

      if let lastFailure = coordinator.lastFailureMessage, !lastFailure.isEmpty {
        Text(lastFailure)
          .font(.caption)
          .foregroundStyle(.red)
      }

      if let testResult {
        LocalModelBriefingDiagnosticResultView(result: testResult)
      }
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private var localModelProgressView: some View {
    if coordinator.loadingState != .idle,
       let message = coordinator.loadingState.statusMessage {
      if let fraction = coordinator.loadingState.copyProgressFraction {
        VStack(alignment: .leading, spacing: 6) {
          ProgressView(value: fraction)
          Text("\(message) \(Int((fraction * 100).rounded()))%")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else if case .failed = coordinator.loadingState {
        EmptyView()
      } else {
        ProgressView(message)
          .font(.caption)
      }
    }
  }

  private func prepareModel() {
    guard !isPreparing else { return }
    isPreparing = true
    coordinator.resetFailure()

    Task {
      let succeeded = await coordinator.prepareLocalModel()
      await MainActor.run {
        isPreparing = false
        if succeeded {
          onModelPrepared()
        }
      }
    }
  }

  private func runTest() {
    guard canRunTest else { return }
    isRunningTest = true
    testResult = nil
    coordinator.resetFailure()

    Task {
      await MainActor.run {
        coordinator.beginManualInference()
      }

      let diagnosticResult = await LocalModelBriefingDiagnosticRunner.run(
        packet: packet,
        fallbackText: fallbackText,
        testLabel: "Current service packet",
        settings: settings
      )

      await MainActor.run {
        testResult = diagnosticResult
        isRunningTest = false
        let succeeded = diagnosticResult.writerResult.source == .localModel
          && diagnosticResult.validation.isValid
        coordinator.completeManualInference(
          succeeded: succeeded,
          failureMessage: diagnosticResult.writerResult.failedReason
            ?? diagnosticResult.validation.reason
        )
      }
    }
  }
}

// MARK: - Local Model GGUF Import (developer diagnostics only)

private extension UTType {
  static let hostBriefingGGUF = UTType(filenameExtension: "gguf") ?? .data
}

private struct LocalModelGGUFImportControls: View {
  @Binding var isShowingModelImporter: Bool
  @Binding var modelImportMessage: String?
  @Binding var modelImportError: String?
  let onImportSuccess: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Local model import")
        .font(.subheadline.weight(.semibold))

      Text("Developer only. Copies a .gguf from Files into Application Support. No network.")
        .font(.caption2)
        .foregroundStyle(.tertiary)

      Button("Import GGUF from Files") {
        modelImportMessage = nil
        modelImportError = nil
        isShowingModelImporter = true
      }

      if let modelImportMessage, !modelImportMessage.isEmpty {
        Text(modelImportMessage)
          .font(.caption)
          .foregroundStyle(.green)
          .textSelection(.enabled)
      }

      if let modelImportError, !modelImportError.isEmpty {
        Text(modelImportError)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
    .padding(.vertical, 4)
    .fileImporter(
      isPresented: $isShowingModelImporter,
      allowedContentTypes: [.hostBriefingGGUF],
      allowsMultipleSelection: false
    ) { result in
      handleImport(result)
    }
  }

  private func handleImport(_ result: Result<[URL], Error>) {
    switch result {
    case .failure(let error):
      modelImportError = error.localizedDescription
      modelImportMessage = nil
    case .success(let urls):
      guard let sourceURL = urls.first else {
        modelImportError = "No file was selected."
        modelImportMessage = nil
        return
      }
      importModel(from: sourceURL)
    }
  }

  private func importModel(from sourceURL: URL) {
    let didAccess = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    do {
      let destination = try HostLocalModelInstaller.installModel(from: sourceURL)
      modelImportMessage = "Model installed at \(destination.path)"
      modelImportError = nil
      onImportSuccess()
    } catch {
      modelImportError = error.localizedDescription
      modelImportMessage = nil
    }
  }
}

// MARK: - Local Model Manual Test (developer diagnostics only)

private enum LocalModelBriefingDiagnosticRunner {
  static func run(
    packet: HostLLMPacket,
    fallbackText: String,
    testLabel: String,
    settings: HostIntelligenceSettings
  ) async -> LocalModelBriefingDiagnosticResult {
    let prompt = HostLLMPacketPromptBuilder.buildPrompt(from: packet)
    let readinessStatus = HostLocalModelReadinessProvider.currentReadiness().status
    let writer = LocalModelHostBriefingWriter()
    let clock = ContinuousClock()

    let coldMark = clock.now
    let coldWriterResult = await writer.writeBriefing(
      packet: packet,
      fallbackText: fallbackText
    )
    let coldDuration = LocalModelDiagnosticDuration.seconds(since: coldMark, on: clock)

    let warmMark = clock.now
    let writerResult = await writer.writeBriefing(
      packet: packet,
      fallbackText: fallbackText
    )
    let warmDuration = LocalModelDiagnosticDuration.seconds(since: warmMark, on: clock)

    let validation = HostBriefingWriterValidator.validationResult(
      writerResult.text,
      packet: packet,
      fallbackText: fallbackText
    )
    let runtimeDiagnostics = HostLlamaBriefingRuntimeDiagnostics.lastRun
    let fallbackOccurred = coldWriterResult.source == .failedFallback
      || writerResult.source == .failedFallback
    let writerDiagnostics = HostBriefingWriterDiagnostics.self

    return LocalModelBriefingDiagnosticResult(
      testLabel: testLabel,
      coldWriterResult: coldWriterResult,
      writerResult: writerResult,
      validation: validation,
      coldDuration: coldDuration,
      warmDuration: warmDuration,
      promptCharacterCount: prompt.count,
      outputCharacterCount: writerResult.text.count,
      readinessStatus: readinessStatus,
      fallbackText: fallbackText,
      fallbackOccurred: fallbackOccurred,
      runtimeDiagnostics: runtimeDiagnostics,
      inferenceSkippedBecauseNoFacts: writerDiagnostics.inferenceSkippedBecauseNoFacts,
      inferenceSkippedBecauseLowRiskSingleFact: writerDiagnostics.inferenceSkippedBecauseLowRiskSingleFact,
      hostBoardLocalModelGateEnabled: settings.useLocalModelOnHostBoard,
      generatedCandidate: writerDiagnostics.lastGeneratedCandidate,
      repairedOutput: writerDiagnostics.lastRepairedOutput,
      candidateValidationFailureReason: writerDiagnostics.lastValidationFailureReason,
      semanticValidationFailureReason: writerDiagnostics.lastSemanticValidationFailureReason
    )
  }
}

private struct LocalModelBriefingDiagnosticTest: View {
  let packet: HostLLMPacket
  let fallbackText: String
  let settings: HostIntelligenceSettings
  let readiness: HostLocalModelReadiness
  let testLabel: String

  @State private var isRunning = false
  @State private var result: LocalModelBriefingDiagnosticResult?

  private var canRunTest: Bool {
    settings.enhancedBriefingProvider == .localModel
      && readiness.status == .ready
      && !isRunning
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Local model manual test")
        .font(.subheadline.weight(.semibold))

      Text("Device testing only. Runs on tap — does not call network or mutate reservations.")
        .font(.caption2)
        .foregroundStyle(.tertiary)

      Button("Test local model briefing") {
        runTest()
      }
      .disabled(!canRunTest)

      if !canRunTest, settings.enhancedBriefingProvider != .localModel {
        Text("Select Local model provider to enable this test.")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      } else if !canRunTest, readiness.status != .ready {
        Text("Prepare or import the GGUF into Application Support to enable this test.")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

      if isRunning {
        ProgressView("Running local inference…")
          .font(.caption)
      }

      if let result {
        LocalModelBriefingDiagnosticResultView(result: result)
      }
    }
    .padding(.vertical, 4)
  }

  private func runTest() {
    guard canRunTest else { return }
    isRunning = true
    result = nil

    Task {
      let diagnosticResult = await LocalModelBriefingDiagnosticRunner.run(
        packet: packet,
        fallbackText: fallbackText,
        testLabel: testLabel,
        settings: settings
      )
      await MainActor.run {
        result = diagnosticResult
        isRunning = false
      }
    }
  }
}

private struct LocalModelSamplePacketTests: View {
  let settings: HostIntelligenceSettings
  let readiness: HostLocalModelReadiness
  let currentPacket: HostLLMPacket
  let currentFallback: String

  @State private var isRunning = false
  @State private var runningSampleName: String?
  @State private var result: LocalModelBriefingDiagnosticResult?
  @State private var evaluationRuns: [HostLocalModelEvaluationRun] = []
  @State private var evaluationProgress: String?

  private var canRunTests: Bool {
    settings.enhancedBriefingProvider == .localModel
      && readiness.status == .ready
      && !isRunning
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Sample Packet Tests")
        .font(.subheadline.weight(.semibold))

      Text("Synthetic HostLLMPacket fixtures for local model quality testing. Diagnostics only.")
        .font(.caption2)
        .foregroundStyle(.tertiary)

      ForEach(HostLLMPacketSampleFactory.Sample.allCases, id: \.self) { sample in
        Button(sample.buttonTitle) {
          runSample(sample)
        }
        .disabled(!canRunTests)
      }

      if !canRunTests, settings.enhancedBriefingProvider != .localModel {
        Text("Select Local model provider to enable sample tests.")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      } else if !canRunTests, readiness.status != .ready {
        Text("Prepare or import the GGUF into Application Support to enable sample tests.")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

      if isRunning, let runningSampleName {
        ProgressView("Running sample \(runningSampleName)…")
          .font(.caption)
      }

      if let result {
        LocalModelBriefingDiagnosticResultView(result: result)
      }

      Text("Local Model Evaluation")
        .font(.subheadline.weight(.semibold))
        .padding(.top, 8)

      Text("Do not enable local model on Host board by default until repeated Busy/Critical tests pass validation consistently and do not produce completed-action claims.")
        .font(.caption2)
        .foregroundStyle(.tertiary)

      Button("Run Busy Sample 5x") {
        runEvaluation(sample: .busy, label: "Busy sample")
      }
      .disabled(!canRunTests)

      Button("Run Critical Sample 5x") {
        runEvaluation(sample: .critical, label: "Critical sample")
      }
      .disabled(!canRunTests)

      if !currentPacket.topFacts.isEmpty {
        Button("Run Current Packet 5x") {
          runEvaluation(
            packet: currentPacket,
            fallbackText: currentFallback,
            label: "Current packet"
          )
        }
        .disabled(!canRunTests)
      }

      Button("Clear Evaluation Results", role: .destructive) {
        evaluationRuns = []
        evaluationProgress = nil
      }
      .disabled(evaluationRuns.isEmpty && evaluationProgress == nil)

      if let evaluationProgress {
        ProgressView(evaluationProgress)
          .font(.caption)
      }

      if !evaluationRuns.isEmpty {
        LocalModelEvaluationSummaryView(runs: evaluationRuns)
      }
    }
    .padding(.vertical, 4)
  }

  private func runEvaluation(
    sample: HostLLMPacketSampleFactory.Sample,
    label: String
  ) {
    runEvaluation(
      packet: HostLLMPacketSampleFactory.packet(for: sample),
      fallbackText: HostLLMPacketSampleFactory.fallbackText(for: sample),
      label: label
    )
  }

  private func runEvaluation(
    packet: HostLLMPacket,
    fallbackText: String,
    label: String
  ) {
    guard canRunTests else { return }
    isRunning = true
    runningSampleName = label
    evaluationProgress = "Running \(label) 0/5…"
    result = nil

    Task {
      let runs = await HostLocalModelEvaluationHarness.runSequential(
        count: 5,
        label: label,
        packet: packet,
        fallbackText: fallbackText,
        settings: settings
      ) { index, total in
        Task { @MainActor in
          evaluationProgress = "Running \(label) \(index)/\(total)…"
        }
      }

      await MainActor.run {
        evaluationRuns = runs
        evaluationProgress = nil
        runningSampleName = nil
        isRunning = false
      }
    }
  }

  private func runSample(_ sample: HostLLMPacketSampleFactory.Sample) {
    guard canRunTests else { return }
    isRunning = true
    runningSampleName = sample.displayName
    result = nil

    Task {
      await MainActor.run {
        HostLocalModelDiagnosticsCoordinator.shared.beginManualInference()
      }

      let diagnosticResult = await LocalModelBriefingDiagnosticRunner.run(
        packet: HostLLMPacketSampleFactory.packet(for: sample),
        fallbackText: HostLLMPacketSampleFactory.fallbackText(for: sample),
        testLabel: "Sample: \(sample.displayName)",
        settings: settings
      )

      await MainActor.run {
        result = diagnosticResult
        runningSampleName = nil
        isRunning = false
        let succeeded = diagnosticResult.writerResult.source == .localModel
          && diagnosticResult.validation.isValid
        HostLocalModelDiagnosticsCoordinator.shared.completeManualInference(
          succeeded: succeeded,
          failureMessage: diagnosticResult.writerResult.failedReason
            ?? diagnosticResult.validation.reason
        )
      }
    }
  }
}

private struct LocalModelBriefingDiagnosticResultView: View {
  let result: LocalModelBriefingDiagnosticResult

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      LabeledContent("Test") {
        Text(result.testLabel)
      }
      if result.inferenceSkippedBecauseNoFacts {
        Text("Local model skipped: no packet facts.")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      if result.inferenceSkippedBecauseLowRiskSingleFact {
        Text("Local model skipped: low-risk single-fact packet uses template.")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      LabeledContent("Host board local model gate") {
        Text(result.hostBoardLocalModelGateEnabled ? "Enabled" : "Disabled")
      }
      LabeledContent("Readiness") {
        Text(result.readinessStatus.rawValue)
      }
      LabeledContent("Prompt characters") {
        Text("\(result.promptCharacterCount)")
      }
      if let promptTokens = result.runtimeDiagnostics?.promptTokenCount, promptTokens > 0 {
        LabeledContent("Prompt tokens") {
          Text("\(promptTokens)")
        }
      }
      LabeledContent("Output characters") {
        Text("\(result.outputCharacterCount)")
      }
      LabeledContent("Cold duration") {
        Text(LocalModelDiagnosticDuration.format(result.coldDuration))
      }
      LabeledContent("Warm duration") {
        Text(LocalModelDiagnosticDuration.format(result.warmDuration))
      }
      LabeledContent("Cold source") {
        Text(result.coldWriterResult.source.displayName)
      }
      LabeledContent("Warm source") {
        Text(result.writerResult.source.displayName)
      }
      LabeledContent("Fallback occurred") {
        Text(result.fallbackOccurred ? "Yes" : "No")
      }
      if let modelSource = result.runtimeDiagnostics?.modelSource {
        LabeledContent("Model source") {
          Text(modelSource)
        }
      }
      if let decodeCode = result.runtimeDiagnostics?.initialDecodeCode {
        LabeledContent("Initial decode code") {
          Text("\(decodeCode)")
        }
      }
      if let runtimeDiagnostics = result.runtimeDiagnostics {
        if runtimeDiagnostics.generationRan {
          if let decodeCode = runtimeDiagnostics.generationDecodeCode {
            LabeledContent("Generation decode code") {
              Text("\(decodeCode)")
            }
          }
        } else if !result.inferenceSkippedBecauseNoFacts,
                  !result.inferenceSkippedBecauseLowRiskSingleFact {
          LabeledContent("Token generation") {
            Text("No token generation ran")
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
        }
      }
      if let candidate = result.generatedCandidate, !candidate.isEmpty {
        LabeledContent("Model candidate preview") {
          Text(candidate)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
      if let repaired = result.repairedOutput, !repaired.isEmpty {
        LabeledContent("Repaired output used") {
          Text(repaired)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
      if let reason = result.candidateValidationFailureReason, !reason.isEmpty {
        LabeledContent("Candidate validation failure") {
          Text(reason)
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
      if let reason = result.semanticValidationFailureReason, !reason.isEmpty {
        LabeledContent("Semantic validation failure") {
          Text(reason)
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
      if let runtimeError = result.runtimeDiagnostics?.lastError, !runtimeError.isEmpty {
        LabeledContent("Runtime error") {
          Text(runtimeError)
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
      LabeledContent("Output text") {
        Text(result.writerResult.text)
          .font(.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
      if let reason = result.writerResult.failedReason, !reason.isEmpty {
        LabeledContent("Failure reason") {
          Text(reason)
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
      LabeledContent("Validation") {
        Text(result.validation.isValid ? "Valid" : "Invalid")
      }
      if let reason = result.validation.reason {
        Text(reason)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      if result.fallbackOccurred {
        LabeledContent("Fallback text") {
          Text(result.fallbackText)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .textSelection(.enabled)
        }
      }
    }
  }
}

private struct LocalModelEvaluationSummaryView: View {
  let runs: [HostLocalModelEvaluationRun]

  private var summary: HostLocalModelEvaluationSummary {
    HostLocalModelEvaluationSummary.build(from: runs)
  }

  var body: some View {
    let candidatePreviews = runs.compactMap(\.candidatePreview).suffix(5)
    let acceptedOutputs = runs.compactMap(\.acceptedOutput).suffix(5)

    VStack(alignment: .leading, spacing: 8) {
      LabeledContent("Total runs") {
        Text("\(summary.totalRuns)")
      }
      LabeledContent("Passed") {
        Text("\(summary.passedRuns)")
      }
      LabeledContent("Fallback") {
        Text("\(summary.fallbackRuns)")
      }
      LabeledContent("Semantic failures") {
        Text("\(summary.semanticFailureRuns)")
      }
      LabeledContent("Average duration") {
        Text(LocalModelDiagnosticDuration.format(summary.averageDuration))
      }
      if !summary.mostCommonFailureReasons.isEmpty {
        LabeledContent("Common failures") {
          Text(summary.mostCommonFailureReasons.joined(separator: " · "))
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
      if !candidatePreviews.isEmpty {
        Text("Last candidate previews")
          .font(.caption.weight(.semibold))
        ForEach(Array(candidatePreviews.enumerated()), id: \.offset) { _, preview in
          Text(preview)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
      if !acceptedOutputs.isEmpty {
        Text("Last accepted outputs")
          .font(.caption.weight(.semibold))
        ForEach(Array(acceptedOutputs.enumerated()), id: \.offset) { _, output in
          Text(output)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
    }
  }
}

private struct OperationalPromptPreviewSection: View {
  let decision: HostDecisionSnapshot

  private var prompts: [HostOperationalBriefingPrompt] {
    HostOperationalBriefingPromptBuilder.buildExpandedPrompts(from: decision)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Operational Prompt Preview")
        .font(.subheadline.weight(.semibold))
        .padding(.top, 8)

      Text("Same deterministic builder used by the Review Intelligence view when separated prompts are enabled.")
        .font(.caption2)
        .foregroundStyle(.tertiary)

      if prompts.isEmpty {
        Text("No operational prompts for the current snapshot.")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      } else {
        ForEach(prompts) { prompt in
          VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Title") {
              Text(prompt.title)
            }
            LabeledContent("Category") {
              Text(prompt.category.rawValue)
            }
            LabeledContent("Severity") {
              Text(prompt.severity.rawValue.capitalized)
            }
            LabeledContent("Source") {
              Text(prompt.source.displayName)
            }
            LabeledContent("Related reservations") {
              Text("\(prompt.relatedReservationIDs.count)")
            }
            Text(prompt.body)
              .font(.caption)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
          .padding(.vertical, 4)
        }
      }
    }
  }
}

private struct LocalModelBriefingDiagnosticResult {
  let testLabel: String
  let coldWriterResult: HostBriefingWriterResult
  let writerResult: HostBriefingWriterResult
  let validation: HostBriefingValidationResult
  let coldDuration: TimeInterval
  let warmDuration: TimeInterval
  let promptCharacterCount: Int
  let outputCharacterCount: Int
  let readinessStatus: HostLocalModelReadinessStatus
  let fallbackText: String
  let fallbackOccurred: Bool
  let runtimeDiagnostics: HostLlamaRunDiagnostics?
  let inferenceSkippedBecauseNoFacts: Bool
  let inferenceSkippedBecauseLowRiskSingleFact: Bool
  let hostBoardLocalModelGateEnabled: Bool
  let generatedCandidate: String?
  let repairedOutput: String?
  let candidateValidationFailureReason: String?
  let semanticValidationFailureReason: String?
}

private enum LocalModelDiagnosticDuration {
  static func seconds(since mark: ContinuousClock.Instant, on clock: ContinuousClock) -> TimeInterval {
    let duration = mark.duration(to: clock.now)
    return Double(duration.components.seconds)
      + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
  }

  static func format(_ seconds: TimeInterval) -> String {
    if seconds < 0.01 {
      return String(format: "%.0f ms", seconds * 1000)
    }
    return String(format: "%.2f s", seconds)
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
