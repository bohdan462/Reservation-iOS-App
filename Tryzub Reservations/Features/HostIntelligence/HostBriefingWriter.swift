//
//  HostBriefingWriter.swift
//  Tryzub Reservations
//
//  Presentation-only briefing writers. The deterministic engine remains authoritative.
//  Future local LLM providers must consume HostLLMPacket only — never raw reservation
//  records or unsanitized private notes.
//

import Foundation

// MARK: - Result Types

struct HostBriefingWriterResult: Equatable {
  let text: String
  let source: HostBriefingWriterSource
  let failedReason: String?
}

/// In-memory diagnostics for developer tools only. Not persisted.
enum HostLocalModelInferenceTracker {
  private static let lock = NSLock()
  enum Task: String {
    case hostBoardNarrative
    case hostBriefing
    /// 4E: Service Intelligence packet-based narrative (planning / recap / non-live paths).
    case serviceBriefingNarrative
    /// 4F: On-demand full staff / management briefing (user-initiated only).
    case staffBriefing
    case guestMessageDraft
    case noteAnalysis
    case diagnosticsPreload

    var priority: Int {
      switch self {
      case .hostBoardNarrative, .guestMessageDraft:
        return 100
      case .staffBriefing:
        return 95
      case .serviceBriefingNarrative:
        return 90
      case .hostBriefing:
        return 80
      case .noteAnalysis, .diagnosticsPreload:
        return 10
      }
    }

    var isLowPriority: Bool {
      priority < 50
    }
  }

  nonisolated(unsafe) private static var activeRequestCount = 0
  nonisolated(unsafe) private static var activeTasks: [Task: Int] = [:]
  nonisolated(unsafe) private static var hostBoardPendingCount = 0

  static var isActive: Bool {
    lock.lock()
    defer { lock.unlock() }
    return activeRequestCount > 0
  }

  static var currentTaskLabel: String? {
    lock.lock()
    defer { lock.unlock() }
    return highestPriorityActiveTaskLocked()?.rawValue
  }

  static var blocksHostBoardNarrative: Bool {
    lock.lock()
    defer { lock.unlock() }
    guard let current = highestPriorityActiveTaskLocked() else { return false }
    return !current.isLowPriority
  }

  static func begin() {
    _ = begin(task: .hostBriefing)
  }

  @discardableResult
  static func begin(task: Task) -> Bool {
    lock.lock()
    defer {
      lock.unlock()
    }
    if task == .noteAnalysis, hostBoardPendingCount > 0 {
      HostLocalModelPriorityTrace.log(
        requested: task.rawValue,
        decision: "defer",
        reason: "host_board_pending"
      )
      return false
    }
    if task == .hostBoardNarrative {
      if let current = highestPriorityActiveTaskLocked(), current.isLowPriority {
        HostLocalModelPriorityTrace.log(
          requested: task.rawValue,
          decision: "wait_or_cancel_lower_priority",
          reason: nil,
          current: current.rawValue
        )
      } else {
        HostLocalModelPriorityTrace.log(
          requested: task.rawValue,
          decision: "run",
          reason: "host_priority"
        )
      }
    }
    activeRequestCount += 1
    activeTasks[task, default: 0] += 1
    return true
  }

  static func end() {
    end(task: .hostBriefing)
  }

  static func end(task: Task) {
    lock.lock()
    defer { lock.unlock() }
    activeRequestCount = max(0, activeRequestCount - 1)
    if let count = activeTasks[task], count > 1 {
      activeTasks[task] = count - 1
    } else {
      activeTasks.removeValue(forKey: task)
    }
  }

  static func beginHostBoardPending() {
    lock.lock()
    defer { lock.unlock() }
    hostBoardPendingCount += 1
  }

  static func endHostBoardPending() {
    lock.lock()
    defer { lock.unlock() }
    hostBoardPendingCount = max(0, hostBoardPendingCount - 1)
  }

  private static func highestPriorityActiveTaskLocked() -> Task? {
    activeTasks
      .filter { $0.value > 0 }
      .keys
      .sorted { lhs, rhs in
        if lhs.priority != rhs.priority {
          return lhs.priority > rhs.priority
        }
        return lhs.rawValue < rhs.rawValue
      }
      .first
  }
}

enum HostLocalModelPriorityTrace {
  static func log(
    requested: String,
    decision: String,
    reason: String? = nil,
    current: String? = nil
  ) {
    #if DEBUG
    var parts = [
      "[LOCAL_MODEL_PRIORITY_TRACE]",
      "requested=\(requested)",
      "decision=\(decision)"
    ]
    if let reason, !reason.isEmpty {
      parts.append("reason=\(reason)")
    }
    if let current, !current.isEmpty {
      parts.append("current=\(current)")
    }
    print(parts.joined(separator: " "))
    #endif
  }
}

enum HostBriefingWriterDiagnostics {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var _lastGeneratedCandidate: String?
  nonisolated(unsafe) private static var _lastRepairedOutput: String?
  nonisolated(unsafe) private static var _lastValidationFailureReason: String?
  nonisolated(unsafe) private static var _lastSemanticValidationFailureReason: String?
  nonisolated(unsafe) private static var _inferenceSkippedBecauseNoFacts = false
  nonisolated(unsafe) private static var _inferenceSkippedBecauseLowRiskSingleFact = false

  static var lastGeneratedCandidate: String? {
    lock.lock()
    defer { lock.unlock() }
    return _lastGeneratedCandidate
  }

  static var lastRepairedOutput: String? {
    lock.lock()
    defer { lock.unlock() }
    return _lastRepairedOutput
  }

  static var lastValidationFailureReason: String? {
    lock.lock()
    defer { lock.unlock() }
    return _lastValidationFailureReason
  }

  static var lastSemanticValidationFailureReason: String? {
    lock.lock()
    defer { lock.unlock() }
    return _lastSemanticValidationFailureReason
  }

  static var inferenceSkippedBecauseNoFacts: Bool {
    lock.lock()
    defer { lock.unlock() }
    return _inferenceSkippedBecauseNoFacts
  }

