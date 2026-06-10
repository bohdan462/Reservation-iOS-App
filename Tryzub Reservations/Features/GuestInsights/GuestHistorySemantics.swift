//
//  GuestHistorySemantics.swift
//  Tryzub Reservations
//
//  Shared source-of-truth for guest history and reservation-note copy.
//

import Foundation

enum GuestHistorySemantics {

  // MARK: - Notes

  static func hasActualReservationNotes(_ reservation: ReservationRecord) -> Bool {
    reservation.hasGuestNotes || reservation.hasStaffNotes
  }

  static func combinedNoteText(for reservation: ReservationRecord) -> String {
    [reservation.guestNotes, reservation.staffNotes]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  static func hasOccasionNoteText(for reservation: ReservationRecord) -> Bool {
    let text = combinedNoteText(for: reservation)
    guard !text.isEmpty else { return false }
    if HostGuestNoteSnippetExtractor.specialOccasionSnippet(from: text) != nil {
      return true
    }
    let lower = text.lowercased()
    return specialOccasionKeywords.contains(where: { lower.contains($0) })
  }

  static func backendNoteFlagIsActionable(
    _ flag: Bool,
    reservation: ReservationRecord,
    requiresOccasionKeywords: Bool = false
  ) -> Bool {
    guard flag else { return false }
    guard hasActualReservationNotes(reservation) else { return false }
    if requiresOccasionKeywords {
      return hasOccasionNoteText(for: reservation)
    }
    return true
  }

  static func hasExplicitAllergyLanguage(in text: String) -> Bool {
    let lower = text.lowercased()
    return explicitAllergyKeywords.contains { keyword in
      lower.contains(keyword)
    }
  }

  static func hasDietaryPreferenceLanguage(in text: String) -> Bool {
    let lower = text.lowercased()
    return dietaryPreferenceKeywords.contains { keyword in
      lower.contains(keyword)
    }
  }

  static func backendAllergyFlagIsActionable(
    _ flag: Bool,
    reservation: ReservationRecord
  ) -> Bool {
    guard backendNoteFlagIsActionable(flag, reservation: reservation) else { return false }
    let text = combinedNoteText(for: reservation)
    guard !text.isEmpty else { return false }
    if hasDietaryPreferenceLanguage(in: text), !hasExplicitAllergyLanguage(in: text) {
      return false
    }
    return hasExplicitAllergyLanguage(in: text)
  }

  static func serverBackedSeenBeforeMessage(guestName: String) -> String {
    "\(guestName) appears to have visited before."
  }

  static func occasionNoteTitle(for reservation: ReservationRecord) -> String {
    let lower = combinedNoteText(for: reservation).lowercased()
    if lower.contains("birthday") { return "Birthday note" }
    if lower.contains("anniversary") { return "Anniversary note" }
    if lower.contains("bachelor party") || lower.contains("bachelorette") {
      return "Occasion note"
    }
    if lower.contains("graduation") || lower.contains("celebration") {
      return "Occasion note"
    }
    return "Guest note"
  }

  static func occasionNoteMessage(
    guestName: String,
    reservation: ReservationRecord
  ) -> String {
    let text = combinedNoteText(for: reservation)
    let lower = text.lowercased()
    if lower.contains("birthday") {
      return "\(guestName) mentioned a birthday."
    }
    if lower.contains("anniversary") {
      return "\(guestName) mentioned an anniversary."
    }
    if text.count <= 80, !text.isEmpty {
      return text
    }
    return "\(guestName) has a guest note attached."
  }

  struct DetailInsightLine: Equatable {
    let title: String
    let detail: String
  }

  struct DetailInsightPresentation: Equatable {
    let historyTitle: String
    let historyDetail: String
    let supplementalLines: [DetailInsightLine]
  }

  static func detailInsightPresentation(
    reservation: ReservationRecord,
    localReport: GuestInsightReport,
    serverSummary: GuestIntelligenceSummaryDTO?
  ) -> DetailInsightPresentation {
    let history: (title: String, detail: String)
    if localReport.hasReliableRepeatGuestHistory {
      history = compactHistoryLine(
        priorReliableVisitCount: localReport.priorReliableVisitCount,
        lastPriorVisitDisplayDate: localReport.lastPriorVisitDisplayDate
      )
    } else if let serverSummary,
              serverSummary.classification == .returning
                || serverSummary.classification == .regular
                || serverSummary.classification == .frequentRegular,
              hasReliableServerReturningIdentity(serverSummary.identityConfidence) {
      history = (
        "Seen before",
        serverBackedSeenBeforeMessage(guestName: reservation.guestName)
      )
    } else {
      history = localReport.guestHistoryLine
    }

    var supplemental: [DetailInsightLine] = []

    if hasOccasionNoteText(for: reservation)
      || serverSummary?.hasSpecialOccasionNote == true {
      supplemental.append(
        DetailInsightLine(
          title: occasionNoteTitle(for: reservation),
          detail: occasionNoteMessage(guestName: reservation.guestName, reservation: reservation)
        )
      )
    }

    let noteText = combinedNoteText(for: reservation)
    if hasDietaryPreferenceLanguage(in: noteText),
       !hasExplicitAllergyLanguage(in: noteText),
       !supplemental.contains(where: { $0.title == occasionNoteTitle(for: reservation) }) {
      supplemental.append(
        DetailInsightLine(
          title: "Dietary note",
          detail: noteText.count <= 80
            ? noteText
            : "\(reservation.guestName) has dietary notes."
        )
      )
    }

    if hasExplicitAllergyLanguage(in: noteText)
      || backendAllergyFlagIsActionable(serverSummary?.hasAllergyNote == true, reservation: reservation) {
      supplemental.append(
        DetailInsightLine(
          title: "Allergy note",
          detail: "\(reservation.guestName) has allergy-related notes."
        )
      )
    }

    return DetailInsightPresentation(
      historyTitle: history.title,
      historyDetail: history.detail,
      supplementalLines: supplemental
    )
  }

  private static func hasReliableServerReturningIdentity(
    _ confidence: GuestIdentityConfidenceDTO
  ) -> Bool {
    switch confidence {
    case .exact, .strong:
      return true
    case .possible, .weak, .unknown:
      return false
    }
  }

  static func guestNoteAlertTitle(for reservation: ReservationRecord) -> String {
    "Check guest note"
  }

  static func containsInventedOccasionNoteLanguage(title: String, detail: String?) -> Bool {
    let titleLower = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if titleLower == "occasion note" || titleLower == "special occasion note" {
      return true
    }

    let detailLower = detail?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
    if detailLower.contains("has a special occasion note") {
      return true
    }
    if detailLower.contains("share this note with the server") {
      return true
    }
    return false
  }

  static func guestNoteAlertReason(for reservation: ReservationRecord) -> String {
    let text = combinedNoteText(for: reservation)
    if text.count <= 80 {
      return text
    }
    return "Guest note attached."
  }

  // MARK: - Visit History

  static func isCleanVisit(_ status: ReservationStatus) -> Bool {
    status != .cancelled && status != .noShow
  }

  static func isPrior(
    record: ReservationRecord,
    to selected: ReservationRecord
  ) -> Bool {
    guard record.remoteID != selected.remoteID else { return false }
    if record.reservationDate < selected.reservationDate { return true }
    if record.reservationDate > selected.reservationDate { return false }
    return record.reservationTime < selected.reservationTime
  }

  static func isPrior(
    date: String,
    time: String,
    to selected: ReservationRecord
  ) -> Bool {
    if date < selected.reservationDate { return true }
    if date > selected.reservationDate { return false }
    return time < selected.reservationTime
  }

  static func priorReliableVisitCount(
    selected: ReservationRecord,
    matchedRecords: [ReservationRecord]
  ) -> Int {
    matchedRecords.filter { record in
      isPrior(record: record, to: selected) && isCleanVisit(record.statusValue)
    }.count
  }

  static func priorReliableVisitCount(
    selected: ReservationRecord,
    matchedReservations: [GuestMatchedReservation]
  ) -> Int {
    matchedReservations.filter { item in
      item.reservationID != selected.remoteID
        && isPrior(date: item.date, time: item.time, to: selected)
        && isCleanVisit(item.status)
    }.count
  }

  static func visitOrdinal(priorReliableVisitCount: Int) -> Int {
    priorReliableVisitCount + 1
  }

  static func hasReliableRepeatHistory(priorReliableVisitCount: Int) -> Bool {
    priorReliableVisitCount >= 1
  }

  static func lastPriorVisitDisplayDate(
    selected: ReservationRecord,
    matchedReservations: [GuestMatchedReservation]
  ) -> String? {
    matchedReservations
      .filter { item in
        item.reservationID != selected.remoteID
          && isPrior(date: item.date, time: item.time, to: selected)
          && isCleanVisit(item.status)
      }
      .sorted { lhs, rhs in
        if lhs.date == rhs.date {
          if lhs.time == rhs.time {
            return lhs.reservationID > rhs.reservationID
          }
          return lhs.time > rhs.time
        }
        return lhs.date > rhs.date
      }
      .first?
      .displayDate
  }

  static func ordinalVisitText(for visitOrdinal: Int) -> String? {
    guard visitOrdinal >= 2 else { return nil }
    switch visitOrdinal {
    case 2: return "2nd visit"
    case 3: return "3rd visit"
    default: return "\(visitOrdinal)th visit"
    }
  }

  static func compactHistoryLine(
    priorReliableVisitCount: Int,
    lastPriorVisitDisplayDate: String?
  ) -> (title: String, detail: String) {
    guard hasReliableRepeatHistory(priorReliableVisitCount: priorReliableVisitCount) else {
      return ("First time", "No prior visits found.")
    }

    let ordinal = visitOrdinal(priorReliableVisitCount: priorReliableVisitCount)
    var detailParts: [String] = []
    if let ordinalText = ordinalVisitText(for: ordinal) {
      detailParts.append(ordinalText)
    }
    if let lastPriorVisitDisplayDate {
      detailParts.append("last \(lastPriorVisitDisplayDate)")
    }

    let detail = detailParts.isEmpty
      ? "Guest has prior reservation history."
      : detailParts.joined(separator: " · ")
    return ("Seen before", detail)
  }

  static func seenBeforeRowLine(
    priorReliableVisitCount: Int,
    lastPriorVisitDisplayDate: String?
  ) -> String {
    let line = compactHistoryLine(
      priorReliableVisitCount: priorReliableVisitCount,
      lastPriorVisitDisplayDate: lastPriorVisitDisplayDate
    )
    if line.detail == "Guest has prior reservation history." {
      return line.title
    }
    return "\(line.title) · \(line.detail)"
  }

  static func returningGuestMessage(
    guestName: String,
    visitOrdinal: Int,
    lastPriorVisitDisplayDate: String?,
    frequent: Bool = false
  ) -> String {
    if visitOrdinal >= 2, let ordinal = ordinalVisitText(for: visitOrdinal) {
      if frequent {
        if let lastPriorVisitDisplayDate {
          return "\(guestName) is a frequent returning guest for their \(ordinal); last visit \(lastPriorVisitDisplayDate)."
        }
        return "\(guestName) is a frequent returning guest for their \(ordinal)."
      }

      if let lastPriorVisitDisplayDate {
        return "\(guestName) is returning for \(ordinal); last visit \(lastPriorVisitDisplayDate)."
      }
      return "\(guestName) is returning for \(ordinal)."
    }

    if frequent {
      return "\(guestName) is a frequent returning guest."
    }
    if let lastPriorVisitDisplayDate {
      return "\(guestName) has been seen before. Last visit \(lastPriorVisitDisplayDate)."
    }
    return "\(guestName) has been seen before."
  }

  // MARK: - Private

  private static let specialOccasionKeywords = [
    "birthday", "anniversary", "engagement", "graduation", "celebration", "special occasion",
    "bachelor party", "bachelorette", "bachelorette party"
  ]

  private static let explicitAllergyKeywords = [
    "allergy", "allergic", "anaphylaxis", "peanut allergy", "shellfish allergy", "severe allergy"
  ]

  private static let dietaryPreferenceKeywords = [
    "vegetarian", "vegan", "pescatarian", "dairy-free", "dairy free", "gluten-free", "gluten free",
    "celiac"
  ]
}
