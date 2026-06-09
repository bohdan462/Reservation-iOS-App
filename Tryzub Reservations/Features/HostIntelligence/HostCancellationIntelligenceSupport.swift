//
//  HostCancellationIntelligenceSupport.swift
//  Tryzub Reservations
//
//  Deterministic cancellation, overdue, and freed-table opportunity analysis.
//

import Foundation

struct HostCancellationIntelligenceResult {
  let facts: [HostBriefingFact]
  let actions: [HostSuggestedAction]
  let tableSignals: [HostTableSignal]
  let overdueReservationIDs: Set<Int>
  let cancellationFactCount: Int
  let opportunityFactCount: Int
  let overdueFactCount: Int
  let lateLargePartyCount: Int
  let pastDueCompleteCount: Int
  let cancellationOpportunityCount: Int
}

enum HostCancellationIntelligenceSupport {

  private static let relevantCancellationWindowMinutes = 90
  private static let freedTableWindowMinutes = 30

  // MARK: - Public

  static func analyze(
    activeReservations: [ReservationRecord],
    allDayReservations: [ReservationRecord],
    tableConfigs: [RestaurantTableConfig],
    now: Date,
    settings: HostIntelligenceSettings
  ) -> HostCancellationIntelligenceResult {
    var facts: [HostBriefingFact] = []
    var actions: [HostSuggestedAction] = []
    var tableSignals: [HostTableSignal] = []

    let cancelled = findCancelledReservationsToday(from: allDayReservations)
    let relevantCancellations = findRecentRelevantCancellations(
      cancelled: cancelled,
      activeReservations: activeReservations,
      now: now
    )
    let noTableActive = activeReservations.filter { $0.isOpenWork && !$0.hasTableAssignment }

    facts.append(contentsOf: detectFreedTableOpportunity(
      cancellations: relevantCancellations,
      noTableReservations: noTableActive,
      tableConfigs: tableConfigs,
      now: now,
      actions: &actions,
      tableSignals: &tableSignals
    ))

    facts.append(contentsOf: detectCancellationReducedSlotPressure(
      cancellations: relevantCancellations,
      activeReservations: activeReservations,
      settings: settings
    ))

    let overdueResults = detectOverdueConfirmedReservations(
      activeReservations: activeReservations,
      now: now,
      settings: settings,
      actions: &actions
    )
    facts.append(contentsOf: overdueResults.facts)
    var overdueIDs = overdueResults.overdueReservationIDs

    facts.append(contentsOf: detectPastDueCompleteCandidates(
      activeReservations: activeReservations,
      now: now,
      actions: &actions
    ))

    let lateLargeParty = detectLateLargePartyRisk(
      activeReservations: activeReservations,
      now: now,
      settings: settings,
      actions: &actions
    )
    facts.append(contentsOf: lateLargeParty.facts)

    let lateNoTable = detectLateNoTableReservation(
      activeReservations: activeReservations,
      now: now,
      actions: &actions,
      tableSignals: &tableSignals
    )
    facts.append(contentsOf: lateNoTable.facts)
    overdueIDs.formUnion(lateNoTable.overdueReservationIDs)

    return HostCancellationIntelligenceResult(
      facts: facts,
      actions: actions,
      tableSignals: tableSignals,
      overdueReservationIDs: overdueIDs,
      cancellationFactCount: facts.filter { $0.category == .cancellation }.count,
      opportunityFactCount: facts.filter { $0.category == .opportunity }.count,
      overdueFactCount: facts.filter {
        $0.category == .overdue && ($0.severity == .warning || $0.severity == .critical)
      }.count,
      lateLargePartyCount: lateLargeParty.count,
      pastDueCompleteCount: facts.filter { $0.id.hasPrefix("past-due-complete-") }.count,
      cancellationOpportunityCount: actions.filter { $0.kind == .reviewCancellationOpportunity }.count
    )
  }

  // MARK: - Cancelled Reservations

