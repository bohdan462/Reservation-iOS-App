//
//  HostLocalModelRuntime.swift
//  Tryzub Reservations
//
//  Abstraction for on-device briefing inference. Implementations must not receive
//  raw reservation records — only prompts built from HostLLMPacket.
//

import Foundation

protocol HostLocalModelRuntime: Actor {
  var runtimeName: String { get }
  var modelName: String? { get }
  func generateBriefing(prompt: String) async throws -> String
}

enum HostLocalModelRuntimeError: LocalizedError, Equatable {
  case runtimeUnavailable
  case modelMissing
  case modelLoadFailed(String)
  case generationFailed(String)
  case outputEmpty

  var errorDescription: String? {
    switch self {
    case .runtimeUnavailable:
      return "Local model runtime is not installed."
    case .modelMissing:
      return "Local briefing model file is not installed."
    case .modelLoadFailed(let detail):
      return "Local model failed to load: \(detail)"
    case .generationFailed(let detail):
      return "Local model generation failed: \(detail)"
    case .outputEmpty:
      return "Local model returned empty output."
    }
  }
}

/// Selects the active on-device runtime implementation.
enum HostLocalModelRuntimeFactory {
  /// True only when a real on-device inference runtime is linked — not merely the adapter shell.
  static var isRuntimeIntegrated: Bool {
    HostLlamaBriefingRuntime.isInferenceRuntimeLinked
  }

  static var isAdapterShellPresent: Bool {
    HostLlamaBriefingRuntime.isAdapterShellPresent
  }

  static var integratedRuntimeName: String? {
    guard isRuntimeIntegrated else { return nil }
    return HostLlamaBriefingRuntime.runtimeDisplayName
  }

  static func makeRuntime() -> HostLocalModelRuntime {
    HostLlamaBriefingRuntime.shared
  }
}
