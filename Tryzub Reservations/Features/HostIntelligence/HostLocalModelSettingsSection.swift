//
//  HostLocalModelSettingsSection.swift
//  Tryzub Reservations
//
//  Local model install progress, prepare/import, and unlocked smoke tests.
//

import SwiftUI

struct HostLocalModelSettingsSection: View {
  @ObservedObject var settingsStore: HostIntelligenceSettingsStore
  @ObservedObject private var autoPrepareCoordinator = HostLocalModelAutoPrepareCoordinator.shared
  @ObservedObject private var diagnosticsCoordinator = HostLocalModelDiagnosticsCoordinator.shared

  @State private var isShowingModelImporter = false
  @State private var modelImportMessage: String?
  @State private var modelImportError: String?
  @State private var isPreparing = false
  @State private var isRunningSmokeTest = false
  @State private var smokeTestResult: LocalModelBriefingDiagnosticResult?

  var body: some View {
    Section("Local Model") {
      modelStatusBlock
      modelProgressBlock
      modelActionsBlock
      smokeTestBlock
    }
  }

  @ViewBuilder
  private var modelStatusBlock: some View {
    let readiness = HostLocalModelReadinessProvider.currentReadiness()
    let bundled = HostLocalModelFileLocator.bundledModelURL() != nil
    let installed = HostLocalModelFileLocator.applicationSupportModelURL() != nil

    LabeledContent("Readiness") {
      Text(readiness.status.rawValue)
    }
    LabeledContent("In app bundle") {
      Text(bundled ? "Yes" : "No")
    }
    LabeledContent("Prepared on device") {
      Text(installed ? "Yes" : "No")
    }

    Text(readiness.detail)
      .font(.caption)
      .foregroundStyle(.secondary)

    if !bundled, !installed {
      Text("On Mac: run Scripts/fetch-host-briefing-model.sh, rebuild, and install on this iPhone. On device: use Import GGUF below (AirDrop the file to Files first).")
        .font(.caption)
        .foregroundStyle(.secondary)
    } else if bundled, !installed {
      Text("This build includes the model. Tap Prepare Now to copy it into private storage on this iPhone.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    if let autoFailure = autoPrepareCoordinator.technicalFailureDetail {
      Text("Auto-prepare: \(autoFailure)")
        .font(.caption)
        .foregroundStyle(.red)
    }

    if let lastFailure = diagnosticsCoordinator.lastFailureMessage, !lastFailure.isEmpty {
      Text(lastFailure)
        .font(.caption)
        .foregroundStyle(.red)
    }
  }

  @ViewBuilder
  private var modelProgressBlock: some View {
    if autoPrepareCoordinator.isPrepareInFlight || autoPrepareCoordinator.phase.showsMoreSection {
      OnDeviceSupportStatusBanner(phase: autoPrepareCoordinator.phase, style: .card)
    }

    if diagnosticsCoordinator.loadingState != .idle,
       let message = diagnosticsCoordinator.loadingState.statusMessage {
      if let fraction = diagnosticsCoordinator.loadingState.copyProgressFraction {
        VStack(alignment: .leading, spacing: 6) {
          ProgressView(value: fraction)
          Text("\(message) \(Int((fraction * 100).rounded()))%")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else if case .failed = diagnosticsCoordinator.loadingState {
        EmptyView()
      } else {
        ProgressView(message)
          .font(.caption)
      }
    }
  }

  @ViewBuilder
  private var modelActionsBlock: some View {
    Button {
      prepareModelNow()
    } label: {
      Label(
        isPreparing ? "Preparing…" : "Prepare Model Now",
        systemImage: "arrow.down.circle"
      )
    }
    .disabled(
      isPreparing
        || diagnosticsCoordinator.loadingState.isBusy
        || autoPrepareCoordinator.isPrepareInFlight
        || (HostLocalModelFileLocator.bundledModelURL() == nil
          && HostLocalModelFileLocator.applicationSupportModelURL() != nil)
    )

    HostLocalModelGGUFImportControls(
      isShowingModelImporter: $isShowingModelImporter,
      modelImportMessage: $modelImportMessage,
      modelImportError: $modelImportError,
      compact: true,
      onImportSuccess: {}
    )

    if settingsStore.settings.enhancedBriefingProvider != .localModel {
      Text("Set Briefing Writer provider to Local model to use on-device inference on the Host board.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var smokeTestBlock: some View {
    Text("LLM smoke tests run on tap even when the model is not ready — results show what failed.")
      .font(.caption2)
      .foregroundStyle(.tertiary)

    Button {
      runSmokeTest()
    } label: {
      Label(
        isRunningSmokeTest ? "Running smoke test…" : "Run Busy Sample Smoke Test",
        systemImage: "sparkles"
      )
    }
    .disabled(isRunningSmokeTest || diagnosticsCoordinator.loadingState.isBusy)

    if isRunningSmokeTest {
      ProgressView("Running local inference…")
        .font(.caption)
    }

    if let smokeTestResult {
      LocalModelBriefingDiagnosticResultView(result: smokeTestResult)
    }
  }

  private func prepareModelNow() {
    guard !isPreparing else { return }
    isPreparing = true
    diagnosticsCoordinator.resetFailure()

    Task {
      let succeeded = await diagnosticsCoordinator.prepareLocalModel()
      await MainActor.run {
        isPreparing = false
        if !succeeded, diagnosticsCoordinator.lastFailureMessage == nil {
          modelImportError = "Could not prepare the local model."
        }
      }
    }
  }

  private func runSmokeTest() {
    guard !isRunningSmokeTest else { return }
    isRunningSmokeTest = true
    smokeTestResult = nil
    diagnosticsCoordinator.resetFailure()

    Task {
      await MainActor.run {
        diagnosticsCoordinator.beginManualInference()
      }

      let result = await LocalModelBriefingDiagnosticRunner.run(
        packet: HostLLMPacketSampleFactory.packet(for: .busy),
        fallbackText: HostLLMPacketSampleFactory.fallbackText(for: .busy),
        testLabel: "Settings smoke test",
        settings: settingsStore.settings
      )

      await MainActor.run {
        smokeTestResult = result
        isRunningSmokeTest = false
        let succeeded = result.writerResult.source == .localModel && result.validation.isValid
        diagnosticsCoordinator.completeManualInference(
          succeeded: succeeded,
          failureMessage: result.writerResult.failedReason ?? result.validation.reason
        )
      }
    }
  }
}
