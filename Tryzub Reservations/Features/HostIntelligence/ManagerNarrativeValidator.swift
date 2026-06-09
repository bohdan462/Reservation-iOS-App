//
//  ManagerNarrativeValidator.swift
//  Tryzub Reservations
//
//  Validates and parses manager narrative model output.
//

import Foundation

struct ManagerNarrativeValidationResult: Equatable {
  let isValid: Bool
  let reason: String?
}

enum ManagerNarrativeOutputParser {

  static func parse(_ raw: String) -> ManagerNarrative {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return ManagerNarrative.empty
    }

    var headline: String?
    var why: String?
    var check: String?

    for line in trimmed.components(separatedBy: .newlines) {
      let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { continue }

      if let parsed = labeledValue(prefix: "HEADLINE:", in: value) {
        headline = parsed
      } else if let parsed = labeledValue(prefix: "WHY:", in: value) {
        why = parsed
      } else if let parsed = labeledValue(prefix: "CHECK:", in: value) {
        check = parsed
      }
    }

    if headline != nil || why != nil || check != nil {
      return ManagerNarrative(
        headline: headline ?? "",
        whyItMatters: normalizedOptionalLine(why),
        checkNext: normalizedOptionalLine(check),
        source: .localModel,
        failedReason: nil
      )
    }

    let lines = trimmed
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    switch lines.count {
    case 0:
      return ManagerNarrative.empty
    case 1:
      return ManagerNarrative(
        headline: lines[0],
        whyItMatters: nil,
        checkNext: nil,
        source: .localModel,
        failedReason: nil
      )
    case 2:
      return ManagerNarrative(
        headline: lines[0],
        whyItMatters: lines[1],
        checkNext: nil,
        source: .localModel,
        failedReason: nil
      )
    default:
      return ManagerNarrative(
        headline: lines[0],
        whyItMatters: lines[1],
        checkNext: lines[2],
        source: .localModel,
        failedReason: nil
      )
    }
  }

  private static func labeledValue(prefix: String, in line: String) -> String? {
    guard line.uppercased().hasPrefix(prefix) else { return nil }
    let value = String(line.dropFirst(prefix.count))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }

  private static func normalizedOptionalLine(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed.uppercased() == "NONE" {
      return nil
    }
    return trimmed
  }
}

enum ManagerNarrativeValidator {

  private static let maxLineLength = 220
  private static let maxCombinedLength = 500
  private static let phonePattern = #"\b\d{3}[-.\s]?\d{3}[-.\s]?\d{4}\b"#
  private static let emailPattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#

  private static let blockedPhrases = [
    "backend", "cached", "cache ", " sync", "synced", " api", "endpoint",
    "payload", "packet", "json", "validation", "diagnostics", "debug output",
    "debug ", "confidence", "capacity ratio", "language model", "local model",
    "llm", "server response", "api server", "backend server", "evidence array",
    "as an ai", "as a model",
    "minimum lead time", "lead time window", "auto-confirm", "auto confirm",
    "candidate", "slot pressure", "party size threshold", "eligible",
    " based on "
  ]

  private static let completionPhrases = [
    "has been confirmed", "have been confirmed", "is confirmed",
    "has been assigned", "table assigned", "is seated", "has been seated",
    "has been cancelled", "has been canceled", "marked no-show",
    "already reviewed", "has been reviewed", "auto-confirmed", "automatically"
  ]

  private static let unsupportedCheckPhrases = [
    "call the guest", "call guest", "text the guest", "message the guest",
    "email the guest", "assign the table", "assign table", "table assigned",
    "confirm automatically", "confirm the reservation", "cancel the reservation",
    "seat the guest", "auto-send", "auto send"
  ]

  static func validationResult(
    _ narrative: ManagerNarrative,
    packet: ManagerNarrativePacket,
    hostPacket: HostLLMPacket,
    fallback: ManagerNarrative
  ) -> ManagerNarrativeValidationResult {
    let headline = narrative.headline.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !headline.isEmpty else {
      return ManagerNarrativeValidationResult(isValid: false, reason: "Headline is empty.")
    }

    for field in [headline, narrative.whyItMatters, narrative.checkNext].compactMap({ $0 }) {
      if let failure = validateField(field, packet: packet, hostPacket: hostPacket) {
        return failure
      }
    }

    let combined = narrative.compactBriefingText
    guard combined.count <= maxCombinedLength else {
      return ManagerNarrativeValidationResult(
        isValid: false,
        reason: "Narrative exceeds \(maxCombinedLength) characters."
      )
    }

    if packet.headlineFacts.isEmpty {
      let normalizedFallbackHeadline = fallback.headline
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if headline != normalizedFallbackHeadline {
        return ManagerNarrativeValidationResult(
          isValid: false,
          reason: "Narrative must match calm fallback when no facts are available."
        )
      }
    }

    if let check = narrative.checkNext?.trimmingCharacters(in: .whitespacesAndNewlines),
       !check.isEmpty {
      if let failure = validateCheckNextLine(check, packet: packet) {
        return failure
      }
    }

    return ManagerNarrativeValidationResult(isValid: true, reason: nil)
  }