  static var inferenceSkippedBecauseLowRiskSingleFact: Bool {
    lock.lock()
    defer { lock.unlock() }
    return _inferenceSkippedBecauseLowRiskSingleFact
  }

  private static let maxCandidateLength = 500

  static func storeCandidate(_ text: String) {
    lock.lock()
    defer { lock.unlock() }
    storeCandidateLocked(text)
  }

  private static func storeCandidateLocked(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    _lastGeneratedCandidate = trimmed.count <= maxCandidateLength
      ? trimmed
      : String(trimmed.prefix(maxCandidateLength))
  }

  static func recordEmptyPacketSkip() {
    lock.lock()
    defer { lock.unlock() }
    _lastGeneratedCandidate = nil
    _lastRepairedOutput = nil
    _lastValidationFailureReason = nil
    _lastSemanticValidationFailureReason = nil
    _inferenceSkippedBecauseNoFacts = true
    _inferenceSkippedBecauseLowRiskSingleFact = false
    HostLlamaBriefingRuntimeDiagnostics.resetLastRun()
  }

  static func recordLowRiskSingleFactSkip() {
    lock.lock()
    defer { lock.unlock() }
    _lastGeneratedCandidate = nil
    _lastRepairedOutput = nil
    _lastValidationFailureReason = nil
    _lastSemanticValidationFailureReason = nil
    _inferenceSkippedBecauseNoFacts = false
    _inferenceSkippedBecauseLowRiskSingleFact = true
    HostLlamaBriefingRuntimeDiagnostics.resetLastRun()
  }

  static func prepareForInference() {
    lock.lock()
    defer { lock.unlock() }
    _inferenceSkippedBecauseNoFacts = false
    _inferenceSkippedBecauseLowRiskSingleFact = false
  }

  static func recordValidationSuccess(generated: String, repaired: String? = nil) {
    lock.lock()
    defer { lock.unlock() }
    storeCandidateLocked(generated)
    _lastRepairedOutput = repaired
    _lastValidationFailureReason = nil
    _lastSemanticValidationFailureReason = nil
  }

  static func recordValidationFailure(generated: String, reason: String?) {
    lock.lock()
    defer { lock.unlock() }
    storeCandidateLocked(generated)
    _lastRepairedOutput = nil
    _lastValidationFailureReason = reason
    _lastSemanticValidationFailureReason = HostBriefingWriterValidator.isSemanticFailureReason(reason)
      ? reason
      : nil
  }

  static func recordRuntimeFailure() {
    lock.lock()
    defer { lock.unlock() }
    _lastGeneratedCandidate = nil
    _lastRepairedOutput = nil
    _lastValidationFailureReason = nil
    _lastSemanticValidationFailureReason = nil
  }
}

enum HostBriefingWriterSource: String, Equatable {
  case template
  case localPlaceholder
  case localModel
  case repairedLocalModel
  case failedFallback

  var displayName: String {
    switch self {
    case .template: return "Template"
    case .localPlaceholder: return "Local placeholder"
    case .localModel: return "Local model"
    case .repairedLocalModel: return "Repaired local model"
    case .failedFallback: return "Fallback"
    }
  }
}

// MARK: - Protocol

/// Rewrites an approved `HostLLMPacket` into host-facing prose. Does not make decisions.
protocol HostBriefingWriter {
  func writeBriefing(
    packet: HostLLMPacket,
    fallbackText: String
  ) async -> HostBriefingWriterResult
}

// MARK: - Template Writer

struct TemplateHostBriefingWriter: HostBriefingWriter {
  func writeBriefing(
    packet: HostLLMPacket,
    fallbackText: String
  ) async -> HostBriefingWriterResult {
    HostBriefingWriterResult(
      text: fallbackText,
      source: .template,
      failedReason: nil
    )
  }
}

// MARK: - Local Placeholder Writer

/// Safe stand-in for a future on-device model. No network, no model runtime.
struct LocalPlaceholderHostBriefingWriter: HostBriefingWriter {
  func writeBriefing(
    packet: HostLLMPacket,
    fallbackText: String
  ) async -> HostBriefingWriterResult {
    let text = Self.buildPlaceholderText(packet: packet, fallbackText: fallbackText)
    if text == fallbackText {
      return HostBriefingWriterResult(text: fallbackText, source: .template, failedReason: nil)
    }
    return HostBriefingWriterResult(
      text: text,
      source: .localPlaceholder,
      failedReason: nil
    )
  }

  static func buildPlaceholderText(
    packet: HostLLMPacket,
    fallbackText: String
  ) -> String {
    guard !packet.topFacts.isEmpty else {
      return fallbackText
    }

    let service = HostBriefingService()
    let facts = packet.topFacts.map { fact in
      HostBriefingFact(
        id: "placeholder-\(fact.category.rawValue)-\(fact.title)",
        severity: fact.severity,
        category: fact.category,
        title: fact.title,
        detail: fact.detail,
        evidence: fact.evidence,
        relatedReservationIDs: [],
        suggestedActionTitle: fact.suggestedAction
      )
    }
    return service.buildTemplateBriefingFallback(
      from: facts,
      serviceState: packet.serviceState
    )
  }
}

// MARK: - Local Model Writer

/// On-device llama.cpp briefing writer. Consumes `HostLLMPacket` only via prompt builder.
/// A real inference backend must validate output and fall back to the template briefing.
/// It must never receive raw reservation records or unsanitized notes.
struct LocalModelHostBriefingWriter: HostBriefingWriter {

