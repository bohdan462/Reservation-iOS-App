//
//  HostTableAssignmentContextSupport.swift
//  Tryzub Reservations
//
//  Slot pressure + proposed seating for table assignment / seat flows.
//

import Foundation

struct HostTableAssignmentProposal: Identifiable, Equatable {
  let id: String
  let tableLabel: String
  let summary: String
  let detail: String?
  let isRecommended: Bool
  let isAvailable: Bool
}

struct HostTableAssignmentContext: Equatable {
  let slotContext: HostReservationSlotContext?
  let proposals: [HostTableAssignmentProposal]
}

enum HostTableAssignmentContextSupport {

  static func build(
    reservation: ReservationRecord,
    dayReservations: [ReservationRecord],
    blockedSlotValues: Set<String>,
    tableConfigs: [RestaurantTableConfig],
    settings: HostIntelligenceSettings,
    localSeatedAtByReservationID: [Int: Date],
    manualTableSuggestions: [String],
    now: Date = Date()
  ) -> HostTableAssignmentContext? {
    guard settings.isEnabled else { return nil }
    guard let serviceDateTime = reservation.serviceDateTime else { return nil }

    let serviceDate = ReservationFormatters.reservationDateKey.date(from: reservation.reservationDate)
      ?? serviceDateTime
    let serviceTime = serviceDateTime
    let bucketStart = ReservationDensityCalculator.bucketStart(for: serviceDateTime)

    let slotContext = HostReservationSlotContextSupport.build(
      serviceDate: serviceDate,
      serviceTime: serviceTime,
      partySize: reservation.partySize,
      excludingReservationID: reservation.remoteID,
      dayReservations: dayReservations,
      blockedSlotValues: blockedSlotValues,
      isServiceClosed: false,
      tableConfigs: tableConfigs,
      settings: settings
    )

    let proposals = buildProposals(
      reservation: reservation,
      bucketStart: bucketStart,
      dayReservations: dayReservations,
      tableConfigs: tableConfigs,
      settings: settings,
      localSeatedAtByReservationID: localSeatedAtByReservationID,
      manualTableSuggestions: manualTableSuggestions,
      now: now
    )

    guard slotContext != nil || !proposals.isEmpty else { return nil }

    return HostTableAssignmentContext(
      slotContext: slotContext,
      proposals: proposals
    )
  }

  // MARK: - Proposals

  private static func buildProposals(
    reservation: ReservationRecord,
    bucketStart: Date,
    dayReservations: [ReservationRecord],
    tableConfigs: [RestaurantTableConfig],
    settings: HostIntelligenceSettings,
    localSeatedAtByReservationID: [Int: Date],
    manualTableSuggestions: [String],
    now: Date
  ) -> [HostTableAssignmentProposal] {
    var proposals: [HostTableAssignmentProposal] = []
    var seenLabels = Set<String>()

    let activeTables = tableConfigs.filter(\.isActive)
    if !activeTables.isEmpty {
      let fits = HostTableIntelligenceSupport.bestTableFitOptions(
        for: reservation,
        tableConfigs: activeTables,
        limit: 4
      )

      for fit in fits {
        let label = HostTableIntelligenceSupport.displayTableNames(fit.tableNames)
        let key = normalizeLabel(label)
        guard seenLabels.insert(key).inserted else { continue }

        let conflict = tableConflict(
          tableNames: fit.tableNames,
          reservation: reservation,
          bucketStart: bucketStart,
          dayReservations: dayReservations,
          localSeatedAtByReservationID: localSeatedAtByReservationID,
          settings: settings,
          now: now
        )

        proposals.append(
          HostTableAssignmentProposal(
            id: fit.id,
            tableLabel: label,
            summary: proposalSummary(for: fit),
            detail: conflict,
            isRecommended: conflict == nil,
            isAvailable: conflict == nil
          )
        )
      }
    }

    for suggestion in manualTableSuggestions {
      let names = HostTableIntelligenceSupport.parseAssignedTableNames(suggestion)
      let label = names.isEmpty ? suggestion : HostTableIntelligenceSupport.displayTableNames(names)
      let key = normalizeLabel(label)
      guard seenLabels.insert(key).inserted else { continue }

      let conflict = tableConflict(
        tableNames: names.isEmpty ? [suggestion] : names,
        reservation: reservation,
        bucketStart: bucketStart,
        dayReservations: dayReservations,
        localSeatedAtByReservationID: localSeatedAtByReservationID,
        settings: settings,
        now: now
      )

      proposals.append(
        HostTableAssignmentProposal(
          id: "manual-\(key)",
          tableLabel: label,
          summary: manualSummary(
            tableNames: names.isEmpty ? [suggestion] : names,
            partySize: reservation.partySize,
            tableConfigs: activeTables
          ),
          detail: conflict,
          isRecommended: false,
          isAvailable: conflict == nil
        )
      )
    }

    return proposals
      .sorted { lhs, rhs in
        if lhs.isAvailable != rhs.isAvailable { return lhs.isAvailable }
        if lhs.isRecommended != rhs.isRecommended { return lhs.isRecommended }
        return lhs.tableLabel.localizedCaseInsensitiveCompare(rhs.tableLabel) == .orderedAscending
      }
      .prefix(5)
      .map { $0 }
  }

