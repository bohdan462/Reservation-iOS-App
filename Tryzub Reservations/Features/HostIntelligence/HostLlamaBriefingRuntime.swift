//
//  HostLlamaBriefingRuntime.swift
//  Tryzub Reservations
//
//  llama.cpp adapter for host briefing generation.
//  Phase 8B.1: compile-safe shell — no SPM package linked yet.
//  Phase 8B.2: add mattt/llama.swift (requires Swift 6) and implement inference here.
//

import Foundation

/// llama.cpp-backed runtime. Inference is deferred until SPM is linked in Phase 8B.2.
final actor HostLlamaBriefingRuntime: HostLocalModelRuntime {

  static let runtimeDisplayName = "llama.cpp"

  /// Swift adapter source is compiled into the app.
  static let isAdapterShellPresent = true

  /// True only when llama.cpp / LlamaSwift SPM is linked and inference is implemented.
  /// Phase 8B.2: set to true after mattt/llama.swift is integrated.
  static let isInferenceRuntimeLinked = false

  static let shared = HostLlamaBriefingRuntime()

  private static let maxOutputTokens = 120
  private static let samplingTemperature = 0.2

  var runtimeName: String { Self.runtimeDisplayName }

  var modelName: String? {
    HostLocalModelFileLocator.firstAvailableModelURL()?.lastPathComponent
  }

  private init() {}

  func generateBriefing(prompt: String) async throws -> String {
    _ = prompt
    _ = Self.maxOutputTokens
    _ = Self.samplingTemperature

    guard HostLocalModelFileLocator.firstAvailableModelURL() != nil else {
      throw HostLocalModelRuntimeError.modelMissing
    }

    // Phase 8B.2: lazy-load GGUF via LlamaSwift, run low-temperature generation,
    // trim output, and return raw text for HostBriefingWriterValidator.
    throw HostLocalModelRuntimeError.runtimeUnavailable
  }
}