  func writeBriefing(
    packet: HostLLMPacket,
    fallbackText: String
  ) async -> HostBriefingWriterResult {
    // Empty packet uses deterministic template; local model inference would add no value.
    if packet.topFacts.isEmpty {
      HostBriefingWriterDiagnostics.recordEmptyPacketSkip()
      return HostBriefingWriterResult(
        text: fallbackText,
        source: .template,
        failedReason: nil
      )
    }

    if HostBriefingHostBoardGate.shouldUseTemplateOnlyOnHostBoard(packet: packet)
      || Self.shouldUseTemplateForLowRiskSingleFact(packet) {
      HostBriefingWriterDiagnostics.recordLowRiskSingleFactSkip()
      return HostBriefingWriterResult(
        text: fallbackText,
        source: .template,
        failedReason: nil
      )
    }

    HostBriefingWriterDiagnostics.prepareForInference()
    HostLocalModelInferenceTracker.begin()
    defer { HostLocalModelInferenceTracker.end() }

    // Use the best available profile so the 3B model is preferred over the 0.5B
    // when it is bundled (iPad/demo build), without breaking debug builds that
    // only have the 0.5B model available.
    let readiness = HostLocalModelReadinessProvider.currentReadiness()

    switch readiness.status {
    case .runtimeMissing:
      return Self.fallbackResult(
        fallbackText: fallbackText,
        reason: HostLocalModelRuntimeError.runtimeUnavailable.errorDescription
          ?? "Local model runtime is not installed."
      )
    case .modelMissing:
      return Self.fallbackResult(
        fallbackText: fallbackText,
        reason: HostLocalModelRuntimeError.modelMissing.errorDescription
          ?? "Local briefing model file is not installed."
      )
    case .unavailable:
      return Self.fallbackResult(
        fallbackText: fallbackText,
        reason: HostLocalModelReadiness.unavailable.detail
      )
    case .ready:
      break
    }

    let prompt = HostLLMPacketPromptBuilder.buildPrompt(from: packet)
    let runtime = HostLocalModelRuntimeFactory.makeRuntime()

    do {
      let generated = try await runtime.generateBriefing(prompt: prompt)
      HostBriefingWriterDiagnostics.storeCandidate(generated)

      let validation = HostBriefingWriterValidator.validationResult(
        generated,
        packet: packet,
        fallbackText: fallbackText
      )

      if validation.isValid {
        HostBriefingWriterDiagnostics.recordValidationSuccess(generated: generated)
        return HostBriefingWriterResult(
          text: generated,
          source: .localModel,
          failedReason: nil
        )
      }

      if HostBriefingWriterValidator.exceedsSentenceLimit(generated) {
        let trimmed = HostBriefingWriterValidator.trimToAllowedSentenceCount(generated)
        let trimmedValidation = HostBriefingWriterValidator.validationResult(
          trimmed,
          packet: packet,
          fallbackText: fallbackText
        )
        if trimmedValidation.isValid {
          HostBriefingWriterDiagnostics.recordValidationSuccess(
            generated: generated,
            repaired: trimmed
          )
          return HostBriefingWriterResult(
            text: trimmed,
            source: .localModel,
            failedReason: nil
          )
        }
      }

      HostBriefingWriterDiagnostics.recordValidationFailure(
        generated: generated,
        reason: validation.reason
      )
      return Self.fallbackResult(
        fallbackText: fallbackText,
        reason: validation.reason ?? "Briefing validation failed."
      )
    } catch let error as HostLocalModelRuntimeError {
      HostBriefingWriterDiagnostics.recordRuntimeFailure()
      return Self.fallbackResult(
        fallbackText: fallbackText,
        reason: error.errorDescription ?? "Local model failed."
      )
    } catch {
      HostBriefingWriterDiagnostics.recordRuntimeFailure()
      return Self.fallbackResult(
        fallbackText: fallbackText,
        reason: error.localizedDescription
      )
    }
  }

  static func previewFallbackResult(
    fallbackText: String,
    packet: HostLLMPacket
  ) -> HostBriefingWriterResult {
    _ = packet
    let readiness = HostLocalModelReadinessProvider.currentReadiness()

    switch readiness.status {
    case .runtimeMissing:
      return fallbackResult(
        fallbackText: fallbackText,
        reason: HostLocalModelRuntimeError.runtimeUnavailable.errorDescription
          ?? "Local model runtime is not installed."
      )
    case .modelMissing:
      return fallbackResult(
        fallbackText: fallbackText,
        reason: HostLocalModelRuntimeError.modelMissing.errorDescription
          ?? "Local briefing model file is not installed."
      )
    case .unavailable:
      return fallbackResult(
        fallbackText: fallbackText,
        reason: HostLocalModelReadiness.unavailable.detail
      )
    case .ready:
      return fallbackResult(
        fallbackText: fallbackText,
        reason: "Preview only — inference not run from diagnostics."
      )
    }
  }

  private static func fallbackResult(
    fallbackText: String,
    reason: String
  ) -> HostBriefingWriterResult {
    HostBriefingWriterResult(
      text: fallbackText,
      source: .failedFallback,
      failedReason: reason
    )
  }

  static func shouldUseTemplateForLowRiskSingleFact(_ packet: HostLLMPacket) -> Bool {
    HostBriefingHostBoardGate.shouldPreferDeterministicHostSummary(packet: packet)
  }
}

// MARK: - Validation

struct HostBriefingValidationResult: Equatable {
  let isValid: Bool
  let reason: String?
}

enum HostBriefingWriterValidator {
  private static let firstPersonExecutionPhrases = [
    "i confirmed",
    "i cancelled",
    "i canceled",
    "i assigned",
    "i seated",
    "i emailed",
    "we confirmed",
    "we cancelled",
    "we canceled",
    "we assigned",
    "we seated",
    "we emailed",
    "reservation has been",
    "table has been"
  ]

  private static let certaintyPhrases = [
    "guaranteed",
    "definitely",
    "for sure",
    "will happen"
  ]

  private static let unsupportedActionPhrases = [
    "automatically",
    "auto-confirmed",
    "auto cancelled",
    "auto canceled"
  ]

  private static let completedReviewPhrases = [
    "has been reviewed",
    "have been reviewed",
    "already reviewed",
    "reviewed and",
    "review complete"
  ]

  private static let assignmentPhrases = [
    "has been assigned",
    "have been assigned",
    "is assigned",
    "table assigned",
    "assigned to table",
    "we assigned",
    "i assigned"
  ]

