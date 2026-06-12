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
  /// Task-aware generation. Each task supplies its own system prompt, token budget,
  /// stop markers, and inference deadline so guest drafts and note analysis do not
  /// inherit the host-briefing system prompt (the cause of "Dear staff" meta-output).
  func generate(prompt: String, profile: HostLocalModelTaskProfile) async throws -> String
}

extension HostLocalModelRuntime {
  /// Default routes task generation through the host-briefing path so any runtime that
  /// only implements `generateBriefing` still works.
  func generate(prompt: String, profile: HostLocalModelTaskProfile) async throws -> String {
    try await generateBriefing(prompt: prompt)
  }
}

/// Per-task inference configuration. Keeps each model task (host briefing, guest message
/// draft, note analysis) cleanly separated: different system prompt, token budget, stop
/// markers, artifact prefixes, and a hard wall-clock timeout so a slow run never hangs the
/// surface — it falls back to the deterministic/template path instead.
struct HostLocalModelTaskProfile: Sendable, Equatable {
  let taskName: String
  let systemPrompt: String
  let maxOutputTokens: Int32
  let echoStopMarkers: [String]
  let artifactPrefixes: [String]
  let maxInferenceSeconds: Double

  /// Host board briefing rewrite — calm staff-facing prose. Unchanged from the original
  /// behavior (100 tokens, host echo markers) to preserve the TestFlight-safe posture.
  static let hostBriefing = HostLocalModelTaskProfile(
    taskName: "hostBriefing",
    systemPrompt: "Rewrite the approved host facts into calm staff-facing prose. Obey every rule in the user message.",
    maxOutputTokens: 100,
    echoStopMarkers: [
      "Write the host briefing now:",
      "Approved facts:",
      "You are rewriting an approved restaurant host briefing",
      "Writing rules:",
      "Forbidden:"
    ],
    artifactPrefixes: [
      "Briefing:",
      "Host briefing:",
      "Final briefing:",
      "Here is the host briefing:",
      "Here is the briefing:",
      "Here is your host briefing:",
      "Here is..."
    ],
    maxInferenceSeconds: 12
  )

  /// Guest-facing email + SMS draft as strict JSON, for staff review only. Larger token
  /// budget (a full email body + SMS JSON does not fit in 100 tokens) and a guest-specific
  /// system prompt that forbids addressing staff.
  static let guestMessageDraft = HostLocalModelTaskProfile(
    taskName: "guestMessageDraft",
    systemPrompt: "You write guest-facing reservation messages as one strict JSON object for restaurant staff to review before sending. Write to the guest only. Never address staff. Never write \"Dear staff\", \"team\", or describe what you are doing. Output only the JSON object.",
    maxOutputTokens: 360,
    echoStopMarkers: [
      "Write the JSON draft now:",
      "Allowlisted packet JSON:",
      "Required JSON keys:",
      "Rules:"
    ],
    artifactPrefixes: [
      "Here is the JSON:",
      "Here is the draft:",
      "JSON:",
      "Draft:",
      "Output:"
    ],
    maxInferenceSeconds: 20
  )

  /// Reservation note analysis — classifies tone + signals into strict JSON. Never asserts
  /// a deposit is paid or an allergy is confirmed; the deterministic analyzer remains the
  /// baseline and model output is additive, staff-reviewed enrichment.
  static let noteAnalysis = HostLocalModelTaskProfile(
    taskName: "noteAnalysis",
    systemPrompt: "You classify one restaurant reservation note into a single strict JSON object for staff review. Never invent facts. Never say a deposit is paid or an allergy is confirmed — only that something is mentioned and should be verified. Output only the JSON object.",
    maxOutputTokens: 300,
    echoStopMarkers: [
      "Write the JSON now:",
      "Note to classify:",
      "Allowed signal types:",
      "Rules:"
    ],
    artifactPrefixes: [
      "Here is the JSON:",
      "JSON:",
      "Output:",
      "Result:"
    ],
    maxInferenceSeconds: 15
  )
}

enum HostLocalModelRuntimeError: LocalizedError, Equatable {
  case runtimeUnavailable
  case modelMissing
  case modelLoadFailed(String)
  case generationFailed(String)
  case timedOut
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
    case .timedOut:
      return "Local model timed out."
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
