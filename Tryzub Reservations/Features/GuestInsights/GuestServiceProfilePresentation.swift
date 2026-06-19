//
//  GuestServiceProfilePresentation.swift
//  Tryzub Reservations
//
//  Display-ready guest history and service briefing built from shared truth.
//

import Foundation

struct GuestServiceProfilePresentation: Equatable {
  struct TodaySummary: Equatable {
    let sectionTitle: String
    let dateLine: String?
    let primaryLine: String
    let tableLine: String
    let reminderLine: String?
    let noteLines: [String]
  }

  struct StatusSummary: Equatable {
    let title: String
    let detail: String?
  }

  struct Metric: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
    let caption: String
  }

  struct Visit: Identifiable, Equatable {
    let id: String
    let reservationID: Int?
    let dateKey: String
    let timeKey: String
    let displayDate: String
    let displayTime: String
    let partySize: Int
    let status: String
    let table: String
    let guestNote: String?
    let staffNote: String?
  }

  struct Note: Identifiable, Equatable {
    enum Kind: String, Equatable {
      case guest = "Guest note"
      case staff = "Staff note"
    }

    let id: String
    let dateKey: String
    let displayDate: String
    let kind: Kind
    let text: String
  }

  struct Pattern: Identifiable, Equatable {
    let id: String
    let text: String
    let systemImage: String
  }

  struct Watchout: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String?
    let systemImage: String
  }

  let guestName: String
  let status: StatusSummary
  let today: TodaySummary
  let metrics: [Metric]
  let pastVisits: [Visit]
  let upcomingReservations: [Visit]
  let notes: [Note]
  let patterns: [Pattern]
  let watchouts: [Watchout]
}