  private static let confirmationCompletionPhrases = [
    "has been confirmed",
    "have been confirmed",
    "is confirmed",
    "confirmed already",
    "has been completed",
    "completed already",
    "marked no-show",
    "has been seated",
    "is seated"
  ]

  private static let resolutionPhrases = [
    "no changes needed",
    "nothing to do",
    "all set",
    "resolved",
    "handled",
    "taken care of"
  ]

  private static let semanticFailureReasons = [
    "Briefing claims an action was already completed.",
    "Briefing says no action is needed despite packet facts.",
    "Briefing suggests unsupported guest contact.",
    "Briefing gives unsafe special-occasion instruction.",
    "Briefing exposes internal system or model language.",
    "Briefing uses pressure language for quiet service.",
    "Briefing claims a table is missing when effective table is assigned.",
    "Briefing claims table assigned when effective table is missing.",
    "Briefing uses the wrong reservation count."
  ]

  private static let metaPhrases = [
    "language model",
    "llm packet",
    "ai model",
    "the model",
    "our model",
    "backend intelligence",
    "backend json",
    "evidence array",
    "debug output",
    "as an ai",
    "as a model",
    "approved facts",
    "writing rules",
    "forbidden behavior"
  ]

  private static let noTableClaimPhrases = [
    "needs table",
    "needs a table",
    "need tables",
    "no table",
    "without table",
    "without tables",
    "no table picked",
    "still need tables",
    "still needs a table"
  ]

  private static let quietBlockedPressurePhrases = [
    "pressure builds",
    "arrival pressure",
    "peak window",
    "wave",
    "capacity pressure",
    "critical slot",
    "optimize"
  ]

  private static let unsafeSpecialOccasionPhrases = [
    "mention the occasion at arrival",
    "mention the occasion",
    "celebrate the occasion",
    "celebrate with the guest",
    "tell the guest happy",
    "wish the guest happy",
    "wish them happy",
    "announce the occasion"
  ]

  static let maxAllowedSentences = 2
  private static let maxLength = 500
  private static let maxSentences = maxAllowedSentences
  private static let maxExclamationMarks = 2

  static func sentenceCount(in text: String) -> Int {
    text
      .split(whereSeparator: { ".!?".contains($0) })
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .count
  }

  static func exceedsSentenceLimit(_ text: String) -> Bool {
    sentenceCount(in: text) > maxSentences
  }

