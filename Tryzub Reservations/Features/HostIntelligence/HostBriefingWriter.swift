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
enum HostBriefingWriterDiagnostics {
  nonisolated(unsafe) static var lastGeneratedCandidate: String?
  nonisolated(unsafe) static var lastRepairedOutput: String?
  nonisolated(unsafe) static var lastValidationFailureReason: String?
  nonisolated(unsafe) static var lastSemanticValidationFailureReason: String?
  nonisolated(unsafe) static var inferenceSkippedBecauseNoFacts = false
  nonisolated(unsafe) static var inferenceSkippedBecauseLowRiskSingleFact = false

  private static let maxCandidateLength = 500

  static func storeCandidate(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    lastGeneratedCandidate = trimmed.count <= maxCandidateLength
      ? trimmed
      : String(trimmed.prefix(maxCandidateLength))
  }

  static func recordEmptyPacketSkip() {
    lastGeneratedCandidate = nil
    lastRepairedOutput = nil
    lastValidationFailureReason = nil
    lastSemanticValidationFailureReason = nil
    inferenceSkippedBecauseNoFacts = true
    inferenceSkippedBecauseLowRiskSingleFact = false
    HostLlamaBriefingRuntimeDiagnostics.lastRun = HostLlamaRunDiagnostics()
  }

  static func recordLowRiskSingleFactSkip() {
    lastGeneratedCandidate = nil
    lastRepairedOutput = nil
    lastValidationFailureReason = nil
    lastSemanticValidationFailureReason = nil
    inferenceSkippedBecauseNoFacts = false
    inferenceSkippedBecauseLowRiskSingleFact = true
    HostLlamaBriefingRuntimeDiagnostics.lastRun = HostLlamaRunDiagnostics()
  }

  static func prepareForInference() {
    inferenceSkippedBecauseNoFacts = false
    inferenceSkippedBecauseLowRiskSingleFact = false
  }

  static func recordValidationSuccess(generated: String, repaired: String? = nil) {
    storeCandidate(generated)
    lastRepairedOutput = repaired
    lastValidationFailureReason = nil
    lastSemanticValidationFailureReason = nil
  }

  static func recordValidationFailure(generated: String, reason: String?) {
    storeCandidate(generated)
    lastRepairedOutput = nil
    lastValidationFailureReason = reason
    lastSemanticValidationFailureReason = HostBriefingWriterValidator.isSemanticFailureReason(reason)
      ? reason
      : nil
  }

  static func recordRuntimeFailure() {
    lastGeneratedCandidate = nil
    lastRepairedOutput = nil
    lastValidationFailureReason = nil
    lastSemanticValidationFailureReason = nil
  }
}

enum HostBriefingWriterSource: String, Equatable {
  case template
  case localPlaceholder
  case localModel
  case failedFallback

  var displayName: String {
    switch self {
    case .template: return "Template"
    case .localPlaceholder: return "Local placeholder"
    case .localModel: return "Local model"
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

    var sentences: [String] = [serviceStateSentence(packet.serviceState)]

    for fact in packet.topFacts {
      guard sentences.count < 4 else { break }

      let detail = fact.detail.trimmingCharacters(in: .whitespacesAndNewlines)
      if !detail.isEmpty {
        sentences.append(detail.hasSuffix(".") ? detail : "\(detail).")
      } else {
        let title = fact.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
          sentences.append(title.hasSuffix(".") ? title : "\(title).")
        }
      }

      if sentences.count < 4,
         let action = fact.suggestedAction?.trimmingCharacters(in: .whitespacesAndNewlines),
         !action.isEmpty {
        sentences.append(action.hasSuffix(".") ? action : "\(action).")
      }
    }

    let text = Array(sentences.prefix(4)).joined(separator: " ")
    return text.isEmpty ? fallbackText : text
  }

  private static func serviceStateSentence(_ state: HostServiceState) -> String {
    switch state {
    case .calm:
      return "Service looks stable."
    case .building:
      return "Service is building."
    case .busy:
      return "Service is busy."
    case .critical:
      return "Service is under heavy pressure."
    }
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

    // Low-risk single-fact packets use deterministic template to avoid model overstatement.
    if Self.shouldUseTemplateForLowRiskSingleFact(packet) {
      HostBriefingWriterDiagnostics.recordLowRiskSingleFactSkip()
      return HostBriefingWriterResult(
        text: fallbackText,
        source: .template,
        failedReason: nil
      )
    }

    HostBriefingWriterDiagnostics.prepareForInference()
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

  private static func shouldUseTemplateForLowRiskSingleFact(_ packet: HostLLMPacket) -> Bool {
    guard packet.topFacts.count == 1, let fact = packet.topFacts.first else {
      return false
    }
    guard packet.serviceState == .calm, packet.pressureScore <= 5 else {
      return false
    }
    guard fact.severity == .info || fact.severity == .watch else {
      return false
    }

    let lowRiskCategories: Set<HostFactCategory> = [
      .preference, .note, .guest, .bookingDecision
    ]
    return lowRiskCategories.contains(fact.category)
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
    "Briefing gives unsafe special-occasion instruction."
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

  static let maxAllowedSentences = 4
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

    if let semanticFailure = semanticValidationFailure(for: lower, packet: packet) {
      return semanticFailure
    }

    return HostBriefingValidationResult(isValid: true, reason: nil)
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

// MARK: - Factory

enum HostBriefingWriterFactory {
  static func effectiveProvider(
    requested: HostBriefingProviderKind,
    settings: HostIntelligenceSettings,
    forHostBoard: Bool
  ) -> HostBriefingProviderKind {
    guard settings.useEnhancedBriefing else { return .template }

    if forHostBoard,
       requested == .localModel,
       !settings.useLocalModelOnHostBoard {
      return .template
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