enum GuestServiceProfilePresentationBuilder {
  static func build(
    selected: ReservationRecord,
    historyPool: [ReservationRecord],
    aggregateProfile: GuestProfileDTO?,
    profilePack: GuestIntelligenceProfilePackDTO?,
    localReport: GuestInsightReport?,
    mergedContext: GuestHistorySemantics.GuestInsightsMergedContext?
  ) -> GuestServiceProfilePresentation {
    let now = Date()
    let resolver = GuestIdentityResolver()
    let selectedIdentity = resolver.identity(for: selected)
    let identityMatches = historyPool.filter { candidate in
      if candidate.remoteID == selected.remoteID { return true }
      guard let match = resolver.match(
        candidate,
        against: selectedIdentity,
        selectedID: selected.remoteID
      ) else { return false }
      return match.confidence == .exact || match.confidence == .strong
    }
    let rawMatches = identityMatches.contains(where: { $0.remoteID == selected.remoteID })
      ? identityMatches
      : identityMatches + [selected]
    let matchedRecords = GuestReservationIntentDeduper()
      .collapse(rawMatches, keeping: selected.remoteID)
      .records

    let localPast = GuestOperationalTruth.validPastVisits(
      selected: selected,
      reservationPool: matchedRecords,
      emitTrace: false
    )
    let localPastVisits = localPast.map(visit(from:))
    let aggregateHistoryRows = aggregateProfile?.fullProfile.bookingHistoryRows ?? []
    let packHistoryRows = profilePack?.fullProfile.bookingHistoryRows ?? []
    let fullHistoryRows = aggregateHistoryRows.isEmpty ? packHistoryRows : aggregateHistoryRows
    let serverPastVisits = fullHistoryRows.isEmpty
      ? serverVisits(from: profilePack, selected: selected)
      : GuestOperationalTruth.cleanPastVisits(from: fullHistoryRows).map(visit(from:))
    let pastVisits = mergedVisits(local: localPastVisits, supplemental: serverPastVisits)
      .sorted(by: newestFirst)

    let localUpcoming = matchedRecords
      .filter { candidate in
        !candidate.isHidden
          && (candidate.supersededById ?? 0) <= 0
          && isUpcomingStatus(candidate.statusValue)
          && (candidate.serviceDateTime.map { $0 > now }
            ?? (serviceKey(candidate.reservationDate, candidate.reservationTime) > currentServiceKey(now)))
      }
      .map(visit(from:))
    let serverUpcoming = fullHistoryRows.isEmpty
      ? (aggregateProfile.flatMap { upcomingVisit(from: $0.nextReservation, now: now) }.map { [$0] } ?? [])
      : fullHistoryRows.filter { $0.outcome == .upcoming }.map(visit(from:))
    let upcoming = mergedVisits(local: localUpcoming, supplemental: serverUpcoming)
      .sorted(by: oldestFirst)

    // Staff-facing counts are row-derived so every counted visit has a visible row.
    let cleanPastVisitCount = pastVisits.count
    let lastVisitDisplay = pastVisits.first?.displayDate
    let upcomingCount = upcoming.count
    let status = statusSummary(
      cleanPastVisitCount: cleanPastVisitCount,
      lastVisitDisplay: lastVisitDisplay,
      mergedContext: mergedContext
    )

    // Prefer backend notes_history (tied to reservation/date/kind) when available.
    // Fall back to row-derived notes when backend has not provided them.
    let serverNotesHistory = aggregateProfile?.fullProfile.notesHistory
      ?? profilePack?.fullProfile.notesHistory
      ?? []
    let notes = serverNotesHistory.isEmpty
      ? notesHistory(selected: selected, pastVisits: pastVisits, upcoming: upcoming)
      : serverNotes(from: serverNotesHistory)
    let patterns = patterns(from: pastVisits)
    let collapsedDuplicate = rawMatches.count > matchedRecords.count
    let ignoredTerminalPeer = rawMatches.contains { candidate in
      candidate.remoteID != selected.remoteID
        && candidate.reservationDate == selected.reservationDate
        && (candidate.isHidden
          || (candidate.supersededById ?? 0) > 0
          || candidate.statusValue == .cancelled
          || candidate.statusValue == .noShow)
    }
    let watchouts = watchouts(
      selected: selected,
      matchedRecords: matchedRecords,
      upcomingCount: upcomingCount,
      collapsedDuplicate: collapsedDuplicate || ignoredTerminalPeer,
      report: localReport
    )

    return GuestServiceProfilePresentation(
      guestName: cleaned(aggregateProfile?.primaryName) ?? selected.guestName,
      status: status,
      today: todaySummary(selected),
      metrics: metrics(
        cleanPastVisitCount: cleanPastVisitCount,
        lastVisitDisplay: lastVisitDisplay,
        upcomingCount: upcomingCount,
        pastVisits: pastVisits
      ),
      pastVisits: pastVisits,
      upcomingReservations: upcoming,
      notes: notes,
      patterns: patterns,
      watchouts: watchouts
    )
  }

  private static func todaySummary(_ selected: ReservationRecord) -> GuestServiceProfilePresentation.TodaySummary {
    let isToday = selected.reservationDate == Date.reservationDateString()
    var noteLines: [String] = []
    if nonBlank(selected.guestNotes) != nil { noteLines.append("Guest note attached") }
    if nonBlank(selected.staffNotes) != nil { noteLines.append("Staff note found") }
    let reminderLine: String? = {
      guard isUpcomingStatus(selected.statusValue) else { return nil }
      if nonBlank(selected.reminderEmailSentAt) != nil { return "Reminder sent" }
      return selected.statusValue == .confirmed ? "Reminder not sent" : nil
    }()
    return .init(
      sectionTitle: isToday ? "Today" : "Selected reservation",
      dateLine: isToday ? nil : selected.displayDate,
      primaryLine: "\(selected.displayTime) · Party of \(selected.partySize) · \(selected.statusValue.displayName)",
      tableLine: tableLabel(selected.assignedTableName),
      reminderLine: reminderLine,
      noteLines: noteLines
    )
  }