  static func trimToAllowedSentenceCount(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard exceedsSentenceLimit(trimmed) else { return trimmed }

    var result = ""
    var sentenceCount = 0
    var sentenceStart = trimmed.startIndex

    for index in trimmed.indices {
      let character = trimmed[index]
      guard ".!?".contains(character) else { continue }

      let end = trimmed.index(after: index)
      let sentence = String(trimmed[sentenceStart..<end])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !sentence.isEmpty else {
        sentenceStart = end
        continue
      }

      if !result.isEmpty {
        result += " "
      }
      result += sentence
      sentenceCount += 1
      if sentenceCount >= maxSentences {
        return result
      }
      sentenceStart = end
    }

    if sentenceCount < maxSentences, sentenceStart < trimmed.endIndex {
      let remainder = String(trimmed[sentenceStart...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !remainder.isEmpty {
        if !result.isEmpty {
          result += " "
        }
        result += remainder
      }
    }

    return result
  }

  static func validate(
    _ text: String,
    packet: HostLLMPacket,
    fallbackText: String? = nil
  ) -> Bool {
    validationResult(text, packet: packet, fallbackText: fallbackText).isValid
  }

  static func validationResult(
    _ text: String,
    packet: HostLLMPacket,
    fallbackText: String? = nil
  ) -> HostBriefingValidationResult {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return HostBriefingValidationResult(isValid: false, reason: "Briefing text is empty.")
    }

    guard trimmed.count <= maxLength else {
      return HostBriefingValidationResult(
        isValid: false,
        reason: "Briefing text exceeds \(maxLength) characters."
      )
    }

    if let reason = groundingFailureReason(for: trimmed, grounding: packet.serviceGrounding) {
      return HostBriefingValidationResult(isValid: false, reason: reason)
    }

    if trimmed == packet.serviceGrounding?.deterministicSummary {
      return HostBriefingValidationResult(isValid: true, reason: nil)
    }

    let sentenceCount = trimmed
      .split(whereSeparator: { ".!?".contains($0) })
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .count
    guard sentenceCount <= maxSentences else {
      return HostBriefingValidationResult(
        isValid: false,
        reason: "Briefing text exceeds \(maxSentences) sentences."
      )
    }

    let exclamationCount = trimmed.filter { $0 == "!" }.count
    guard exclamationCount <= maxExclamationMarks else {
      return HostBriefingValidationResult(
        isValid: false,
        reason: "Briefing text contains too many exclamation marks."
      )
    }

    if packet.topFacts.isEmpty, let fallbackText {
      let normalizedFallback = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed != normalizedFallback {
        return HostBriefingValidationResult(
          isValid: false,
          reason: "Enhanced output must match template when no packet facts are available."
        )
      }
    }

    let lower = trimmed.lowercased()
    for phrase in firstPersonExecutionPhrases where lower.contains(phrase) {
      return HostBriefingValidationResult(
        isValid: false,
        reason: "Briefing text contains a forbidden execution claim."
      )
    }

    for phrase in certaintyPhrases where lower.contains(phrase) {
      return HostBriefingValidationResult(
        isValid: false,
        reason: "Briefing text contains unsafe certainty language."
      )
    }

    for phrase in unsupportedActionPhrases where lower.contains(phrase) {
      return HostBriefingValidationResult(
        isValid: false,
        reason: "Briefing text contains unsupported automatic action language."
      )
    }

    for phrase in metaPhrases where lower.contains(phrase) {
      return HostBriefingValidationResult(
        isValid: false,
        reason: "Briefing exposes internal system or model language."
      )
    }

    if let semanticFailure = semanticValidationFailure(for: lower, packet: packet) {
      return semanticFailure
    }

    return HostBriefingValidationResult(isValid: true, reason: nil)
  }

  static func groundingFailureReason(
    for text: String,
    grounding: HostServiceGroundingSummary?
  ) -> String? {
    guard let grounding else { return nil }
    let lower = text.lowercased()

    if grounding.isQuietService,
       quietBlockedPressurePhrases.contains(where: { lower.contains($0) }) {
      return "Briefing uses pressure language for quiet service."
    }

    if grounding.allRelevantReservationsHaveTables,
       noTableClaimPhrases.contains(where: { lower.contains($0) }) {
      return "Briefing claims a table is missing when effective table is assigned."
    }

    if grounding.effectiveNoTableCount > 0,
       lower.contains("table assigned") {
      return "Briefing claims table assigned when effective table is missing."
    }

    if grounding.activeReservationCount == 1,
       lower.range(of: #"(?<!\d)[2-9]\s+reservations\b"#, options: .regularExpression) != nil {
      return "Briefing uses the wrong reservation count."
    }

    if grounding.activeReservationCount != 1,
       lower.contains("1 reservation") {
      return "Briefing uses the wrong reservation count."
    }

    return nil
  }

  static func isSemanticFailureReason(_ reason: String?) -> Bool {
    guard let reason else { return false }
    return semanticFailureReasons.contains(reason)
  }

  static func packetSupportsActionPhrase(_ phrase: String, packet: HostLLMPacket) -> Bool {
    let needle = phrase.lowercased()
    guard !needle.isEmpty else { return false }

    let corpus = packetActionCorpus(packet)
    return corpus.contains(needle)
  }

  static func packetSupportsConfirmAvailability(_ packet: HostLLMPacket) -> Bool {
    let corpus = packetActionCorpus(packet)
    return corpus.contains("confirm")
      && (corpus.contains("availability") || corpus.contains("available"))
  }

  private static func packetActionCorpus(_ packet: HostLLMPacket) -> String {
    packet.topFacts
      .flatMap { fact -> [String] in
        [fact.title, fact.detail, fact.suggestedAction ?? ""]
      }
      .joined(separator: " ")
      .lowercased()
  }

  private static func semanticValidationFailure(
    for lower: String,
    packet: HostLLMPacket
  ) -> HostBriefingValidationResult? {
    for phrase in completedReviewPhrases + assignmentPhrases + confirmationCompletionPhrases
      where lower.contains(phrase) {
      return HostBriefingValidationResult(
        isValid: false,
        reason: "Briefing claims an action was already completed."
      )
    }

    if !packet.topFacts.isEmpty {
      for phrase in resolutionPhrases where lower.contains(phrase) {
        return HostBriefingValidationResult(
          isValid: false,
          reason: "Briefing says no action is needed despite packet facts."
        )
      }
    }

    if lower.contains("confirm guest availability")
      || lower.contains("confirm the guest's availability")
      || lower.contains("confirm guest's availability")
      || (lower.contains("confirm") && lower.contains("availability")) {
      if !packetSupportsConfirmAvailability(packet) {
        return HostBriefingValidationResult(
          isValid: false,
          reason: "Briefing suggests unsupported guest contact."
        )
      }
    }

    if lower.contains("call the guest")
      || (lower.contains("call") && lower.contains("guest")) {
      if !packetSupportsActionPhrase("call", packet: packet)
        && !packetSupportsActionPhrase("review-call", packet: packet) {
        return HostBriefingValidationResult(
          isValid: false,
          reason: "Briefing suggests unsupported guest contact."
        )
      }
    }

    if lower.contains("email the guest")
      || (lower.contains("email") && lower.contains("guest")) {
      if !packetSupportsActionPhrase("email", packet: packet)
        && !packetSupportsActionPhrase("generate-email", packet: packet) {
        return HostBriefingValidationResult(
          isValid: false,
          reason: "Briefing suggests unsupported guest contact."
        )
      }
    }

    if unsafeSpecialOccasionPhrases.contains(where: { lower.contains($0) }) {
      if !packetSupportsDirectOccasionInstruction(packet) {
        return HostBriefingValidationResult(
          isValid: false,
          reason: "Briefing gives unsafe special-occasion instruction."
        )
      }
    }

    return nil
  }

  private static func packetSupportsDirectOccasionInstruction(_ packet: HostLLMPacket) -> Bool {
    let corpus = packetActionCorpus(packet)
    return unsafeSpecialOccasionPhrases.contains(where: { corpus.contains($0) })
  }
}

// MARK: - Debug Formatting

enum HostLLMPacketDebugFormatter {
  static func debugSummary(from packet: HostLLMPacket) -> String {
    var lines: [String] = [
      "Service state: \(packet.serviceState.rawValue)",
      "Pressure score: \(Int(packet.pressureScore.rounded()))",
      "Generated at: \(packet.generatedAtDescription)"
    ]

    if packet.topFacts.isEmpty {
      lines.append("Top facts: none")
    } else {
      lines.append("Top facts:")
      for fact in packet.topFacts.prefix(5) {
        var factLine = "- [\(fact.severity.rawValue)/\(fact.category.rawValue)] \(fact.title)"
        let detail = fact.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty {
          factLine += ": \(detail)"
        }
        if let action = fact.suggestedAction?.trimmingCharacters(in: .whitespacesAndNewlines),
           !action.isEmpty {
          factLine += " (action: \(action))"
        }
        lines.append(factLine)
      }
    }

    if !packet.forbiddenBehaviors.isEmpty {
      lines.append("Forbidden behaviors:")
      packet.forbiddenBehaviors.forEach { lines.append("- \($0)") }
    }

    if !packet.writingRules.isEmpty {
      lines.append("Writing rules:")
      packet.writingRules.forEach { lines.append("- \($0)") }
    }

    return lines.joined(separator: "\n")
  }
}

// MARK: - Host Board Context & Gate

struct HostBriefingHostBoardContext: Equatable {
  var selectedDateKey: String = ""
  var floorSourceLabel: String = ""
  var layoutFingerprint: String = ""
  var guestIntelligenceGeneration: String = ""
  var isStartupNetworkPassInFlight: Bool
  var isHistoryPrefetching: Bool
  var isLocalModelInferenceActive: Bool
  var isReservationRefreshInFlight: Bool
  var isAvailabilitySummaryLoading: Bool
  var isGuestIntelligenceLoading: Bool = false
  var hostBoardDateNavigationAt: Date?
  var startupUIReleasedAt: Date?
  var now: Date