  private static func validateCheckNextLine(
    _ check: String,
    packet: ManagerNarrativePacket
  ) -> ManagerNarrativeValidationResult? {
    let loweredCheck = check.lowercased()

    if unsupportedCheckPhrases.contains(where: { loweredCheck.contains($0) }) {
      return ManagerNarrativeValidationResult(
        isValid: false,
        reason: "Check-next line suggests an unsupported staff action."
      )
    }

    if loweredCheck.contains("message the guest") || loweredCheck.contains("draft message") {
      let allowsDraft = packet.availableActions.contains {
        let title = $0.title.lowercased()
        return title.contains("draft message") || title.contains("message")
      }
      if !allowsDraft {
        return ManagerNarrativeValidationResult(
          isValid: false,
          reason: "Check-next line suggests messaging without an available draft action."
        )
      }
    }

    guard !packet.availableActions.isEmpty else {
      return nil
    }

    if checkOverlapsAvailableActions(loweredCheck, actions: packet.availableActions) {
      return nil
    }

    return ManagerNarrativeValidationResult(
      isValid: false,
      reason: "Check-next line does not match an available staff action."
    )
  }

  private static func checkOverlapsAvailableActions(
    _ loweredCheck: String,
    actions: [ManagerNarrativeAction]
  ) -> Bool {
    actions.contains { action in
      let title = action.title.lowercased()
      let hint = action.destinationHint.lowercased()

      if !title.isEmpty,
         (loweredCheck.contains(title) || title.contains(loweredCheck)) {
        return true
      }

      if !hint.isEmpty, hint != "none", loweredCheck.contains(hint) {
        return true
      }

      let titleWords = title
        .split(whereSeparator: { $0.isWhitespace })
        .map(String.init)
        .filter { $0.count > 3 }
      if titleWords.contains(where: { loweredCheck.contains($0) }) {
        return true
      }

      return destinationHintKeywords(for: hint).contains { keyword in
        loweredCheck.contains(keyword)
      }
    }
  }

  private static func destinationHintKeywords(for hint: String) -> [String] {
    switch hint {
    case "table plan": return ["table plan", "joined tables", "table fit"]
    case "guest note": return ["guest note", "allergy", "accessibility"]
    case "new bookings": return ["new booking", "needs attention"]
    case "schedule": return ["open times", "seating wave", "arrival"]
    case "reservation": return ["reservation", "details"]
    default: return []
    }
  }

  private static func validateField(
    _ text: String,
    packet: ManagerNarrativePacket,
    hostPacket: HostLLMPacket
  ) -> ManagerNarrativeValidationResult? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    guard trimmed.count <= maxLineLength else {
      return ManagerNarrativeValidationResult(
        isValid: false,
        reason: "Narrative line exceeds \(maxLineLength) characters."
      )
    }

    if HostBriefingWriterValidator.sentenceCount(in: trimmed) > 1 {
      return ManagerNarrativeValidationResult(
        isValid: false,
        reason: "Each narrative line must be one sentence."
      )
    }

    let lower = trimmed.lowercased()
    if containsBlockedTechnicalLanguage(lower) {
      return ManagerNarrativeValidationResult(
        isValid: false,
        reason: "Narrative contains blocked technical language."
      )
    }

    for phrase in completionPhrases where lower.contains(phrase) {
      return ManagerNarrativeValidationResult(
        isValid: false,
        reason: "Narrative claims an action was already completed."
      )
    }

    if lower.range(of: phonePattern, options: [.regularExpression, .caseInsensitive]) != nil {
      return ManagerNarrativeValidationResult(
        isValid: false,
        reason: "Narrative contains a phone-like string."
      )
    }

    if lower.range(of: emailPattern, options: [.regularExpression, .caseInsensitive]) != nil {
      return ManagerNarrativeValidationResult(
        isValid: false,
        reason: "Narrative contains an email-like string."
      )
    }

    if let semantic = HostBriefingWriterValidator.validationResult(
      trimmed,
      packet: hostPacket,
      fallbackText: nil
    ).reason, HostBriefingWriterValidator.isSemanticFailureReason(semantic) {
      return ManagerNarrativeValidationResult(isValid: false, reason: semantic)
    }

    return nil
  }

  private static func containsBlockedTechnicalLanguage(_ lower: String) -> Bool {
    for phrase in blockedPhrases where lower.contains(phrase) {
      return true
    }

    if lower.range(of: #"(?:^|\s)a\.i\.(?:\s|$)|(?:^|\s)ai(?:\s|$)"#, options: .regularExpression) != nil {
      return true
    }

    if lower.range(of: #"\bmodel\b"#, options: .regularExpression) != nil {
      return true
    }

    return false
  }
}