  private static func proposalSummary(for fit: HostTableFitOption) -> String {
    let fitLabel: String
    switch fit.fitQuality {
    case .exact: fitLabel = "Exact fit"
    case .tight: fitLabel = "Tight fit"
    case .comfortable: fitLabel = "Comfortable fit"
    case .oversized: fitLabel = "Roomy fit"
    case .unavailable: fitLabel = "Check capacity"
    }

    if fit.isCombination {
      return "Combined · seats \(fit.totalCapacity) · \(fitLabel.lowercased())"
    }
    if let section = fit.section?.nilIfBlank {
      return "Seats \(fit.totalCapacity) · \(section) · \(fitLabel.lowercased())"
    }
    return "Seats \(fit.totalCapacity) · \(fitLabel.lowercased())"
  }

  private static func manualSummary(
    tableNames: [String],
    partySize: Int,
    tableConfigs: [RestaurantTableConfig]
  ) -> String {
    if let matched = HostTableIntelligenceSupport.matchingTables(for: tableNames, in: tableConfigs) {
      let capacity = matched.reduce(0) { $0 + $1.capacity }
      if capacity >= partySize {
        return "Seats \(capacity) · matches party"
      }
      return "Seats \(capacity) · may be tight for \(partySize)"
    }
    return tableNames.count > 1 ? "Combined table" : "Saved table option"
  }

  // MARK: - Conflicts

  private static func tableConflict(
    tableNames: [String],
    reservation: ReservationRecord,
    bucketStart: Date,
    dayReservations: [ReservationRecord],
    localSeatedAtByReservationID: [Int: Date],
    settings: HostIntelligenceSettings,
    now: Date
  ) -> String? {
    let normalizedTargets = Set(tableNames.map { HostTableIntelligenceSupport.normalizeTableName($0) })
    guard !normalizedTargets.isEmpty else { return nil }
    guard let serviceDate = reservation.serviceDateTime else { return nil }

    for seated in dayReservations where seated.remoteID != reservation.remoteID {
      guard seated.statusValue == .seated,
            let assigned = seated.assignedTableName else { continue }

      let seatedTables = HostTableIntelligenceSupport
        .parseAssignedTableNames(assigned)
        .map { HostTableIntelligenceSupport.normalizeTableName($0) }
      guard !Set(seatedTables).isDisjoint(with: normalizedTargets) else { continue }

      if let seatedAt = localSeatedAtByReservationID[seated.remoteID] {
        let turnMinutes = estimatedTurnMinutes(partySize: seated.partySize, settings: settings)
        let release = seatedAt.addingTimeInterval(TimeInterval(turnMinutes * 60))
        if release <= serviceDate {
          continue
        }
        let releaseLabel = ReservationFormatters.shortTime.string(from: release)
        return "\(assigned) in use until about \(releaseLabel) (\(seated.guestName))"
      }

      return "\(assigned) in use now (\(seated.guestName))"
    }

    let peers = matchingReservations(
      in: dayReservations,
      bucketStart: bucketStart,
      excludingReservationID: reservation.remoteID
    )

    for peer in peers {
      guard let assigned = peer.assignedTableName else { continue }
      let peerTables = HostTableIntelligenceSupport
        .parseAssignedTableNames(assigned)
        .map { HostTableIntelligenceSupport.normalizeTableName($0) }
      guard !Set(peerTables).isDisjoint(with: normalizedTargets) else { continue }
      return "\(assigned) booked for \(peer.guestName) at this time"
    }

    return nil
  }

  private static func matchingReservations(
    in reservations: [ReservationRecord],
    bucketStart: Date,
    excludingReservationID: Int
  ) -> [ReservationRecord] {
    reservations.filter { reservation in
      guard reservation.isExpectedGuest else { return false }
      guard reservation.remoteID != excludingReservationID else { return false }
      guard let peerBucket = ReservationDensityCalculator.bucketStart(for: reservation) else {
        return false
      }
      return peerBucket == bucketStart
    }
  }

  private static func estimatedTurnMinutes(
    partySize: Int,
    settings: HostIntelligenceSettings
  ) -> Int {
    if partySize <= 2 { return 75 }
    if partySize >= settings.largePartyThreshold { return 120 }
    return 90
  }

  private static func normalizeLabel(_ value: String) -> String {
    HostTableIntelligenceSupport.normalizeTableName(value)
  }
}

private extension String {
  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