  var isEnrichmentLoading: Bool {
    isAvailabilitySummaryLoading || isGuestIntelligenceLoading
  }

  var enrichmentCompletionState: String {
    isEnrichmentLoading ? "loading" : "complete"
  }
}

@MainActor
enum HostLocalModelWarmthTracker {
  private(set) static var isWarm = false

  static func markWarm() {
    isWarm = true
  }

  static func reset() {
    isWarm = false
  }
}

enum HostBoardOperationalCategory: String, CaseIterable {
  case lateNoTable
  case unresolvedLateCleanup
  case longSeated
  case operationalTension
  case futureTablePlanning
  case guestNoteOccasion
  case seenBeforeRegular
  case capacityTableMismatch
  case servicePressure

  var traceLabel: String {
    switch self {
    case .lateNoTable: return "overdue"
    case .unresolvedLateCleanup: return "cleanup"
    case .longSeated: return "longSeated"
    case .operationalTension: return "operationalTension"
    case .futureTablePlanning: return "futurePlanning"
    case .guestNoteOccasion: return "guestNote"
    case .seenBeforeRegular: return "seenBefore"
    case .capacityTableMismatch: return "tableMismatch"
    case .servicePressure: return "pressure"
    }
  }
}

enum HostDateGateTrace {
  static func log(
    selectedDate: String,
    stable: Bool,
    remainingMs: Int,
    decision: String
  ) {
    #if DEBUG
    print(
      "[HOST_DATE_GATE_TRACE] selected=\(selectedDate) stable=\(stable) remainingMs=\(remainingMs) decision=\(decision)"
    )
    #endif
  }
}

enum HostEnrichmentGateTrace {
  static func log(
    floor: String,
    guestIntel: String,
    availability: String,
    dateStable: Bool,
    decision: String
  ) {
    #if DEBUG
    print(
      "[HOST_ENRICHMENT_GATE_TRACE] floor=\(floor) guestIntel=\(guestIntel) availability=\(availability) dateStable=\(dateStable) decision=\(decision)"
    )
    #endif
  }
}

@MainActor
enum HostBoardModelDecisionTrace {
  struct Snapshot: Equatable {
    var decision: String
    var skipReason: String?
    var packetCategories: String
    var complexityScore: Int
    var aiWorthy: Bool
    var aiWorthyReason: String
    var lastLiveModelRunAt: Date?
    var lastVisibleSource: String
    var lastModelDurationMs: Int?
    var lastRejectionReason: String?
    var enrichmentLoading: Bool
  }

  private(set) static var latest: Snapshot?

  static func record(
    allowed: Bool,
    skipReason: HostBriefingHostBoardGate.SkipReason?,
    packet: HostLLMPacket,
    enrichmentLoading: Bool,
    visibleSource: String? = nil,
    modelRunAt: Date? = nil,
    modelEligibleReason: String? = nil
  ) {
    let categories = HostBriefingHostBoardGate.operationalCategories(for: packet)
    let categoryLabels = categories.map(\.traceLabel).sorted().joined(separator: ",")
    let aiWorthy = HostBriefingHostBoardGate.hasOperationalTension(packet: packet)
    let gateReason = HostBriefingHostBoardGate.gateReason(
      allowed: allowed,
      skipReason: skipReason,
      packet: packet,
      modelEligibleReason: modelEligibleReason
    )
    latest = Snapshot(
      decision: allowed ? "Used" : "Skipped",
      skipReason: skipReason?.rawValue,
      packetCategories: categoryLabels,
      complexityScore: HostBriefingHostBoardGate.complexityScore(for: packet),
      aiWorthy: aiWorthy,
      aiWorthyReason: gateReason,
      lastLiveModelRunAt: modelRunAt ?? latest?.lastLiveModelRunAt,
      lastVisibleSource: visibleSource ?? latest?.lastVisibleSource ?? "template",
      lastModelDurationMs: latest?.lastModelDurationMs,
      lastRejectionReason: latest?.lastRejectionReason,
      enrichmentLoading: enrichmentLoading
    )
    HostBriefingHostBoardGate.logGateDecision(
      allowed: allowed,
      reason: gateReason,
      packet: packet,
      enrichmentLoading: enrichmentLoading
    )
  }

  static func recordVisibleSource(_ source: String, modelRunAt: Date? = nil) {
    guard var snapshot = latest else { return }
    snapshot.lastVisibleSource = source
    if let modelRunAt {
      snapshot.lastLiveModelRunAt = modelRunAt
    }
    latest = snapshot
  }

  static func recordModelDuration(_ durationMs: Int) {
    guard var snapshot = latest else { return }
    snapshot.lastModelDurationMs = durationMs
    latest = snapshot
  }

  static func recordRejectionReason(_ reason: String?) {
    guard var snapshot = latest else { return }
    snapshot.lastRejectionReason = reason
    latest = snapshot
  }
}

enum HostBriefingHostBoardGate {
  static let stabilizationDelay: TimeInterval = 20
  static let minimumOperationalCategoriesForModel = 2

  enum SkipReason: String {
    case host_board_gate_off
    case host_board_template_only
    case model_not_ready
    case startup_in_flight
    case reservation_refresh_in_flight
    case enrichment_loading
    case date_navigation
    case local_model_in_flight
    case stabilization_delay
    case no_meaningful_facts
  }

  static let dateNavigationCooldown: TimeInterval = 4

