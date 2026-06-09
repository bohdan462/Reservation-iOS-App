//
//  HostLocalModelLoadingState.swift
//  Tryzub Reservations
//
//  Diagnostics-only loading phases for manual local model prepare/test.
//

import Foundation

enum HostLocalModelLoadingState: Equatable {
  case idle
  case checkingModel
  case copyingBundledModel(progress: Double?)
  case ready
  case loadingRuntime
  case generating
  case completed
  case failed(String)

  var isBusy: Bool {
    switch self {
    case .checkingModel, .copyingBundledModel, .loadingRuntime, .generating:
      return true
    case .idle, .ready, .completed, .failed:
      return false
    }
  }

  var statusMessage: String? {
    switch self {
    case .idle:
      return nil
    case .checkingModel:
      return "Checking on-device model…"
    case .copyingBundledModel:
      return "Preparing on-device model…"
    case .ready:
      return "Local model is ready."
    case .loadingRuntime:
      return "Loading model runtime…"
    case .generating:
      return "Generating local briefing…"
    case .completed:
      return "Local model test completed."
    case .failed(let message):
      return message
    }
  }

  var copyProgressFraction: Double? {
    if case .copyingBundledModel(let progress) = self {
      return progress
    }
    return nil
  }
}

enum HostLocalModelProgressReporter {
  static func reportLoadingRuntimeIfManual() {
    Task { @MainActor in
      let coordinator = HostLocalModelDiagnosticsCoordinator.shared
      guard coordinator.isManualOperationInFlight else { return }
      coordinator.setPhase(.loadingRuntime)
    }
  }

  static func reportGeneratingIfManual() {
    Task { @MainActor in
      let coordinator = HostLocalModelDiagnosticsCoordinator.shared
      guard coordinator.isManualOperationInFlight else { return }
      coordinator.setPhase(.generating)
    }
  }
}
