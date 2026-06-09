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
  var analyticsLoadedAt: Date? = nil
  let restaurantSetup: RestaurantSetup?
  let localSeatedAtByReservationID: [Int: Date]
  let settings: HostIntelligenceSettings
  var briefingSource: HostBriefingWriterSource? = nil
  var briefingFailureReason: String? = nil
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

      LocalModelBriefingDiagnosticTest(
        packet: packet,
        fallbackText: fallback,
        settings: settings,
        readiness: localModelReadiness
      )

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

// MARK: - Local Model Manual Test (developer diagnostics only)

private struct LocalModelBriefingDiagnosticTest: View {
  let packet: HostLLMPacket
  let fallbackText: String
  let settings: HostIntelligenceSettings
  let readiness: HostLocalModelReadiness

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

      Button("Test Local Model Briefing") {
        runTest()
      }
      .disabled(!canRunTest)

      if !canRunTest, settings.enhancedBriefingProvider != .localModel {
        Text("Select Local model provider to enable this test.")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      } else if !canRunTest, readiness.status != .ready {
        Text("Install the GGUF model in Application Support to enable this test.")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

      if isRunning {
        ProgressView("Running local inference…")
          .font(.caption)
      }

      if let result {
        LabeledContent("Readiness") {
          Text(result.readinessStatus.rawValue)
        }
        LabeledContent("Prompt characters") {
          Text("\(result.promptCharacterCount)")
        }
        LabeledContent("Output characters") {
          Text("\(result.outputCharacterCount)")
        }
        LabeledContent("Cold duration") {
          Text(String(format: "%.2f s", result.coldDuration))
        }
        LabeledContent("Warm duration") {
          Text(String(format: "%.2f s", result.warmDuration))
        }
        LabeledContent("Source") {
          Text(result.writerResult.source.displayName)
        }
        Text(result.writerResult.text)
          .font(.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
        if let reason = result.writerResult.failedReason, !reason.isEmpty {
          Text(reason)
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        LabeledContent("Validation") {
          Text(result.validation.isValid ? "Valid" : "Invalid")
        }
        if let reason = result.validation.reason {
          Text(reason)
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        if result.writerResult.source == .failedFallback {
          Text("Fallback occurred — template text was used.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
    }
    .padding(.vertical, 4)
  }

  private func runTest() {
    guard canRunTest else { return }
    isRunning = true
    result = nil

    Task {
      let prompt = HostLLMPacketPromptBuilder.buildPrompt(from: packet)
      let readinessStatus = HostLocalModelReadinessProvider.currentReadiness().status
      let writer = LocalModelHostBriefingWriter()

      let coldStart = Date()
      _ = await writer.writeBriefing(packet: packet, fallbackText: fallbackText)
      let coldDuration = Date().timeIntervalSince(coldStart)

      let warmStart = Date()
      let writerResult = await writer.writeBriefing(
        packet: packet,
        fallbackText: fallbackText
      )
      let warmDuration = Date().timeIntervalSince(warmStart)

      let validation = HostBriefingWriterValidator.validationResult(
        writerResult.text,
        packet: packet,
        fallbackText: fallbackText
      )

      await MainActor.run {
        result = LocalModelBriefingDiagnosticResult(
          writerResult: writerResult,
          validation: validation,
          coldDuration: coldDuration,
          warmDuration: warmDuration,
          promptCharacterCount: prompt.count,
          outputCharacterCount: writerResult.text.count,
          readinessStatus: readinessStatus
        )
        isRunning = false
      }
    }
  }
}

private struct LocalModelBriefingDiagnosticResult {
  let writerResult: HostBriefingWriterResult
  let validation: HostBriefingValidationResult
  let coldDuration: TimeInterval
  let warmDuration: TimeInterval
  let promptCharacterCount: Int
  let outputCharacterCount: Int
  let readinessStatus: HostLocalModelReadinessStatus
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