  static func shouldUseTemplateOnlyOnHostBoard(packet: HostLLMPacket) -> Bool {
    packet.isHostBoardTemplateOnlyPacket
      || shouldPreferDeterministicHostSummary(packet: packet)
  }

  /// Template-only unless the packet has real operational tension.
  static func shouldPreferDeterministicHostSummary(packet: HostLLMPacket) -> Bool {
    guard packet.hasMeaningfulBriefingFacts else { return true }
    return !hasOperationalTension(packet: packet)
  }

  static func hasOperationalTension(packet: HostLLMPacket) -> Bool {
    if packet.topFacts.contains(where: { fact in
      fact.evidence.contains { $0.lowercased().hasPrefix("operationaltension=") }
    }) {
      return true
    }

    let categories = operationalCategories(for: packet)
    if categories.contains(.operationalTension) {
      return true
    }
    if categories.contains(.lateNoTable), categories.contains(.longSeated) {
      return true
    }
    if categories.contains(.lateNoTable), categories.contains(.unresolvedLateCleanup) {
      return true
    }
    if categories.contains(.lateNoTable),
       categories.contains(.capacityTableMismatch) || categories.contains(.servicePressure) {
      return true
    }
    if categories.contains(.capacityTableMismatch), categories.contains(.servicePressure) {
      return true
    }
    // Guest notes (dietary, occasion, preference) + unassigned tables during live service
    // are independently significant together — the model should synthesize a briefing.
    if categories.contains(.capacityTableMismatch), categories.contains(.guestNoteOccasion) {
      return true
    }

    let operationalThemes: Set<HostBoardOperationalCategory> = [
      .lateNoTable,
      .unresolvedLateCleanup,
      .longSeated,
      .operationalTension,
      .capacityTableMismatch,
      .servicePressure
    ]
    return categories.intersection(operationalThemes).count >= 2
  }

  static func gateReason(
    allowed: Bool,
    skipReason: SkipReason?,
    packet: HostLLMPacket,
    modelEligibleReason: String? = nil
  ) -> String {
    if allowed {
      if let modelEligibleReason, !modelEligibleReason.isEmpty {
        return modelEligibleReason
      }
      return hasOperationalTension(packet: packet) ? "operational_tension" : "complex_packet"
    }
    if skipReason == .host_board_template_only {
      return "independent_simple_facts"
    }
    return skipReason?.rawValue ?? "unknown"
  }

  static func operationalCategories(for packet: HostLLMPacket) -> Set<HostBoardOperationalCategory> {
    var categories = Set<HostBoardOperationalCategory>()
    for fact in packet.topFacts {
      classifyOperationalCategory(for: fact, into: &categories)
    }
    return categories
  }

  static func complexityScore(for packet: HostLLMPacket) -> Int {
    let categories = operationalCategories(for: packet)
    var score = categories.count * 10
    score += min(packet.topFacts.count, 5)
    if packet.topFacts.contains(where: { $0.severity == .critical }) {
      score += 5
    }
    if packet.topFacts.contains(where: { $0.severity == .warning }) {
      score += 3
    }
    return score
  }

  @MainActor
  static func shouldUseLocalModelOnHostBoard(
    settings: HostIntelligenceSettings,
    context: HostBriefingHostBoardContext,
    packet: HostLLMPacket,
    modelEligibleReason: String? = nil
  ) -> Bool {
    localModelSkipReason(
      settings: settings,
      context: context,
      packet: packet,
      modelEligibleReason: modelEligibleReason
    ) == nil
  }

  @MainActor
  static func localModelSkipReason(
    settings: HostIntelligenceSettings,
    context: HostBriefingHostBoardContext,
    packet: HostLLMPacket,
    modelEligibleReason: String? = nil
  ) -> SkipReason? {
    guard settings.useEnhancedBriefing else { return .host_board_gate_off }
    guard settings.enhancedBriefingProvider == .localModel else { return .host_board_gate_off }
    guard settings.useLocalModelOnHostBoard else { return .host_board_gate_off }
    guard packet.hasMeaningfulBriefingFacts else { return .no_meaningful_facts }
    if modelEligibleReason == nil,
       shouldUseTemplateOnlyOnHostBoard(packet: packet) {
      return .host_board_template_only
    }
    // Use the best available profile so the 3B model is recognized as ready when
    // it is bundled (iPad/demo build), even when the 0.5B file is absent.
    if HostLocalModelReadinessProvider.currentReadiness().status != .ready {
      return .model_not_ready
    }
    if context.isStartupNetworkPassInFlight { return .startup_in_flight }
    if context.isReservationRefreshInFlight { return .reservation_refresh_in_flight }
    let dateRemainingMs = dateNavigationRemainingMs(context: context)
    let dateStable = dateRemainingMs == 0
    HostDateGateTrace.log(
      selectedDate: context.selectedDateKey,
      stable: dateStable,
      remainingMs: dateRemainingMs,
      decision: dateStable ? "allow" : "block"
    )
    let availabilityState = context.isAvailabilitySummaryLoading ? "loading" : "fresh"
    let guestIntelState = context.isGuestIntelligenceLoading ? "loading" : "fresh"
    HostEnrichmentGateTrace.log(
      floor: context.floorSourceLabel,
      guestIntel: guestIntelState,
      availability: availabilityState,
      dateStable: dateStable,
      decision: context.isEnrichmentLoading ? "block" : "allow"
    )
    if context.isEnrichmentLoading { return .enrichment_loading }
    if !dateStable {
      return .date_navigation
    }
    if context.isLocalModelInferenceActive,
       HostLocalModelInferenceTracker.blocksHostBoardNarrative {
      return .local_model_in_flight
    }
    guard let releasedAt = context.startupUIReleasedAt else { return .stabilization_delay }
    if context.now.timeIntervalSince(releasedAt) < stabilizationDelay {
      return .stabilization_delay
    }
    return nil
  }

  private static func dateNavigationRemainingMs(context: HostBriefingHostBoardContext) -> Int {
    guard let navigationAt = context.hostBoardDateNavigationAt else { return 0 }
    let remaining = max(0, dateNavigationCooldown - context.now.timeIntervalSince(navigationAt))
    return Int((remaining * 1000).rounded(.up))
  }

