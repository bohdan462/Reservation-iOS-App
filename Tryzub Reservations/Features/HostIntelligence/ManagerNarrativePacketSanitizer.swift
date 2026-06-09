//
//  ManagerNarrativePacketSanitizer.swift
//  Tryzub Reservations
//
//  Strips unsafe lines from ManagerNarrativePacket input before local model use.
//

import Foundation

enum ManagerNarrativePacketSanitizer {

  static let maxLineLength = 180

  private static let phonePattern = #"\b\d{3}[-.\s]?\d{3}[-.\s]?\d{4}\b"#
  private static let emailPattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
  private static let evidenceMarkers = [
    "source=", "evidence=", "guest_key", "reservation_id", "remote_id",
    "backend_", "json", "payload", "packet", "debug"
  ]

  /// Returns a staff-safe line for model input, or nil when the value should be omitted.
  static func staffSafeLine(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard !looksLikeJSON(trimmed) else { return nil }
    guard !containsEmail(trimmed) else { return nil }
    guard !containsPhone(trimmed) else { return nil }
    guard !looksLikeEvidence(trimmed) else { return nil }

    if trimmed.count <= maxLineLength {
      return trimmed
    }
    return String(trimmed.prefix(maxLineLength))
  }

  static func staffSafeOptionalLine(_ value: String?) -> String? {
    guard let value else { return nil }
    return staffSafeLine(value)
  }

  // MARK: - Private

  private static func containsEmail(_ text: String) -> Bool {
    text.range(of: emailPattern, options: [.regularExpression, .caseInsensitive]) != nil
  }

  private static func containsPhone(_ text: String) -> Bool {
    text.range(of: phonePattern, options: [.regularExpression, .caseInsensitive]) != nil
  }

  private static func looksLikeJSON(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 2 else { return false }
    let startsLikeJSON = trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    let endsLikeJSON = trimmed.hasSuffix("}") || trimmed.hasSuffix("]")
    return startsLikeJSON && endsLikeJSON
  }

  private static func looksLikeEvidence(_ text: String) -> Bool {
    let lower = text.lowercased()
    return evidenceMarkers.contains { lower.contains($0) }
  }
}
