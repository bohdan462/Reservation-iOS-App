//
//  HostLocalModelDiagnosticsCoordinator.swift
//  Tryzub Reservations
//
//  Manual local model prepare/test state for developer diagnostics only.
//

import Combine
import Foundation

@MainActor
final class HostLocalModelDiagnosticsCoordinator: ObservableObject {
  static let shared = HostLocalModelDiagnosticsCoordinator()

  @Published private(set) var loadingState: HostLocalModelLoadingState = .idle
  @Published private(set) var lastFailureMessage: String?

  private var manualOperationCount = 0

  var isManualOperationInFlight: Bool { manualOperationCount > 0 }

  private init() {}

  var modelStatusTitle: String {
    HostLocalModelReadinessProvider.currentReadiness().title
  }

  var modelStatusDetail: String {
    HostLocalModelReadinessProvider.currentReadiness().detail
  }

  var modelPathSourceLabel: String {
    HostLocalModelFileLocator.resolvedModelSourceDisplayName()
  }

  var canPrepareBundledModel: Bool {
    !loadingState.isBusy
      && HostLocalModelFileLocator.applicationSupportModelURL() == nil
      && HostLocalModelFileLocator.bundledModelURL() != nil
  }

  var isInferenceModelInstalled: Bool {
    HostLocalModelFileLocator.inferenceModelURL() != nil
  }

  func setPhase(_ phase: HostLocalModelLoadingState) {
    loadingState = phase
    if case .failed(let message) = phase {
      lastFailureMessage = message
    }
  }

  func resetFailure() {
    lastFailureMessage = nil
    if case .failed = loadingState {
      loadingState = .idle
    }
  }

  func prepareLocalModel() async -> Bool {
    guard !loadingState.isBusy else { return false }

    beginManualOperation()
    defer { endManualOperation() }

    setPhase(.checkingModel)
    lastFailureMessage = nil

    if HostLocalModelFileLocator.applicationSupportModelURL() != nil {
      setPhase(.ready)
      try? await Task.sleep(nanoseconds: 400_000_000)
      setPhase(.idle)
      return true
    }

    guard HostLocalModelFileLocator.bundledModelURL() != nil else {
      let message = "No bundled model resource found in the app. Import a .gguf from Files instead."
      setPhase(.failed(message))
      return false
    }

    do {
      setPhase(.copyingBundledModel(progress: nil))
      _ = try await HostLocalModelInstaller.installBundledModel { [weak self] progress in
        Task { @MainActor in
          self?.setPhase(.copyingBundledModel(progress: progress))
        }
      }
      setPhase(.ready)
      try? await Task.sleep(nanoseconds: 400_000_000)
      setPhase(.idle)
      return true
    } catch {
      setPhase(.failed(error.localizedDescription))
      return false
    }
  }

  func beginManualInference() {
    beginManualOperation()
    setPhase(.checkingModel)
    lastFailureMessage = nil
  }

  func completeManualInference(succeeded: Bool, failureMessage: String? = nil) {
    if succeeded {
      setPhase(.completed)
    } else if let failureMessage, !failureMessage.isEmpty {
      setPhase(.failed(failureMessage))
    } else {
      setPhase(.failed("Local model briefing test failed."))
    }
    endManualOperation()
    Task {
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      await MainActor.run {
        if !self.isManualOperationInFlight {
          self.setPhase(.idle)
        }
      }
    }
  }

  private func beginManualOperation() {
    manualOperationCount += 1
  }

  private func endManualOperation() {
    manualOperationCount = max(0, manualOperationCount - 1)
  }
}