  static func findCancelledReservationsToday(
    from allDayReservations: [ReservationRecord]
  ) -> [ReservationRecord] {
    allDayReservations
      .filter { !$0.isHidden && $0.statusValue == .cancelled }
      .sorted { lhs, rhs in
        let lhsDate = lhs.serviceDateTime ?? .distantPast
        let rhsDate = rhs.serviceDateTime ?? .distantPast
        if lhsDate == rhsDate {
          return lhs.remoteID > rhs.remoteID
        }
        return lhsDate > rhsDate
      }
  }

  static func findRecentRelevantCancellations(
    cancelled: [ReservationRecord],
    activeReservations: [ReservationRecord],
    now: Date
  ) -> [ReservationRecord] {
    cancelled.filter { reservation in
      if reservation.hasTableAssignment {
        return true
      }

      if isWithinMinutes(
        of: now,
        serviceDate: reservation.serviceDateTime,
        window: relevantCancellationWindowMinutes
      ) {
        return true
      }

      guard let cancelledServiceDate = reservation.serviceDateTime else {
        return false
      }

      return activeReservations.contains { active in
        guard active.isOpenWork, !active.hasTableAssignment,
              let activeServiceDate = active.serviceDateTime else {
          return false
        }
        return abs(activeServiceDate.timeIntervalSince(cancelledServiceDate)) / 60
          <= Double(freedTableWindowMinutes)
      }
    }
  }

  // MARK: - Opportunity Analyzers

  private static func detectFreedTableOpportunity(
    cancellations: [ReservationRecord],
    noTableReservations: [ReservationRecord],
    tableConfigs: [RestaurantTableConfig],
    now: Date,
    actions: inout [HostSuggestedAction],
    tableSignals: inout [HostTableSignal]
  ) -> [HostBriefingFact] {
    var facts: [HostBriefingFact] = []

    for cancellation in cancellations {
      guard let tableName = cancellation.assignedTableName else { continue }

      let nearbyNoTable = noTableReservations.filter { reservation in
        isWithinMinutes(
          of: cancellation.serviceDateTime,
          serviceDate: reservation.serviceDateTime,
          window: freedTableWindowMinutes
        )
      }

      if let match = nearbyNoTable.first(where: { reservation in
        canFreedTableFitReservation(
          tableName: tableName,
          reservation: reservation,
          tableConfigs: tableConfigs
        )
      }) {
        let detail =
          "\(tableName) opened after \(cancellation.guestName) canceled; it may help \(match.guestName), party of \(match.partySize)."
        facts.append(
          HostBriefingFact(
            id: "cancellation-freed-table-\(cancellation.remoteID)-\(match.remoteID)",
            severity: .watch,
            category: .opportunity,
            title: "Cancellation opened table",
            detail: detail,
            evidence: [
              "freedTable=\(tableName)",
              "cancelledPartySize=\(cancellation.partySize)"
            ],
            relatedReservationIDs: [cancellation.remoteID, match.remoteID],
            suggestedActionTitle: "Review \(tableName) for \(match.guestName)."
          )
        )

        actions.append(
          HostSuggestedAction(
            id: "cancellation-opportunity-action-\(cancellation.remoteID)-\(match.remoteID)",
            severity: .watch,
            kind: .reviewCancellationOpportunity,
            title: "Review \(tableName) for \(match.guestName)",
            reason: detail,
            relatedReservationIDs: [cancellation.remoteID, match.remoteID],
            targetSlotTime: match.reservationTime,
            targetTableName: tableName,
            requiresStaffConfirmation: true
          )
        )

        tableSignals.append(
          HostTableSignal(
            id: "cancellation-freed-table-signal-\(cancellation.remoteID)",
            tableName: tableName,
            kind: .cancellationFreedTable,
            severity: .watch,
            title: "Cancellation opened table",
            detail: detail,
            relatedReservationIDs: [cancellation.remoteID, match.remoteID],
            evidence: ["freedTable=\(tableName)"]
          )
        )
      } else if !nearbyNoTable.isEmpty {
        let detail = "\(tableName) opened after \(cancellation.guestName) canceled."
        facts.append(
          HostBriefingFact(
            id: "cancellation-freed-table-generic-\(cancellation.remoteID)",
            severity: .info,
            category: .opportunity,
            title: "Cancellation opened table",
            detail: detail,
            evidence: ["freedTable=\(tableName)"],
            relatedReservationIDs: [cancellation.remoteID],
            suggestedActionTitle: "Review nearby no-table reservations."
          )
        )
      } else {
        let detail = "\(tableName) opened after \(cancellation.guestName) canceled."
        facts.append(
          HostBriefingFact(
            id: "cancellation-freed-table-unassigned-\(cancellation.remoteID)",
            severity: .info,
            category: .opportunity,
            title: "Cancellation opened table",
            detail: detail,
            evidence: ["freedTable=\(tableName)"],
            relatedReservationIDs: [cancellation.remoteID],
            suggestedActionTitle: nil
          )
        )
      }
    }

    return facts
  }