  private static func statusSummary(
    cleanPastVisitCount: Int,
    lastVisitDisplay: String?,
    mergedContext: GuestHistorySemantics.GuestInsightsMergedContext?
  ) -> GuestServiceProfilePresentation.StatusSummary {
    if cleanPastVisitCount >= 3 {
      return .init(title: "Regular guest", detail: "\(cleanPastVisitCount) past visits")
    }
    if cleanPastVisitCount > 0 {
      return .init(
        title: "Seen before",
        detail: lastVisitDisplay.map { "Last visit \($0)" } ?? "\(cleanPastVisitCount) past \(cleanPastVisitCount == 1 ? "visit" : "visits")"
      )
    }
    if mergedContext?.historyDetail == "Guest history found" {
      return .init(title: "Guest history found", detail: nil)
    }
    return .init(title: "First time here", detail: nil)
  }

  private static func metrics(
    cleanPastVisitCount: Int,
    lastVisitDisplay: String?,
    upcomingCount: Int,
    pastVisits: [GuestServiceProfilePresentation.Visit]
  ) -> [GuestServiceProfilePresentation.Metric] {
    let usualParty = supportedMode(pastVisits.map(\.partySize))
    return [
      .init(id: "past", title: "Past visits", value: "\(cleanPastVisitCount)", caption: "Clean visits"),
      .init(id: "last", title: "Last visit", value: lastVisitDisplay ?? "—", caption: lastVisitDisplay == nil ? "No past visit" : "Most recent"),
      .init(id: "upcoming", title: "Upcoming", value: "\(upcomingCount)", caption: "Future reservations"),
      .init(id: "party", title: "Usually", value: usualParty.map { "Party of \($0)" } ?? "—", caption: usualParty == nil ? "Not enough history" : "Most common size")
    ]
  }

  private static func visit(from record: ReservationRecord) -> GuestServiceProfilePresentation.Visit {
    .init(
      id: "local-\(record.remoteID)",
      reservationID: record.remoteID,
      dateKey: record.reservationDate,
      timeKey: record.reservationTime,
      displayDate: displayDate(record.reservationDate),
      displayTime: record.displayTime,
      partySize: record.partySize,
      status: record.statusValue.displayName,
      table: tableLabel(record.assignedTableName),
      guestNote: trimmedNote(record.guestNotes),
      staffNote: trimmedNote(record.staffNotes)
    )
  }

  private static func serverVisits(
    from pack: GuestIntelligenceProfilePackDTO?,
    selected: ReservationRecord
  ) -> [GuestServiceProfilePresentation.Visit] {
    guard let pack, hasReliableIdentity(pack) else { return [] }
    return pack.matchedVisitPreview.compactMap { preview in
      let status = ReservationStatus(rawValue: preview.status.lowercased())
      guard let status,
            status == .confirmed || status == .seated || status == .completed,
            preview.reservationId != selected.remoteID,
            serviceKey(preview.date, preview.time) < serviceKey(selected.reservationDate, selected.reservationTime) else {
        return nil
      }
      if let confidence = preview.matchConfidence?.lowercased(),
         confidence != "exact", confidence != "strong" {
        return nil
      }
      return .init(
        id: "history-\(preview.reservationId)-\(preview.date)-\(preview.time)",
        reservationID: preview.reservationId > 0 ? preview.reservationId : nil,
        dateKey: preview.date,
        timeKey: preview.time,
        displayDate: displayDate(preview.date),
        displayTime: displayTime(preview.time),
        partySize: preview.partySize,
        status: status.displayName,
        table: tableLabel(preview.tableName),
        guestNote: trimmedNote(preview.guestNotesPreview) ?? signalPreview(preview.signals),
        staffNote: trimmedNote(preview.staffNotesPreview)
      )
    }
  }

  private static func visit(from row: GuestHistoryRow) -> GuestServiceProfilePresentation.Visit {
    .init(
      id: "history-\(row.id)-\(row.serviceDate)-\(row.serviceTime)",
      reservationID: row.id > 0 ? row.id : nil,
      dateKey: row.serviceDate,
      timeKey: row.serviceTime,
      displayDate: displayDate(row.serviceDate),
      displayTime: displayTime(row.serviceTime),
      partySize: row.partySize,
      status: row.status.displayName,
      table: tableLabel(row.tableName),
      guestNote: trimmedNote(row.guestNotes),
      staffNote: trimmedNote(row.staffNotes)
    )
  }

