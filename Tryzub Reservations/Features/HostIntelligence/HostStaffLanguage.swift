//
//  HostStaffLanguage.swift
//  Tryzub Reservations
//
//  Rewrites internal Host/booking phrases into plain restaurant staff language.
//

import Foundation

enum HostStaffLanguage {

  private static let exactReplacements: [(String, String)] = [
    (
      "requested time is inside minimum lead time window",
      "that time is coming up soon"
    ),
    (
      "this request can be confirmed based on slot pressure and party size",
      "the time looks manageable for this party. staff should still check the details"
    ),
    (
      "this request can be confirmed based on table pressure and party",
      "the time looks manageable for this party. staff should still check the details"
    ),
    ("review auto-confirm candidate for", "check booking for"),
    ("review auto-confirm candidate", "confirm if details look right"),
    ("auto-confirm candidate", "looks safe to confirm"),
    ("auto confirm candidate", "looks safe to confirm"),
    ("needs manual review before confirming", "needs a staff check before confirming"),
    ("need manual review before confirming", "need a staff check before confirming"),
    ("manual review before confirming", "staff check before confirming"),
    ("manual review", "staff check"),
    ("minimum lead time window", "coming up soon"),
    ("minimum lead time", "coming up soon"),
    ("slot pressure", "table pressure"),
    ("seating pressure", "table pressure"),
    ("party size threshold", "large party"),
    ("no suitable table fit exists for this party size", "no table looks like a good fit for this party"),
    ("critical large party requires staff review", "large party needs a staff check before confirming"),
    ("large party requires staff review before confirmation", "large party needs a staff check before confirming"),
    ("suspici" + "ously large party " + "size", "large party needs a table plan"),
    ("large party size requires review", "large party needs a table plan"),
    ("party size needs review", "large party needs a table plan"),
    ("guest may be " + "concerned", "guest may expect a reply"),
    ("the guest may have a concern", "the guest may expect a response"),
    (
      "manual/call-in or no usable email; staff should review before confirmation",
      "this booking needs a staff check before confirming"
    ),
    ("allergy signal requires staff review before confirmation", "allergy note needs a staff check before confirming"),
    (
      "accessibility needs require staff review before confirmation",
      "accessibility needs require a staff check before confirming"
    ),
    (
      "previous service issue requires staff review before confirmation",
      "previous service issue needs a staff check before confirming"
    ),
    (
      "possible duplicate booking requires staff review",
      "possible duplicate booking needs a staff check"
    ),
    ("guest risk signal requires staff review", "guest note needs a staff check"),
    ("is under heavy pressure and needs staff review", "is busy and needs a staff check"),
    ("has less pressure", "looks less busy"),
    ("booking risk signals should be reviewed", "bookings need a closer look"),
    ("booking risk signal should be reviewed", "one booking needs a closer look"),
    ("may need confirmation review", "still needs a staff check"),
    ("require manual review before accepting more bookings in this slot", "check before adding more bookings at this time"),
    ("should be reviewed manually", "need a staff check"),
  ]

  private static let blockedPhrases = [
    "minimum lead time",
    "lead time window",
    "auto-confirm",
    "auto confirm",
    "candidate",
    "slot pressure",
    "party size threshold",
    "confidence",
    "eligible",
    " based on ",
    "threshold=",
    "evidence=",
  ]

  static func rewrite(_ text: String) -> String {
    var line = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !line.isEmpty else { return line }

    for (pattern, replacement) in exactReplacements {
      line = line.replacingOccurrences(of: pattern, with: replacement, options: .caseInsensitive)
    }

    line = line.replacingOccurrences(
      of: #"\bparty size\b"#,
      with: "party",
      options: [.regularExpression, .caseInsensitive]
    )

    return collapseWhitespace(line)
  }

  static func leadTimeReason(requestedTime: String) -> String {
    "Guest wants \(requestedTime), but that time is coming up soon."
  }

  static func autoConfirmReason() -> String {
    "The time looks manageable for this party. Staff should still check the details."
  }

  static func noTableHeadline(guestName: String) -> String {
    let firstName = firstName(from: guestName)
    return "\(firstName)'s party arrives soon and still needs a table."
  }

  static func compactReservationDetail(timeLabel: String, partySize: Int) -> String {
    let guestLabel = partySize == 1 ? "1 guest" : "\(partySize) guests"
    return "\(timeLabel) · \(guestLabel)"
  }

  static func dueSoonNoTableDetail(guestName: String, timeLabel: String) -> String {
    noTableHeadline(guestName: guestName)
  }

  private static func firstName(from guestName: String) -> String {
    let trimmed = guestName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "Guest" }
    return trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? trimmed
  }

  static func dueSoonBookingReason(requestedTime: String) -> String {
    "Guest wants \(requestedTime), and that is coming up soon. Check details before confirming."
  }

  static func containsBlockedTechnicalLanguage(_ text: String) -> Bool {
    let lower = text.lowercased()
    return blockedPhrases.contains { lower.contains($0) }
  }

  private static let genericCheckPhrases = [
    "check details before confirming",
    "check before confirming",
    "confirm if details look right",
    "check reservation",
    "confirm details",
    "check details",
    "check the floor plan",
  ]

  static func isGenericCheckLine(_ text: String) -> Bool {
    let normalized = normalizeStaffLine(text)
    guard !normalized.isEmpty else { return false }
    return genericCheckPhrases.contains { phrase in
      normalized == phrase || normalized.hasPrefix(phrase)
    }
  }

  static func areSameStaffMeaning(_ lhs: String, _ rhs: String) -> Bool {
    let a = normalizeStaffLine(lhs)
    let b = normalizeStaffLine(rhs)
    guard !a.isEmpty, !b.isEmpty else { return false }
    if a == b { return true }
    if isGenericCheckLine(a), isGenericCheckLine(b) { return true }
    if a.contains(b) || b.contains(a) {
      if isGenericCheckLine(a) || isGenericCheckLine(b) {
        return true
      }
    }
    return false
  }

  private static func normalizeStaffLine(_ text: String) -> String {
    text
      .lowercased()
      .replacingOccurrences(of: #"[^\w\s]"#, with: "", options: .regularExpression)
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func collapseWhitespace(_ text: String) -> String {
    text
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