  static func logGateDecision(
    allowed: Bool,
    reason: String,
    packet: HostLLMPacket,
    enrichmentLoading: Bool
  ) {
    #if DEBUG
    let categories = operationalCategories(for: packet)
    let categoryTrace = categories.map(\.traceLabel).sorted().joined(separator: ",")
    let categorySuffix = categoryTrace.isEmpty ? "" : " categories=\(categoryTrace)"
    print(
      "[HOST_AI_GATE] surface=hostBoard allowed=\(allowed) reason=\(reason)\(categorySuffix) enrichmentLoading=\(enrichmentLoading)"
    )
    if !categoryTrace.isEmpty {
      print(
        "[HOST_AI_GATE] categories=\(categoryTrace) count=\(categories.count) complexityScore=\(complexityScore(for: packet))"
      )
    }
    #endif
  }

  private static func classifyOperationalCategory(
    for fact: HostLLMFact,
    into categories: inout Set<HostBoardOperationalCategory>
  ) {
    let evidence = fact.evidence.joined(separator: " ").lowercased()
    let title = fact.title.lowercased()
    let detail = fact.detail.lowercased()

    let isFuturePlanning = evidence.contains("selecteddate=") && detail.contains("before service")
      || (fact.category == .table && title.contains("still need tables") && detail.contains("before service"))
    if isFuturePlanning {
      categories.insert(.futureTablePlanning)
      return
    }

    if evidence.contains("operationaltension=true")
        || title.contains("check table status before resolving") {
      categories.insert(.operationalTension)
    }
    if evidence.contains("notable=true") || title.contains("late reservation still has no table") {
      categories.insert(.lateNoTable)
    }
    if evidence.contains("unresolvedlatecleanup=true") || title.contains("resolve late reservation") {
      categories.insert(.unresolvedLateCleanup)
    }
    if title.contains("possible missed completion")
        || title.contains("check table status")
        || evidence.contains("missedcompletion=true")
        || evidence.contains("seatedcompletiongrace=true")
        || (fact.category == .timing && evidence.contains("elapsedminutes=") && evidence.contains("seated=true")) {
      categories.insert(.longSeated)
    }

    switch fact.category {
    case .allergy, .note, .preference:
      categories.insert(.guestNoteOccasion)
    case .guest:
      if title.contains("seen before") || title.contains("regular")
          || title.contains("returning") || title.contains("vip") {
        categories.insert(.seenBeforeRegular)
      } else {
        categories.insert(.guestNoteOccasion)
      }
    case .table, .capacity, .largeParty:
      categories.insert(.capacityTableMismatch)
    case .arrivalWave, .analytics:
      categories.insert(.servicePressure)
    default:
      break
    }
  }
}

enum HostIntelligenceDiagnostics {
  static func skipLocalModel(reason: String) {
    #if DEBUG
    print("[HOST_AI] local model skipped: \(localModelSkipLabel(for: reason))")
    #endif
  }

  static func skipBriefing(reason: String) {
    #if DEBUG
    print("[HOST_AI] briefing skipped: \(briefingSkipLabel(for: reason))")
    #endif
  }

  static func localModelAttempted(surface: String) {
    #if DEBUG
    print("[HOST_AI] host board local model attempted surface=\(surface)")
    #endif
  }

  static func localModelFallback(reason: String) {
    #if DEBUG
    print("[HOST_AI] local model fallback: \(reason)")
    #endif
  }

  static func modelOutputUsed(source: String) {
    #if DEBUG
    print("[HOST_AI] model_output_used source=\(source)")
    #endif
  }

  static func modelOutputRejected(reason: String) {
    #if DEBUG
    print("[HOST_AI] model_output_rejected reason=\(reason)")
    #endif
  }

  static func repairedOutputUsed(labelsRemoved: Bool) {
    #if DEBUG
    print("[HOST_AI] repaired_output_used labelsRemoved=\(labelsRemoved)")
    #endif
  }

  private static func localModelSkipLabel(for reason: String) -> String {
    switch reason {
    case "host_board_gate_off":
      return "enhanced briefing off, provider not local model, or Host board local model disabled"
    case "host_board_template_only":
      return "host board template-only because simple operational facts are clearer as deterministic copy"
    case "model_not_ready", "model_cold":
      return "local model is not ready yet"
    case "startup_in_flight":
      return "startup reservation refresh still in flight"
    case "reservation_refresh_in_flight":
      return "reservation refresh still in flight"
    case "enrichment_loading":
      return "guest or availability enrichment is still loading"
    case "date_navigation":
      return "host date navigation still settling"
    case "local_model_in_flight":
      return "another local model inference is active"
    case "stabilization_delay":
      return "waiting for post-startup stabilization window"
    case "no_meaningful_facts":
      return "no meaningful briefing facts in packet"
    default:
      return reason
    }
  }

  private static func briefingSkipLabel(for reason: String) -> String {
    switch reason {
    case "same_packet":
      return "packet unchanged since last briefing"
    default:
      return reason
    }
  }
}

// MARK: - Factory

enum HostBriefingWriterFactory {
  static func effectiveProvider(
    requested: HostBriefingProviderKind,
    settings: HostIntelligenceSettings,
    forHostBoard: Bool,
    hostBoardAllowsLocalModel: Bool = true
  ) -> HostBriefingProviderKind {
    guard settings.useEnhancedBriefing else { return .template }

    if forHostBoard, requested == .localModel {
      if !settings.useLocalModelOnHostBoard || !hostBoardAllowsLocalModel {
        return .template
      }
    }

    return requested
  }

  static func writer(for provider: HostBriefingProviderKind) -> HostBriefingWriter {
    switch provider {
    case .template:
      return TemplateHostBriefingWriter()
    case .localPlaceholder:
      return LocalPlaceholderHostBriefingWriter()
    case .localModel:
      return LocalModelHostBriefingWriter()
    }
  }
}