  private static func upcomingVisit(
    from next: GuestProfileNextReservationDTO?,
    now: Date
  ) -> GuestServiceProfilePresentation.Visit? {
    guard let next else { return nil }
    let id = next.reservationId ?? next.id
    let date = next.reservationDate ?? next.date ?? ""
    let time = next.reservationTime ?? next.time ?? ""
    let status = ReservationStatus(rawValue: next.status ?? "confirmed") ?? .confirmed
    guard isUpcomingStatus(status),
          serviceKey(date, time) > currentServiceKey(now) else {
      return nil
    }
    return .init(
      id: "upcoming-\(id ?? 0)-\(date)-\(time)",
      reservationID: id,
      dateKey: date,
      timeKey: time,
      displayDate: displayDate(date),
      displayTime: displayTime(time),
      partySize: next.partySize ?? 0,
      status: status.displayName,
      table: tableLabel(next.tableName),
      guestNote: nil,
      staffNote: nil
    )
  }

  private static func mergedVisits(
    local: [GuestServiceProfilePresentation.Visit],
    supplemental: [GuestServiceProfilePresentation.Visit]
  ) -> [GuestServiceProfilePresentation.Visit] {
    var result = local
    var reservationIDs = Set(local.compactMap(\.reservationID))
    var signatures = Set(local.map(visitSignature))
    for visit in supplemental {
      if let id = visit.reservationID, reservationIDs.contains(id) { continue }
      let signature = visitSignature(visit)
      guard !signatures.contains(signature) else { continue }
      result.append(visit)
      if let id = visit.reservationID { reservationIDs.insert(id) }
      signatures.insert(signature)
    }
    return result
  }

  // Convert backend notes_history items — already reservation-tied and authoritative.
  private static func serverNotes(
    from items: [GuestNoteHistoryItem]
  ) -> [GuestServiceProfilePresentation.Note] {
    var seen: Set<String> = []
    return items.compactMap { item in
      let value = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { return nil }
      let kind: GuestServiceProfilePresentation.Note.Kind = item.noteType == .staff ? .staff : .guest
      // Dedupe by (reservationID, kind, normalizedText) — keeps two reservations with
      // identical text, collapses only true duplicates from the same reservation/kind.
      let key = "\(item.reservationID)|\(kind.rawValue)|\(value.lowercased())"
      guard seen.insert(key).inserted else { return nil }
      return .init(
        id: "\(item.reservationID)-\(kind.rawValue)",
        dateKey: item.date,
        displayDate: item.displayDate,
        kind: kind,
        text: value
      )
    }
    .sorted {
      if $0.dateKey != $1.dateKey { return $0.dateKey > $1.dateKey }
      return $0.kind.rawValue < $1.kind.rawValue
    }
  }

  // Fallback: derive notes from local row cache when backend notes_history is absent.
  private static func notesHistory(
    selected: ReservationRecord,
    pastVisits: [GuestServiceProfilePresentation.Visit],
    upcoming: [GuestServiceProfilePresentation.Visit]
  ) -> [GuestServiceProfilePresentation.Note] {
    let selectedVisit = visit(from: selected)
    let visits = [selectedVisit] + pastVisits + upcoming
    var seen: Set<String> = []
    var notes: [GuestServiceProfilePresentation.Note] = []
    for visit in visits {
      let values: [(GuestServiceProfilePresentation.Note.Kind, String?)] = [
        (.guest, visit.guestNote),
        (.staff, visit.staffNote)
      ]
      for (kind, value) in values {
        guard let value = trimmedNote(value) else { continue }
        // Dedupe by (reservationID, kind, normalizedText) so two different reservations
        // that happen to share the same note text are both preserved.
        let rid = visit.reservationID.map(String.init) ?? visit.id
        let normalized = "\(rid)|\(kind.rawValue)|\(value.lowercased())"
        guard seen.insert(normalized).inserted else { continue }
        notes.append(.init(
          id: "\(visit.id)-\(kind.rawValue)",
          dateKey: visit.dateKey,
          displayDate: visit.displayDate,
          kind: kind,
          text: value
        ))
      }
    }
    return notes.sorted {
      if $0.dateKey != $1.dateKey { return $0.dateKey > $1.dateKey }
      return $0.kind.rawValue < $1.kind.rawValue
    }
  }

