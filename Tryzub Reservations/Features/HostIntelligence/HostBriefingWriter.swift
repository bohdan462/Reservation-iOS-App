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

enum HostBriefingWriterSource: String, Equatable {
  case template
  case localPlaceholder
  case failedFallback

  var displayName: String {
    switch self {
    case .template: return "Template"
    case .localPlaceholder: return "Local placeholder"
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

  private static let maxLength = 500
  private static let maxSentences = 4
  private static let maxExclamationMarks = 2

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

    return HostBriefingValidationResult(isValid: true, reason: nil)
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
  static func writer(for provider: HostBriefingProviderKind) -> HostBriefingWriter {
    switch provider {
    case .template:
      return TemplateHostBriefingWriter()
    case .localPlaceholder:
      return LocalPlaceholderHostBriefingWriter()
    }
  }
}
