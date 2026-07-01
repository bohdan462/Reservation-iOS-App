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

  /// Host-board manager narrative for the 3B wording model.
  /// Two focused staff-facing sentences: the key operational issue and the key supporting
  /// detail. Larger token budget and longer timeout than hostBriefing to accommodate the
  /// 3B model's slower but richer output.
  static let managerNarrative = HostLocalModelTaskProfile(
    taskName: "managerNarrative",
    systemPrompt: """
    You write a concise operational note for restaurant staff (not guests).
    Use up to 3 short sentences when rich context exists; otherwise 1–2.
    Lead with service pressure or the most urgent issue.
    Explain the arrival pressure wave using only provided pressure facts.
    Use direct staff language. Never use labels, bullets, announcement tone, or guest-facing wording.
    Never promise cake, discounts, decorations, VIP treatment, or special surprises.
    """,
    maxOutputTokens: 160,
    echoStopMarkers: [
      "Write the manager narrative now:",
      "Approved facts:",
      "Service state:",
      "Available staff checks:",
      "Writing rules:",
      "Surface:"
    ],
    artifactPrefixes: [
      "Manager:",
      "Host:",
      "Briefing:",
      "Manager briefing:",
      "Here is the briefing:",
      "Here is the narrative:",
      "Output:"
    ],
    maxInferenceSeconds: 25
  )

  /// 4E — Service Intelligence packet narrative rewrite.
  /// Consumes structured BriefingFact fields only (see HostServiceBriefingNarrativePromptBuilder).
  /// Larger token budget than hostBriefing to accommodate compact + optional section lines.
  static let serviceBriefingNarrative = HostLocalModelTaskProfile(
    taskName: "serviceBriefingNarrative",
    systemPrompt: """
    You are a restaurant host briefing assistant. \
    Rewrite approved facts into calm, direct staff language. \
    Never address guests. Never invent facts. Never use technical or model language. \
    Output only the formatted block requested by the user message.
    """,
    maxOutputTokens: 200,
    echoStopMarkers: [
      "COMPACT:",
      "SECTION ",
      "Service context:",
      "Approved facts:",
      "Allowed guest names",
      "Forbidden in output:",
      "Output format",
    ],
    artifactPrefixes: [
      "Here is the briefing:",
      "Here is the output:",
      "Briefing:",
      "Output:",
      "Result:",
    ],
    maxInferenceSeconds: 15
  )

  /// 4F — On-demand full staff / management briefing.
  /// Multi-section operational briefing generated only on explicit request (never
  /// on packet rebuild). Consumes StaffBriefingPacket safe facts via
  /// StaffBriefingPromptBuilder. Largest token budget of any task and a long
  /// wall-clock deadline, because this is a deliberate, user-initiated action that
  /// falls back to the deterministic template on timeout.
  ///
  /// NOTE: kept within the existing 2048-token runtime context window. Output is
  /// capped so prompt + output stay inside that budget; the validator also enforces
  /// a hard 1200-word ceiling. If a larger context window becomes available, this
  /// budget can grow without changing the compact-narrative profiles.
  static let staffBriefing = HostLocalModelTaskProfile(
    taskName: "staffBriefing",
    systemPrompt: """
    You write an internal staff and management briefing for a restaurant team. \
    Use only the structured facts provided. Never address guests. Never invent \
    reservations, guests, tables, counts, attachments, reminders, confirmations, \
    cancellations, no-shows, allergies, birthdays, or regular status. Never claim \
    anything was sent, confirmed, seated, completed, assigned, or reviewed unless \
    the provided facts explicitly support it. Write like one manager briefing \
    another person: plain, warm, conversational sentences — not a report. Start \
    with a natural opener such as "Here's the picture before service," "Here's \
    what's happening right now," or "Here's the wrap-up." Use paragraphs first; \
    use bullets only for concrete action items. Do not mention data sources, \
    systems, packets, notes, or how this briefing was generated. No AI/meta \
    language. Output only the formatted block requested by the user message.
    """,
    maxOutputTokens: 768,
    echoStopMarkers: [
      "BRIEFING MODE:",
      "SERVICE STATE:",
      "COUNTS (ground truth",
      "STATUS COUNTS",
      "PRIORITY FACTS",
      "ALLOWED GUEST NAMES",
      "STYLE:",
      "OUTPUT FORMAT",
      "FORBIDDEN IN OUTPUT:",
    ],
    artifactPrefixes: [
      "Here is the briefing:",
      "Here is the staff briefing:",
      "Staff briefing:",
      "Briefing:",
      "Output:",
      "Result:",
    ],
    maxInferenceSeconds: 55
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