  private static func patterns(
    from visits: [GuestServiceProfilePresentation.Visit]
  ) -> [GuestServiceProfilePresentation.Pattern] {
    guard visits.count >= 2 else { return [] }
    var result: [GuestServiceProfilePresentation.Pattern] = []
    if let party = supportedMode(visits.map(\.partySize)) {
      result.append(.init(id: "party", text: "Usually books for \(party)", systemImage: "person.2"))
    }
    let hours = visits.compactMap { hour(from: $0.timeKey) }
    if let usualHour = supportedMode(hours) {
      result.append(.init(id: "time", text: "Usually around \(displayHour(usualHour))", systemImage: "clock"))
    }
    let weekdays = visits.compactMap { weekday(from: $0.dateKey) }
    if let usualWeekday = supportedMode(weekdays) {
      result.append(.init(id: "weekday", text: "Often \(usualWeekday)", systemImage: "calendar"))
    }
    let average = Double(visits.reduce(0) { $0 + $1.partySize }) / Double(visits.count)
    result.append(.init(id: "average", text: "Average party \(Int(average.rounded()))", systemImage: "number"))
    if let largest = visits.map(\.partySize).max() {
      result.append(.init(id: "largest", text: "Largest party \(largest)", systemImage: "person.3"))
    }
    return result
  }

  private static func watchouts(
    selected: ReservationRecord,
    matchedRecords: [ReservationRecord],
    upcomingCount: Int,
    collapsedDuplicate: Bool,
    report: GuestInsightReport?
  ) -> [GuestServiceProfilePresentation.Watchout] {
    var result: [GuestServiceProfilePresentation.Watchout] = []
    if isUpcomingStatus(selected.statusValue), selected.assignedTableName == nil {
      result.append(.init(id: "table", title: "No table picked", detail: "Choose a table before service.", systemImage: "tablecells"))
    }
    if selected.statusValue == .confirmed, nonBlank(selected.reminderEmailSentAt) == nil {
      result.append(.init(id: "reminder", title: "Reminder not sent", detail: nil, systemImage: "bell.slash"))
    }
    if nonBlank(selected.guestNotes) != nil {
      result.append(.init(id: "guest-note", title: "Guest note attached", detail: "Read the note before seating.", systemImage: "note.text"))
    }
    if nonBlank(selected.staffNotes) != nil {
      result.append(.init(id: "staff-note", title: "Staff note found", detail: "Review prior staff context.", systemImage: "person.text.rectangle"))
    }
    if upcomingCount > 0 {
      result.append(.init(id: "upcoming", title: "Upcoming reservation also exists", detail: "This guest has another active booking.", systemImage: "calendar.badge.clock"))
    }
    if GuestOperationalTruth.possibleCorrection(reservation: selected, peers: matchedRecords) {
      result.append(.init(id: "correction", title: "Possible correction", detail: "Check the active same-day reservation.", systemImage: "arrow.triangle.2.circlepath"))
    } else if collapsedDuplicate {
      result.append(.init(id: "ignored-duplicate", title: "Cancelled duplicate ignored", detail: "It is not counted as a past visit.", systemImage: "checkmark.circle"))
    }
    for warning in report?.warnings ?? [] where !result.contains(where: { $0.title == warning.title }) {
      result.append(.init(id: "warning-\(warning.id)", title: warning.title, detail: warning.message, systemImage: warning.systemImage))
    }
    return result
  }

  private static func hasReliableIdentity(_ pack: GuestIntelligenceProfilePackDTO) -> Bool {
    if let confidence = pack.resolvedSummary?.identityConfidence {
      return confidence == .exact || confidence == .strong
    }
    let confidence = pack.hostProfilePacket?.identityConfidence?.lowercased()
    return confidence == "exact" || confidence == "strong"
  }