  private static func detectCancellationReducedSlotPressure(
    cancellations: [ReservationRecord],
    activeReservations: [ReservationRecord],
    settings: HostIntelligenceSettings
  ) -> [HostBriefingFact] {
    var facts: [HostBriefingFact] = []

    for cancellation in cancellations {
      guard let cancelledSlot = cancellation.serviceDateTime else { continue }

      let activeInSlot = activeReservations.filter { reservation in
        guard reservation.isOpenWork || reservation.statusValue == .seated,
              let serviceDate = reservation.serviceDateTime else {
          return false
        }
        return slotBucket(for: serviceDate, intervalMinutes: settings.slotIntervalMinutes)
          == slotBucket(for: cancelledSlot, intervalMinutes: settings.slotIntervalMinutes)
      }

      let reservationCount = activeInSlot.count
      let guestCount = activeInSlot.reduce(0) { $0 + $1.partySize }
      let largePartyCount = activeInSlot.filter {
        $0.partySize >= settings.largePartyThreshold
      }.count

      let isBusySlot = reservationCount > settings.maxReservationsPerSlot
        || largePartyCount > settings.maxLargePartiesPerSlot
        || guestCount >= settings.largePartyThreshold * 2

      guard isBusySlot else { continue }

      let timeLabel = cancellation.displayTime
      facts.append(
        HostBriefingFact(
          id: "cancellation-reduced-pressure-\(cancellation.remoteID)",
          severity: .info,
          category: .cancellation,
          title: "Cancellation reduced pressure",
          detail: "Cancellation reduced pressure at \(timeLabel).",
          evidence: [
            "cancelledPartySize=\(cancellation.partySize)",
            "remainingReservations=\(reservationCount)",
            "remainingGuests=\(guestCount)"
          ],
          relatedReservationIDs: [cancellation.remoteID] + activeInSlot.map(\.remoteID),
          suggestedActionTitle: nil
        )
      )
    }

    return facts
  }

  // MARK: - Overdue Analyzers

  private static func detectOverdueConfirmedReservations(
    activeReservations: [ReservationRecord],
    now: Date,
    settings: HostIntelligenceSettings,
    actions: inout [HostSuggestedAction]
  ) -> (facts: [HostBriefingFact], overdueReservationIDs: Set<Int>) {
    var facts: [HostBriefingFact] = []
    var overdueIDs = Set<Int>()

    for reservation in activeReservations where reservation.isOpenWork && reservation.hasTableAssignment {
      guard let minutesLate = minutesLate(for: reservation, now: now) else { continue }

      overdueIDs.insert(reservation.remoteID)
      let severity = overdueSeverity(minutesLate: minutesLate)

      let detail =
        "\(reservation.guestName), party of \(reservation.partySize), was due \(minutesLate) minutes ago."
      facts.append(
        HostBriefingFact(
          id: "overdue-reservation-\(reservation.remoteID)",
          severity: severity,
          category: .overdue,
          title: "Reservation overdue",
          detail: detail,
          evidence: [
            "minutesLate=\(minutesLate)",
            "status=\(reservation.statusValue.rawValue)"
          ],
          relatedReservationIDs: [reservation.remoteID],
          suggestedActionTitle: "Review whether to call, seat, cancel, or mark no-show."
        )
      )

      actions.append(
        HostSuggestedAction(
          id: "overdue-review-action-\(reservation.remoteID)",
          severity: severity,
          kind: .reviewReservation,
          title: "Review overdue reservation for \(reservation.guestName)",
          reason: detail,
          relatedReservationIDs: [reservation.remoteID],
          targetSlotTime: reservation.reservationTime,
          targetTableName: reservation.assignedTableName,
          requiresStaffConfirmation: true
        )
      )

      if minutesLate >= 30 {
        actions.append(
          HostSuggestedAction(
            id: "overdue-mark-noshow-action-\(reservation.remoteID)",
            severity: severity,
            kind: .markNoShow,
            title: "Review no-show for \(reservation.guestName)",
            reason: "Reservation is \(minutesLate) minutes past due.",
            relatedReservationIDs: [reservation.remoteID],
            targetSlotTime: reservation.reservationTime,
            targetTableName: reservation.assignedTableName,
            requiresStaffConfirmation: true
          )
        )
      }
    }

    return (facts, overdueIDs)
  }

