//
//  HostLocalModelReadiness.swift
//  Tryzub Reservations
//
//  Readiness state for a future on-device briefing model. No runtime is bundled yet.
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
    .runtimeMissing
  }
}