  private static func signalPreview(_ signals: GuestIntelligenceVisitSignalsDTO?) -> String? {
    guard let signals else { return nil }
    let values: [(String, String?)] = [
      ("Occasion", signals.occasion),
      ("Dietary", signals.dietary),
      ("Allergy", signals.allergy),
      ("Accessibility", signals.accessibility),
      ("Table preference", signals.tablePreference),
      ("Service note", signals.serviceIssue)
    ]
    let lines = values.compactMap { label, value -> String? in
      guard let value = nonBlank(value) else { return nil }
      return "\(label): \(value)"
    }
    return lines.isEmpty ? nil : lines.joined(separator: " · ")
  }

  private static func supportedMode<T: Hashable>(_ values: [T]) -> T? {
    guard values.count >= 2 else { return nil }
    let counts = values.reduce(into: [T: Int]()) { $0[$1, default: 0] += 1 }
    guard let best = counts.max(by: { $0.value < $1.value }), best.value >= 2 else { return nil }
    return best.key
  }

  private static func weekday(from dateKey: String) -> String? {
    guard let date = ReservationFormatters.reservationDateKey.date(from: dateKey) else { return nil }
    return DateFormatter().weekdaySymbols[Calendar.current.component(.weekday, from: date) - 1]
  }

  private static func hour(from time: String) -> Int? {
    Int(time.prefix(2))
  }

  private static func displayHour(_ hour: Int) -> String {
    let date = Calendar.current.date(from: DateComponents(hour: hour)) ?? Date()
    return date.formatted(.dateTime.hour())
  }

  private static func displayDate(_ dateKey: String) -> String {
    guard let date = ReservationFormatters.reservationDateKey.date(from: dateKey) else { return dateKey }
    return ReservationFormatters.mediumDate.string(from: date)
  }

  private static func displayTime(_ time: String) -> String {
    let normalized = String(time.prefix(5))
    let apiValue = normalized.count == 5 ? normalized + ":00" : normalized
    guard let date = ReservationFormatters.apiTime.date(from: apiValue) else { return normalized }
    return ReservationFormatters.shortTime.string(from: date)
  }

  private static func tableLabel(_ raw: String?) -> String {
    guard let table = nonBlank(raw) else { return "No table picked" }
    return table.lowercased().hasPrefix("table") ? table : "Table \(table)"
  }

  private static func trimmedNote(_ raw: String?) -> String? {
    guard let value = nonBlank(raw) else { return nil }
    if value.count <= 180 { return value }
    return String(value.prefix(177)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
  }

  private static func cleaned(_ raw: String?) -> String? {
    nonBlank(raw)
  }

  private static func nonBlank(_ raw: String?) -> String? {
    guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }

  private static func isUpcomingStatus(_ status: ReservationStatus) -> Bool {
    status == .new || status == .needsReview || status == .confirmed
  }

  private static func serviceKey(_ date: String, _ time: String) -> String {
    "\(date) \(String(time.prefix(5)))"
  }

  private static func currentServiceKey(_ date: Date) -> String {
    let components = Calendar.current.dateComponents([.hour, .minute], from: date)
    return String(
      format: "%@ %02d:%02d",
      date.reservationDateString(),
      components.hour ?? 0,
      components.minute ?? 0
    )
  }

  private static func visitSignature(_ visit: GuestServiceProfilePresentation.Visit) -> String {
    "\(visit.dateKey)|\(String(visit.timeKey.prefix(5)))|\(visit.partySize)"
  }

  private static func newestFirst(
    _ lhs: GuestServiceProfilePresentation.Visit,
    _ rhs: GuestServiceProfilePresentation.Visit
  ) -> Bool {
    serviceKey(lhs.dateKey, lhs.timeKey) > serviceKey(rhs.dateKey, rhs.timeKey)
  }

  private static func oldestFirst(
    _ lhs: GuestServiceProfilePresentation.Visit,
    _ rhs: GuestServiceProfilePresentation.Visit
  ) -> Bool {
    serviceKey(lhs.dateKey, lhs.timeKey) < serviceKey(rhs.dateKey, rhs.timeKey)
  }
}