  private static func detectPastDueCompleteCandidates(
    activeReservations: [ReservationRecord],
    now: Date,
    actions: inout [HostSuggestedAction]
  ) -> [HostBriefingFact] {
    var facts: [HostBriefingFact] = []

    for reservation in activeReservations where reservation.canMarkPastDueComplete {
      guard reservation.isPastDueCompleteEligible(now: now) else { continue }

      let minutesLate = minutesLate(for: reservation, now: now) ?? 0
      let detail =
        "\(reservation.guestName) is past the completion grace window."

      facts.append(
        HostBriefingFact(
          id: "past-due-complete-\(reservation.remoteID)",
          severity: .watch,
          category: .overdue,
          title: "Past-due completion review",
          detail: detail,
          evidence: [
            "minutesLate=\(minutesLate)",
            "graceMinutes=\(ReservationRecord.pastDueCompleteGraceMinutes)"
          ],
          relatedReservationIDs: [reservation.remoteID],
          suggestedActionTitle: "Review whether to mark completed."
        )
      )

      actions.append(
        HostSuggestedAction(
          id: "past-due-complete-action-\(reservation.remoteID)",
          severity: .watch,
          kind: .completeReservation,
          title: "Review completion for \(reservation.guestName)",
          reason: detail,
          relatedReservationIDs: [reservation.remoteID],
          targetSlotTime: reservation.reservationTime,
          targetTableName: reservation.assignedTableName,
          requiresStaffConfirmation: true
        )
      )
    }

    return facts
  }

  private static func detectLateLargePartyRisk(
    activeReservations: [ReservationRecord],
    now: Date,
    settings: HostIntelligenceSettings,
    actions: inout [HostSuggestedAction]
  ) -> (facts: [HostBriefingFact], count: Int) {
    var facts: [HostBriefingFact] = []
    var count = 0

    for reservation in activeReservations where reservation.isOpenWork {
      guard reservation.partySize >= settings.largePartyThreshold,
            let minutesLate = minutesLate(for: reservation, now: now),
            minutesLate > 0 else {
        continue
      }

      count += 1
      let severity: HostSeverity = minutesLate >= 31 ? .critical : .warning
      let detail =
        "Party of \(reservation.partySize) is \(minutesLate) minutes late; holding the table may affect upcoming seating."

      facts.append(
        HostBriefingFact(
          id: "late-large-party-\(reservation.remoteID)",
          severity: severity,
          category: .largeParty,
          title: "Large party late",
          detail: detail,
          evidence: ["minutesLate=\(minutesLate)", "partySize=\(reservation.partySize)"],
          relatedReservationIDs: [reservation.remoteID],
          suggestedActionTitle: "Review seating plan before holding the table longer."
        )
      )

      actions.append(
        HostSuggestedAction(
          id: "late-large-party-action-\(reservation.remoteID)",
          severity: severity,
          kind: .reviewReservation,
          title: "Review late large party for \(reservation.guestName)",
          reason: detail,
          relatedReservationIDs: [reservation.remoteID],
          targetSlotTime: reservation.reservationTime,
          targetTableName: reservation.assignedTableName,
          requiresStaffConfirmation: true
        )
      )
    }

    return (facts, count)
  }

