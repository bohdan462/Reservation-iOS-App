//
//  HostLocalModelReadiness.swift
//  Tryzub Reservations
//
//  Readiness state for on-device briefing model. Lightweight — no model loading.
//

import Foundation

enum HostLocalModelReadinessStatus: String, Codable, Equatable {
  case unavailable
  case modelMissing
  case runtimeMissing
  case ready
}

struct HostLocalModelReadiness: Codable, Equatable {
  let status: HostLocalModelReadinessStatus
  let title: String
  let detail: String
  let modelName: String?
  let runtimeName: String?
}

extension HostLocalModelReadiness {
  static let unavailable = HostLocalModelReadiness(
    status: .unavailable,
    title: "Local model unavailable",
    detail: "On-device briefing is not available in this build.",
    modelName: nil,
    runtimeName: nil
  )

  static let runtimeMissing = HostLocalModelReadiness(
    status: .runtimeMissing,
    title: "Local model runtime missing",
    detail: "No local model runtime is included in this build.",
    modelName: nil,
    runtimeName: nil
  )

  static let modelMissing = HostLocalModelReadiness(
    status: .modelMissing,
    title: "Local model file missing",
    detail: "A model runtime may be present, but no briefing model is installed.",
    modelName: nil,
    runtimeName: nil
  )

  /// Preview/diagnostics placeholder only — not a real ready state in this build.
  static let readyPlaceholder = HostLocalModelReadiness(
    status: .ready,
    title: "Local model ready",
    detail: "Placeholder readiness state for future diagnostics.",
    modelName: "host-briefing-placeholder",
    runtimeName: "future-runtime"
  )
}

enum HostLocalModelReadinessProvider {
  static func currentReadiness() -> HostLocalModelReadiness {
    guard HostLocalModelRuntimeFactory.isRuntimeIntegrated else {
      let adapterNote = HostLocalModelRuntimeFactory.isAdapterShellPresent
        ? "Adapter shell is present, but inference runtime is not linked."
        : "No local model adapter is present."
      return HostLocalModelReadiness(
        status: .runtimeMissing,
        title: "Local model runtime missing",
        detail: "\(adapterNote) \(HostLocalModelFileLocator.modelLookupPathDescription())",
        modelName: HostLocalModelFileLocator.expectedModelFileName,
        runtimeName: nil
      )
    }

    let runtimeName = HostLocalModelRuntimeFactory.integratedRuntimeName
    let presence = HostLocalModelFileLocator.modelPresenceDescription()
    let source = HostLocalModelFileLocator.modelSourceLabel()

    guard HostLocalModelFileLocator.firstAvailableModelURL() != nil else {
      return HostLocalModelReadiness(
        status: .modelMissing,
        title: "Local model file missing",
        detail: "\(presence) Expected file: \(HostLocalModelFileLocator.expectedModelFileName).",
        modelName: HostLocalModelFileLocator.expectedModelFileName,
        runtimeName: runtimeName
      )
    }

    return HostLocalModelReadiness(
      status: .ready,
      title: "Local model ready",
      detail: "\(presence) Source: \(source).",
      modelName: HostLocalModelFileLocator.expectedModelFileName,
      runtimeName: runtimeName
    )
  }
}
