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

      if let parsed = labeledValue(label: "HEADLINE", in: value) {
        headline = parsed
      } else if let parsed = labeledValue(label: "WHY", in: value) {
        why = parsed
      } else if let parsed = labeledValue(label: "CHECK", in: value) {
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

    let sentences = sentences(in: trimmed)
    switch sentences.count {
    case 0:
      return ManagerNarrative.empty
    case 1:
      return ManagerNarrative(
        headline: sentences[0],
        whyItMatters: nil,
        checkNext: nil,
        source: .localModel,
        failedReason: nil
      )
    case 2:
      return ManagerNarrative(
        headline: sentences[0],
        whyItMatters: sentences[1],
        checkNext: nil,
        source: .localModel,
        failedReason: nil
      )
    default:
      return ManagerNarrative(
        headline: sentences[0],
        whyItMatters: sentences[1],
        checkNext: sentences[2],
        source: .localModel,
        failedReason: nil
      )
    }
  }

  private static func sentences(in text: String) -> [String] {
    text
      .replacingOccurrences(of: "\n", with: " ")
      .split(whereSeparator: { ".!?".contains($0) })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .prefix(3)
      .map { value in
        value.hasSuffix(".") || value.hasSuffix("!") || value.hasSuffix("?")
          ? value
          : "\(value)."
      }
  }

  private static func labeledValue(label: String, in line: String) -> String? {
    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
    let upperLine = trimmedLine.uppercased()
    let upperLabel = label.uppercased()
    guard upperLine.hasPrefix(upperLabel) else { return nil }

    var remainder = String(trimmedLine.dropFirst(upperLabel.count))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if remainder.first == ":" || remainder.first == "=" {
      remainder = String(remainder.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return remainder.isEmpty ? nil : remainder
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

  private static let leakedLabelTokens = [
    "HEADLINE", "WHY", "CHECK"
  ]

  private static let rawCategoryTagPattern = #"\[[^\]]+/[^\]]+\]"#
  private static let numberedDiagnosticPattern = #"^\s*\d+\.\s*(?:\[|\w)"#

  private static let unnaturalStaffPhrases = [
    "lighter than usual window",
    "lightness of the window",
    "safer alternate window",
    "impact on the service",
    "usual peak"
  ]

  private static let unsupportedCheckPhrases = [
    "call the guest", "call guest", "text the guest", "message the guest",
    "email the guest", "assign the table", "assign table", "table assigned",
    "confirm automatically", "confirm the reservation", "cancel the reservation",
    "seat the guest", "auto-send", "auto send"
  ]

  private static let announcementTonePhrases = [
    "attention all staff",
    "dear staff",
    "hello team",
    "good evening team",
    "good morning team"
  ]

  private static let tableAvailablePhrases = [
    " is available",
    "table is free",
    "table is now available",
    "table can be used",
    "table has opened"
  ]

  static func containsLeakedModelLabels(in narrative: ManagerNarrative) -> Bool {
    for field in [narrative.headline, narrative.whyItMatters, narrative.checkNext].compactMap({ $0 }) {
      if containsLeakedModelLabels(in: field) {
        return true
      }
    }
    return false
  }

  static func containsLeakedModelLabels(in text: String) -> Bool {
    containsRawDiagnosticFormatting(in: text)
      || containsStructuralModelLabels(in: text)
  }

  static func containsRawDiagnosticFormatting(in text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }

    if trimmed.range(of: rawCategoryTagPattern, options: .regularExpression) != nil {
      return true
    }

    if trimmed.range(of: numberedDiagnosticPattern, options: .regularExpression) != nil {
      return true
    }

    return false
  }

  static func stripRolePrefixIfNeeded(_ text: String) -> (text: String, stripped: Bool)? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let lower = trimmed.lowercased()
    for prefix in ["manager:", "host:"] {
      if lower.hasPrefix(prefix) {
        let stripped = String(trimmed.dropFirst(prefix.count))
          .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }
        return (stripped, true)
      }
    }
    return (trimmed, false)
  }

  static func repairStaffCopy(_ raw: String) -> String? {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }

    if let stripped = stripRolePrefixIfNeeded(text) {
      text = stripped.text
    }

    let lines = text
      .components(separatedBy: .newlines)
      .map { line -> String in
        var cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(
          of: rawCategoryTagPattern,
          with: "",
          options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
          of: #"^\s*\d+\.\s*"#,
          with: "",
          options: .regularExpression
        )
        for token in leakedLabelTokens {
          let pattern = "(?i)^\\s*\(token)\\s*[:=]\\s*"
          cleaned = cleaned.replacingOccurrences(
            of: pattern,
            with: "",
            options: .regularExpression
          )
        }
        cleaned = cleaned.replacingOccurrences(of: " — ", with: ". ")
        cleaned = cleaned.replacingOccurrences(of: " - ", with: ". ")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      .filter { !$0.isEmpty }

    if !lines.isEmpty {
      text = lines.joined(separator: " ")
    }

    text = text.replacingOccurrences(
      of: rawCategoryTagPattern,
      with: "",
      options: .regularExpression
    )
    text = text.replacingOccurrences(of: "  ", with: " ")
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !text.isEmpty else { return nil }
    guard !containsRawDiagnosticFormatting(in: text) else { return nil }
    guard !containsStructuralModelLabels(in: text) else { return nil }
    return text
  }

  private static func containsStructuralModelLabels(in text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }

    let upper = trimmed.uppercased()
    for token in leakedLabelTokens {
      if upper.contains("\(token) =") || upper.contains("\(token)=") {
        return true
      }
      if upper.hasPrefix("\(token):") || upper.hasPrefix("\(token) :") {
        return true
      }
      if upper == token {
        return true
      }
    }

    let lower = trimmed.lowercased()
    if unnaturalStaffPhrases.contains(where: { lower.contains($0) }) {
      return true
    }

    return false
  }

  private static let hospitalityFluffPhrases = [
    "excellent hospitality", "provide excellent", "valued vip", "valued guest",
    "warm welcome", "exceptional service", "delight the guest", "make them feel special",
    "go above and beyond", "white glove", "five-star"
  ]

  private static let unsafePromisePhrases = [
    "offer cake", "provide cake", "free dessert", "complimentary",
    "discount", "decoration", "special treatment", "vip treatment",
    "surprise them", "make it special", "promise"
  ]

  static func sentenceCount(in narrative: ManagerNarrative) -> Int {
    [narrative.headline, narrative.whyItMatters, narrative.checkNext]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .count
  }

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

    let totalSentences = sentenceCount(in: narrative)
    if totalSentences > 3 {
      return ManagerNarrativeValidationResult(
        isValid: false,
        reason: "Narrative exceeds 3 sentences."
      )
    }

    if containsLeakedModelLabels(in: narrative) {
      return ManagerNarrativeValidationResult(
        isValid: false,
        reason: "Narrative contains labeled or unnatural staff output."
      )
    }

    for field in [headline, narrative.whyItMatters, narrative.checkNext].compactMap({ $0 }) {
      if let failure = validateOperationalClaims(field, hostPacket: hostPacket) {
        return failure
      }
      if let failure = validateHospitalityAndPromises(field) {
        return failure
      }
      if let failure = validatePressureClaims(field, packet: packet) {
        return failure
      }
      if let failure = validateField(field, packet: packet, hostPacket: hostPacket) {
        return failure
      }
    }

    if let why = narrative.whyItMatters,
       HostStaffLanguage.areSameStaffMeaning(headline, why) {
      return ManagerNarrativeValidationResult(
        isValid: false,
        reason: "Narrative repeats the same meaning in headline and why."
      )
    }

    if let check = narrative.checkNext?.trimmingCharacters(in: .whitespacesAndNewlines),
       !check.isEmpty {
      if HostStaffLanguage.areSameStaffMeaning(headline, check)
          || (narrative.whyItMatters.map { HostStaffLanguage.areSameStaffMeaning($0, check) } == true) {
        return ManagerNarrativeValidationResult(
          isValid: false,
          reason: "Narrative repeats the same meaning across lines."
        )
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
    case "floor plan": return ["floor plan", "joined tables", "table fit"]
    case "guest note": return ["guest note", "allergy", "accessibility"]
    case "new bookings": return ["new booking", "needs attention"]
    case "schedule": return ["open times", "seating wave", "arrival"]
    case "reservation": return ["reservation", "details"]
    default: return []
    }
  }

  private static func validateHospitalityAndPromises(
    _ text: String
  ) -> ManagerNarrativeValidationResult? {
    let lower = text.lowercased()
    if hospitalityFluffPhrases.contains(where: { lower.contains($0) }) {
      return ManagerNarrativeValidationResult(
        isValid: false,
        reason: "Narrative contains generic hospitality fluff."
      )
    }
    if unsafePromisePhrases.contains(where: { lower.contains($0) }) {
      return ManagerNarrativeValidationResult(
        isValid: false,
        reason: "Narrative contains an unsafe promise."
      )
    }
    if lower.contains("vip") && !lower.contains("returning") {
      return ManagerNarrativeValidationResult(
        isValid: false,
        reason: "Narrative uses VIP language without support."
      )
    }
    return nil
  }

  private static func validatePressureClaims(
    _ text: String,
    packet: ManagerNarrativePacket
  ) -> ManagerNarrativeValidationResult? {
    guard let facts = packet.arrivalPressureFacts else { return nil }
    let lower = text.lowercased()

    // Reject invented peak guest counts not in packet
    if let peakGuests = extractFirstInteger(after: ["guests", "guest"], in: lower),
       facts.peakGuestCount > 0,
       peakGuests != facts.peakGuestCount,
       lower.contains("peak") || lower.contains("wave") || lower.contains("pressure") {
      return ManagerNarrativeValidationResult(
        isValid: false,
        reason: "Narrative invents a peak guest count not in pressure facts."
      )
    }

    if let peakRes = extractFirstInteger(after: ["reservations", "reservation"], in: lower),
       facts.peakReservationCount > 0,
       peakRes != facts.peakReservationCount,
       lower.contains("peak") || lower.contains("wave") {
      return ManagerNarrativeValidationResult(
        isValid: false,
        reason: "Narrative invents a peak reservation count not in pressure facts."
      )
    }

    return nil
  }

  private static func extractFirstInteger(after keywords: [String], in lower: String) -> Int? {
    for keyword in keywords {
      guard let range = lower.range(of: keyword) else { continue }
      let prefix = String(lower[..<range.lowerBound])
      let digits = prefix.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
      if let last = digits.last { return last }
    }
    return nil
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

    for phrase in completionPhrases where containsCompletionPhrase(phrase, in: lower) {
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

  private static func containsCompletionPhrase(_ phrase: String, in lower: String) -> Bool {
    guard lower.contains(phrase) else { return false }
    switch phrase {
    case "is confirmed":
      return !lower.contains("still confirmed")
    case "table assigned":
      return !lower.contains("no table assigned") && !lower.contains("without a table")
    case "is seated":
      return !lower.contains("not seated") && !lower.contains("was not seated")
    default:
      return true
    }
  }

  static func validateOperationalClaims(
    _ text: String,
    hostPacket: HostLLMPacket
  ) -> ManagerNarrativeValidationResult? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let lower = trimmed.lowercased()

    if announcementTonePhrases.contains(where: { lower.contains($0) }) {
      return ManagerNarrativeValidationResult(isValid: false, reason: "announcement_tone")
    }

    if lower.hasPrefix("manager:") || lower.contains("manager: ") {
      return ManagerNarrativeValidationResult(isValid: false, reason: "manager_prefix")
    }

    if lower.contains("please check your reservation")
        || lower.contains("your reservation is")
        || lower.contains("you are late") {
      return ManagerNarrativeValidationResult(isValid: false, reason: "second_person_guest_facing")
    }

    if tableAvailablePhrases.contains(where: { lower.contains($0) }) {
      return ManagerNarrativeValidationResult(isValid: false, reason: "unsupported_table_available_claim")
    }

    for fact in hostPacket.topFacts {
      guard let guestName = guestName(from: fact) else { continue }
      let guestLower = guestName.lowercased()
      guard lower.contains(guestLower) else { continue }

      let evidence = fact.evidence.joined(separator: " ").lowercased()
      let titleLower = fact.title.lowercased()
      let seatedGuest = evidence.contains("seated=true")
        || evidence.contains("missedcompletion=true")
        || evidence.contains("seatedcompletiongrace=true")
        || titleLower.contains("possible missed completion")
        || titleLower.contains("marked seated")
      let unseatedLate = evidence.contains("notable=true")
        || evidence.contains("unresolvedlatecleanup=true")
        || evidence.contains("seated=false")
        || titleLower.contains("late reservation still has no table")
        || titleLower.contains("resolve late reservation")

      if seatedGuest {
        if lower.contains("\(guestLower) is late")
            || lower.contains("\(guestLower) has no table")
            || lower.contains("\(guestLower) still has no table") {
          return ManagerNarrativeValidationResult(
            isValid: false,
            reason: "unsupported_no_table_claim_for_seated_reservation"
          )
        }
        if lower.contains("\(guestLower) is late and has no table") {
          return ManagerNarrativeValidationResult(
            isValid: false,
            reason: "unsupported_late_claim_for_seated_reservation"
          )
        }
      }

      if unseatedLate {
        if lower.contains("\(guestLower) has been seated")
            || lower.contains("\(guestLower) is seated")
            || lower.contains("\(guestLower) was seated") {
          return ManagerNarrativeValidationResult(
            isValid: false,
            reason: "unsupported_seated_claim_for_unseated_reservation"
          )
        }
      }
    }

    return nil
  }

  private static func guestName(from fact: HostLLMFact) -> String? {
    let detail = fact.detail.trimmingCharacters(in: .whitespacesAndNewlines)
    if let comma = detail.firstIndex(of: ",") {
      let name = String(detail[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
      return name.isEmpty ? nil : name
    }
    if detail.contains(" still has no table") {
      let name = detail.replacingOccurrences(of: " still has no table assigned", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return name.isEmpty ? nil : name
    }
    if detail.contains(" has been marked seated") {
      let name = detail.components(separatedBy: " has been marked seated").first?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return name?.isEmpty == false ? name : nil
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