  private static func detectLateNoTableReservation(
    activeReservations: [ReservationRecord],
    now: Date,
    actions: inout [HostSuggestedAction],
    tableSignals: inout [HostTableSignal]
  ) -> (facts: [HostBriefingFact], overdueReservationIDs: Set<Int>) {
    var facts: [HostBriefingFact] = []
    var overdueIDs = Set<Int>()

    for reservation in activeReservations where reservation.isOpenWork && !reservation.hasTableAssignment {
      guard let minutesLate = minutesLate(for: reservation, now: now) else { continue }

      overdueIDs.insert(reservation.remoteID)
      let severity = overdueSeverity(minutesLate: minutesLate)
      let detail =
        "\(reservation.guestName), party of \(reservation.partySize), is \(minutesLate) minutes late and still has no table."

      facts.append(
        HostBriefingFact(
          id: "overdue-no-table-\(reservation.remoteID)",
          severity: severity,
          category: .overdue,
          title: "Late reservation still has no table",
          detail: detail,
          evidence: ["minutesLate=\(minutesLate)", "noTable=true"],
          relatedReservationIDs: [reservation.remoteID],
          suggestedActionTitle: "Assign a table or review the reservation now."
        )
      )

      actions.append(
        HostSuggestedAction(
          id: "overdue-no-table-action-\(reservation.remoteID)",
          severity: severity,
          kind: .assignTable,
          title: "Assign table for late \(reservation.guestName)",
          reason: detail,
          relatedReservationIDs: [reservation.remoteID],
          targetSlotTime: reservation.reservationTime,
          targetTableName: nil,
          requiresStaffConfirmation: true
        )
      )

      tableSignals.append(
        HostTableSignal(
          id: "overdue-no-table-signal-\(reservation.remoteID)",
          tableName: nil,
          kind: .noTableAssigned,
          severity: severity,
          title: "Late reservation still has no table",
          detail: detail,
          relatedReservationIDs: [reservation.remoteID],
          evidence: ["minutesLate=\(minutesLate)"]
        )
      )
    }

    return (facts, overdueIDs)
  }

  // MARK: - Helpers

  private static func canFreedTableFitReservation(
    tableName: String,
    reservation: ReservationRecord,
    tableConfigs: [RestaurantTableConfig]
  ) -> Bool {
    let options = HostTableIntelligenceSupport.bestTableFitOptions(
      for: reservation,
      tableConfigs: tableConfigs,
      limit: 3
    )

    let normalizedFreed = HostTableIntelligenceSupport.normalizeTableName(tableName)
    return options.contains { option in
      option.tableNames.contains { candidate in
        HostTableIntelligenceSupport.normalizeTableName(candidate) == normalizedFreed
      }
    }
  }

  private static func minutesLate(for reservation: ReservationRecord, now: Date) -> Int? {
    guard let serviceDate = reservation.serviceDateTime else { return nil }
    let secondsLate = now.timeIntervalSince(serviceDate)
    guard secondsLate > 0 else { return nil }
    return Int(ceil(secondsLate / 60))
  }

  private static func overdueSeverity(minutesLate: Int) -> HostSeverity {
    if minutesLate >= 31 { return .critical }
    if minutesLate >= 16 { return .warning }
    return .watch
  }

  private static func isWithinMinutes(
    of referenceDate: Date?,
    serviceDate: Date?,
    window: Int
  ) -> Bool {
    guard let referenceDate, let serviceDate else { return false }
    let minutes = abs(serviceDate.timeIntervalSince(referenceDate)) / 60
    return minutes <= Double(window)
  }

  private static func isWithinMinutes(
    of now: Date,
    serviceDate: Date?,
    window: Int
  ) -> Bool {
    guard let serviceDate else { return false }
    let minutes = abs(serviceDate.timeIntervalSince(now)) / 60
    return minutes <= Double(window)
  }

  private static func slotBucket(for date: Date, intervalMinutes: Int) -> Date {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    guard let minute = components.minute else { return date }
    let roundedMinute = (minute / intervalMinutes) * intervalMinutes
    var adjusted = components
    adjusted.second = 0
    adjusted.minute = roundedMinute
    return calendar.date(from: adjusted) ?? date
  }
}
